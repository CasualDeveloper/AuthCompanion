# Machine control contract: proposed design

This is a design for future releases, not commands already available.
[The agent guide](agent-guide.md) lists the shipped interfaces.
[System design](design.md) owns the architecture; each component repository
owns its schemas, validators, transactions, and authentication behavior.

The common contract is semantic, not a shared runtime dependency. Use a small
vocabulary across products while allowing component-specific state and
independent schema versions. Human and machine output describe the same result.

## Discover without touching authentication state

Proposed `describe --format json` returns compiled interface metadata without
resolving dependencies, reading configuration, invoking sudo, or probing
authentication. Its small version-1 bootstrap schema includes product version,
supported operation/schema pairs, exact argument forms, effect classes, target
scope, authority, and local schema references. It works in degraded
installations. Do not embed every fixture or schema in the default response.

Use the same typed command definitions for help and description where practical.
Avoid a second handwritten command registry. Describe is distinct from status:
supported capability is static; current availability is observed. Advertised
argument templates are documentation. The coordinator selects from its own
closed vocabulary and fixed resolver, never executes arbitrary advertised argv.

Existing `--format json` contracts remain unchanged during migration. New
incompatible shapes use explicit `--schema-version N`; pinentry and
AuthCompanion move to a new major schema, while PAM publishes its first.
Numbers are local to each interface, not product versions or suite-wide epochs.
Description advertises valid combinations and defaults. Legacy unqualified
invocations retain their original schema for the current product major.
Breaking default/removal requires a published product-major migration and a
compatible coordinator release. Do not assume all standalone consumers are
known. Never silently downgrade or retry another format after a mutation.

New command forms accept documented options in any order and provide subcommand
help; keep existing v1 argument forms valid. Machine consumers use declared
operation/option fields, not a growing collection of shell-specific recipes.

Recognized JSON mode in new interfaces returns exactly one bounded JSON document
on stdout, including usage, authorization, dependency, conflict, and recovery
errors. Exit 0 means the requested observation/operation completed, 1 means
operational failure or conflict, and 2 means invalid invocation. A successful
observation may still report unhealthy or unknown state. Process termination
can prevent any envelope; absence is never success. stderr carries bounded,
redacted diagnostics, never required machine semantics.

## Operation vocabulary and effects

| Operation | Scope and contract |
| --- | --- |
| `describe` | Static metadata; no managed-state reads or writes |
| `status` | Passive snapshot, explicit unknowns, suggested next observations |
| `plan [setup|restore|uninstall]` | Passive preview of one intention; the documented no-argument default remains setup |
| `setup` | Own the planned configuration transition; explicit machine confirmation |
| `restore` | Restore the recorded baseline with the owner's drift checks |
| `uninstall --prepare` | Prove removal is safe after restoration; no package/cache deletion |
| `doctor` | Configuration checks with evidence and privilege requirements exposed |
| `doctor auth` | Pinentry's explicit human-interactive probe; never hidden in passive commands |
| `cache purge` | Pinentry-only secret deletion, separately authorized |

Do not manufacture symmetrical commands where they serve no purpose. PAM does
not acquire a custom authentication probe; its end-to-end check remains an
explicit user-operated sudo command. AuthCompanion is not a cache or Homebrew
manager. Proposed suite uninstall preparation delegates to the owners only
when removal of those components is the stated intention.

Each operation declares its effects and affected resources: observation, user
configuration, machine configuration, interactive authentication, secret deletion,
or package management. Administrator inspection is read-only for managed state
but is still a privilege boundary. User consent, available process privilege,
and machine confirmation are different conditions.

Passive status/plan never invoke sudo, access Keychain items, change preferences,
configuration or journals, reload gpg-agent, or launch UI. They do not create
state directories or take a write-producing lifecycle lock. Private bounded
process-capture storage, where needed by the coordinator, is not a lifecycle
write and is promptly discarded.

PAM's new unprivileged machine status/plan inspect only public policy. They
report private lifecycle state as unknown and the plan as `observational`.
Explicit read-only inspection through `sudo -n` can supply root-validated
evidence and an `authoritative` plan. Only a complete authoritative plan can
supply mutation preconditions. Root-only records stay root-only. Existing root
human commands retain their behavior.

## State and evidence

Keep these facts separate instead of compressing them to one healthy label:

- **Installation:** executable identity, product version, supported contract,
  and compatibility decision. Location establishes the supported installation,
  not cryptographic proof of publisher identity.
