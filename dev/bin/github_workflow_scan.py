#!/usr/bin/env python3
"""
Scans GitHub Actions workflow files for pinned actions and reports when
newer versions are available.

Also validates that every action reference follows the required format:
  # https://github.com/owner/repo        <- line immediately above uses:
  uses: owner/repo@<40-char-sha> # vX.Y.Z
                   ^-- Must be a sha1, not a tag
                                 ^ Must show the tag used

Additionally validates the YAML structure of workflow files and runs
shellcheck on embedded shell scripts via Docker.

Exits 1 when any format violation is found, any action is outdated,
or any validation error is detected.

Usage: github_workflow_scan.py [OPTIONS] [<workflows-dir>]

  See --help for full usage.
"""

import re
import sys
import pathlib
import subprocess
import tempfile
from dataclasses import dataclass, field

try:
    import yaml
except ImportError:
    sys.exit("pyyaml is required: pip install pyyaml")

# ─── Colors ───────────────────────────────────────────────────────────────────

BOLD      = '\033[1m'
DARK_CYAN = '\033[38;2;0;139;139m'
GREEN     = '\033[38;2;0;200;0m'
GRAY      = '\033[2m'
ORANGE    = '\033[38;2;220;120;0m'
RED       = '\033[0;31m'
RESET     = '\033[0m'
YELLOW    = '\033[38;2;200;200;0m'

if not sys.stdout.isatty():
    BOLD = DARK_CYAN = GREEN = GRAY = ORANGE = RED = RESET = YELLOW = ''

# ─── Constants ────────────────────────────────────────────────────────────────

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT_DIR   = SCRIPT_DIR.parent.parent

SEMVER_RE = re.compile(r'^v\d+\.\d+\.\d+$')

# ─── Workflow file discovery ──────────────────────────────────────────────────

def _workflow_files(workflows_dir: pathlib.Path) -> list:
    """Return workflow files sorted by name, matching both .yml and .yaml.

    GitHub accepts either extension; this repository standardises on .yaml.
    """
    return sorted(
        path for path in workflows_dir.iterdir()
        if path.suffix in ('.yml', '.yaml')
    )

# ─── Exceptions ───────────────────────────────────────────────────────────────

class UsageError(Exception):
    """Raised for invalid CLI usage (bad arguments, missing directories)."""

class HelpRequested(Exception):
    """Raised when --help is passed."""

# ─── CLI / Options ────────────────────────────────────────────────────────────

@dataclass
class Options:
    def __init__(self):
        pass

    fix_format:      bool = False
    report_outdated: bool = False
    update:          bool = False
    workflows_dir:   str  = ''

# ─── Help ─────────────────────────────────────────────────────────────────────

def print_help() -> None:
    print(
        f'{BOLD}Usage:{RESET} github_workflow_scan.py [{DARK_CYAN}OPTIONS{RESET}] [{ORANGE}<workflows-dir>{RESET}]\n'
        '\n'
        'Check GitHub Actions workflow files for format compliance.\n'
        'Lints workflow YAML structure and shellchecks embedded shell scripts.\n'
        'Optionally report outdated actions, fix violations, or update to latest versions in-place.\n'
        '\n'
        f'{BOLD}Options:{RESET}\n'
        f'  {DARK_CYAN}--report-outdated{RESET}   Also check whether actions are up to date (requires network)\n'
        f'  {DARK_CYAN}--fix-format{RESET}        Fix actions format violations in-place:\n'
        '                        - insert missing  # https://github.com/owner/repo  comment\n'
        '                        - add or correct the  # vX.Y.Z  inline version comment\n'
        '                        - resolve floating tag refs (e.g. @v4) to SHA1 pins\n'
        f'  {DARK_CYAN}--update{RESET}            Update all actions to their latest version in-place\n'
        f'  {DARK_CYAN}-h, --help{RESET}          Show this help message and exit\n'
        '\n'
        f'{BOLD}Arguments:{RESET}\n'
        f'  {ORANGE}<workflows-dir>{RESET}  Directory containing *.yml workflow files.\n'
        '                   Defaults to .github/workflows.\n'
        '\n'
        f'{BOLD}Exit codes:{RESET}\n'
        f'  {GREEN}0{RESET}  No format violations and no validation errors\n'
        f'  {RED}1{RESET}  Format violations found, validation errors, or (with --report-outdated) outdated actions\n'
        '\n'
        f'{BOLD}Examples:{RESET}\n'
        f'  github_workflow_scan.py                          {GRAY}# format + structural lint{RESET}\n'
        f'  github_workflow_scan.py {DARK_CYAN}--report-outdated{RESET}     {GRAY}# also check for updates{RESET}\n'
        f'  github_workflow_scan.py {DARK_CYAN}--fix-format{RESET}          {GRAY}# fix format violations{RESET}\n'
        f'  github_workflow_scan.py {DARK_CYAN}--update{RESET}              {GRAY}# update to latest versions{RESET}\n'
        f'  github_workflow_scan.py {DARK_CYAN}--fix-format --update{RESET} {GRAY}# fix then update{RESET}\n'
        f'  github_workflow_scan.py {ORANGE}.github/workflows{RESET}      {GRAY}# check a specific directory{RESET}\n'
    )

