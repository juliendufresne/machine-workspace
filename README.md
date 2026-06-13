# workspace

Stamp a git identity plus SSH and GPG access onto a machine, scoped to one or
more directory trees.

A "workspace" is a directory tree (for example `~/Workspace/Personal` or
`~/Workspace/Acme`) with its own git identity: its own `user.name` and
`user.email`, its own GPG signing key, and its own SSH key per provider. Point
the tool at a tree and any repository you clone under it commits, signs, and
authenticates as that identity, while a repository under another tree uses
another. One machine can carry a personal identity and a work identity side by
side without them ever crossing.

The tool is OS-agnostic and single-purpose. It writes only under `$HOME`: no
package manager, no sudo. Everything it touches is your own git and ssh
configuration and the keys it generates.

## What it does

- **Per-tree git identity.** Each workspace gets its own `.gitconfig` inside the
  tree, pulled in by a conditional `includeIf` block in `~/.gitconfig`, so git
  picks the right name, email, and signing key by where the repository lives.
- **GPG signing.** A signing key per identity, with `commit.gpgsign` and
  `tag.gpgsign` on, so every commit and tag under the tree is signed.
- **SSH access per provider.** An SSH key and a `~/.ssh/config` host alias per
  provider (`github.com-personal` and the like), so a clone through the alias
  authenticates with exactly that identity's key and no other.
- **Idempotent and reversible.** Re-running converges to the same state; every
  machine-managed edit sits between labelled markers, so an uninstall restores
  your files exactly.

## Quick start

On a fresh machine, download `install.sh` and then run it. It is plain
POSIX sh (it runs under dash and busybox ash, not only bash), clones this
repository into `${XDG_DATA_HOME:-$HOME/.local/share}/workspace`, and then runs
`bin/workspace`. It is replayable: re-running it fast-forwards an existing clone
with `git pull --ff-only` before running `bin/workspace` again, so the same two
steps bootstrap and refresh.

```sh
# curl
curl -fsSL https://raw.githubusercontent.com/juliendufresne/machine-workspace/main/install.sh -o install.sh
sh install.sh

# wget
wget -qO install.sh https://raw.githubusercontent.com/juliendufresne/machine-workspace/main/install.sh
sh install.sh
```

Downloading to a file and running it as two steps lets you read the script
before you run it. Piping the download straight into `sh` works too: the prompts
read from `/dev/tty`, not standard input, so a pipe taking over stdin does not
stop them from reaching you.

`git` is required to clone, and `bin/workspace` needs bash >= 4.2: the script
checks for a suitable bash up front and tells you if it is missing or too old
(e.g. `brew install bash` on macOS). It never overwrites an existing install
directory: when that directory already holds this repository it fast-forwards it
in place, and when it holds something else it warns and stops.

Generating keys also needs `ssh-keygen` and `gpg` on `PATH`.

## Usage

`bin/workspace` takes one action, defaulting to `create`, and each action takes
an optional `[name]` that scopes it to a single workspace:

```sh
bin/workspace               # define and provision workspaces (default action)
bin/workspace create        # same as above
bin/workspace create Acme   # define (or edit) just Acme, then provision only it
bin/workspace remove        # choose workspaces to remove and whether to drop their keys
bin/workspace remove Acme   # remove just Acme (after asking about its keys)
bin/workspace show          # report each workspace's gitconfig link, directory, and ssh aliases
bin/workspace show Acme      # report just Acme
```

`create` with no name opens a "Workspace creation" menu: it lists the
workspaces from previous runs so you can edit them, lets you create new ones, and
provisions each workspace inline as you finish defining it before redrawing the
menu (there is no separate batch pass). For each one it asks for the path, the git
identity, the GPG key settings, and the SSH keys (a key's provider is chosen as
part of the SSH-key step), then generates the keys and writes the config.
Passphrases are asked for with a hidden prompt at the moment a key is generated,
kept only in memory, and never stored. Each public key is shown and, for a key
tied to a provider, blocks on an authentication probe until the provider
recognizes it. `create <name>`
skips the menu: it edits that workspace when it already exists, otherwise defines
it starting at the path question, and provisions only that one.

`remove` with no name opens a removal menu: a checklist of the registered
workspaces, plus a prompt for whether to also delete the generated keys (kept by
default, since their public halves may still be registered with a provider). It
unlinks the marked blocks from `~/.gitconfig` and `~/.ssh/config`, and removes a
workspace's directory only when it holds nothing but what the tool recorded
creating. `remove <name>` skips the checklist, asks only the keys question, and
removes just that one; it exits with status 2 when no such workspace exists.

`show` with no name reports, per workspace, whether its IncludeIf block is in
`~/.gitconfig`, whether its directory exists, and whether each host's SSH key
exists. `show <name>` reports just that one, exiting with status 2 when no such
workspace exists.

The SSH-key step `create` runs is also a standalone executable, `libexec/manage-ssh-keys`,
for managing keys without re-running the whole `create` flow. It is not a
`bin/workspace` verb; run it directly:

```sh
libexec/manage-ssh-keys        # ask which workspace the keys are for, or create one outside any workspace
libexec/manage-ssh-keys Acme   # manage just Acme's SSH keys
```

With no name it lists the registered workspaces plus an "outside any workspace"
choice. That choice generates a standalone key (with an optional `~/.ssh/config`
Host block) that is recorded in no registry, so the tool will not track, edit, or
remove it later; you manage and remove it by hand.

Each workspace that has an SSH key gets a managed `clone-repo` helper at its root.
A clone URL copied from a provider points at the bare host (`git@github.com:...`),
so it would authenticate with the default key rather than the workspace's; this
helper rewrites the clone to go through the workspace's host alias. Run it from the
workspace root in any of three shapes (it refuses, rather than falling back to the
default key, for a provider the workspace has no key for):

```sh
cd ~/Workspace/Personal
./clone-repo                                         # pick a managed provider, then enter owner/repo
./clone-repo https://github.com/owner/repo.git       # a full https or ssh URL
./clone-repo github owner/repo                        # a provider (or host, or alias) and owner/repo
```

It is a managed file, rewritten on every run, so edit the repo source
(`libexec/clone-repo`) rather than the copy.

`bin/enable-push` is a second standalone command, also not a `bin/workspace`
verb. Run from inside a git repository, it configures only that repository (never
your global git config) by reusing keys the machine already holds: it switches the
`origin` remote to one of the `~/.ssh/config` host aliases so you can push, points
`user.signingkey` at an existing GPG key, and sets the committer identity. It
takes no arguments and needs git, a working directory inside a git repository, and
an `origin` remote:

```sh
cd ~/Workspace/Acme/some-clone   # any clone whose pushes you want to enable
/path/to/machine-workspace/bin/enable-push
```

The interactive menus need a terminal. With no terminal (a piped or unattended
run) a bare `create` or `remove` cannot drive its menu, so it warns and exits
without changes. To run unattended, pass a `[name]`: every prompt then resolves to
its seeded default from the registry (and an empty passphrase), so a workspace
defined in a previous run is reprovisioned without questions.

