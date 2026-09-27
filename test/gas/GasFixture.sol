// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolFixture} from "../helpers/PoolFixture.sol";
import {Band} from "../../src/Band.sol";
import {PriceBandHook} from "../../src/PriceBandHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";

/// @dev Only ordinary gasleft() measurements: no version-dependent gas snapshot cheatcodes.
/// Deploy dependency artifacts to keep their creation code out of this test contract's runtime.
abstract contract GasFixture is PoolFixture {
    PoolKey internal plainKey;

    function setUp() public virtual override {
        vm.warp(START - 3600);
        vm.deal(address(this), 1e30);
        token = Band(deployCode("Band.sol:Band"));
        manager = IPoolManager(deployCode("PoolManager.sol:PoolManager", abi.encode(address(this))));
        hook = _deployGasHook();
        swapRouter = PoolSwapTest(deployCode("PoolSwapTest.sol:PoolSwapTest", abi.encode(manager)));
        liquidityRouter = PoolModifyLiquidityTest(
            deployCode("PoolModifyLiquidityTest.sol:PoolModifyLiquidityTest", abi.encode(manager))
        );
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(liquidityRouter), type(uint256).max);
        key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 3000, 60, IHooks(address(hook)));
        plainKey = key;
        plainKey.hooks = IHooks(address(0));
        id = key.toId();
        manager.initialize(key, TickMath.getSqrtPriceAtTick(-1000));
        manager.initialize(plainKey, TickMath.getSqrtPriceAtTick(-1000));
        ModifyLiquidityParams memory position = ModifyLiquidityParams(-12000, 12000, 1e21, 0);
        liquidityRouter.modifyLiquidity{value: LARGE_INPUT}(key, position, "");
        liquidityRouter.modifyLiquidity{value: LARGE_INPUT}(plainKey, position, "");

        // Activate the band, then populate a nonzero accumulator. Both pools have identical
        // price, liquidity and fee history before each fresh test execution.
        vm.warp(START);
        _prepareSwap(key, -1050);
        _prepareSwap(plainKey, -1050);
        vm.warp(START + 900);
        _prepareSwap(key, -1100);
        _prepareSwap(plainKey, -1100);
    }

    function _deployGasHook() private returns (PriceBandHook deployed) {
        bytes memory code = abi.encodePacked(vm.getCode("PriceBandHook.sol:PriceBandHook"), abi.encode(manager));
        bytes32 hash = keccak256(code);
        for (uint256 salt; salt < 200_000; ++salt) {
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), hash))))
            );
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK != FLAGS) continue;
            address at;
            assembly ("memory-safe") {
                at := create2(0, add(code, 32), mload(code), salt)
            }
            require(at != address(0) && at == predicted, "hook deployment failed");
            return PriceBandHook(at);
        }
        revert("salt search exhausted");
    }

    function _prepareSwap(PoolKey memory pool, int24 target) private {
        swapRouter.swap{value: LARGE_INPUT}(
            pool,
            SwapParams(true, -int256(LARGE_INPUT), TickMath.getSqrtPriceAtTick(target) + 1),
            PoolSwapTest.TestSettings(false, false),
            ""
        );
    }

    function _measureCall(string memory label, address target, bytes memory input)
        internal
        returns (bool ok, bytes memory result)
    {
        uint256 beforeGas = gasleft();
        (ok, result) = target.call(input);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint(label, used);
    }

    function _measureView(string memory label, address target, bytes memory input)
        internal
        returns (bytes memory result)
    {
        uint256 beforeGas = gasleft();
        bool ok;
        (ok, result) = target.staticcall(input);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint(label, used);
        assertTrue(ok, label);
    }
}
