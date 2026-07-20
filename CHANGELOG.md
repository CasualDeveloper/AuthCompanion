# Changelog

## 0.1.0 - 2026-07-20

### Added

- Swift 6 command-line coordinator for pinentry-companion 0.2.0 and
  pam-companion 0.1.0.
- Passive `status` and `plan` commands that never invoke sudo or modify state.
- Explicitly confirmed `setup` and `restore` commands with component-owned
  transactions and compensating rollback.
- Root refusal so user-scoped GPG operations cannot accidentally target root's
  home directory.
- Stable schema-versioned JSON output alongside concise human output.
- Fixed Homebrew dependency discovery, exact component version checks, and
  shell-free process execution.
- Universal arm64 and x86_64 ad hoc hardened-runtime release archives for
  macOS 14 or newer.

### Security

- Accept component executables only when Homebrew's fixed `opt` paths resolve
  inside the expected formula Cellars.
- Inspect visible PAM objects without following symlinks and reject unsafe,
  writable, non-root-owned, malformed, or oversized state.
- Validate pinentry machine envelopes, exit-status agreement, plan-state
  consistency, and lifecycle mutation invariants before acting on them.
- Restore PAM before pinentry after a post-commit PAM verification failure and
  report any unproven rollback as manual recovery required.
