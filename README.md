# AuthCompanion

AuthCompanion sets up two independent macOS authentication tools with one
command:

- [`pinentry-companion`](https://github.com/CasualDeveloper/pinentry-companion)
  approves GPG signing with Touch ID or Apple Watch.
- [`pam-companion`](https://github.com/CasualDeveloper/pam-companion) approves
  `sudo` with Touch ID or Apple Watch.

AuthCompanion 0.1 is a Swift command-line tool. It coordinates the two released
components but does not duplicate their authentication or configuration code.

## Install and set up

```sh
brew install CasualDeveloper/tap/authcompanion
authcompanion status
authcompanion plan
authcompanion setup --yes
```

The Homebrew formula installs both component formulas as dependencies. Run
AuthCompanion as your login user, without `sudo`. During setup it invokes
`sudo pam-companion` for the PAM steps that require administrator access. It
never reads or stores your administrator password.

Setup performs these operations in order:

1. Read pinentry-companion's passive plan.
2. Ask pam-companion to validate its setup with `--dry-run`.
3. Configure or adopt pinentry-companion's GPG setup.
4. Configure pam-companion and verify its health.
5. Verify the visible PAM policy and module postcondition.

The related `sudo` commands run together, so macOS normally reuses the same
short-lived sudo authentication timestamp. AuthCompanion does not invalidate
that timestamp or force repeated authentication.

If GPG already points to a different pinentry and you intend to replace it,
review the plan and use the explicit takeover form:

```sh
authcompanion setup --take-over --yes
```

## Check and restore

```sh
authcompanion status
authcompanion doctor
authcompanion restore --yes
```

`status` and `plan` are passive. They do not invoke `sudo`, write files, reload
GPG, access the Keychain, or show an authentication prompt.

Restore asks pam-companion to restore its recorded system state before asking
pinentry-companion to restore the current user's recorded GPG state. A failure
at the privileged boundary therefore leaves the working GPG configuration
untouched.

## Component ownership and recovery

Each component owns its own state:

- pinentry-companion owns the current user's GPG configuration record;
- pam-companion owns the machine PAM transaction and its root-only rollback
  record;
- AuthCompanion stores no third lifecycle database.

If PAM fails after pinentry setup, AuthCompanion restores pinentry. If PAM was
already committed when its health check fails, AuthCompanion restores PAM first
and then pinentry. It reports `manualRequired` if either component cannot prove
its rollback.

## Commands and JSON output

```text
authcompanion status [--format json]
authcompanion plan [--format json]
authcompanion setup --yes [--take-over] [--format json]
authcompanion restore --yes [--format json]
authcompanion doctor [--format json]
authcompanion --version
authcompanion --help
```

JSON responses use schema version 1 and contain exactly one document on
standard output. Exit status `0` means success or a non-blocking warning, `1`
means an operational error or conflict, and `2` means the invocation is
invalid.

AuthCompanion resolves only the fixed Homebrew `opt` locations for the two
formulas, verifies that they resolve inside their respective Cellars, and
requires the supported component versions. It never searches `PATH`, accepts
an executable override, or builds a shell command.

## Requirements and build

- macOS 14 or newer
- `pinentry-companion` 0.2.0
- `pam-companion` 0.1.0
- Swift 6.3.3 for release archives
- macOS Command Line Tools for builds and packaging
- Xcode, or another toolchain containing XCTest, only for the test suite

```sh
swift build -c release
```

The Swiftly toolchain can build the product but does not include XCTest on this
machine. Run tests with an installed Xcode explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test -Xswiftc -warnings-as-errors
```

## Release integrity

The project does not currently use an Apple Developer Program membership.
Release binaries are universal, ad hoc signed with the hardened runtime, and
not notarized. The Homebrew formula pins the archive SHA-256 digest. Releases
also include checksums and GitHub build-provenance attestations.

Create and verify a local candidate without changing authentication state:

```sh
swiftly run ./Scripts/package-release.sh --allow-dirty
./Scripts/verify-release.sh dist/authcompanion-0.1.0.tar.gz
```

See [RELEASING.md](RELEASING.md) for the release and single live setup gate.

## Privacy

AuthCompanion has no daemon, network service, telemetry, or credential store.
The component tools delegate device-owner authentication to macOS.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).