- **Target:** user or machine scope, selected GPG home where relevant, and the
  account-shared preference affected by a GPG-home change.
- **Configuration:** aligned, absent, foreign, ambiguous, or unknown.
- **Ownership:** managed, untracked, released, or unknown, with drift and recovery
  availability reported independently.
- **Authentication:** not probed, available/unavailable according to a named
  capability check, or an explicitly observed authentication result. Include
  context and time; a capability check cannot promise eventual authentication.
- **Evidence:** owning component, observed resources, visibility, and whether
  observation was complete or detected concurrent change.

An unprivileged view of native PAM might contain this fragment:

```json
{
  "configuration": "aligned",
  "ownership": "unknown",
  "evidence": {"source": "publicPolicy", "complete": false},
  "authentication": {"state": "notProbed"},
  "nextActions": [{"id": "inspectManagedPAM", "authority": "administrator"}]
}
```

This is an illustrative fragment, not a final JSON Schema. Add valid and invalid
fixtures before a consumer depends on a wire shape. Partial suite discovery
still reports the present component when the other is missing. Missing binary,
unsupported contract, unreadable journal, invalid response, and unavailable
authentication need distinct diagnostics.

## Plans are evidence-bound previews

A plan includes intention, scope, affected resources, before/after summaries,
required authority, blockers, actions, and reversibility. Exclude configuration
and secret contents. A suite plan preserves each component's evidence and
orders dependencies. It cannot turn incomplete PAM evidence into readiness.

Proposed `--expect-state TOKEN` binds a machine mutation to the reviewed
component, product/schema and binary identity, operation, normalized options
(including takeover), target identity, relevant state/journal generation, and
planned effects. Clients treat it as opaque. It is not authorization and cannot
encode arbitrary privileged commands or paths. Keep it out of public reports.
An observational plan cannot issue a token covering inaccessible state.

The owner validates the expectation under its existing transaction lock before
any lifecycle write, including automatic recovery of an earlier transaction.
If recovery is needed before a complete plan is possible, return
`recoveryRequired` and plan that recovery explicitly. Never recover first and
then call a mismatched request an untouched stale plan.

The owner also validates each resource immediately before replacement, retaining
existing safe-open, metadata, policy, compare-and-swap, and postcondition checks.
Hold the lock
through durable result-state persistence. For root operations, create and
verify authoritative preconditions inside root inspection/application without
exposing private journal metadata.

A component lock serializes cooperating invocations; it cannot lock out editors,
Homebrew, or other tools. Do not claim multi-file atomicity against those
writers. If drift occurs before any write, return stale with no mutation. If
it occurs after a partial transition, report and recover that transition under
the normal component rules; never label it an untouched stale plan.

The token is a state-equality guard, not a single-use authorization or proof that
nothing happened between observations. Managed transitions change the recorded
generation while owner evidence survives, even if configuration bytes return
to an earlier value. Full release can delete that record. Identical untracked
state, including after full restore, can legitimately produce the same token;
no global history service or tombstone registry detects invisible external
A-to-B-to-A edits. Fresh permission and all write-time checks still apply.

Retain existing human setup workflows. New machine mutations require their
declared expectation and literal confirmation. Old schemas retain their prior
contract until migration. Stale state returns `plan.stale` and requires a new
plan, never silent application of a replacement plan. Changing GNUPGHOME,
takeover, binary identity, or intention invalidates the reviewed expectation.
Preview and apply share the component's transition logic.

## Results, partial work, and compensation

Preserve each component's result in suite output. Distinguish requested
completion from effects: `none`, `committed`, `reverted`, `partial`, or
`unknown`. Report verified postconditions and recovery availability. A boolean
`changed` is insufficient for failures; old v1 fields keep their historical
meaning rather than being silently reinterpreted.

Where needed, attempt identity and journal generation live in the owner's
existing record. They identify a bounded attempt and its recovery state, not
exactly-once execution or unlimited history. Persist what is needed to reconcile
a result before reporting commit. Snapshots need no persisted identifier.
An emitted receipt is a result document, not a suite database or bearer token.

Automatic reversal is allowed only when all of these are proven:

1. This invocation made the owned transition and the owner has the relevant
   before-state.
2. Current state and journal generation still match that transition.
3. Reversal preserves everything that predated this invocation, including
   earlier managed/adopted setup and account-shared preference dependencies.
