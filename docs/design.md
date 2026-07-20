# AuthCompanion CLI v1 design

AuthCompanion 0.1 is a Homebrew-installed Swift CLI that composes the released
`pinentry-companion` and `pam-companion` products. It does not embed either
component, edit GPG or PAM files, own another lifecycle journal, ship a root
helper, or require a Developer ID certificate. Each component remains the sole
owner of its configuration and rollback state.

## Product shape

The first release is deliberately CLI-only. A GUI can later invoke the same
core, but it is not required to install or understand the suite and would add
distribution complexity without improving the authentication paths.

The supported component contracts are initially exact:

- `pinentry-companion` 0.2.0 machine contract v1;
- `pam-companion` 0.1.0 fixed CLI and exit-status contract.

The Homebrew formula depends on both formulas. Runtime discovery resolves only
their fixed `opt` paths below the Homebrew prefix; AuthCompanion never searches
`PATH` or accepts an arbitrary executable override in production.

## Commands

```text
authcompanion status [--format json]
authcompanion plan [--format json]
authcompanion setup --yes [--take-over] [--format json]
authcompanion restore --yes [--format json]
authcompanion doctor [--format json]
authcompanion --version
authcompanion --help
```

Human output is the default. JSON output is a stable versioned contract.
Mutations require the literal `--yes`; AuthCompanion itself must run as the
login user, not root. The user authorizes `/usr/bin/sudo` directly with
`sudo -v`. AuthCompanion invokes `/usr/bin/sudo -n` only for the fixed
`pam-companion` executable and fixed lifecycle arguments, so sudo fails instead
of requesting a password when authorization is unavailable. Component
processes also receive `/dev/null` as standard input. No shipped coordinator
path reads an administrator password.

`status` and `plan` are passive. They invoke only pinentry-companion's passive
JSON endpoints and inspect the readable PAM policy/module paths. They never
invoke `sudo`, write files, reload GPG, access Keychain, or authenticate.

## Setup sequence

1. Read pinentry's passive plan and visible PAM state.
2. Verify an existing sudo authorization and run
   `sudo -n pam-companion setup --dry-run` before any mutation.
3. Run `pinentry-companion setup --yes --format json` (or its explicit
   `--take-over` form).
4. Run `sudo -n pam-companion setup`.
5. Run `sudo -n pam-companion doctor` and verify visible PAM postconditions.

If PAM setup fails after pinentry committed a change, AuthCompanion asks PAM to
recover its transaction and then invokes pinentry's exact machine restore. A
failed PAM recovery or failed or indeterminate pinentry rollback is reported as
manual recovery required. There is no speculative replay.

## Restore sequence

1. Verify an existing sudo authorization and run
   `sudo -n pam-companion restore --dry-run`.
2. Restore PAM.
3. Restore pinentry through its machine contract.

PAM is restored first so failure at the privileged boundary leaves the working
pinentry configuration untouched. A later pinentry failure is safe to retry
through the component's compare-and-swap restore command.

## Distribution

AuthCompanion is distributed as a universal, ad hoc hardened-runtime archive
for macOS 14 or newer, with checksums and GitHub build provenance. The project
does not claim Developer ID signing, notarization, or an installer package.
