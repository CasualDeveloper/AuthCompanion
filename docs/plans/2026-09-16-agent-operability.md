# Agent operability implementation plan

Status: implementation in progress. The source identities below describe the
starting point; the completed commits listed next are the current implementation
evidence.

## Progress through 2026-09-21

Completed and pushed:

- pinentry-companion `0f14db7`: reject configuration or preference changes
  made after transaction preparation, preserving the external edit and prior
  lifecycle record.
- pinentry-companion `cda1662`: preserve an already equivalent configured path
  when the plan says no change.
- pinentry-companion `6ba75f2`: distinguish real no-op setup from ownership
  recording and interrupted-restore recovery; correct the impossible adopted
  uninstall retry guidance.
- pam-companion `76cd46d`: add strict, privileged status/doctor JSON with six
  lifecycle conditions, redacted errors, schema, and fixtures. Mutation JSON
  and public-policy-only observation remain unimplemented.
- AuthCompanion `2e96617` and `4bfcecb`: execute validated stable Homebrew opt
  paths and fail plans whose PAM observation is unavailable.
- AuthCompanion `da41fe4`: preserve partial setup instead of using enrollment
  restore as speculative per-operation compensation.
- AuthCompanion `94eb0e6`: capture both child streams privately and enforce a
  live combined-output limit, deadline, and bounded termination.

Verified after the final code changes in each repository: pinentry 136 tests,
PAM 62 tests, and AuthCompanion 47 tests passed with warnings treated as errors;
the relevant release builds and format/diff checks passed. These are isolated
tests and builds, not live GPG, Keychain, PAM, or authentication gates.

Next implementation work:

The [release compatibility decision](../release-compatibility.md) now defines
the bounded 0.2.0 coordinator bridge. Source versions are reserved as pinentry
0.2.1, PAM 0.2.0, and AuthCompanion 0.2.0. The bridge keeps the shared existing
commands and explicitly accepts both old and candidate component versions;
consuming PAM JSON is not a prerequisite for this compatibility change.

1. Verify and promote the tap guard, then run the candidate artifact and
   applicable live gates before publishing the coordinator-first bridge.
2. Consume PAM's existing privileged inspection JSON in a separate coordinator
   slice. Keep the published 0.1.1 command path while it remains supported.
3. Give PAM mutation results truthful effect/recovery semantics and evaluate
   whether PAM-owned public observation can replace the duplicate parser.

The sections below retain the longer-term design options. Deferred discovery,
expectation-token, and receipt work is not a release gate for this bridge.

Deferred until a demonstrated need remains after those steps: mandatory
`describe`, generalized next-action metadata, persisted receipts, expectation
tokens, automatic conditional compensation, and suite uninstall preparation.

Implement in order: pinentry-companion, pam-companion, then AuthCompanion.
Finish and verify one component before starting the next. Keep component
candidates as drafts until the release compatibility gate below is ready.

## Outcome and constraints

A person or agent can discover the installed interface, determine what is
known, preview a precisely scoped operation, execute it under the owner's
checks, and continue from a truthful result without reading source or replaying
a conversation. Unknown state, missing authority, and partial completion remain
explicit. Validated fixtures and versioned documentation preserve what is learned.

Keep all three independently installable Homebrew products. Preserve native
pam_tid, password fallback, the complete pinentry cache opt-in gate, existing
GPG-home/preference coordination, and component-owned rollback records.
Keep user secrets and authentication out of the coordinator. No GUI, daemon,
network runtime, shared Swift package, new enrollment registry, or paid signing
membership is required.

