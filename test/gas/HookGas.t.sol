// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GasFixture} from "./GasFixture.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

contract HookGasTest is GasFixture {
    function testGas_LOWER_OFFSET() public {
        assertEq(
            abi.decode(
                _measureView("PriceBandHook.LOWER_OFFSET", address(hook), abi.encodeWithSignature("LOWER_OFFSET()")),
                (int24)
            ),
            2231
        );
    }

    function testGas_UPPER_OFFSET() public {
        assertEq(
            abi.decode(
                _measureView("PriceBandHook.UPPER_OFFSET", address(hook), abi.encodeWithSignature("UPPER_OFFSET()")),
                (int24)
            ),
            1823
        );
    }

    function testGas_poolManager() public {
        assertEq(
            abi.decode(
                _measureView("PriceBandHook.poolManager", address(hook), abi.encodeWithSignature("poolManager()")),
                (address)
            ),
            address(manager)
        );
    }

    function testGas_getHookPermissions() public {
        bytes memory result = _measureView(
            "PriceBandHook.getHookPermissions", address(hook), abi.encodeCall(hook.getHookPermissions, ())
        );
        Hooks.Permissions memory expected;
        expected.afterInitialize = true;
        expected.afterSwap = true;
        assertEq(result, abi.encode(expected));
    }

    function testGas_lastTick() public {
        assertEq(
            abi.decode(
                _measureView("PriceBandHook.lastTick", address(hook), abi.encodeCall(hook.lastTick, (id))), (int24)
            ),
            -1100
        );
    }

    function testGas_band_insideHour() public {
        _measureBand(START + 1800, -1000, "PriceBandHook.band.insideHour");
    }

    function testGas_band_closingHour() public {
        _measureBand(START + 3600, -1088, "PriceBandHook.band.closingHour");
    }

    function testGas_band_after1000Hours() public {
        _measureBand(START + 1000 * 3600 + 900, -1100, "PriceBandHook.band.after1000Hours");
    }

    function testGas_band_unknownPool() public {
        bytes memory result = _measureView(
            "PriceBandHook.band.unknownPool",
            address(hook),
            abi.encodeCall(hook.band, (PoolId.wrap(bytes32(uint256(1)))))
        );
        assertEq(result, abi.encode(false, int24(0), int24(0), int24(0), uint256(0)));
    }

    function _measureBand(uint256 timestamp, int24 average, string memory label) private {
        vm.warp(timestamp);
        bytes memory result = _measureView(label, address(hook), abi.encodeCall(hook.band, (id)));
        assertEq(result, abi.encode(true, average, average - 2231, average + 1823, timestamp / 3600 - 1));
        assertEq(hook.lastTick(id), -1100, "view does not persist state");
    }

    function testGas_afterInitialize() public {
        // Unit measurement from the authorized caller on a fresh observation key. Real
        // PoolManager initialization is also covered by the integration fixture and gas trace.
        PoolKey memory fresh = key;
        fresh.tickSpacing = 120;
        bytes memory input = abi.encodeCall(hook.afterInitialize, (address(this), fresh, uint160(1 << 96), int24(0)));
        vm.prank(address(manager));
        (bool ok, bytes memory result) = _measureCall("PriceBandHook.afterInitialize", address(hook), input);
        assertTrue(ok);
        assertEq(abi.decode(result, (bytes4)), hook.afterInitialize.selector);
        assertEq(hook.lastTick(fresh.toId()), 0);
        vm.warp(START + 3600);
        (bool active, int24 average,,,) = hook.band(fresh.toId());
        assertTrue(active);
        assertEq(average, 0);
    }

    function testGas_afterSwap_insideHour() public {
        _measureAfterSwap(START + 1800, -1000, "PriceBandHook.afterSwap.insideHour");
    }

    function testGas_afterSwap_closingHour() public {
        _measureAfterSwap(START + 3600, -1088, "PriceBandHook.afterSwap.closingHour");
    }

    function testGas_afterSwap_after1000Hours() public {
        _measureAfterSwap(START + 1000 * 3600 + 900, -1100, "PriceBandHook.afterSwap.after1000Hours");
    }

    function _measureAfterSwap(uint256 timestamp, int24 average, string memory label) private {
        vm.warp(timestamp);
        bytes memory input = abi.encodeCall(
            hook.afterSwap,
            (address(this), key, SwapParams(true, -1 ether, uint160(1 << 95)), BalanceDelta.wrap(0), bytes(""))
        );
        vm.prank(address(manager));
        (bool ok, bytes memory result) = _measureCall(label, address(hook), input);
        assertTrue(ok);
        assertEq(result, abi.encode(hook.afterSwap.selector, int128(0)));
        _bandIs(average, timestamp / 3600 - 1);
        assertEq(hook.lastTick(id), -1100);
    }

    function _disabled(string memory label, bytes memory input) private {
        vm.prank(address(manager));
        (bool ok, bytes memory result) = _measureCall(label, address(hook), input);
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(BaseHook.HookNotImplemented.selector));
    }

    function testGas_beforeInitialize_disabled() public {
        _disabled(
            "PriceBandHook.beforeInitialize.revert",
            abi.encodeCall(hook.beforeInitialize, (address(this), key, uint160(1 << 96)))
        );
    }

    function testGas_beforeSwap_disabled() public {
        _disabled(
            "PriceBandHook.beforeSwap.revert",
            abi.encodeCall(
                hook.beforeSwap, (address(this), key, SwapParams(true, -1 ether, uint160(1 << 95)), bytes(""))
            )
        );
    }

    function testGas_beforeAddLiquidity_disabled() public {
        _disabled(
            "PriceBandHook.beforeAddLiquidity.revert",
            abi.encodeCall(
                hook.beforeAddLiquidity, (address(this), key, ModifyLiquidityParams(-60, 60, 1, 0), bytes(""))
            )
        );
    }

    function testGas_beforeRemoveLiquidity_disabled() public {
        _disabled(
            "PriceBandHook.beforeRemoveLiquidity.revert",
            abi.encodeCall(
                hook.beforeRemoveLiquidity, (address(this), key, ModifyLiquidityParams(-60, 60, -1, 0), bytes(""))
            )
        );
    }

    function testGas_afterAddLiquidity_disabled() public {
        _disabled(
            "PriceBandHook.afterAddLiquidity.revert",
            abi.encodeCall(
                hook.afterAddLiquidity,
                (
                    address(this),
                    key,
                    ModifyLiquidityParams(-60, 60, 1, 0),
                    BalanceDelta.wrap(0),
                    BalanceDelta.wrap(0),
                    bytes("")
                )
            )
        );
    }

    function testGas_afterRemoveLiquidity_disabled() public {
        _disabled(
            "PriceBandHook.afterRemoveLiquidity.revert",
            abi.encodeCall(
                hook.afterRemoveLiquidity,
                (
                    address(this),
                    key,
                    ModifyLiquidityParams(-60, 60, -1, 0),
                    BalanceDelta.wrap(0),
                    BalanceDelta.wrap(0),
                    bytes("")
                )
            )
        );
    }

    function testGas_beforeDonate_disabled() public {
        _disabled(
            "PriceBandHook.beforeDonate.revert",
            abi.encodeCall(hook.beforeDonate, (address(this), key, uint256(1), uint256(1), bytes("")))
        );
    }

    function testGas_afterDonate_disabled() public {
        _disabled(
            "PriceBandHook.afterDonate.revert",
            abi.encodeCall(hook.afterDonate, (address(this), key, uint256(1), uint256(1), bytes("")))
        );
    }
}
