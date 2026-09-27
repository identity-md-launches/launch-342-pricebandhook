// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Band} from "../../src/Band.sol";
import {PriceBandHook} from "../../src/PriceBandHook.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";

abstract contract PoolFixture is Test {
    using StateLibrary for IPoolManager;

    uint256 internal constant START = 100 * 3600;
    uint160 internal constant FLAGS = Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG;
    uint256 internal constant LARGE_INPUT = 1e25;

    IPoolManager internal manager;
    Band internal token;
    PriceBandHook internal hook;
    PoolSwapTest internal swapRouter;
    PoolModifyLiquidityTest internal liquidityRouter;
    PoolKey internal key;
    PoolId internal id;

    function setUp() public virtual {
        vm.warp(START);
        vm.deal(address(this), 1e30);
        token = new Band();
        manager = IPoolManager(address(new PoolManager(address(this))));
        hook = _deployHook();
        swapRouter = new PoolSwapTest(manager);
        liquidityRouter = new PoolModifyLiquidityTest(manager);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(liquidityRouter), type(uint256).max);
        key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 3000, 60, IHooks(address(hook)));
        id = key.toId();
    }

    function _deployHook() internal returns (PriceBandHook deployed) {
        bytes32 codeHash = keccak256(abi.encodePacked(type(PriceBandHook).creationCode, abi.encode(manager)));
        for (uint256 salt; salt < 200_000; ++salt) {
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), codeHash))))
            );
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK == FLAGS) {
                deployed = new PriceBandHook{salt: bytes32(salt)}(manager);
                assertEq(address(deployed), predicted);
                return deployed;
            }
        }
        revert("salt search exhausted");
    }

    function _initialize(int24 tick) internal {
        manager.initialize(key, TickMath.getSqrtPriceAtTick(tick));
    }

    function _seedWide() internal {
        liquidityRouter.modifyLiquidity{value: LARGE_INPUT}(key, ModifyLiquidityParams(-12000, 12000, 1e21, 0), "");
    }

    function _tick() internal view returns (int24 tick) {
        (, tick,,) = manager.getSlot0(id);
    }

    function _move(int24 target) internal returns (BalanceDelta delta) {
        // One sqrt unit above the tick avoids reporting tick-1 when falling onto an initialized tick.
        uint160 limit = TickMath.getSqrtPriceAtTick(target) + 1;
        (uint160 current,,,) = manager.getSlot0(id);
        if (limit == current) ++limit;
        bool buy = limit < current;
        delta = swapRouter.swap{value: buy ? LARGE_INPUT : 0}(
            key, SwapParams(buy, -int256(LARGE_INPUT), limit), PoolSwapTest.TestSettings(false, false), ""
        );
        assertEq(_tick(), target, "swap did not reach requested tick");
    }

    function _bandIs(int24 expected, uint256 hour) internal view {
        (bool active, int24 avg, int24 lower, int24 upper, uint256 h) = hook.band(id);
        assertTrue(active);
        assertEq(avg, expected);
        assertEq(lower, expected - 2231);
        assertEq(upper, expected + 1823);
        assertEq(h, hour);
    }

    function _outOfBand(int24 tick, int24 lower, int24 upper) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hook),
            IHooks.afterSwap.selector,
            abi.encodeWithSelector(PriceBandHook.PriceOutOfBand.selector, tick, lower, upper),
            abi.encodePacked(Hooks.HookCallFailed.selector)
        );
    }

    function _expectMoveReverts(int24 tick, int24 lower, int24 upper) internal {
        // Prepare state-dependent arguments before arming expectRevert (getSlot0 is external).
        uint160 limit = TickMath.getSqrtPriceAtTick(tick) + 1;
        (uint160 current,,,) = manager.getSlot0(id);
        if (limit == current) ++limit;
        bool buy = limit < current;
        vm.expectRevert(_outOfBand(tick, lower, upper));
        swapRouter.swap{value: buy ? LARGE_INPUT : 0}(
            key, SwapParams(buy, -int256(LARGE_INPUT), limit), PoolSwapTest.TestSettings(false, false), ""
        );
    }

    receive() external payable {}
}
