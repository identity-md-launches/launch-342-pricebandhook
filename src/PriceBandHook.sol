// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

/// @notice Restricts ticks relative to the previous UTC hour's time-weighted average tick.
/// @dev Each pool is independent. No custody, fees, owner, user identity or custom deltas.
contract PriceBandHook is BaseHook {
    using StateLibrary for IPoolManager;

    int24 public constant LOWER_OFFSET = 2231;
    int24 public constant UPPER_OFFSET = 1823;
    uint256 private constant HOUR = 3600;

    struct Observation {
        uint256 updatedAt;
        int256 tickSeconds;
        uint16 coveredSeconds;
        int24 tick;
        int24 average;
        bool initialized;
        bool active;
    }

    mapping(PoolId => Observation) private observations;

    error PriceOutOfBand(int24 tick, int24 lower, int24 upper);
    error PoolNotInitialized(PoolId poolId);

    /// @notice Only the latest completed hour is emitted when a swap crosses hour boundaries.
    event HourClosed(PoolId indexed poolId, uint256 hour, int24 avgTick);

    constructor(IPoolManager poolManager_) BaseHook(poolManager_) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions.afterInitialize = true;
        permissions.afterSwap = true;
    }

    /// @notice Last tick observed at initialization or after a successful swap; zero for an unknown pool.
    function lastTick(PoolId poolId) external view returns (int24) {
        return observations[poolId].tick;
    }

    /// @notice Preview the band that a swap in this block would enforce, including idle hours.
    /// @return active Whether at least one hour boundary has passed since initialization.
    /// @return avgTick Floor of the time-weighted tick in the latest completed hour.
    /// @return lower Inclusive lower tick (avgTick - 2231).
    /// @return upper Inclusive upper tick (avgTick + 1823).
    /// @return hour UTC hour index of the average. All numeric outputs are zero when inactive.
    function band(PoolId poolId)
        external
        view
        returns (bool active, int24 avgTick, int24 lower, int24 upper, uint256 hour)
    {
        Observation memory observation = observations[poolId];
        if (!observation.initialized) return (false, 0, 0, 0, 0);
        observation = _advance(observation, block.timestamp);
        if (!observation.active) return (false, 0, 0, 0, 0);
        (lower, upper) = _bounds(observation.average);
        return (true, observation.average, lower, upper, block.timestamp / HOUR - 1);
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick) internal override returns (bytes4) {
        // PoolManager permits initialization only once. It also bounds tick to TickMath's range.
        observations[key.toId()] = Observation({
            updatedAt: block.timestamp,
            tickSeconds: 0,
            coveredSeconds: 0,
            tick: tick,
            average: 0,
            initialized: true,
            active: false
        });
        return BaseHook.afterInitialize.selector;
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        Observation memory observation = observations[poolId];
        if (!observation.initialized) revert PoolNotInitialized(poolId);
        uint256 previousHour = observation.updatedAt / HOUR;
        // Accrue the PREVIOUS tick up to now before observing the post-swap tick.
        observation = _advance(observation, block.timestamp);
        (, int24 tick,,) = poolManager.getSlot0(poolId);

        if (observation.active) {
            (int24 lower, int24 upper) = _bounds(observation.average);
            if (
                (tick < lower || tick > upper)
                    && _distance(tick, lower, upper) >= _distance(observation.tick, lower, upper)
            ) revert PriceOutOfBand(tick, lower, upper);
        }

        observation.tick = tick;
        observations[poolId] = observation;
        if (block.timestamp / HOUR > previousHour) {
            emit HourClosed(poolId, block.timestamp / HOUR - 1, observation.average);
        }
        return (BaseHook.afterSwap.selector, 0);
    }

    /// @dev Constant work even for arbitrarily long idle gaps; never multiplies a tick by the gap length.
    function _advance(Observation memory observation, uint256 timestamp) private pure returns (Observation memory) {
        uint256 previousHour = observation.updatedAt / HOUR;
        uint256 currentHour = timestamp / HOUR;
        if (currentHour == previousHour) {
            uint256 elapsed = timestamp - observation.updatedAt;
            observation.tickSeconds += int256(observation.tick) * int256(elapsed);
            observation.coveredSeconds += uint16(elapsed);
        } else {
            if (currentHour - previousHour == 1) {
                uint256 remaining = HOUR - observation.updatedAt % HOUR;
                int256 integral = observation.tickSeconds + int256(observation.tick) * int256(remaining);
                observation.average = _floorAverage(integral, uint256(observation.coveredSeconds) + remaining);
            } else {
                // At least one complete idle hour follows the partly accumulated hour. The
                // most recent completed hour held the previous tick for all 3600 seconds.
                observation.average = observation.tick;
            }
            observation.active = true;
            uint256 elapsed = timestamp % HOUR;
            observation.tickSeconds = int256(observation.tick) * int256(elapsed);
            observation.coveredSeconds = uint16(elapsed);
        }
        observation.updatedAt = timestamp;
        return observation;
    }

    function _floorAverage(int256 integral, uint256 secondsCovered) private pure returns (int24) {
        int256 divisor = int256(secondsCovered);
        int256 average = integral / divisor;
        if (integral < 0 && integral % divisor != 0) --average;
        // A weighted average is within the input tick range, hence safely within int24.
        return int24(average);
    }

    function _bounds(int24 average) private pure returns (int24 lower, int24 upper) {
        // Core ticks are in [-887272, 887272]; offsets cannot overflow int24. Do not clamp
        // to TickMath endpoints: the mathematical band is allowed to extend beyond them.
        return (average - LOWER_OFFSET, average + UPPER_OFFSET);
    }

    function _distance(int24 tick, int24 lower, int24 upper) private pure returns (int256) {
        if (tick < lower) return int256(lower) - tick;
        if (tick > upper) return int256(tick) - upper;
        return 0;
    }
}
