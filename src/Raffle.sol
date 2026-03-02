// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title Raffle
/// @author Ivan Hrekov (1vnhk)
/// @notice This contract is for creating a sample raffle (lottery)
/// @dev Implements Chainlink VRFv2.5
contract Raffle {
    uint256 private immutable i_entranceFee;

    constructor(uint256 fee) {
        i_entranceFee = fee;
    }

    function enter() public payable {}

    function pickWinner() public {}

    /**
     * Getter functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
