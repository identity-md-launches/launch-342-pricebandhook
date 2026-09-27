// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Band} from "../../src/Band.sol";

contract BandGasTest is Test {
    Band private token;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        token = new Band();
        token.transfer(ALICE, 100 ether);
        token.approve(ALICE, 10 ether);
        token.approve(BOB, type(uint256).max);
    }

    function _read(string memory label, bytes memory input) private returns (bytes memory result) {
        Band target = token;
        uint256 beforeGas = gasleft();
        bool ok;
        (ok, result) = address(target).staticcall(input);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint(label, used);
        assertTrue(ok);
    }

    function _write(string memory label, bytes memory input) private {
        Band target = token;
        uint256 beforeGas = gasleft();
        (bool ok, bytes memory result) = address(target).call(input);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint(label, used);
        assertTrue(ok);
        assertTrue(abi.decode(result, (bool)));
    }

    function testGas_name() public {
        assertEq(abi.decode(_read("Band.name", abi.encodeWithSignature("name()")), (string)), "Band");
    }

    function testGas_symbol() public {
        assertEq(abi.decode(_read("Band.symbol", abi.encodeWithSignature("symbol()")), (string)), "BAND");
    }

    function testGas_decimals() public {
        assertEq(abi.decode(_read("Band.decimals", abi.encodeWithSignature("decimals()")), (uint8)), 18);
    }

    function testGas_totalSupply() public {
        assertEq(abi.decode(_read("Band.totalSupply", abi.encodeWithSignature("totalSupply()")), (uint256)), SUPPLY);
    }

    function testGas_balanceOf() public {
        assertEq(abi.decode(_read("Band.balanceOf", abi.encodeCall(token.balanceOf, (ALICE))), (uint256)), 100 ether);
    }

    function testGas_allowance() public {
        assertEq(
            abi.decode(_read("Band.allowance", abi.encodeCall(token.allowance, (address(this), ALICE))), (uint256)),
            10 ether
        );
    }

    function testGas_approve_newSpender() public {
        _write("Band.approve.new", abi.encodeCall(token.approve, (address(0xCAFE), 20 ether)));
        assertEq(token.allowance(address(this), address(0xCAFE)), 20 ether);
    }

    function testGas_approve_replace() public {
        _write("Band.approve.replace", abi.encodeCall(token.approve, (ALICE, 20 ether)));
        assertEq(token.allowance(address(this), ALICE), 20 ether);
    }

    function testGas_transfer_newRecipient() public {
        _write("Band.transfer.new", abi.encodeCall(token.transfer, (BOB, 1 ether)));
        assertEq(token.balanceOf(BOB), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testGas_transfer_existingRecipient() public {
        _write("Band.transfer.existing", abi.encodeCall(token.transfer, (ALICE, 1 ether)));
        assertEq(token.balanceOf(ALICE), 101 ether);
    }

    function testGas_transferFrom_finiteAllowance() public {
        vm.prank(ALICE);
        _write(
            "Band.transferFrom.finite", abi.encodeCall(token.transferFrom, (address(this), address(0xCAFE), 1 ether))
        );
        assertEq(token.balanceOf(address(0xCAFE)), 1 ether);
        assertEq(token.allowance(address(this), ALICE), 9 ether);
    }

    function testGas_transferFrom_infiniteAllowance() public {
        vm.prank(BOB);
        _write(
            "Band.transferFrom.infinite", abi.encodeCall(token.transferFrom, (address(this), address(0xCAFE), 1 ether))
        );
        assertEq(token.balanceOf(address(0xCAFE)), 1 ether);
        assertEq(token.allowance(address(this), BOB), type(uint256).max);
    }
}
