# Producer conformance fixtures

These are copies of pinentry-companion's checked-in JSON fixtures, not rewritten
consumer examples. Tests consume the copies offline without a sibling checkout.

- `pinentry/0.2.0`: published tag `v0.2.0`, commit
  `f13d598a495f6039f9f2d12a82ee3c24f9e9b5bf`, under `Contracts/Fixtures/`.
- `pinentry/0.2.1`: candidate commit
  `11fd31208389bf28076910ebf6155c2139982ecd`, under `Contracts/Fixtures/`,
  including ownership-recorded and recovered-setup responses.
  The producer's tests compare emitted responses with those same fixtures.

Refresh the relevant version's copies when its contract changes and run the
producer's fixture validation before the consumer suite. These tests establish
source-level conformance; release verification must also test the exact packaged
artifacts. A schema version alone does not establish arbitrary future-version
compatibility.