# ─── Arg parsing ──────────────────────────────────────────────────────────────

def parse_args(argv: list) -> Options:
    opts = Options()
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == '--fix-format':
            opts.fix_format = True
        elif arg == '--update':
            opts.update = True
        elif arg == '--report-outdated':
            opts.report_outdated = True
        elif arg in ('-h', '--help'):
            raise HelpRequested()
        elif arg.startswith('-'):
            raise UsageError(f'unknown option: {arg}\nRun with --help for usage.')
        elif opts.workflows_dir:
            raise UsageError(f'unexpected argument: {arg}')
        else:
            opts.workflows_dir = arg
        i += 1
    return opts

# ─── Directory resolution ─────────────────────────────────────────────────────

def resolve_workflows_dir(explicit: str) -> pathlib.Path:
    if explicit:
        p = pathlib.Path(explicit)
        if not p.is_dir():
            raise UsageError(f'directory not found: {explicit}')

        return p

    candidate = ROOT_DIR / '.github' / 'workflows'
    if candidate.is_dir():
        return candidate

    raise UsageError('no workflow directory found (searched .github/workflows)')

# ==============================================================================
# GitHub Actions — format check, fix, update
# ==============================================================================

# An action ref is owner/repo, optionally followed by a /subdir path
# (e.g. actions/cache/restore), then @ref. `action` captures owner/repo (the
# repo that owns the tags and the github.com URL); `subpath` captures the rest
# of the path so it is excluded from the @ref checks but preserved on rewrite.
ACTION_RE = re.compile(
    r'^(?P<indent>\s*)uses:\s+'
    r'(?P<action>[A-Za-z0-9][A-Za-z0-9_.\-]*/[A-Za-z0-9][A-Za-z0-9_.\-]*)'
    r'(?P<subpath>(?:/[A-Za-z0-9_.\-]+)*)'
    r'(?P<rest>.*)$'
)

@dataclass
class Cache:
    sha:       dict     = field(default_factory=dict)            # "repo:tag" -> commit SHA
    tag:       dict     = field(default_factory=dict)            # "repo:sha" -> semver tag
    latest:    dict     = field(default_factory=dict)            # "repo"     -> latest semver tag
    ls_remote: callable = field(default_factory=lambda: _ls_remote)  # injectable for tests

# ─── Network helpers ──────────────────────────────────────────────────────────

