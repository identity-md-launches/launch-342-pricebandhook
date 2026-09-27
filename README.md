# Band / PriceBandHook

Contract-stage contribution for **lab-price-band-hook**, targeting Sepolia (chain ID **11155111**).
This repository delivers implemented contracts, local tests, vendored dependencies and ABI exports.
The separate manifest assignment owns `launch.json`; independent contributors review the accepted
source and manifest. Services publish source, attest, admit and deploy through the launch factory,
then start the static frontend assignment. Those service outcomes are not claimed by this contribution.

## Build and test

```sh
forge build
forge test
forge fmt --check
python3 scripts/export-abi.py
```

The compiler is pinned to **Solidity 0.8.26**, with Cancun EVM, optimization enabled at 200 runs and
`bytecode_hash = "none"`. Install that compiler through the verifier's normal toolchain. All imported
Solidity dependencies are ordinary files under `lib/`; there are no submodules, network imports,
FFI, filesystem cheatcode permissions or environment-dependent tests. No dependency installation is
needed to build offline with the pinned compiler installed. Dependency commits, archive hashes and
the selected upstream files are recorded in [docs/dependencies.json](docs/dependencies.json).
Upstream source is unmodified, with licenses retained. The v4-periphery revision includes its
original `BaseHook` and is paired with its pinned v4-core revision.

## Contracts

| Artifact | Constructor | Behavior |
| --- | --- | --- |
| `src/Band.sol:Band` | No arguments | ERC-20 named Band, symbol BAND, 18 decimals. Mints exactly 1,000,000,000 BAND (`1000000000000000000000000000` base units) to `msg.sender` once. |
| `src/PriceBandHook.sol:PriceBandHook` | `IPoolManager poolManager_` | Ownerless v4-periphery `BaseHook`. Enables exactly `afterInitialize` and `afterSwap`. |

BAND uses the vendored OpenZeppelin ERC-20 implementation. It has ordinary transfer/approval
semantics, no transfer tax, public mint/burn, owner, pausing or upgrade path. The deploying factory
receives the entire supply; a service must not predeploy it to a different recipient and assume the
factory owns it.

The hook has no custody or payment logic, no fees, custom deltas, token approvals, external oracle,
user allowlist or administrative operations. Its sole external read during a swap is the immutable
PoolManager's slot0 through [v4 StateLibrary](https://github.com/Uniswap/v4-core/blob/a7cf038cd568801a79a9b4cf92cd5b52c95c8585/src/libraries/StateLibrary.sol).
Both enabled callbacks inherit `onlyPoolManager`. All other callbacks are disabled and their inherited
implementations revert. No callback trusts the router as a user. **hookData is unauthenticated and
ignored**: empty, malformed and arbitrary data have no authority and credit nobody.

### Hour calculation

State is independent for each `PoolId = keccak256(abi.encode(poolKey))`. Any pool can attach the hook;
there is no token, fee or tick-spacing restriction in initialization, and liquidity additions/removals
are never gated by this hook.

UTC hour index is `timestamp / 3600`. Initialization records the tick and timestamp. Before checking
each swap, the hook accrues the **previous** tick through the current timestamp. Each tick therefore
has the weight of the seconds it actually held, not swap volume. Same-timestamp swaps have zero
duration. The initialization hour includes only the seconds after initialization. Until that hour's
first boundary, the band is inactive (this interval can be shorter than 3600 seconds).

For the last completed hour, `A = floor(sum(tick * seconds) / seconds covered)`, including negative
rounding toward minus infinity. The inclusive band is `[A - 2231, A + 1823]`. A post-swap tick `t1`
is accepted if inside that band, or if its distance to the nearest edge is strictly less than the
previous tick `t0`'s distance. Equal distance outside the band is rejected. A swap may cross the
entire band and finish outside the opposite side if it is still strictly closer. This implements the
specified recovery rule and allows movement back toward the band.

When multiple boundaries pass without a swap, the most recent completed hour held `lastTick` for
its entire duration, so its average is `lastTick`. The implementation discards older closed hours in
constant work and only integrates the current hour's seconds. It never loops over idle hours or
multiplies a tick by an unbounded elapsed interval. All timestamps are assumed to move forward, as on
the target chain. Accumulated seconds never exceed 3600 and observed ticks come from core's TickMath
range, so the arithmetic casts and tick offsets fit their types.

`band()` uses the same time advancement as swaps without writing storage. A failed swap reverts the
pool change, token settlement and hook state together. `HourClosed` is emitted only on a successful
swap that crosses a boundary, once for the **latest** completed hour. Idle hours have no eager events;
consumers must query `band()` instead of treating the last event as a live price feed.

For the approved ETH/BAND pool, tick denotes log-base-1.0001 of **BAND per ETH**. The average tick
represents a time-weighted **geometric** price, not the arithmetic average of prices. BAND per ETH is
`1.0001^A`; ETH per BAND is its reciprocal. Tick offsets approximate 80%–120% in BAND per ETH, or
83.3%–125% in ETH per BAND. The band can extend beyond TickMath's usable endpoints; it is deliberately
not clamped or silently narrowed by the contract.

