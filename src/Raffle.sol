// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title Raffle
/// @author Ivan Hrekov (1vnhk)
/// @notice This contract is for creating a sample raffle (lottery)
/// @dev Implements Chainlink VRFv2.5
contract Raffle {
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__FeeIsTooLow();
    error Raffle__IntervalIsTooLow();

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    address payable[] private s_players;

    event Entered(address indexed player);

    constructor(uint256 fee, uint256 interval) {
        require(fee > 0, Raffle__FeeIsTooLow());
        require(interval > 0, Raffle__IntervalIsTooLow());

        i_entranceFee = fee;
        i_interval = interval;
    }

    function enter() external payable {
        require(msg.value >= i_entranceFee, Raffle__SendMoreToEnterRaffle());

        s_players.push(payable(msg.sender));

        emit Entered(msg.sender);
    }

    // How to get a random number?
    // Use random number to pick a winner
    // Should be called automatically: when?
    function pickWinner() external {}

    /**
     * Getter functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }
}
