// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolFixture} from "./helpers/PoolFixture.sol";
import {Vm} from "forge-std/Vm.sol";
import {PriceBandHook} from "../src/PriceBandHook.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

contract PriceBandHookTest is PoolFixture {
    using StateLibrary for IPoolManager;

    function setUp() public override {
        super.setUp();
        _initialize(0);
        _seedWide();
    }

    function test_permissionsAndMinedAddress() public view {
        Hooks.Permissions memory expected;
        expected.afterInitialize = true;
        expected.afterSwap = true;
        assertEq(abi.encode(hook.getHookPermissions()), abi.encode(expected));
        assertEq(uint160(address(hook)) & Hooks.ALL_HOOK_MASK, 0x1040);
        assertEq(address(hook.poolManager()), address(manager));
    }

    function test_constructorRejectsWrongAddressFlags() public {
        // Find a salt with wrong flags, then use the real constructor (no validation override).
        bytes32 hash = keccak256(abi.encodePacked(type(PriceBandHook).creationCode, abi.encode(manager)));
        for (uint256 salt;; ++salt) {
            address at = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), hash))))
            );
            if (uint160(at) & Hooks.ALL_HOOK_MASK == FLAGS) continue;
            vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, at));
            new PriceBandHook{salt: bytes32(salt)}(manager);
            break;
        }
    }

    function test_bothCallbacksRejectNonManager() public {
        vm.expectRevert(ImmutableState.NotPoolManager.selector);
        hook.afterInitialize(address(this), key, uint160(1 << 96), 123);
        vm.expectRevert(ImmutableState.NotPoolManager.selector);
        hook.afterSwap(address(this), key, SwapParams(true, -1, 1), BalanceDelta.wrap(0), "");
        assertEq(hook.lastTick(id), 0);
    }

    function test_unknownPoolViewsAreInactive() public view {
        PoolId unknown = PoolId.wrap(bytes32(uint256(123)));
        (bool active, int24 avg, int24 lower, int24 upper, uint256 hour) = hook.band(unknown);
        assertFalse(active);
        assertEq(abi.encode(avg, lower, upper, hour), abi.encode(int24(0), int24(0), int24(0), uint256(0)));
        assertEq(hook.lastTick(unknown), 0);
    }

    function test_firstHourUnbounded() public {
        vm.warp(START + 3599);
        _move(-5000);
        _move(6000);
        (bool active,,,,) = hook.band(id);
        assertFalse(active);
        assertEq(hook.lastTick(id), 6000);
    }

    function test_edgesInclusive() public {
        vm.warp(START + 3600);
        _move(-2231);
        _move(1823);
        _bandIs(0, 100);
    }

    function test_oneTickOutsideEitherEdgeReverts() public {
        vm.warp(START + 3600);
        _expectMoveReverts(-2232, -2231, 1823);
        _expectMoveReverts(1824, -2231, 1823);
        assertEq(_tick(), 0);
        assertEq(hook.lastTick(id), 0);
    }

    function test_recoveryFromBelowBandAndStrictDistance() public {
        vm.warp(START + 3599);
        _move(-5000);
        vm.warp(START + 3600);
        _bandIs(-2, 100);
        _move(-4999); // Still outside, but strictly closer.
        _expectMoveReverts(-5000, -2233, 1821);
        _expectMoveReverts(-4999, -2233, 1821); // Equal distance is insufficient.
        _move(-3000);
        _move(-2233);
    }

    function test_recoveryFromAboveBand() public {
        vm.warp(START + 3599);
        _move(5000);
        vm.warp(START + 3600);
        _bandIs(1, 100);
        _move(4999);
        _expectMoveReverts(5000, -2230, 1824);
        _move(1824);
    }

    function test_crossingWholeBandUsesDistanceToNearestEdge() public {
        vm.warp(START + 3599);
        _move(-5000);
        vm.warp(START + 3600);
        _move(3000); // Overshoots, but distance falls from 2767 to 1179.
        _expectMoveReverts(-4000, -2233, 1821); // Distance 1767 is worse.
    }

    function test_oneHourGapClosesWeightedHour() public {
        vm.warp(START + 900);
        _move(1000);
        vm.warp(START + 2700);
        _move(-1000);
        vm.warp(START + 3600);
        _bandIs(250, 100); // (0*900 + 1000*1800 - 1000*900) / 3600
        _move(0);
        _bandIs(250, 100);
    }

    function test_negativeFractionRoundsDown() public {
        vm.warp(START + 1800);
        _move(-1);
        vm.warp(START + 3600);
        _bandIs(-1, 100); // -0.5 must floor, never truncate to zero.
        _expectMoveReverts(1823, -2232, 1822);
        _move(1822);
    }

    function test_thousandHourGapUsesHeldTickAndOnlyLatestEvent() public {
        vm.warp(START + 123);
        _move(-731);
        vm.warp(START + 1000 * 3600 + 456);
        _bandIs(-731, 1099);
        vm.recordLogs();
        _move(-700);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(hook)) continue;
            ++count;
            assertEq(logs[i].topics[0], keccak256("HourClosed(bytes32,uint256,int24)"));
            assertEq(logs[i].topics[1], PoolId.unwrap(id));
            assertEq(logs[i].data, abi.encode(uint256(1099), int24(-731)));
        }
        assertEq(count, 1);
        _bandIs(-731, 1099);
        vm.warp(START + 1001 * 3600);
        _bandIs(-704, 1100); // floor((-731*456 - 700*3144)/3600)
    }

    function test_viewPredictsEnforcementWithoutUpdatingLastTick() public {
        _move(1234);
        vm.warp(START + 3600);
        _bandIs(1234, 100);
        assertEq(hook.lastTick(id), 1234);
        _expectMoveReverts(1234 + 1824, 1234 - 2231, 1234 + 1823);
        _move(1234 + 1823);
        _bandIs(1234, 100);
    }

    function test_revertedSwapRollsBackPoolBalancesAndHourAccumulator() public {
        vm.warp(START + 1800);
        _move(-100);
        vm.warp(START + 3600);
        uint256 ethBefore = address(manager).balance;
        uint256 bandBefore = token.balanceOf(address(manager));
        _expectMoveReverts(1800, -2281, 1773);
        assertEq(_tick(), -100);
        assertEq(hook.lastTick(id), -100);
        assertEq(address(manager).balance, ethBefore);
        assertEq(token.balanceOf(address(manager)), bandBefore);
        _bandIs(-50, 100);
        _move(0);
        vm.warp(START + 7200);
        _bandIs(0, 101);
    }

    function test_sameTimestampSwapsHaveZeroWeight() public {
        _move(1200);
        _move(-1200);
        _move(77);
        vm.warp(START + 3600);
        _bandIs(77, 100);
    }

    function test_noRepeatedHourEventWithinAnHour() public {
        vm.warp(START + 3600);
        _move(-100);
        vm.recordLogs();
        _move(100);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].emitter != address(hook));
        }
    }

    function test_liquidityRemovalRemainsAvailableOutsideBand() public {
        vm.warp(START + 3599);
        _move(-5000);
        vm.warp(START + 3600);
        liquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-12000, 12000, -int256(1e21), 0), "");
        assertEq(manager.getLiquidity(id), 0);
        assertEq(hook.lastTick(id), -5000);
    }

    function test_partialBuyStopsOneTickInsideInitializedLowerEdge() public {
        // avg 11 makes the lower edge -2220, an initialized multiple of tickSpacing 60.
        _move(11);
        liquidityRouter.modifyLiquidity{value: LARGE_INPUT}(key, ModifyLiquidityParams(-2220, 2220, 1e20, 0), "");
        vm.warp(START + 3600);
        _bandIs(11, 100);
        vm.expectRevert(_outOfBand(-2221, -2220, 1834));
        swapRouter.swap{value: LARGE_INPUT}(
            key,
            SwapParams(true, -int256(LARGE_INPUT), TickMath.getSqrtPriceAtTick(-2220)),
            PoolSwapTest.TestSettings(false, false),
            ""
        );
        BalanceDelta delta = swapRouter.swap{value: LARGE_INPUT}(
            key,
            SwapParams(true, -int256(LARGE_INPUT), TickMath.getSqrtPriceAtTick(-2219)),
            PoolSwapTest.TestSettings(false, false),
            ""
        );
        assertEq(_tick(), -2219);
        assertGt(delta.amount0(), -int256(LARGE_INPUT));
        assertLt(delta.amount0(), 0);
        assertGt(delta.amount1(), 0);
        assertEq(address(swapRouter).balance, 0, "unused ETH refunded");
    }

    function test_partialSellStopsOneTickInsideUpperEdge() public {
        vm.warp(START + 3600);
        BalanceDelta delta = _move(1822);
        assertGt(delta.amount1(), -int256(LARGE_INPUT));
        assertLt(delta.amount1(), 0);
        assertGt(delta.amount0(), 0);
    }

    function testFuzz_weightedHourMatchesIndependentFloor(int24 first, int24 second, uint16 split) public {
        first = int24(bound(int256(first), -6000, 6000));
        second = int24(bound(int256(second), -6000, 6000));
        split = uint16(bound(split, 1, 3599));
        _move(first);
        vm.warp(START + split);
        if (second != first) _move(second);
        vm.warp(START + 3600);
        int256 numerator = int256(first) * int256(uint256(split)) + int256(second) * int256(3600 - uint256(split));
        // Independent floor identity: -ceil(abs(n)/d) for a negative numerator.
        int24 expected = int24(numerator < 0 ? -((-numerator + 3599) / 3600) : numerator / 3600);
        _bandIs(expected, 100);
        // Returning into the band must be possible even if second is far outside it.
        if (expected != second) _move(expected);
        _bandIs(expected, 100);
    }
}

