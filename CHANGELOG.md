# Changelog

## 0.2.0 - Unreleased

### Changed

- Accept pinentry-companion 0.2.0/0.2.1 and pam-companion 0.1.1/0.2.0 as an
  explicit rolling-upgrade set, validating each pinentry response against its
  observed executable version.
- Report observed component versions and preserve partial setup results instead
  of invoking enrollment restore as automatic per-operation compensation.
- Execute validated stable Homebrew opt paths and reject plans when PAM
  inspection is unavailable.
- Bound child execution and output, with private capture of both streams.

### Verification

- Cover all four component combinations and copied producer fixtures in the
  coordinator tests. Exact release-artifact and live gates remain required
  before publication.

## 0.1.2 - 2026-07-21

### Fixed

- Support pam-companion 0.1.1 and its native `pam_tid.so` lifecycle.
- Report the native Touch ID policy as configured while treating retired
  `pam_companion.so` and `pam_watchid.so` installations as migration state.

## 0.1.1 - 2026-07-21

### Fixed

- Require users to authorize sudo directly with `sudo -v` before setup,
  restore, or doctor.
- Run every coordinator-owned sudo command with `-n` so unavailable
  authorization fails instead of presenting a password prompt.
- Connect component standard input to `/dev/null`; no shipped coordinator path
  reads an administrator password.

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
