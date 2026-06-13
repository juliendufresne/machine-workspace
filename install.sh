#!/usr/bin/env sh
set -eu

# Download-and-pipe bootstrap for the workspace tool. Clones the repository into
# ${XDG_DATA_HOME:-$HOME/.local/share}/workspace and runs its bin/workspace.
# Replayable: when that directory already holds this repository it fast-forwards it
# with `git pull --ff-only` instead of cloning, then runs bin/workspace again.
#
# Strict POSIX sh on purpose: it is meant to be fetched and piped straight into
# `sh` (see the README), so it must run under dash and busybox ash, not only bash.
# No bashisms, no `pipefail`. bin/workspace itself requires bash >= 4.2, so this
# script verifies a suitable bash is present before handing off to it.

# ─── Functions ───────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   require_bash
#
# Description:
#   Succeed when a bash new enough for bin/workspace (>= 4.2) is on PATH.
#   Prints actionable guidance to stderr and fails otherwise. Reads the
#   version from a bash subprocess so this POSIX shell need not understand
#   BASH_VERSINFO itself.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when a bash >= 4.2 is on PATH
#   1 when bash is missing or too old
#
# Example:
#   require_bash
#--------------------------------------------------
require_bash() {
  if ! command -v bash > /dev/null 2>&1
  then
    printf 'install: bash is required by bin/workspace but was not found on PATH.\n' >&2

    return 1
  fi

  version="$( bash -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null )" || version=''
  major="${version%%.*}"
  minor="${version#*.}"

  if [ -z "${major}" ] || [ "${major}" -lt 4 ] || { [ "${major}" -eq 4 ] && [ "${minor}" -lt 2 ]; }
  then
    printf 'install: bin/workspace requires bash >= 4.2 (found %s).\n' "${version:-unknown}" >&2
    printf 'On macOS install a newer bash, e.g. brew install bash\n' >&2

    return 1
  fi
}

#--------------------------------------------------
# Function:
#   normalize_git_url <url>
#
# Description:
#   Reduce a git remote URL to its bare "owner/repo" identity and print it to
#   stdout, so two URLs that point at the same repository compare equal whatever
#   the transport. Strips a trailing ".git", any "scheme://" prefix, an scp-style
#   "host:path" colon and any leading path, keeping only the final two path
#   segments. Handles the HTTPS form, both SSH forms and host aliases.
#
# Arguments:
#   <url>  The git remote URL to normalize
#
# Returns:
#   0 always
#
# Example:
#   normalize_git_url 'git@github.com:owner/repo.git'
#--------------------------------------------------
normalize_git_url() {
  url="$1"

  url="${url%.git}"
  url="${url%/}"
  url="${url#*://}"

  # scp-style "git@host:owner/repo": turn the first ':' into '/'.
  case "${url}" in
    *:*) url="${url%%:*}/${url#*:}" ;;
    *) ;;
  esac

  repo="${url##*/}"
  url="${url%/*}"
  owner="${url##*/}"

  printf '%s/%s\n' "${owner}" "${repo}"
}

#--------------------------------------------------
# Function:
#   same_repo <dir>
#
# Description:
#   Succeed when <dir> is a git working tree whose "origin" remote points at the
#   repository this script installs, comparing by normalized "owner/repo" so the
#   transport (HTTPS or SSH) does not matter. A directory that is not a git
#   repository, or that has no "origin" remote, is not a match. Runs git
#   read-only.
#
# Arguments:
#   <dir>  The directory to inspect
#
# Returns:
#   0 when <dir>'s origin matches this repository
#   1 when <dir> is not a git repository, has no origin, or points elsewhere
#
# Example:
#   same_repo "${install_dir}"
#--------------------------------------------------
same_repo() {
  dir="$1"

  remote_url="$( git -C "${dir}" remote get-url origin 2>/dev/null )" || return 1
  remote_id="$( normalize_git_url "${remote_url}" )"
  self_id="$( normalize_git_url "${REPOSITORY_URL}" )"

  [ "${remote_id}" = "${self_id}" ]
}

# ─── Main ────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   main [args...]
#
# Description:
#   Bring the repository in the XDG data directory up to date and run its
#   bin/workspace. Requires git and a bash >= 4.2 (to run bin/workspace),
#   checking both up front so it fails before touching anything. Replayable:
#   when the install directory is absent it clones; when it already holds this
#   repository it fast-forwards it with `git pull --ff-only`; either way it then
#   runs bin/workspace. Refuses an install directory that exists but holds a
#   different repository. Prints progress to stdout and errors to stderr, and
#   has the side effects of creating the install directory, cloning or pulling
#   into it, and executing bin/workspace.
#
# Arguments:
#   args...  Passed through to bin/workspace
#
# Returns:
#   0 on success
#   1 when git is missing, bash is unsuitable, the clone or pull fails, or the
#     install directory holds a different repository
#
# Example:
#   main "$@"
#--------------------------------------------------
main() {
  install_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/workspace"

  if ! command -v git > /dev/null 2>&1
  then
    printf 'install: git is required but was not found on PATH.\n' >&2

    return 1
  fi

  require_bash || return 1

  if [ -d "${install_dir}/.git" ]
  then
    printf 'Updating %s\n' "${install_dir}"
    if ! git -C "${install_dir}" pull --ff-only
    then
      printf 'install: git pull --ff-only failed.\n' >&2

      return 1
    fi
  elif [ -e "${install_dir}" ] && ! same_repo "${install_dir}"
  then
    cat >&2 <<EOF
install: ${install_dir} already exists.

Refusing to overwrite it. Remove or move it aside, then re-run this script.
EOF

    return 1
  elif [ ! -e "${install_dir}" ]
  then
    parent_dir="$( dirname "${install_dir}" )"
    mkdir -p "${parent_dir}"

    printf 'Cloning %s into %s\n' "${REPOSITORY_URL}" "${install_dir}"
    if ! git clone "${REPOSITORY_URL}" "${install_dir}"
    then
      printf 'install: git clone failed.\n' >&2

      return 1
    fi
  fi

  printf 'Running %s\n' "${install_dir}/bin/workspace"
  "${install_dir}/bin/workspace"
}

# ─── Constants / globals ─────────────────────────────────────────────

# Canonical HTTPS clone URL - HTTPS, not SSH, so the bootstrap works on a fresh
# machine with no key configured; the remote can be switched afterwards.
REPOSITORY_URL='https://github.com/juliendufresne/machine-workspace.git'

# ─── Execute ─────────────────────────────────────────────────────────

# Run only when executed directly, not when sourced by the shellspec spec
# (which sets TEST_FLAG before Include). POSIX sh has no BASH_SOURCE, so gate on
# that flag the way the rest of the repository already does.
[ -n "${TEST_FLAG:-}" ] || main "$@"