contract InitializationTest is PoolFixture {
    using StateLibrary for IPoolManager;

    function test_partialInitializationHourOnlyCountsCoveredSeconds() public {
        vm.warp(START + 1800);
        _initialize(-100);
        _seedWide();
        vm.warp(START + 2700);
        _move(101);
        vm.warp(START + 3600);
        _bandIs(0, 100); // (-100*900 + 101*900) / 1800 floors to zero.
    }

    function test_initializationOneSecondBeforeBoundary() public {
        vm.warp(START + 3599);
        _initialize(-123);
        vm.warp(START + 3600);
        _bandIs(-123, 100);
    }

    function test_initializationAtTimestampZeroStillActivates() public {
        vm.warp(0);
        _initialize(37);
        vm.warp(3600);
        _bandIs(37, 0);
    }

    function test_anyPoolMayAttachAndStateIsIndependent() public {
        _initialize(-100);
        _seedWide();
        PoolKey memory other = key;
        other.fee = 500;
        other.tickSpacing = 10;
        manager.initialize(other, TickMath.getSqrtPriceAtTick(999));
        vm.warp(START + 1800);
        _move(-200);
        vm.warp(START + 3600);
        _bandIs(-150, 100);
        (bool active, int24 avg,,, uint256 hour) = hook.band(other.toId());
        assertTrue(active);
        assertEq(avg, 999);
        assertEq(hour, 100);
        assertEq(hook.lastTick(other.toId()), 999);
    }

    function test_duplicateInitializationCannotResetHistory() public {
        _initialize(100);
        vm.warp(START + 3600);
        vm.expectRevert(); // Core's PoolAlreadyInitialized.
        manager.initialize(key, TickMath.getSqrtPriceAtTick(200));
        _bandIs(100, 100);
        assertEq(hook.lastTick(id), 100);
    }

    function test_tickExtremesDoNotOverflowOrClampBand() public {
        _initialize(TickMath.MIN_TICK);
        PoolKey memory other = key;
        other.fee = 500;
        manager.initialize(other, TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK - 1));
        vm.warp(START + 3600);
        _bandIs(TickMath.MIN_TICK, 100);
        (, int24 avg,, int24 upper,) = hook.band(other.toId());
        assertEq(avg, TickMath.MAX_TICK - 1);
        assertEq(upper, TickMath.MAX_TICK - 1 + 1823);
    }
}
