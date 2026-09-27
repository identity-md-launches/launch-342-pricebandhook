// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GasFixture} from "./GasFixture.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

contract SwapGasTest is GasFixture {
    using StateLibrary for IPoolManager;

    function testGas_swap_withoutHook_insideHour() public {
        _measureSwap(false, START + 1800, "swap.withoutHook.insideHour", -1000);
    }

    function testGas_swap_withHook_insideHour() public {
        _measureSwap(true, START + 1800, "swap.withHook.insideHour", -1000);
    }

    function testGas_swap_withoutHook_closingHour() public {
        _measureSwap(false, START + 3600, "swap.withoutHook.closingHour", -1088);
    }

    function testGas_swap_withHook_closingHour() public {
        _measureSwap(true, START + 3600, "swap.withHook.closingHour", -1088);
    }

    function testGas_swap_withoutHook_after1000Hours() public {
        _measureSwap(false, START + 1000 * 3600 + 900, "swap.withoutHook.after1000Hours", -1100);
    }

    function testGas_swap_withHook_after1000Hours() public {
        _measureSwap(true, START + 1000 * 3600 + 900, "swap.withHook.after1000Hours", -1100);
    }

    function _measureSwap(bool hooked, uint256 timestamp, string memory label, int24 average) private {
        vm.warp(timestamp);
        PoolKey memory pool = hooked ? key : plainKey;
        PoolSwapTest router = swapRouter;
        SwapParams memory params = SwapParams(true, -1 ether, TickMath.getSqrtPriceAtTick(-1500));
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings(false, false);

        // No reads of hook/pool/token state before the measured call. This includes the router,
        // unlock, swap, callback and both settlements; setup, warp and assertions are excluded.
        uint256 beforeGas = gasleft();
        BalanceDelta delta = router.swap{value: 1 ether}(pool, params, settings, "");
        uint256 used = beforeGas - gasleft();
        emit log_named_uint(label, used);

        assertEq(delta.amount0(), -1 ether, "entire exact input was consumed");
        assertGt(delta.amount1(), 0, "buy delivered BAND");
        (, int24 tick,,) = manager.getSlot0(pool.toId());
        assertLt(tick, -1100);
        assertGt(tick, -1500);
        assertEq(address(router).balance, 0, "router settled ETH");
        assertEq(token.balanceOf(address(router)), 0, "router settled BAND");
        assertEq(token.balanceOf(address(this)) + token.balanceOf(address(manager)), token.totalSupply());
        assertEq(address(this).balance + address(manager).balance, 1e30);
        if (hooked) {
            assertEq(hook.lastTick(id), tick);
            _bandIs(average, timestamp / 3600 - 1);
            assertEq(token.balanceOf(address(hook)), 0);
            assertEq(address(hook).balance, 0);
        }
    }
}