4. The owner performs conditional reversal under its lock and verifies the
   resulting state.

Ordinary restore targets the enrollment baseline and does not satisfy this rule
by itself. Initially limit compensation to new enrollments where this invocation
created ownership and every resource transition being reversed, and the two
baselines coincide. Exclude adoption, migration, and pre-existing shared-preference
dependencies from initial automatic compensation. Return partial state otherwise,
without requiring generalized checkpoint history. Never compensate an unchanged
component or another invocation's work.

After crash, lost output, timeout, failed rollback, or expired sudo authority,
inspect the owners before deciding what can be retried. A missing receipt
forbids automatic compensation unless the owner can recover matching durable
attempt evidence. Fresh status alone does not prove attribution. An unfinished
transaction may require recovery; a complete partial installation may simply
need setup of the remaining component. Restoring everything is not the default.

The suite retains the setup order: authoritative PAM preflight before pinentry
mutation, then PAM application. It rechecks the PAM expectation before applying
it. Restore checks PAM first so a privileged failure leaves GPG untouched.
Neither ordering implies atomicity or permission to undo pre-existing state.

## Actionable errors without command injection

Diagnostics have stable namespaced codes, affected component/resource, concise
explanations, and typed next actions. An action includes its ID, intended effect,
authority, preconditions, and retry disposition: safe, reinspect, or human
decision. Commands use a closed operation vocabulary, known argument forms,
and trusted component roles resolved by the caller. Text is display data, never
an executable shell instruction. A version/describe response does not establish
trust in an arbitrary binary.

| Condition | Required next decision |
| --- | --- |
| Missing package | Name the Homebrew package; install only within the user's task |
| Unsupported contract/version | Report required and observed values; no automatic downgrade |
| `sudo.authorizationRequired` | Person authorizes sudo directly in the invoking terminal |
| `plan.stale` | Reobserve and compare new effects to the authorized intention |
| Foreign configuration | Explain takeover and restoration; never append takeover automatically |
| State lock busy | Bounded observation retry; avoid competing mutations |
| Invalid/truncated result or timeout | Effects unknown; inspect before retry or compensation |
| Unavailable/drifted recovery record | Preserve state; follow the owner's explicit recovery guidance |
| Authentication not probed | Stop if configuration was the question; request a human check only if needed |

Technical repeatability does not supply user authority. Do not use endless
retries, cache resets, or repeated biometric approval to obtain a green result.
A sudo timestamp in another terminal is not assumed reusable by this process.

## Bounded execution and compatibility

The coordinator uses absolute resolved executables, argument arrays, null stdin
for machine commands, and non-interactive sudo. Bound both output streams while
the child runs. Give observations and mutations separate finite deadlines and
drain streams without deadlock. Cancellation permits a bounded cooperative stop;
forced termination makes effects uncertain. Never delete locks or journals to
force progress, and establish whether a timed-out writer is still active before
starting another mutation.

Cache static description within one invocation while binary identity is
unchanged. Check target state and authority at mutation time. Binary replacement
invalidates prior compatibility evidence. Document the local-install trust
assumption instead of treating Cellar containment as signature verification.

Compatibility requires a supported installation, an accepted product-version
range, and the required schemas/capabilities. An advertised schema is not enough.
Keep exact product pins until conformance tests justify a bounded range.
Unknown effect/recovery values block mutation. New schema majors need explicit
consumer support.

PAM owns its policy interpretation and privileged evidence. Retire AuthCompanion's
duplicate PAM parser after it consumes the owner contract. Retain v1 support for
the published migration period, not an undocumented indefinite fallback.

## Compounding evidence with a small maintenance cost

Bundle schemas, a small command reference, and version-bound examples with each
owning release so the installed interface works offline. Record contract
versions and tested dependency sets beside artifact checksums. The tap must
validate the resolved suite combination as well as individual binaries.

Each new failure class gets the smallest synthetic fixture and owner-level
regression that explains it. Consumer tests use producer fixtures from a pinned
revision or verified release, never a sibling checkout. Cross-product tests
cover externally relevant boundaries without repeating component test matrices.

Caller-retained receipts support handoff; export is explicit and redacted.
Historical evidence includes versions, scope, and invalidation conditions.
It never authorizes a future action or proves current state. Exclude passphrases,
key material, full GPG configurations, Keychain inventories, private account
identifiers, and raw sudo/authentication transcripts.