def _ls_remote(*args: str) -> str:
    """Run git ls-remote with the given arguments (caller controls order)."""
    try:
        return subprocess.check_output(
            ['git', 'ls-remote', *args],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        return ''

def _semver_key(v: str) -> tuple:
    m = re.match(r'^v(\d+)\.(\d+)\.(\d+)$', v)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else (0, 0, 0)

def version_gt(a: str, b: str) -> bool:
    return a != b and _semver_key(a) > _semver_key(b)

def tag_to_sha(repo: str, tag: str, ls_remote=None) -> str:
    if ls_remote is None:
        ls_remote = _ls_remote
    url = f'https://github.com/{repo}.git'
    out = ls_remote(url, f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}')
    sha = ''
    for line in out.splitlines():
        parts = line.split('\t', 1)
        if len(parts) != 2:
            continue
        if parts[1].endswith('^{}'):
            return parts[0]   # deref entry — commit SHA for annotated tags
        if not sha:
            sha = parts[0]
    return sha

def sha_to_tag(repo: str, sha: str, ls_remote=None) -> str:
    if ls_remote is None:
        ls_remote = _ls_remote
    url = f'https://github.com/{repo}.git'
    out = ls_remote('--tags', url)
    tags = []
    for line in out.splitlines():
        parts = line.split('\t', 1)
        if len(parts) == 2 and parts[0] == sha:
            t = re.sub(r'\^\{\}$', '', parts[1].removeprefix('refs/tags/'))
            if SEMVER_RE.match(t):
                tags.append(t)
    return sorted(tags, key=_semver_key)[-1] if tags else ''

def latest_semver_tag(repo: str, ls_remote=None) -> str:
    if ls_remote is None:
        ls_remote = _ls_remote
    url = f'https://github.com/{repo}.git'
    out = ls_remote('--tags', '--refs', url)
    tags = [
        line.split('\t', 1)[1].removeprefix('refs/tags/')
        for line in out.splitlines()
        if '\t' in line
    ]
    tags = [t for t in tags if SEMVER_RE.match(t)]
    return sorted(tags, key=_semver_key)[-1] if tags else ''

def cached_tag_to_sha(repo: str, tag: str, cache: Cache) -> str:
    key = f'{repo}:{tag}'
    if key not in cache.sha:
        cache.sha[key] = tag_to_sha(repo, tag, cache.ls_remote)
    return cache.sha[key]

def cached_sha_to_tag(repo: str, sha: str, cache: Cache) -> str:
    key = f'{repo}:{sha}'
    if key not in cache.tag:
        cache.tag[key] = sha_to_tag(repo, sha, cache.ls_remote)
    return cache.tag[key]

def cached_latest_tag(repo: str, cache: Cache) -> str:
    if repo not in cache.latest:
        cache.latest[repo] = latest_semver_tag(repo, cache.ls_remote)
    return cache.latest[repo]

# ─── Action scanning ──────────────────────────────────────────────────────────

_USES_RE = re.compile(
    r'uses:\s+([A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-]+)((?:/[A-Za-z0-9_.\-]+)*)@([0-9a-f]{40})\s+#\s+(v\d+\.\d+\.\d+)'
)

def _scan_uses_lines(workflows_dir: pathlib.Path):
    """Yield unique (repo, subpath, sha, tag) tuples for every properly-formatted action.

    `subpath` is '' for a plain owner/repo ref and '/subdir' for a subdirectory
    action (e.g. actions/cache/restore); it is part of the dedup key so two
    subpaths of the same repo at the same version are not collapsed.
    """
    seen = set()
    for filepath in _workflow_files(workflows_dir):
        for line in filepath.read_text().splitlines():
            m = _USES_RE.search(line)
            if m:
                key = (m.group(1), m.group(2), m.group(3), m.group(4))
                if key not in seen:
                    seen.add(key)
                    yield key

# ─── Format check ─────────────────────────────────────────────────────────────

def _find_format_violations(workflows_dir: pathlib.Path) -> list:
    """Return a list of violation strings (empty = no violations)."""
    violations = []
    for filepath in _workflow_files(workflows_dir):
        rel   = filepath.name
        lines = filepath.read_text().splitlines()
        prev  = ''
        for lineno, cur in enumerate(lines, 1):
            m = ACTION_RE.match(cur)
            if not m:
                prev = cur
                continue
            indent = m.group('indent')
            action = m.group('action')
            rest   = m.group('rest')

            # Rule 1: must be pinned to a 40-char SHA1
            if not re.match(r'^@[0-9a-f]{40}(\s|$)', rest):
                violations.append(f'{rel}:{lineno}: `{action}{rest}` — not pinned to a SHA1')

            # Rule 2: must end with an inline version comment (# vX.Y.Z)
            if not re.search(r'\s#\sv\d+\.\d+\.\d+\s*$', rest):
                violations.append(f'{rel}:{lineno}: `{action}` — missing inline version comment (# vX.Y.Z)')

            # Rule 3: line immediately above must be the GitHub URL comment
            expected = f'{indent}# https://github.com/{action}'
            if prev != expected:
                violations.append(f'{rel}:{lineno}: `{action}` — line above must be: # https://github.com/{action}')

            prev = cur
    return violations


def check_format(workflows_dir: pathlib.Path) -> bool:
    """Print any format violations and return True if none found."""
    violations = _find_format_violations(workflows_dir)
    for v in violations:
        print(f'  {RED}{v}{RESET}')
    return len(violations) == 0

# ─── Fix ──────────────────────────────────────────────────────────────────────

def fix_file(filepath: pathlib.Path, cache: Cache) -> bool:
    """
    Fix all GitHub Actions format violations in a single workflow file in-place.
    Returns True if the file was modified.
    Expected format:

    # https://github.com/page-of-the-github-action
    uses: github/action@sha1 # vX.Y.Z
    """
    lines    = filepath.read_text().splitlines()
    out      = []
    modified = False

    for cur in lines:
        m = ACTION_RE.match(cur)
        if not m:
            out.append(cur)
            continue

        indent  = m.group('indent')
        action  = m.group('action')
        subpath = m.group('subpath')
        rest    = m.group('rest')
        sha     = ''
        tag     = ''

        sha_m = re.match(r'^@([0-9a-f]{40})', rest)
        if sha_m:
            # Already has a SHA.
            sha   = sha_m.group(1)
            tag_m = re.search(r'\s#\s(v\d+\.\d+\.\d+)\s*$', rest)
            if tag_m:
                tag = tag_m.group(1)   # version comment present — keep it
            else:
                tag = cached_sha_to_tag(action, sha, cache)  # look up the tag
        else:
            ref_m = re.match(r'^@(\S+)', rest)
            if ref_m:
                # Floating tag ref (e.g. @v4) — resolve to SHA + full semver.
                ref = ref_m.group(1)
                sha = cached_tag_to_sha(action, ref, cache)
                if sha:
                    tag = cached_sha_to_tag(action, sha, cache)

        if not sha or not tag:
            print(f'  {YELLOW}warning:{RESET} could not resolve {action}{rest} — skipping', file=sys.stderr)
            out.append(cur)
            continue

        fixed_uses  = f'{indent}uses: {action}{subpath}@{sha} # {tag}'
        url_comment = f'{indent}# https://github.com/{action}'

        # Ensure the URL comment immediately precedes this uses: line.
        if out:
            prev_out = out[-1]
            if prev_out == url_comment:
                pass  # already correct
            elif re.match(r'^\s*#\shttps://github\.com/', prev_out):
                out[-1] = url_comment  # wrong URL comment — fix it
                modified = True
            else:
                out.append(url_comment)  # no URL comment — insert one
                modified = True
        else:
            out.append(url_comment)
            modified = True

        if fixed_uses != cur:
            modified = True
        out.append(fixed_uses)

    if modified:
        filepath.write_text('\n'.join(out) + '\n')
        return True
    return False


def fix_files(workflows_dir: pathlib.Path, cache: Cache) -> None:
    fixed = 0
    clean = 0
    for filepath in _workflow_files(workflows_dir):
        rel = filepath.name
        if fix_file(filepath, cache):
            print(f'  {GREEN}✓{RESET} fixed: {rel}')
            fixed += 1
        else:
            clean += 1
    if fixed == 0:
        print(f'  {GREEN}✓ no violations to fix{RESET}')
    else:
        print(f'\n  {fixed} file(s) updated, {clean} already clean')

# ─── Update ───────────────────────────────────────────────────────────────────

def update_files(workflows_dir: pathlib.Path, cache: Cache) -> None:
    updated = 0
    current_count = 0

    for repo, subpath, current_sha, current_tag in _scan_uses_lines(workflows_dir):
        # Tags live on the repo, not the subdir, so resolve versions against
        # `repo`; keep `subpath` only to rewrite the exact reference in place.
        display = f'{repo}{subpath}'
        latest  = cached_latest_tag(repo, cache)
        if not latest:
            print(f'  {RED}✗{RESET} {display:<45} could not resolve latest version')
            continue

        if version_gt(latest, current_tag):
            new_sha = cached_tag_to_sha(repo, latest, cache)
            if not new_sha:
                print(f'  {RED}✗{RESET} {display:<45} could not resolve SHA for {latest}')
                continue

            old = f'{repo}{subpath}@{current_sha} # {current_tag}'
            new = f'{repo}{subpath}@{new_sha} # {latest}'
            for fp in _workflow_files(workflows_dir):
                content = fp.read_text()
                if old in content:
                    fp.write_text(content.replace(old, new))

            print(f'  {GREEN}↑{RESET} {display:<45} {current_tag} -> {latest}')
            cache.latest[repo] = latest
            updated += 1
        else:
            current_count += 1

    if updated == 0:
        print(f'  {GREEN}✓ all actions already up to date{RESET}')
    else:
        print(f'\n  {updated} action(s) updated, {current_count} already current')

# ==============================================================================
# Shell scripts — extraction, shellcheck, reporting
# ==============================================================================

GHAS_RE          = re.compile(r'\$\{\{[^}]*\}\}')
ALLOWED_SHELLS   = {'bash', 'pwsh', 'python', 'sh', 'cmd', 'powershell'}
CHECKABLE_SHELLS = {'shell', 'bash'}

# ─── Extraction ───────────────────────────────────────────────────────────────

def _parse_workflow_files(workflows_dir: pathlib.Path, tmp_path: pathlib.Path) -> list:
    """
    Parse workflow YAML files, validate structure, and extract shell scripts.
    Shell scripts are written to tmp_path for shellcheck.
    Returns a list of result dicts (one per .yml file).
    """
    results = []

    for filepath in _workflow_files(workflows_dir):
        rel    = filepath.name
        stem   = filepath.stem
        result = {'file': rel, 'jobs': [], 'scripts': 0, 'errors': []}

        # ── YAML parse ────────────────────────────────────────────────────────
        try:
            with open(filepath) as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as exc:
            msg = 'invalid YAML'
            if hasattr(exc, 'problem_mark'):
                msg += f' (line {exc.problem_mark.line + 1})'
            result['errors'].append(msg)
            results.append(result)
            continue

        if not isinstance(doc, dict):
            result['errors'].append('root node is not an object')
            results.append(result)
            continue

        if 'jobs' not in doc:
            result['errors'].append('missing "jobs" property')
            results.append(result)
            continue

        if not isinstance(doc.get('jobs'), dict):
            result['errors'].append('"jobs" is not an object')
            results.append(result)
            continue

        # ── Jobs / steps ──────────────────────────────────────────────────────
        for job_name, job in (doc.get('jobs') or {}).items():
            job_result = {'name': job_name, 'steps': [], 'errors': []}

            if not isinstance(job, dict):
                job_result['errors'].append(f'"{job_name}" is not an object')
                result['jobs'].append(job_result)
                continue

            if 'steps' not in job:
                job_result['errors'].append('missing "steps" property')
                result['jobs'].append(job_result)
                continue

            if not isinstance(job.get('steps'), list):
                job_result['errors'].append('"steps" is not a list')
                result['jobs'].append(job_result)
                continue

            for step_idx, step in enumerate(job.get('steps') or []):
                step_name = f'step #{step_idx}'
                if isinstance(step, dict) and isinstance(step.get('name'), str):
                    step_name = step['name'].replace('|', ';')

                step_result = {'name': step_name}

                if not isinstance(step, dict):
                    step_result['error'] = f'step #{step_idx} is not an object'
                    job_result['steps'].append(step_result)
                    continue

                if 'run' not in step:
                    continue

                script = step['run'].rstrip('\n')
                script = GHAS_RE.sub('${GHAS_EXPR}', script)
                shell  = step.get('shell', 'bash')

                if shell not in CHECKABLE_SHELLS:
                    if shell not in ALLOWED_SHELLS:
                        step_result['error'] = (
                            f'invalid shell: {shell} '
                            f'(known: {", ".join(sorted(ALLOWED_SHELLS))})'
                        )
                        job_result['steps'].append(step_result)
                    continue

                job_safe    = re.sub(r'[^a-zA-Z0-9_-]', '_', job_name)
                script_name = f'{stem}__{job_safe}__step{step_idx:02d}.sh'
                (tmp_path / script_name).write_text(f'#!/bin/{shell}\n{script}\n')
                step_result['script'] = script_name
                result['scripts'] += 1
                job_result['steps'].append(step_result)

            result['jobs'].append(job_result)

        results.append(result)

    return results

# ─── Shellcheck ───────────────────────────────────────────────────────────────

def _parse_shellcheck_output(output: str) -> dict:
    """Parse shellcheck stdout into {filename: {line_info: error_text}}."""
    errors      = {}
    cur_file    = None
    cur_line    = None
    cur_content = []
    file_re     = re.compile(r'^In (.*\.sh) (line \d+):$')

    for line in output.splitlines():
        m = file_re.match(line)
        if m:
            if cur_file and cur_content:
                errors.setdefault(cur_file, {})[cur_line] = '\n'.join(cur_content)
            cur_file    = m.group(1)
            cur_line    = m.group(2)
            cur_content = []
            continue
        if cur_file is None:
            continue
        cur_content.append(line)

    if cur_content and cur_file:
        errors.setdefault(cur_file, {})[cur_line] = '\n'.join(cur_content)

    return errors

def _run_shellcheck(working_dir: pathlib.Path) -> dict:
    """Run shellcheck on all .sh files in working_dir."""
    script_paths = sorted(working_dir.glob('*.sh'))
    if not script_paths:
        return {}

    cmd = [
        'shellcheck',
        '--rcfile=dev/.shellcheckrc',
        *[str(path) for path in script_paths],
    ]

    proc = subprocess.run(
        cmd,
        cwd=ROOT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    return _parse_shellcheck_output(proc.stdout)

# ─── Reporting ────────────────────────────────────────────────────────────────

def _report_validation_results(results: list, shellcheck_errors: dict) -> bool:
    """Print per-file validation results. Returns True if no errors found."""
    ok = True

    for result in results:
        rel = result['file']

        if result['errors']:
            ok = False
            for err in result['errors']:
                print(f'  {RED}✗{RESET} {RED}{rel} — {err}{RESET}')
            continue

        file_printed      = False
        file_has_error    = False
        scripts_checked   = 0
        jobs_with_scripts = set()

        for job_result in result['jobs']:
            job_name    = job_result['name']
            job_printed = False

            if job_result['errors']:
                ok = False
                file_has_error = True
                if not file_printed:
                    print(f'  {RED}✗{RESET} {rel}')
                    file_printed = True
                for err in job_result['errors']:
                    print(f'       {RED}✗{RESET} {RED}job: {job_name} — {err}{RESET}')
                continue

            for step_result in job_result['steps']:
                step_name = step_result['name']

                if 'error' in step_result:
                    ok = False
                    file_has_error = True
                    if not file_printed:
                        print(f'  {RED}✗{RESET} {rel}')
                        file_printed = True
                    if not job_printed:
                        print(f'       job: {job_name}')
                        job_printed = True
                    print(f'          {RED}✗{RESET} {RED}step: {step_name} — {step_result["error"]}{RESET}')
                    continue

                if 'script' not in step_result:
                    continue

                script_name = step_result['script']

                if script_name not in shellcheck_errors:
                    scripts_checked += 1
                    jobs_with_scripts.add(job_name)
                    continue

                # Shellcheck failure
                ok = False
                file_has_error = True
                if not file_printed:
                    print(f'  {RED}✗{RESET} {rel}')
                    file_printed = True
                if not job_printed:
                    print(f'       job: {job_name}')
                    job_printed = True
                print(f'          {RED}✗{RESET} {RED}step: {step_name}{RESET}')
                for line_info, error_text in shellcheck_errors[script_name].items():
                    print(f'             on {line_info}:')
                    for error_line in error_text.split('\n'):
                        print(f'             {error_line}')

        if not file_has_error:
            if not scripts_checked:
                print(f'  {GREEN}✓{RESET} {rel}: structure valid, no shell scripts')
            else:
                job_word    = 'job'    if len(jobs_with_scripts) == 1 else 'jobs'
                script_word = 'script' if scripts_checked        == 1 else 'scripts'
                print(
                    f'  {GREEN}✓{RESET} {rel}: structure valid, '
                    f'{scripts_checked} {script_word} shellchecked across '
                    f'{len(jobs_with_scripts)} {job_word}'
                )

    return ok

# ─── Validation ───────────────────────────────────────────────────────────────

def validate_workflows(workflows_dir: pathlib.Path, run_shellcheck=None) -> bool:
    """
    Lint workflow YAML structure and run shellcheck on embedded shell scripts.
    Returns True if no errors found.
    """
    if run_shellcheck is None:
        run_shellcheck = _run_shellcheck
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = pathlib.Path(tmp_dir)
        results  = _parse_workflow_files(workflows_dir, tmp_path)
        shellcheck_errors = {}
        if any(r['scripts'] > 0 for r in results):
            shellcheck_errors = run_shellcheck(tmp_path)

    return _report_validation_results(results, shellcheck_errors)

# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    try:
        opts = parse_args(sys.argv[1:])
    except HelpRequested:
        print_help()
        sys.exit(0)
    except UsageError as e:
        print(f'error: {e}', file=sys.stderr)
        sys.exit(1)

    cache = Cache()

    try:
        workflows_dir = resolve_workflows_dir(opts.workflows_dir)
    except UsageError as e:
        print(f'error: {e}', file=sys.stderr)
        sys.exit(1)
    print(f'{BOLD}Scanning:{RESET} {workflows_dir}')

    # ── Fix (must run before --update) ────────────────────────────────────────
    if opts.fix_format:
        print(f'\n{BOLD}Fixing:{RESET}')
        fix_files(workflows_dir, cache)

    # ── Update ────────────────────────────────────────────────────────────────
    if opts.update:
        print(f'\n{BOLD}Updating:{RESET}')
        update_files(workflows_dir, cache)

    # ── Format check ──────────────────────────────────────────────────────────
    print(f'\n{BOLD}Format:{RESET}')
    format_ok = check_format(workflows_dir)
    if format_ok:
        print(f'  {GREEN}✓ all actions properly formatted{RESET}')

    # ── Lint ──────────────────────────────────────────────────────────────────
    print(f'\n{BOLD}Lint:{RESET}')
    validate_ok = validate_workflows(workflows_dir)

    # ── Updates check (opt-in) ────────────────────────────────────────────────
    up_to_date = 0
    outdated   = 0
    errors     = 0
    if opts.report_outdated:
        print(f'\n{BOLD}Updates:{RESET}')

        seen_repo_tag = set()
        for repo, _subpath, _sha, current_tag in _scan_uses_lines(workflows_dir):
            if (repo, current_tag) in seen_repo_tag:
                continue
            seen_repo_tag.add((repo, current_tag))

            latest = cached_latest_tag(repo, cache)
            if not latest:
                print(f'  {repo:<50} {RED}✗ could not resolve latest version{RESET}')
                errors += 1
                continue

            if version_gt(latest, current_tag):
                print(
                    f'  {repo:<50} current: {YELLOW}{current_tag:<10}{RESET}  '
                    f'latest: {GREEN}{latest:<10}{RESET}  {YELLOW}⚠ update available{RESET}'
                )
                outdated += 1
            else:
                print(
                    f'  {repo:<50} current: {current_tag:<10}  '
                    f'latest: {latest:<10}  {GREEN}✓{RESET}'
                )
                up_to_date += 1

    # ── Summary ───────────────────────────────────────────────────────────────
    print()
    parts = []
    if not format_ok:
        parts.append(f'{RED}format violations found{RESET}')
    if not validate_ok:
        parts.append(f'{RED}lint errors found{RESET}')
    if opts.report_outdated:
        if errors > 0:
            parts.append(f'{RED}{errors} resolution error(s){RESET}')
        parts.append(f'{GREEN}{up_to_date} up to date{RESET}')
        if outdated > 0:
            parts.append(f'{YELLOW}{outdated} outdated{RESET}')

    print(', '.join(parts))

    fail = not (format_ok and validate_ok)
    if opts.report_outdated:
        fail = fail or outdated > 0 or errors > 0
    if fail:
        sys.exit(1)


if __name__ == '__main__':
    main()