## Deployment handoff

These are approved parameters supplied by the workflow, not a claim of live deployment verification:

| Parameter | Required value |
| --- | --- |
| Chain | Sepolia, `11155111` |
| Hook constructor's sole argument | PoolManager `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| Hook permission mask | `0x1040` / `4160` = `afterInitialize` (bit 12) + `afterSwap` (bit 6) |
| Address test | `uint160(hookAddress) & 0x3fff == 0x1040` |
| Pool currency0 | Native ETH, `address(0)` |
| Pool currency1 | The factory-deployed BAND token address |
| Pool LP fee / tick spacing | `3000` / `60` |
| Hook fees / return deltas | None; `afterSwap` returns its selector and `int128(0)` |
| Opening liquidity | One-sided BAND, with range below the opening price, no ETH required for seeding |

The service must mine a CREATE2 salt for the actual factory/deployer address and exact init code
(`PriceBandHook.creationCode` followed by ABI encoding of the PoolManager argument). Constructor
validation checks all 14 permission bits. Changes to source, compiler, constructor arguments or
deployer require recomputing the salt. The tests mine and deploy the real production hook; they do
not disable address validation or replace PoolManager code at another address.

Opening price, liquidity amount and range, factory address, final token/hook addresses, salt and
deployment transaction remain deployment-service inputs/results. The rehearsal uses tick 0 and
range `[-12000, -60]` at liquidity `10^21` solely as deterministic local fixtures. Production choices
must maintain native-ETH/BAND ordering, 60-tick alignment and one-sided BAND funding. Any seed choice
and opening price must be reviewed for compatibility with the band on a delayed first buy.

The manifest contributor records the concrete artifacts, constructor argument, pool parameters and
the two permissions. Services own policy, signed artifact linkage, publication, attestation,
admission and deployment. Independent review should report concrete source, constructor, policy
or authorization conflicts. Source tests do not substitute for independent review or the live-chain
factory rehearsal. No transaction, funded-wallet operation or live deployment was performed here.

## Frontend integration handoff

ABIs and API semantics are in [docs/ABI.md](docs/ABI.md). The later one-page static site has label
`lab-price-band-hook`, exports `dist/index.html`, and uses these workflow-supplied Sepolia addresses:

| Component | Address |
| --- | --- |
| PoolSwapTest router | `0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe` |
| StateView | `0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C` |
| V4Quoter | `0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227` |

Read `band(poolId)` and StateView's `getSlot0(poolId)` at the same block, refreshing before a swap.
Display activity, previous hour's average and both reciprocal price units, the allowed band and
current price. Derive current price from `(sqrtPriceX96 / 2^96)^2`, rather than rounding it to a tick.
ETH and BAND both have 18 decimals in this launch; other attached pools require decimal adjustment.

In v4, negative `amountSpecified` is exact input. `zeroForOne = true` buys BAND with ETH and decreases
the tick; `false` sells BAND and increases it. For an active band use a buy limit at **lower + 1 tick**
or sell limit at **upper - 1 tick**, converted with TickMath, with valid core price limits and normal
user slippage protection. A falling swap ending exactly on an initialized edge may report `edge - 1`;
the integration test reproduces that revert and verifies the one-tick-inside partial-fill solution.
The router returns unused ETH; approve only the intended BAND amount for a sell and account for
partial input consumption. Disable a direction that worsens a price already outside the band.

When inactive, the numeric band outputs are zero sentinels: use user slippage limits instead. Near
TickMath endpoints, clamp the proposed limit into core's valid range and ensure it lies on the
requested side of the current price. A quote cannot promise execution at a later block/hour. If a
full-size V4Quoter request reverts at the hook's band, do not present it as a successful partial-fill
quote; simulate the actual limited router call or reduce the requested quote size. These are frontend
integration responsibilities, not additional on-chain hooks.

## Verification and limitations

The local suite contains **44 tests**, all passing with the pinned compiler. See
[docs/TESTING.md](docs/TESTING.md) for coverage. Local results have no independent review or admission
authority. The on-chain spot tick can be manipulated through trading or sparse liquidity; this
mechanism is a deterministic relative-price constraint, not an external fair-price oracle, MEV
protection, a fixed peg or a permanent price floor. The first partial hour is unbounded, subsequent
hourly bands follow the pool, and validators influence timestamps within chain constraints.

The implementation has no owner who can rescue a poor initial price, pause, change the rule or
withdraw accidentally sent funds. Review launch economics, gas and the actual factory/router on a
Sepolia fork before release. Services must verify the supplied addresses/code, independently review
the final source and manifest, monitor the deployed pool, and run the fork rehearsal. This assignment
does not assert that those later responsibilities have been completed.
