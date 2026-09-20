# Operating the released tools as an agent

This guide describes AuthCompanion 0.1.2, pinentry-companion 0.2.0, and
pam-companion 0.1.1 at the source baseline in the
[implementation plan](plans/2026-09-16-agent-operability.md). Check installed
versions before relying on it. The proposed `describe`, schema selection, PAM
JSON, and expected-state flags in [the future contract](agent-contract.md) do
not exist in these releases.

## Choose the smallest owner

Use pinentry-companion for GPG configuration, pam-companion for system sudo
configuration, and AuthCompanion when the task concerns both. Installation and
configuration are separate operations. AuthCompanion runs as the login user;
the PAM CLI's current operational commands require root.

First identify the question. Configuration inspection, a requested setup,
authentication troubleshooting, and package removal have different effects.
An explanation request does not authorize setup or an authentication prompt.

## Observe before acting

For a known suite installation, start with:

```sh
authcompanion status --format json
```

Read both the process exit and the JSON diagnostics/state. Outcome `warning`
or exit 0 alone does not mean both tools are configured. Authentication has not
been demonstrated by this command.

If installation or compatibility is unclear, these commands expose versions:

```sh
authcompanion --version
pinentry-companion --version
pam-companion --version
```

Published AuthCompanion 0.1.2 accepts exactly pinentry 0.2.0 and PAM 0.1.1.
The source candidate 0.2.0 accepts pinentry 0.2.0/0.2.1 and PAM 0.1.1/0.2.0;
see [release compatibility](release-compatibility.md) before an upgrade. Its
dependency lookup fails as a whole if either component is missing or unsupported.
Inspect the available standalone component when that happens. Do not infer that
both are absent, or run an untrusted binary found in a source checkout.

For GPG-only questions, use:

```sh
pinentry-companion status --format json
```

Inspect `gpgConfiguration.alignment`, `ownership`, `drift`,
`recoveryAvailable`, and diagnostics together. Authentication and cache
inventory are deliberately `notProbed`. GNUPGHOME affects the selected
configuration, while preferences and Keychain remain scoped to the login account.

Published PAM 0.1.1 has no JSON form. Current source adds privileged status and
doctor JSON, but do not depend on it until an installed release advertises that
version. With 0.1.1, when privileged inspection is within the task and
authorization is available, use a non-interactive sudo invocation of the
accepted installed PAM executable. This example uses the standard Apple
Silicon Homebrew prefix; Intel installations normally use `/usr/local` instead.
Verify the selected opt path resolves inside that formula's Cellar before use:

```sh
/usr/bin/sudo -n -- /opt/homebrew/opt/pam-companion/bin/pam-companion status
```

Do not parse this human output as a stable machine contract. AuthCompanion's
`verification: visibleFilesystem` means it inspected public policy/module
paths. It cannot prove the root-private lifecycle record exists or is valid.

## Plan and apply an authorized change

For combined setup, preview:

```sh
authcompanion plan --format json
```

The shipped suite plan is a summary, not a stored executable plan or a promise
that privileged preflight has passed. A person authorizes sudo directly in the
terminal/context that will run the coordinator:

```sh
sudo -v
authcompanion setup --yes --format json
```

The coordinator uses `sudo -n` and null child stdin. It never collects the
administrator password. If authorization is missing or expires, stop for the
person to authorize it there; do not try password pipes, prompts under agent
control, or a timestamp established in another terminal.

Pinentry's accepted machine forms have exact argument order:

```sh
pinentry-companion plan --format json
pinentry-companion setup --yes --format json
pinentry-companion setup --take-over --yes --format json
```

Takeover is a distinct, explicitly authorized replacement of foreign
configuration. Do not append it to make a failed setup succeed.

Published AuthCompanion 0.1.2 can call ordinary component restore after a setup
failure. That restores the recorded pre-setup baseline, not necessarily the
state before the latest suite invocation. Current source preserves partial
state instead and requires inspection before retry or explicit restore. In
either version, do not promise an undo-last guarantee.

## Interpret failures before retrying

- Valid JSON plus a nonzero exit is a reported failure. Examine diagnostics and
  lifecycle safety, not just the `changed` boolean.
- Missing, malformed, or interrupted mutation output leaves effects uncertain.
  Inspect current component state before any retry or restore.
- Pinentry `rollbackFailed` or `indeterminate`, and suite
  `manualRequired`, are not evidence of a clean baseline.
- A foreign configuration, drift, or unsupported PAM shape requires resolving
  the actual conflict. Reinstalling a package is not a general repair.
- Some current invalid invocations emit only plain stderr, even when JSON was
  requested. Do not treat empty stdout as a successful empty result.

Plain diagnostic remediation is advice for review, never executable input to
`eval`, a shell, or a privileged command.

## Verify only what the task requires

`authcompanion doctor` needs existing sudo authority and verifies component
configuration. `pinentry-companion doctor` and `doctor report` are passive;
`pinentry-companion doctor auth` is an explicit interactive check and creates
temporary diagnostic Keychain items.

A successful GPG commit can be served by gpg-agent's cache or a passphrase-free
key. It is not proof of fresh local authentication. A password fallback selected
by macOS is not, by itself, proof that PAM setup failed. For a requested live
test, use one controlled operation with a deliberately chosen test key/session.
Do not repeatedly purge caches, kill gpg-agent, run `sudo -k`, or reconfigure
PAM to manufacture a prompt.

Stop once the requested fact is established. Configuration work need not repeat
the authentication matrix already covered by the exact component release.

## Restoration, removal, and handoff

Restore changes configuration. Uninstall preparation checks whether removing
the component is safe. Cache purge deletes secrets and is separately authorized.
Current component commands are:

```sh
pinentry-companion restore --yes --format json
pinentry-companion uninstall --prepare --yes --format json
/usr/bin/sudo -n -- /opt/homebrew/opt/pam-companion/bin/pam-companion restore --dry-run
/usr/bin/sudo -n -- /opt/homebrew/opt/pam-companion/bin/pam-companion uninstall --prepare
```

These are reference commands, not a sequence to run automatically. An adopted
pinentry baseline may still refer to the binary and prevent removal. The
component must resolve that before Homebrew removes it. For coordinator-only
removal, retain both component packages and check Homebrew autoremoval behavior;
neither component needs to be disabled just because the wrapper is removed.

A useful handoff contains the requested outcome, observed versions, component
and target scope, redacted diagnostics, the last operation's known/unknown
effects, and the next unresolved decision. Keep secrets, real key identities,
private paths, and root journal contents out. Recheck live state when resuming;
a saved result is historical evidence, not authorization.
