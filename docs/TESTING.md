# Local verification

The tests deploy a real vendored v4-core `PoolManager` at its genuine address, mine the production
hook's CREATE2 address, and route swaps and liquidity operations through the core test routers.
No mock slot0, manager relocation, RPC, funded account, network, filesystem cheatcode or environment
variable is needed. Each test has its own setup and clock. No test requires execution ordering.

| Suite | Tests | Main assertions |
| --- | ---: | --- |
| `BandTest` | 9 | Metadata and whole supply to the actual deployer, exact transfers, approval consumption/revocation, invalid recipient/balance/allowance failures, no mint/admin/burn/upgrade selectors. |
| `PriceBandHookTest` | 21 | Exact permissions/address, constructor failure at wrong flags, both callback access checks, first hour unbounded, inclusive edges and one-tick reverts, strict recovery from either side and across the band, weighted averages, negative floor, gaps, view/enforcement parity, rollback, same-timestamp weighting, latest-only events, ungated withdrawal and partial-fill limits. |
| `InitializationTest` | 6 | Partial initialization hour, one second before a boundary, timestamp zero, independent pools, duplicate initialization rejection, TickMath extrema and unclamped bands. |
| `LaunchRehearsalTest` | 5 | One-sided BAND liquidity, first buy without pre-existing ETH, sell and unwind with conservation, delayed launch buy, exact-output semantics, ignored hookData, runtime size and opcode scan. |
| `HourModelTest` | 3 | History-based differential sequence fuzzing, bounded gas for a 1000-hour gap, and an extreme timestamp without elapsed-time multiplication overflow. |

The four fuzz tests each run 256 cases by default. The sequence model runs 16 proposed swaps per
case. It records all successful tick changes and sums segment overlap with the completed hour,
independently of the production rolling accumulator. It checks both acceptance/reversion, view
results, lastTick/core agreement, ETH/BAND conservation and absence of hook custody after each step.
The launch withdrawal allows at most four base units of core rounding dust per currency across
mint, two fee accruals and burn; total funds across user and manager are conserved exactly.

Useful focused commands:

```sh
forge test --match-contract LaunchRehearsalTest -vv
forge test --match-contract HourModelTest -vv
forge test --match-test test_partialBuyStopsOneTickInsideInitializedLowerEdge -vv
```

The delivered acceptance run passes 44 tests with no skips. The protected inputs were read as
requirements; local tests exercise their permission, caller, fixed-supply, transfer and opcode
properties, while their independent attestation-driven run remains the verifier's responsibility.
Local tests do not claim a security audit, independent review, live Sepolia fork rehearsal,
deployment or manifest admission. A factory-specific fork rehearsal must use the actual factory,
PoolManager, seed parameters and intended router before release.
