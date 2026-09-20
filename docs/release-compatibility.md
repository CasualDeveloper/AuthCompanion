# Release compatibility

The next source candidates are AuthCompanion 0.2.0, pinentry-companion 0.2.1,
and pam-companion 0.2.0. Version changes in source do not publish releases.
The last published set remains AuthCompanion 0.1.2, pinentry 0.2.0, and PAM 0.1.1
until the release gates pass and publication is explicitly performed.

## Bounded bridge

AuthCompanion 0.2.0 accepts exactly these combinations:

| pinentry-companion | pam-companion | Supported |
| --- | --- | --- |
| 0.2.0 | 0.1.1 | Yes |
| 0.2.1 | 0.1.1 | Yes |
| 0.2.0 | 0.2.0 | Yes |
| 0.2.1 | 0.2.0 | Yes |

The executable's allowlists in
[ComponentVersion.swift](../Sources/AuthCompanionCore/ComponentVersion.swift)
are authoritative. There is no open-ended semantic-version range, runtime
registry, latest-release lookup, or automatic downgrade. Unknown versions fail
before privilege checks or lifecycle commands.

The verifier returns the versions actually observed. Pinentry's status, plan,
and mutation envelopes must match that observed version and schema v1, including
the existing consistency checks on outcomes, effects, and exit codes.
Reports use observed versions rather than one compiled-in preferred version.
A changed version between probing and passive planning stops before mutation;
a mismatched mutation response requires inspection and is never retried or
automatically reversed.

## Common command surface

The bridge uses the commands already shared by both component generations:

- Pinentry status/plan/setup/restore JSON v1 and human doctor.
- PAM human setup/restore (including dry-run) and doctor, using their documented
  exit statuses rather than parsing stdout.

PAM 0.2.0 adds privileged JSON status/doctor. Consuming that interface is separate
follow-up work; its presence does not require an adapter just to keep the old
commands working. Structured PAM mutation results and public-policy observation
remain future work. This bridge does not claim those capabilities.

Each component still owns its lifecycle engine and recovery. The coordinator
preserves partial setup instead of treating ordinary enrollment restore as
undo-last. The bridge does not turn a configuration check into proof of current
Touch ID or Watch availability.

## Evidence and release order

The application tests cover all four pairs across status, setup, restore, and
doctor with recording runners. They verify the exact non-interactive PAM command
forms and version propagation. Consumer tests also read offline copies of
producer JSON fixtures, including the candidate's ownership and recovery
results. These are source-level checks, not proof that a release archive passed
a live lifecycle test.

The tap's CI and release-sync workflow additionally install the proposed formula
set, run the normal formula tests, and then run
`check-suite-compatibility.rb`. That guard:

1. Refuses root execution and setuid executables.
2. Probes all PAM command forms consumed by the coordinator without sudo,
   requiring their root-required refusal rather than an unknown-command error.
3. Runs passive suite status with a new, nonexistent GNUPGHOME.
4. Checks JSON identity/outcome, dependency diagnostics, and reported component
   versions against the installed executables. It also checks that the GPG
   target was not created.

There is one compatibility exception for bootstrapping the guard: published
AuthCompanion 0.1.2 omits PAM's version when public policy is not configured.
Only that coordinator with PAM 0.1.1 may omit it; the bridge must report both.
This exception describes a released response shape, not permission to accept
unknown versions.

Publish in this order after exact-artifact and applicable live gates:

1. Land and verify the tap guard against the currently published set.
2. Publish and promote AuthCompanion 0.2.0 while the component pins stay old.
3. Publish/promote either component candidate. The intermediate mixed pair must
   pass the same gate before tap sync pushes it.
4. Verify the final installed combination.

A rejected combination leaves the remote tap unchanged because the push step
runs only after the guard passes. Do not weaken or skip the guard to promote
an incompatible release.

Homebrew upgrades are not atomic. A user holding AuthCompanion 0.1.2 while
independently upgrading a component can get a version refusal; upgrade the
coordinator first. The existing authentication integrations do not run through
the coordinator. Arbitrarily held old coordinator versions are not promised
compatibility with future components.

The candidate version numbers reserve this tested bridge. Any additional
component behavior change before publication must rerun its owner tests and
the affected consumer checks. No release tag, public asset, or tap formula URL
should move merely because a source version was prepared.
