// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolFixture} from "./helpers/PoolFixture.sol";

/// @dev Differential sequence test. The reference retains ALL successful tick changes and
/// integrates their overlap with a requested hour; it has no rolling accumulator or gap shortcut.
contract HourModelTest is PoolFixture {
    struct History {
        uint256[17] timestamps;
        int24[17] ticks;
        uint256 count;
    }

    function testFuzz_swapSequenceMatchesHistoryAndConservesFunds(bytes32 seed, uint16 startOffset) public {
        History memory history;
        history.timestamps[0] = START + bound(startOffset, 0, 3599);
        history.count = 1;
        vm.warp(history.timestamps[0]);
        _initialize(0);
        _seedWide();
        uint256 ethTotal = address(this).balance + address(manager).balance;

        for (uint256 i; i < 16; ++i) {
            seed = keccak256(abi.encode(seed, i));
            uint256 random = uint256(seed);
            uint256 step = random % 5;
            uint256 dt;
            if (step == 1) dt = (random >> 8) % 600;
            if (step == 2) dt = 3600 - block.timestamp % 3600;
            if (step == 3) dt = 3600 + (random >> 8) % 3600;
            if (step == 4) dt = 1000 * 3600 + (random >> 8) % 3600;
            vm.warp(block.timestamp + dt);

            bool active = block.timestamp / 3600 > history.timestamps[0] / 3600;
            int24 average;
            if (active) {
                average = _averageFromHistory(history, block.timestamp / 3600 - 1);
                _bandIs(average, block.timestamp / 3600 - 1);
            } else {
                (bool observed,,,,) = hook.band(id);
                assertFalse(observed);
            }

            int24 candidate = int24(int256((random >> 32) % 12001) - 6000);
            int24 old = history.ticks[history.count - 1];
            bool allowed = !active || _distanceFromBand(candidate, average) == 0
                || _distanceFromBand(candidate, average) < _distanceFromBand(old, average);
            if (allowed) {
                _move(candidate);
                history.timestamps[history.count] = block.timestamp;
                history.ticks[history.count++] = candidate;
            } else {
                _expectMoveReverts(candidate, average - 2231, average + 1823);
            }
            if (active) _bandIs(average, block.timestamp / 3600 - 1);
            assertEq(hook.lastTick(id), history.ticks[history.count - 1]);
            assertEq(_tick(), hook.lastTick(id));
            assertEq(address(this).balance + address(manager).balance, ethTotal);
            assertEq(token.balanceOf(address(this)) + token.balanceOf(address(manager)), token.totalSupply());
            assertEq(address(hook).balance, 0);
            assertEq(token.balanceOf(address(hook)), 0);
        }
    }

    function _averageFromHistory(History memory history, uint256 hour) private pure returns (int24) {
        uint256 start = hour * 3600;
        uint256 end = start + 3600;
        if (history.timestamps[0] > start) start = history.timestamps[0];
        int256 integral;
        for (uint256 j; j < history.count; ++j) {
            uint256 from = history.timestamps[j] > start ? history.timestamps[j] : start;
            uint256 to = j + 1 < history.count ? history.timestamps[j + 1] : end;
            if (to > end) to = end;
            if (to > from) integral += int256(history.ticks[j]) * int256(to - from);
        }
        int256 duration = int256(end - start);
        return int24(integral < 0 ? -((-integral + duration - 1) / duration) : integral / duration);
    }

    function _distanceFromBand(int24 tick, int24 average) private pure returns (uint256) {
        int256 relative = int256(tick) - average;
        if (relative < -2231) return uint256(-2231 - relative);
        if (relative > 1823) return uint256(relative - 1823);
        return 0;
    }

    function test_idleGapGasIsBoundedIndependentlyOfGapLength() public {
        _initialize(0);
        _seedWide();
        uint256 snap = vm.snapshotState();
        vm.warp(START + 3600);
        uint256 before = gasleft();
        _move(-100);
        uint256 oneHourGas = before - gasleft();
        assertTrue(vm.revertToStateAndDelete(snap));
        vm.warp(START + 1000 * 3600);
        before = gasleft();
        _move(-100);
        uint256 thousandHourGas = before - gasleft();
        assertLt(thousandHourGas, oneHourGas + 10_000);
        emit log_named_uint("one-hour swap gas (including test assertions)", oneHourGas);
        emit log_named_uint("1000-hour swap gas (including test assertions)", thousandHourGas);
    }

    function test_extremeIdleGapDoesNotMultiplyTickByElapsedTime() public {
        _initialize(-887272);
        vm.warp(type(uint256).max);
        _bandIs(-887272, type(uint256).max / 3600 - 1);
    }
}
