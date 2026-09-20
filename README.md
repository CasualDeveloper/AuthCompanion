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
sudo -v
authcompanion setup --yes
```

The Homebrew formula installs both component formulas as dependencies. Run
AuthCompanion as your login user, without `sudo`. Authorize `sudo` directly
before setup. AuthCompanion invokes only `sudo -n` commands, which tell sudo to
fail instead of requesting a password. Component input is also connected to
`/dev/null`. AuthCompanion never reads or stores your administrator password.

Setup performs these operations in order:

1. Read pinentry-companion's passive plan.
2. Ask pam-companion to validate its setup with `--dry-run`.
3. Configure or adopt pinentry-companion's GPG setup.
4. Configure pam-companion and verify its health.
5. Verify the visible PAM policy and module postcondition.

The related privileged commands reuse the short-lived authorization created by
`sudo -v`. If it is missing or expires, AuthCompanion stops and asks you to run
`sudo -v` again instead of presenting its own password prompt.

If GPG already points to a different pinentry and you intend to replace it,
review the plan and use the explicit takeover form:

```sh
authcompanion setup --take-over --yes
```

## Check and restore

```sh
authcompanion status
sudo -v && authcompanion doctor
sudo -v && authcompanion restore --yes
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

If setup stops after pinentry-companion commits, AuthCompanion preserves the
observed component state and reports `manualRequired`. It does not use ordinary
component restore as an automatic undo: restore targets each component's
recorded enrollment baseline, which may predate the current suite invocation.
Run status and doctor before deciding whether to retry setup or explicitly
restore the enrolled configuration.

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

Accepted JSON operations use schema version 1 and contain exactly one document
on standard output. Some malformed invocations currently return only an error
on standard error. Exit status `0` means success or a non-blocking warning, `1`
means an operational error or conflict, and `2` means the invocation is
invalid.

AuthCompanion resolves only the fixed Homebrew `opt` locations for the two
formulas, verifies that they resolve inside their respective Cellars, and
requires the supported component versions. It never searches `PATH`, accepts
an executable override, or builds a shell command.

## Using the system from an agent

Start with the [current agent guide](docs/agent-guide.md). It explains which
commands are passive, what their evidence proves, and when a person needs to
authorize or authenticate. Configuration, lifecycle ownership, and successful
Touch ID/Watch authentication are different facts.

The [system design](docs/design.md), [proposed machine contract](docs/agent-contract.md),
and [sequential implementation plan](docs/plans/2026-09-16-agent-operability.md)
describe the next interfaces. Proposed commands and stronger recovery guarantees
in those documents are not features of the current release.

## Requirements and build

- macOS 14 or newer
- `pinentry-companion` 0.2.0
- `pam-companion` 0.1.1
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
./Scripts/verify-release.sh dist/authcompanion-0.1.2.tar.gz
```

See [RELEASING.md](RELEASING.md) for the release and single live setup gate.

## How it was built

AuthCompanion was developed with Codex and GPT-5.6 as engineering tools. Codex
helped inspect the existing component code, implement and test the Swift 6 PAM
lifecycle manager and orchestration CLI, and exercise the packaging, release, recovery,
and rollback paths. GPT-5.6 was used to reason through the security model and
failure cases, especially partial PAM commits, configuration drift, and how to
prove that a rollback completed.

The architecture and product decisions remained human-led, and every Touch ID,
Apple Watch, GPG-signing, and `sudo` path was verified on real Mac hardware.
Neither Codex nor GPT-5.6 is part of the shipped product: AuthCompanion makes no
model calls at runtime.

## Privacy

AuthCompanion has no daemon, network service, telemetry, or credential store.
The component tools delegate device-owner authentication to macOS.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).
