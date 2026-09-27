// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

/// @dev ABI constants in concrete dependency artifacts; internal library functions are inlined.
contract DependencyConstantsGasTest is Test {
    mapping(string => address) private targets;

    function setUp() public {
        targets["BalanceDeltaLibrary"] = deployCode("BalanceDelta.sol:BalanceDeltaLibrary");
        targets["BeforeSwapDeltaLibrary"] = deployCode("BeforeSwapDelta.sol:BeforeSwapDeltaLibrary");
        targets["CurrencyLibrary"] = deployCode("Currency.sol:CurrencyLibrary");
        targets["LPFeeLibrary"] = deployCode("LPFeeLibrary.sol:LPFeeLibrary");
        targets["ProtocolFeeLibrary"] = deployCode("ProtocolFeeLibrary.sol:ProtocolFeeLibrary");
        targets["StateLibrary"] = deployCode("StateLibrary.sol:StateLibrary");
        targets["stdError"] = deployCode("StdError.sol:stdError");
        targets["ImmutableState"] = deployCode("ImmutableState.sol:ImmutableState", abi.encode(address(0xBEEF)));
    }

    function _read(string memory name, string memory functionName) private returns (bytes memory result) {
        address target = targets[name];
        bytes memory input = abi.encodeWithSignature(string.concat(functionName, "()"));
        uint256 beforeGas = gasleft();
        bool ok;
        (ok, result) = target.staticcall(input);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint(string.concat(name, ".", functionName), used);
        assertTrue(ok);
    }

    function testGas_ImmutableState_poolManager() public {
        assertEq(abi.decode(_read("ImmutableState", "poolManager"), (address)), address(0xBEEF));
    }

    function testGas_BalanceDeltaLibrary_ZERO_DELTA() public {
        assertEq(abi.decode(_read("BalanceDeltaLibrary", "ZERO_DELTA"), (uint256)), 0);
    }

    function testGas_BeforeSwapDeltaLibrary_ZERO_DELTA() public {
        assertEq(abi.decode(_read("BeforeSwapDeltaLibrary", "ZERO_DELTA"), (uint256)), 0);
    }

    function testGas_CurrencyLibrary_ADDRESS_ZERO() public {
        assertEq(abi.decode(_read("CurrencyLibrary", "ADDRESS_ZERO"), (uint256)), 0);
    }

    function testGas_LPFeeLibrary_DYNAMIC_FEE_FLAG() public {
        assertEq(abi.decode(_read("LPFeeLibrary", "DYNAMIC_FEE_FLAG"), (uint256)), 8388608);
    }

    function testGas_LPFeeLibrary_MAX_LP_FEE() public {
        assertEq(abi.decode(_read("LPFeeLibrary", "MAX_LP_FEE"), (uint256)), 1000000);
    }

    function testGas_LPFeeLibrary_OVERRIDE_FEE_FLAG() public {
        assertEq(abi.decode(_read("LPFeeLibrary", "OVERRIDE_FEE_FLAG"), (uint256)), 4194304);
    }

    function testGas_LPFeeLibrary_REMOVE_OVERRIDE_MASK() public {
        assertEq(abi.decode(_read("LPFeeLibrary", "REMOVE_OVERRIDE_MASK"), (uint256)), 12582911);
    }

    function testGas_ProtocolFeeLibrary_MAX_PROTOCOL_FEE() public {
        assertEq(abi.decode(_read("ProtocolFeeLibrary", "MAX_PROTOCOL_FEE"), (uint256)), 1000);
    }

    function testGas_StateLibrary_FEE_GROWTH_GLOBAL0_OFFSET() public {
        assertEq(abi.decode(_read("StateLibrary", "FEE_GROWTH_GLOBAL0_OFFSET"), (uint256)), 1);
    }

    function testGas_StateLibrary_LIQUIDITY_OFFSET() public {
        assertEq(abi.decode(_read("StateLibrary", "LIQUIDITY_OFFSET"), (uint256)), 3);
    }

    function testGas_StateLibrary_POOLS_SLOT() public {
        assertEq(abi.decode(_read("StateLibrary", "POOLS_SLOT"), (uint256)), 6);
    }

    function testGas_StateLibrary_POSITIONS_OFFSET() public {
        assertEq(abi.decode(_read("StateLibrary", "POSITIONS_OFFSET"), (uint256)), 6);
    }

    function testGas_StateLibrary_TICKS_OFFSET() public {
        assertEq(abi.decode(_read("StateLibrary", "TICKS_OFFSET"), (uint256)), 4);
    }

    function testGas_StateLibrary_TICK_BITMAP_OFFSET() public {
        assertEq(abi.decode(_read("StateLibrary", "TICK_BITMAP_OFFSET"), (uint256)), 5);
    }

    function testGas_stdError_arithmeticError() public {
        assertEq(
            abi.decode(_read("stdError", "arithmeticError"), (bytes)),
            abi.encodeWithSignature("Panic(uint256)", uint256(17))
        );
    }

    function testGas_stdError_assertionError() public {
        assertEq(
            abi.decode(_read("stdError", "assertionError"), (bytes)),
            abi.encodeWithSignature("Panic(uint256)", uint256(1))
        );
    }

    function testGas_stdError_divisionError() public {
        assertEq(
            abi.decode(_read("stdError", "divisionError"), (bytes)),
            abi.encodeWithSignature("Panic(uint256)", uint256(18))
        );
    }

    function testGas_stdError_encodeStorageError() public {
        assertEq(
            abi.decode(_read("stdError", "encodeStorageError"), (bytes)),
            abi.encodeWithSignature("Panic(uint256)", uint256(34))
        );
    }

    function testGas_stdError_enumConversionError() public {
        assertEq(
            abi.decode(_read("stdError", "enumConversionError"), (bytes)),
            abi.encodeWithSignature("Panic(uint256)", uint256(33))
        );
    }

    function testGas_stdError_indexOOBError() public {
        assertEq(
            abi.decode(_read("stdError", "indexOOBError"), (bytes)),
            abi.encodeWithSignature("Panic(uint256)", uint256(50))
        );
    }

    function testGas_stdError_memOverflowError() public {
        assertEq(
            abi.decode(_read("stdError", "memOverflowError"), (bytes)),
            abi.encodeWithSignature("Panic(uint256)", uint256(65))
        );
    }

    function testGas_stdError_popError() public {
        assertEq(
            abi.decode(_read("stdError", "popError"), (bytes)), abi.encodeWithSignature("Panic(uint256)", uint256(49))
        );
    }

    function testGas_stdError_zeroVarError() public {
        assertEq(
            abi.decode(_read("stdError", "zeroVarError"), (bytes)),
            abi.encodeWithSignature("Panic(uint256)", uint256(81))
        );
    }
}
