// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolFixture} from "./helpers/PoolFixture.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

contract LaunchRehearsalTest is PoolFixture {
    function setUp() public override {
        super.setUp();
        _initialize(0);
        // The entire position is below the opening price: currency1 (BAND) only.
        liquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-12000, -60, 1e21, 0), "");
    }

    function test_launchOneSidedBandFirstBuyThenSellAndUnwind() public {
        assertEq(address(manager).balance, 0, "pool initially has no ETH");
        assertGt(token.balanceOf(address(manager)), 0, "pool seeded with BAND");
        uint256 ethTotal = address(this).balance;
        uint256 bandBeforeBuy = token.balanceOf(address(this));
        BalanceDelta buy = _move(-1000);
        assertLt(buy.amount0(), 0);
        assertGt(buy.amount1(), 0);
        assertEq(token.balanceOf(address(this)) - bandBeforeBuy, uint256(int256(buy.amount1())));
        assertEq(address(manager).balance, uint256(-int256(buy.amount0())));

        BalanceDelta sell = _move(-500);
        assertGt(sell.amount0(), 0);
        assertLt(sell.amount1(), 0);
        assertEq(address(this).balance + address(manager).balance, ethTotal);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(address(manager)), token.totalSupply());
        assertEq(address(hook).balance, 0);
        assertEq(token.balanceOf(address(hook)), 0);
        assertEq(address(swapRouter).balance, 0);
        assertEq(token.balanceOf(address(swapRouter)), 0);

        vm.warp(START + 3600);
        _bandIs(-500, 100);
        liquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-12000, -60, -int256(1e21), 0), "");
        assertEq(address(this).balance + address(manager).balance, ethTotal);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(address(manager)), token.totalSupply());
        // Mint/burn and each of the two fee-growth accruals can round by a unit.
        assertLe(address(manager).balance, 4, "only rounding dust remains");
        assertLe(token.balanceOf(address(manager)), 4, "only rounding dust remains");
    }

    function test_delayedFirstBuyIntoEthlessPoolHonorsActiveBand() public {
        vm.warp(START + 1000 * 3600);
        _bandIs(0, 1099);
        _expectMoveReverts(-2232, -2231, 1823);
        assertEq(address(manager).balance, 0);
        _move(-1000);
        _move(-500);
    }

    function test_exactOutputBuysAndSellsAlsoEnforceBand() public {
        vm.warp(START + 3600);
        BalanceDelta buy = swapRouter.swap{value: LARGE_INPUT}(
            key,
            SwapParams(true, int256(LARGE_INPUT), TickMath.getSqrtPriceAtTick(-1000) + 1),
            PoolSwapTest.TestSettings(false, false),
            ""
        );
        assertEq(_tick(), -1000);
        assertGt(buy.amount1(), 0);
        assertLt(buy.amount1(), int256(LARGE_INPUT), "partially filled exact output");
        BalanceDelta sell = swapRouter.swap(
            key,
            SwapParams(false, int256(LARGE_INPUT), TickMath.getSqrtPriceAtTick(-500) + 1),
            PoolSwapTest.TestSettings(false, false),
            ""
        );
        assertEq(_tick(), -500);
        assertGt(sell.amount0(), 0);
        vm.expectRevert(_outOfBand(-2232, -2231, 1823));
        swapRouter.swap{value: LARGE_INPUT}(
            key,
            SwapParams(true, int256(LARGE_INPUT), TickMath.getSqrtPriceAtTick(-2232) + 1),
            PoolSwapTest.TestSettings(false, false),
            ""
        );
    }

    function test_hookDataHasNoAuthorityOrAccountingEffect() public {
        uint256 snap = vm.snapshotState();
        BalanceDelta empty = _move(-1000);
        assertTrue(vm.revertToStateAndDelete(snap));
        BalanceDelta arbitrary = swapRouter.swap{value: LARGE_INPUT}(
            key,
            SwapParams(true, -int256(LARGE_INPUT), TickMath.getSqrtPriceAtTick(-1000) + 1),
            PoolSwapTest.TestSettings(false, false),
            abi.encode(address(0xBEEF), uint256(100))
        );
        assertEq(BalanceDelta.unwrap(empty), BalanceDelta.unwrap(arbitrary));
        assertEq(hook.lastTick(id), -1000);
    }

    function test_runtimeHasNoEscapeHatchesAndFitsEip170() public view {
        _checkRuntime(address(token).code);
        _checkRuntime(address(hook).code);
    }

    function _checkRuntime(bytes memory code) private pure {
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xff && op != 0xf4 && op != 0xf2, "escape hatch opcode");
        }
    }
}