The normative design is [system design](../design.md) plus
[the machine contract](../agent-contract.md). The
[current guide](../agent-guide.md) documents released behavior.
Owner-specific work is defined in the
[pinentry design](https://github.com/CasualDeveloper/pinentry-companion/blob/main/docs/design.md)
and [PAM design](https://github.com/CasualDeveloper/pam-companion/blob/main/docs/design.md).
Links to main are development navigation; released artifacts must bind their
schemas and compatibility evidence to immutable source/artifact identities.

## Inspected baseline and drift check

Inspected on 2026-09-16. All four working trees were clean before this
documentation work. These are local inspected source identities, not a claim
that remote branches cannot have advanced.

| Repository | Baseline source | Relevant product |
| --- | --- | --- |
| AuthCompanion | `f79453093e8f738649e2f58bff524434f68a78b5` | 0.1.2 |
| pinentry-companion | `f13d598a495f6039f9f2d12a82ee3c24f9e9b5bf` | 0.2.0 |
| pam-companion | `61e1431090133f590f6e6e939f6ec3621357ead8` | 0.1.1 |
| homebrew-tap | `62ec6642fb762bce796221c2bac4e61dce20e18c` | Published formula set |

Before implementation, inspect status/diffs and the named symbols below. Preserve
subsequent work and refresh assumptions that changed; do not reset a repository
to these hashes. Compare current installed help/schema with the plan before
running commands. Source checkout paths are developer choices, never runtime
dependencies.

| Current evidence | Owning path and consequence |
| --- | --- |
| Partial discovery is lost; exact product pins gate every operation | AuthCompanion `Sources/AuthCompanionCore/Application.swift`, `Dependencies.swift`, `ComponentVersion.swift` |
| PAM visible configuration is conflated with managed state | AuthCompanion `PAMInspection.swift`, `AuthCompanionManager.visiblePAMStatus` |
| Ordinary baseline restore is used for setup compensation | AuthCompanion `AuthCompanionManager.rollbackSetup`; inspect both component restore engines before changing this |
| Output is checked after exit; stderr is forwarded; no deadline | AuthCompanion `Sources/AuthCompanionCore/SystemAdapters.swift`, `SystemToolRunner.run` |
| Strict v1 schemas reject added fields; uncertain failures can say changed false | pinentry `Contracts/Schemas/`, `LifecycleMachineCommand.swift`, `ManagementModels.swift` |
| Existing GPG transaction baseline differs from enrollment baseline | pinentry `LifecycleManager.swift`, `LifecycleRecord.swift`, `LifecycleState.swift` |
| Root-only human CLI wraps structured internal status and durable recovery | PAM `PAMCommandLine.swift`, `PAMCommandLineRunner.swift`, `PAMLifecycleModels.swift`, `PAMLifecycleManager.swift` |
| Independent latest-release promotion lacks a suite compatibility test | tap `.github/scripts/sync-releases.rb`, `.github/workflows/sync-releases.yml`, `Formula/authcompanion.rb` |

Pinentry paths above are under `Sources/PinentryCompanionCore/`; PAM paths are
under `Sources/PAMCompanionCore/`. Existing tests use injected adapters and
temporary filesystem fixtures. Extend those seams rather than the real login
account, Keychain, GPG home, or system PAM.

## 1. Finish pinentry's agent contract

1. Add compiled interface description and a small command/effect declaration.
   Keep no-argument Assuan behavior separate. Describe must work with absent
   dependencies and may not instantiate authentication/cache adapters.
2. Define next-major machine schemas and golden/invalid fixtures first.
   Preserve v1 output and exact legacy argument forms. New explicit schema
   selection carries evidence, effect/recovery outcomes, typed next actions,
   and the target/account-shared preference distinction.
3. Expose setup, restore, and uninstall plans through the same transition
   logic used by lifecycle application. Add expected-state checks at the owner
   boundary, binding identity/options/target/generation/effects. Validate before
   recovery as well as ordinary writes; an interrupted prior transaction must
   not be silently recovered by a stale request.
4. Preserve original versus per-transaction baselines in `LifecycleRecord`.
   Demonstrate whether a newly created enrollment can be conditionally reversed
   by attempt identity without undoing pre-existing/adopted state or another
   GPG home's preference dependency. Initial automatic compensation excludes
   adoption, migration, and pre-existing shared-preference dependencies. If
   attribution or before-state cannot be proven, report partial/unknown and provide
   recovery inspection; do not add general checkpoint history to satisfy this
   phase.
5. Make failure effects truthful, including failure after partial writes and
   lost output. Persist attempt evidence needed for reconciliation in the
   existing record before reporting a commit. No receipt means no assumption
   of attribution.
6. Bundle the implemented schemas, compact operator reference, and description
   in release artifacts. Keep the fallback pinentry and secret handling
   unchanged. Publish no new tap default at this stage.

Acceptance: passive commands create no lifecycle files and call no Keychain,
LocalAuthentication, fallback, or agent-reload adapter; every new machine
outcome and usage error validates; v1 fixtures still pass; a changed target,
binary, takeover option, journal generation, or shared preference rejects stale
expectations, including when an older transaction needs recovery. Repeated
setup is idempotent; adopted setup is never silently
removed by compensation. Assuan smoke output stays byte-compatible.

Use `PassiveManagementTests`, `LifecycleMachineCommandTests`,
`LifecycleManagerTests`, `LifecycleStateTests`, `LifecycleLockTests`,
and `PinentryServerTests` as the nearest test seams. Extend
`Scripts/validate-contracts.py` for new schema families without weakening v1.

## 2. Give PAM its own complete machine boundary

1. Add describe and versioned JSON adapters over the current lifecycle engine.
   Add owner-local schemas/fixtures/validation, following shared semantics.
   Keep root human commands and native pam_tid behavior.
2. Move public-policy observation into a narrowly scoped PAM reader. Expose
   unprivileged machine status and observational plans with private ownership
   unknown. The reader must not attempt journal access or silently escalate.
3. Add explicit root read-only status/plan/doctor that proves journal, policy,
   fallback, and recovery state. Only this complete plan can issue a token for
   a privileged mutation. Public output must not reveal saved file contents,
   xattrs, backup names, or account identifiers.
4. Extend `PAMLifecycleManaging` and result models for structured actions,
   truthful effects, conditional expectations, and attempt attribution.
   Translate `PAMLifecycleError` cases to stable codes rather than parsing
   error descriptions. Preserve all path, policy, metadata, and external-module
   reference checks.
5. Validate each target at its transition, retain the component lock through
   durable record updates, and report partial effects if an external writer
   changes state between writes. A lock does not make arbitrary external
   writers disappear.
6. Prove guarded reversal only for this invocation's eligible new enrollment.
   Existing managed state, unmanaged native PAM adoption, schema migrations,
   and interrupted restore retain their original recovery semantics.
   Keep the candidate unpublished until combined promotion is safe.

Acceptance: non-root machine observation accesses public data only and emits
unknown ownership; non-root mutation fails before lifecycle writes; root
fixtures distinguish configured-managed, configured-unmanaged, legacy,
drifted, and interrupted. Missing authority is machine-readable. All existing
fault-injection, password-fallback, metadata, reference-scanning, and restore
tests continue passing. JSON status must not create the state directory or
lock. No live PAM file is used by these tests.

Extend `PAMCommandLineTests`, `PAMCommandLineRunnerTests`, and
`PAMLifecycleTests`. Add public-observation tests with sentinels for forbidden
private reads. Root behavior in unit tests uses injected IDs/temporary fixtures,
not elevation of the test process.

## 3. Make AuthCompanion a faithful composition

1. Replace all-or-nothing discovery with per-component results. Describe works
   with neither component installed. Retain fixed Homebrew resolution and
   inspect identities before execution. Partial status still reports whichever
   component is available.
2. Add a typed PAM decoder and preserve pinentry's detailed evidence. Move new
   suite output to an explicitly selected schema. Retain the published v1
   contract during migration and add missing suite schemas/fixtures.
3. Consume PAM public observation for passive status/plan; retire the duplicated
   policy parser for the new PAM contract after owner-contract tests pass. The
   bounded old-release adapter described below remains only for actual rollout
   compatibility. Root preflight
   consumes PAM's authoritative plan before either component mutates. No passive
   suite command invokes sudo.
4. Keep accepted release versions exact initially. Introduce bounded product
   ranges only with schema/capability checks and conformance evidence for the
   chosen range. Build the coordinator release to handle both the current and
   candidate component generations during rollout, including mixed pairs. New
   guarded machine operations require their capabilities; older interfaces use
   the explicitly identified legacy contract and conservative evidence, never
   fabricated guarantees. Keep this adapter limited to the supported published
   versions and the documented migration period. Emit supported/observed details
   when incompatible, without
   automatically installing, downgrading, or choosing another executable.
5. Propagate component expectation tokens and compare effects to the authorized
   intention. Preserve actual before/after/result evidence, including unknown
   outcomes. Apply guarded compensation only when attribution and immediate
   before-state are proven. Reconcile after a restart instead of maintaining a
   suite journal or resuming a guessed operation.
6. Bound child runtime and both output streams; preserve machine failures
   without forwarding private raw stderr. Use finite observation/mutation
   budgets and bounded cancellation. Initial test candidates are 5 seconds for
   observations, 60 seconds for mutations, and 2 seconds for cooperative stop;
   measure them before fixing release defaults. A timeout must not start a
   competing writer.
7. Return enough verified postconditions and typed next actions to avoid a
   mandatory doctor call after every mutation. Add restore/uninstall plans
   and suite uninstall preparation only through component contracts.
8. Keep human output concise and honest about unknowns. Never render a
   configured-policy observation as proven lifecycle ownership or successful
   interactive authentication.

Acceptance: fixed-order fake invocation tests cover missing component,
unsupported schema, invalid response, no-op, stale plan, lost sudo authority,
partial commit, timeout before/after commit, failed compensation, and restart
inspection. A pre-existing healthy component survives another's failure.
Doctor results retain their evidence limit. Restoration and package-removal
preparation are distinct from cache deletion.

Use `ApplicationTests`, `DependencyResolutionTests`,
`PinentryContractTests`, `SuiteManagerTests`, and `SystemAdapterTests`.
Replace duplicated PAM interpretation tests with producer-fixture conformance
tests. Fake child executables can test hangs/output floods without touching
authentication state.

## 4. Complete distribution before promoting any candidate

This gate is a dependency of publishing the work from stages 1 to 3, not a
cleanup to postpone until afterward.

1. Produce schemas and a release compatibility declaration from the same typed
   constants used by the shipped binaries. Include product version, supported
   schema versions, accepted dependency versions/ranges, and source identity.
   Bind these to the exact archive through its checksum/provenance.
2. Extend existing archive verifiers for description, schema validity,
   no-prompt observation, and portable load commands. Remove build-machine
   toolchain rpaths before final signing where the supported runtime permits;
   verify both architecture slices and loading on the supported macOS matrix.
   Do not regenerate already published assets as part of this work.
3. In the tap, stage proposed formulas and validate rolling compatibility before
   pushing changes. The next coordinator must work with current/current,
   candidate/current, current/candidate, and candidate/candidate component
   pairs. A fixture-only schema match is insufficient; smoke the exact accepted
   artifacts. Independent latest tags are not evidence of compatibility.
4. If the set is incompatible, retain the last known compatible pins and report
   what blocks promotion. Do not publish half the set, mutate user's auth state
   in brew tests, or fix an installed tap with an unrequested reset.
5. Publish and promote the compatible coordinator first, while current component
   pins remain in place. Then publish/promote component candidates under that
   coordinator's verified rolling-compatibility range. Follow the existing
   release workflow and authorization. Verify discovery after each accepted
   formula promotion and with a partial package upgrade.
   Coordinator-only removal must retain component packages, including avoiding
   unintended Homebrew autoremoval.

The existing tap automation means a public component release can be picked up
without a manual tap edit. Finish its compatibility guard before the first such
publication, or keep all candidates drafts. A single tap commit cannot make
installed package upgrades atomic. Users can retain an older exact-pinned
coordinator while independently upgrading a component; that unsupported pair
must fail without mutation, with documented instructions to upgrade the
coordinator. Do not promise compatibility for arbitrary held versions. The
new coordinator's tested mixed pairs are the supported rolling upgrade path.

## Verification and interaction budget

Commands below are future implementation checks, not tests claimed to have run
for this documentation update. Run targeted suites for each changed boundary,
then each repository's existing required build/test/package gates. Use an
installed toolchain that supplies XCTest; inspect its actual path rather than
assuming a particular Xcode installation.

```sh
# In the relevant repository, with the selected XCTest-capable Swift toolchain:
swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
git diff --check

# Existing pinentry contract validation:
python3 Scripts/validate-contracts.py
```

Use the existing `RELEASING.md` in each repository for exact archive checks and
controlled live gates. Do not run a live setup, purge, or signing test merely
because a documentation or machine-rendering change occurred. Account-level
preferences/Keychain are not isolated by setting HOME or GNUPGHOME.

| Scenario | Evidence required | Interaction/resource target |
| --- | --- | --- |
| Known configured system | Distinct configuration/ownership/authentication facts | One suite status request; zero UI, sudo, network, or managed-state writes |
| Unknown installed interface | Description usable with missing dependencies | One describe, then only the needed observation |
| Already satisfied setup | Verified unchanged result, recovery baseline preserved | No reload or extra doctor probe unless a relevant check requires it |
| First requested setup | Exact effects, root preflight, per-component postconditions | One explicit authorization boundary; no product password handling |
| Foreign config or stale plan | Typed conflict and no unreviewed effects | No automatic takeover/retry loop |
| PAM success followed by lost response | Durable evidence or effects unknown | Inspect once; no speculative restore |
| Interrupted or concurrent operation | Ownership/generation/active-writer evidence | Bounded wait; no lock deletion or competing writer |
| Commit signs without prompting | Cache/key/probe limits explained | No surprise cache purge or personal-key passphrase attempts |
| Component update | Old consumer support and new consumer conformance | Offline fixture tests, then one combined artifact smoke |
| A previously seen failure recurs | Stable code, fixture, documented next action | No transcript archaeology or full matrix rerun |

Instrument child-process count, output bytes, elapsed time, prompts, and sudo
invocations in the fixture scenarios. Starting output targets are 8 KiB for
describe and 16 KiB for ordinary status; they are design budgets, not measured
claims. Keep a larger explicit hard cap for complete structured failures.
Do not truncate JSON to meet a budget: return a bounded structured error.
Preserve fresh passing evidence while relevant inputs are unchanged.

## Decisions and stop conditions

Settled: thin CLI composition; component-owned state; native PAM; explicit
unknowns and effects; optional caller-retained receipts; no suite journal;
versioned contracts; sequential delivery; compatible tap promotion.

Wire-level field names, exact safe process budgets, and accepted product ranges
are implementation decisions constrained by the fixture gates. They are not
reasons to expand the product or stop ordinary work.

Stop the affected mutation/release path if the target is ambiguous, the owner
cannot establish its recovery boundary, the available toolchain cannot verify
a changed contract, a required privilege/human interaction is unavailable, or
the candidate dependency set is incompatible. Continue independent fixture/docs
work. Never substitute a live personal key or active PAM configuration for a
missing test fixture.

A clean documentation review completes this planning task only. Runtime
completion requires implemented contracts, owner and consumer conformance
tests, exact-archive verification, and the compatible tap result. Report these
separately rather than calling a written plan a shipped feature.
