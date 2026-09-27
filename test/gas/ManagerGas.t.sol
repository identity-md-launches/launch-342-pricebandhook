// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GasFixture} from "./GasFixture.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

/// @dev Supplementary coverage of the concrete dependency ABI. Core swap/settlement entry points
/// are measured in real unlock transactions, not calls that merely revert while locked.
contract ManagerGasTest is GasFixture, IUnlockCallback {
    using StateLibrary for IPoolManager;

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    PoolKey private dynamicKey;
    enum Action {
        Mint,
        Burn,
        Clear,
        Donate,
        SettleFor
    }

    function setUp() public override {
        super.setUp();
        manager.unlock(abi.encode(Action.Mint));
        manager.approve(ALICE, 0, 5 ether);
        manager.setProtocolFeeController(address(this));
        manager.setProtocolFee(plainKey, 1000);
        swapRouter.swap{value: 1 ether}(
            plainKey,
            SwapParams(true, -1 ether, TickMath.getSqrtPriceAtTick(-1500)),
            PoolSwapTest.TestSettings(false, false),
            ""
        );
        dynamicKey = key;
        dynamicKey.fee = 0x800000;
        manager.initialize(dynamicKey, uint160(1 << 96));
    }

    function _write(string memory label, bytes memory input) private returns (bytes memory result) {
        bool ok;
        (ok, result) = _measureCall(label, address(manager), input);
        assertTrue(ok, label);
    }

    function testGas_PoolManager_allowance() public {
        assertEq(
            abi.decode(
                _measureView(
                    "PoolManager.allowance",
                    address(manager),
                    abi.encodeCall(manager.allowance, (address(this), ALICE, 0))
                ),
                (uint256)
            ),
            5 ether
        );
    }

    function testGas_PoolManager_balanceOf() public {
        assertEq(
            abi.decode(
                _measureView(
                    "PoolManager.balanceOf", address(manager), abi.encodeCall(manager.balanceOf, (address(this), 0))
                ),
                (uint256)
            ),
            10 ether
        );
    }

    function testGas_PoolManager_isOperator() public {
        assertFalse(
            abi.decode(
                _measureView(
                    "PoolManager.isOperator",
                    address(manager),
                    abi.encodeCall(manager.isOperator, (address(this), ALICE))
                ),
                (bool)
            )
        );
    }

    function testGas_PoolManager_owner() public {
        assertEq(
            abi.decode(
                _measureView("PoolManager.owner", address(manager), abi.encodeWithSignature("owner()")), (address)
            ),
            address(this)
        );
    }

    function testGas_PoolManager_protocolFeeController() public {
        assertEq(
            abi.decode(
                _measureView(
                    "PoolManager.protocolFeeController",
                    address(manager),
                    abi.encodeCall(manager.protocolFeeController, ())
                ),
                (address)
            ),
            address(this)
        );
    }

    function testGas_PoolManager_protocolFeesAccrued() public {
        assertEq(
            abi.decode(
                _measureView(
                    "PoolManager.protocolFeesAccrued",
                    address(manager),
                    abi.encodeCall(manager.protocolFeesAccrued, (Currency.wrap(address(0))))
                ),
                (uint256)
            ),
            1e15
        );
    }

    function testGas_PoolManager_supportsInterface() public {
        assertTrue(
            abi.decode(
                _measureView(
                    "PoolManager.supportsInterface",
                    address(manager),
                    abi.encodeWithSignature("supportsInterface(bytes4)", bytes4(0x01ffc9a7))
                ),
                (bool)
            )
        );
    }

    function testGas_PoolManager_approve() public {
        assertTrue(
            abi.decode(_write("PoolManager.approve", abi.encodeCall(manager.approve, (BOB, 0, 1 ether))), (bool))
        );
        assertEq(manager.allowance(address(this), BOB, 0), 1 ether);
    }

    function testGas_PoolManager_setOperator() public {
        assertTrue(
            abi.decode(_write("PoolManager.setOperator", abi.encodeCall(manager.setOperator, (BOB, true))), (bool))
        );
        assertTrue(manager.isOperator(address(this), BOB));
    }

    function testGas_PoolManager_transfer() public {
        assertTrue(
            abi.decode(_write("PoolManager.transfer", abi.encodeCall(manager.transfer, (BOB, 0, 1 ether))), (bool))
        );
        assertEq(manager.balanceOf(BOB, 0), 1 ether);
    }

    function testGas_PoolManager_transferFrom() public {
        vm.prank(ALICE);
        assertTrue(
            abi.decode(
                _write(
                    "PoolManager.transferFrom", abi.encodeCall(manager.transferFrom, (address(this), BOB, 0, 1 ether))
                ),
                (bool)
            )
        );
        assertEq(manager.balanceOf(BOB, 0), 1 ether);
        assertEq(manager.allowance(address(this), ALICE, 0), 4 ether);
    }

    function testGas_PoolManager_transferOwnership() public {
        _write("PoolManager.transferOwnership", abi.encodeWithSignature("transferOwnership(address)", BOB));
        assertEq(PoolManager(address(manager)).owner(), BOB);
    }

    function testGas_PoolManager_setProtocolFeeController() public {
        _write("PoolManager.setProtocolFeeController", abi.encodeCall(manager.setProtocolFeeController, (BOB)));
        assertEq(manager.protocolFeeController(), BOB);
    }

    function testGas_PoolManager_setProtocolFee() public {
        _write("PoolManager.setProtocolFee", abi.encodeCall(manager.setProtocolFee, (plainKey, uint24(500))));
        (,, uint24 fee,) = manager.getSlot0(plainKey.toId());
        assertEq(fee, 500);
    }

    function testGas_PoolManager_collectProtocolFees() public {
        bytes memory result = _write(
            "PoolManager.collectProtocolFees",
            abi.encodeCall(manager.collectProtocolFees, (BOB, Currency.wrap(address(0)), 0))
        );
        assertEq(abi.decode(result, (uint256)), 1e15);
        assertEq(BOB.balance, 1e15);
    }

    function testGas_PoolManager_updateDynamicLPFee() public {
        vm.prank(address(hook));
        _write("PoolManager.updateDynamicLPFee", abi.encodeCall(manager.updateDynamicLPFee, (dynamicKey, uint24(2500))));
        (,,, uint24 fee) = manager.getSlot0(dynamicKey.toId());
        assertEq(fee, 2500);
    }

    function testGas_PoolManager_initialize() public {
        PoolKey memory fresh = plainKey;
        fresh.tickSpacing = 120;
        assertEq(
            abi.decode(
                _write("PoolManager.initialize", abi.encodeCall(manager.initialize, (fresh, uint160(1 << 96)))), (int24)
            ),
            0
        );
    }

    function testGas_PoolManager_extsload_single() public {
        _measureView(
            "PoolManager.extsload.single", address(manager), abi.encodeWithSignature("extsload(bytes32)", bytes32(0))
        );
    }

    function testGas_PoolManager_extsload_range() public {
        bytes memory result = _measureView(
            "PoolManager.extsload.range2",
            address(manager),
            abi.encodeWithSignature("extsload(bytes32,uint256)", bytes32(0), 2)
        );
        assertEq(abi.decode(result, (bytes32[])).length, 2);
    }

    function testGas_PoolManager_extsload_sparse() public {
        bytes32[] memory slots = new bytes32[](2);
        slots[1] = bytes32(uint256(6));
        bytes memory result = _measureView(
            "PoolManager.extsload.sparse2", address(manager), abi.encodeWithSignature("extsload(bytes32[])", slots)
        );
        assertEq(abi.decode(result, (bytes32[])).length, 2);
    }

    function testGas_PoolManager_exttload_single() public {
        assertEq(
            abi.decode(
                _measureView(
                    "PoolManager.exttload.single",
                    address(manager),
                    abi.encodeWithSignature("exttload(bytes32)", bytes32(0))
                ),
                (bytes32)
            ),
            bytes32(0)
        );
    }

    function testGas_PoolManager_exttload_sparse() public {
        bytes32[] memory slots = new bytes32[](2);
        slots[1] = bytes32(uint256(6));
        bytes memory result = _measureView(
            "PoolManager.exttload.sparse2", address(manager), abi.encodeWithSignature("exttload(bytes32[])", slots)
        );
        assertEq(result, abi.encode(new bytes32[](2)));
    }

    function testGas_PoolManager_unlock_mint_sync_settle() public {
        _write("PoolManager.unlock.mint", abi.encodeCall(manager.unlock, (abi.encode(Action.Mint))));
        assertEq(manager.balanceOf(address(this), 0), 20 ether);
    }

    function testGas_PoolManager_burn_take() public {
        _write("PoolManager.unlock.burn", abi.encodeCall(manager.unlock, (abi.encode(Action.Burn))));
        assertEq(manager.balanceOf(address(this), 0), 9 ether);
    }

    function testGas_PoolManager_clear() public {
        _write("PoolManager.unlock.clear", abi.encodeCall(manager.unlock, (abi.encode(Action.Clear))));
        assertEq(manager.balanceOf(address(this), 0), 9 ether);
    }

    function testGas_PoolManager_donate() public {
        _write("PoolManager.unlock.donate", abi.encodeCall(manager.unlock, (abi.encode(Action.Donate))));
    }

    function testGas_PoolManager_settleFor() public {
        _write("PoolManager.unlock.settleFor", abi.encodeCall(manager.unlock, (abi.encode(Action.SettleFor))));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        Action action = abi.decode(data, (Action));
        Currency native = Currency.wrap(address(0));
        if (action == Action.Mint) {
            manager.sync(native);
            assertEq(manager.settle{value: 10 ether}(), 10 ether);
            manager.mint(address(this), 0, 10 ether);
        } else if (action == Action.Burn || action == Action.Clear) {
            manager.burn(address(this), 0, 1 ether);
            if (action == Action.Burn) manager.take(native, address(this), 1 ether);
            else manager.clear(native, 1 ether);
        } else if (action == Action.Donate) {
            manager.donate(key, 1 ether, 1 ether, "");
            manager.sync(native);
            assertEq(manager.settle{value: 1 ether}(), 1 ether);
            manager.sync(key.currency1);
            token.transfer(address(manager), 1 ether);
            assertEq(manager.settle(), 1 ether);
        } else {
            manager.sync(native);
            assertEq(manager.settleFor{value: 1 ether}(address(this)), 1 ether);
            manager.take(native, address(this), 1 ether);
        }
        return "";
    }

    function testGas_PoolSwapTest_manager() public {
        assertEq(
            abi.decode(
                _measureView("PoolSwapTest.manager", address(swapRouter), abi.encodeWithSignature("manager()")),
                (address)
            ),
            address(manager)
        );
    }

    function testGas_PoolModifyLiquidityTest_manager() public {
        assertEq(
            abi.decode(
                _measureView(
                    "PoolModifyLiquidityTest.manager", address(liquidityRouter), abi.encodeWithSignature("manager()")
                ),
                (address)
            ),
            address(manager)
        );
    }

    function testGas_PoolModifyLiquidityTest_modifyLiquidity_threeArgs() public {
        // A zero delta collects accrued LP fees without changing liquidity.
        liquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-12000, 12000, 0, 0), "");
        assertEq(manager.getLiquidity(id), 1e21);
    }

    function testGas_PoolModifyLiquidityTest_modifyLiquidity_fiveArgs() public {
        liquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-12000, 12000, 0, 0), "", false, false);
        assertEq(manager.getLiquidity(id), 1e21);
    }
}
