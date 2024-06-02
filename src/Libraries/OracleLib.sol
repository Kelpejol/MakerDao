// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

/**
 * @title OracleLib
 * @author Olukayode paul
 * @notice This library is used to check chainlink oracle for stale data
 * If a price is stale, the function will revert, and render the Engine unstable -> This is by design
 * we want the engine to freeze if the price become stale.
 *
 * so if the Chainlink network explodes and you have a lot of money locked in the protocol....Too bad
 */

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__stalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(
        AggregatorV3Interface _priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answerInRound
        ) = _priceFeed.latestRoundData();

        if (block.chainid == 11155111) {
            uint256 secondsSince = block.timestamp - updatedAt;
            if (secondsSince > TIMEOUT) {
                revert OracleLib__stalePrice();
            }
        }

        return (roundId, answer, startedAt, updatedAt, answerInRound);
    }
}
