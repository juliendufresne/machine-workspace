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

