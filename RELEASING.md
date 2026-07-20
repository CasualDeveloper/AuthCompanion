# Releasing AuthCompanion

Release archives contain one universal `authcompanion` executable. It is built
with Swift 6.3.3 for macOS 14 or newer and ad hoc signed with the hardened
runtime.

The project has no Apple Developer Program membership. Do not claim Developer
ID identity, notarization, or Gatekeeper approval. Distribution integrity comes
from the Homebrew formula digest, release checksums, GitHub provenance
attestations, and verification of the exact archive.

## Prepare a candidate

1. Update `AuthCompanionVersion.current` and `CHANGELOG.md` together.
2. Run the full XCTest suite with Xcode and build the release product with
   Swiftly 6.3.3.
3. Confirm `swift format lint` and `git diff --check` pass, then commit the
   release source.
4. From a clean tree, package and verify the candidate:

   ```sh
   swiftly run ./Scripts/package-release.sh
   ./Scripts/verify-release.sh dist/authcompanion-<version>.tar.gz
   ./Scripts/test-release-verifier.sh dist/authcompanion-<version>.tar.gz
   ```

The verifier checks the exact archive layout and checksums, universal
architectures, macOS 14 deployment target, ad hoc hardened-runtime signature,
system-only linked dependencies, CLI version, help, and passive JSON output.

## Draft release

Push the reviewed source to `main` and wait for the hosted macOS checks. Create
and push the matching annotated tag, such as `v0.1.0`. The tag workflow rebuilds
from that tag, checks intrinsic version equality, attests the archive, and
creates a draft GitHub release. It does not publish automatically.

Manual workflow runs create a seven-day candidate artifact without creating a
tag or release.

## One live setup gate

The two component releases have their own authentication and rollback gates.
AuthCompanion's live gate verifies only the final coordinator archive. Do not
repeat the components' full authentication matrices.

1. Keep a separate administrator shell available for recovery.
2. Verify that the installed component versions match AuthCompanion's declared
   dependencies.
3. Extract the exact draft archive and run `authcompanion status` and
   `authcompanion plan` from it.
4. Run `authcompanion setup --yes` once. Complete the sudo authentication when
   macOS requests it. Do not run `sudo -k` between coordinator steps.
5. Run `authcompanion status` and `authcompanion doctor` immediately. The
   existing sudo timestamp should cover the PAM doctor command.
6. Confirm GPG signing still uses pinentry-companion and a normal `sudo` command
   still uses pam-companion. Do not force extra uncached authentication unless
   the coordinator changed an authentication path.

Stop on an unexpected component version, PAM shape, lifecycle conflict,
rollback error, or manual recovery result.

## Publish and update Homebrew

After the live gate succeeds, publish the existing draft without rebuilding:

```sh
gh release edit v<version> --draft=false --repo CasualDeveloper/AuthCompanion
```

Add `authcompanion` to `CasualDeveloper/homebrew-tap` with the published archive
URL and SHA-256 digest. The formula must depend on both component formulas and
install only `bin/authcompanion`. It must not invoke setup, modify GPG or PAM,
or use sudo during installation.

Run strict formula audit, install, version, help, passive status, passive plan,
and uninstall checks before merging the tap change.
