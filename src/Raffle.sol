// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title Raffle
/// @author Ivan Hrekov (1vnhk)
/// @notice This contract is for creating a sample raffle (lottery)
/// @dev Implements Chainlink VRFv2.5
contract Raffle {
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__FeeIsTooLow();

    uint256 private immutable i_entranceFee;
    address payable[] private s_players;

    event Entered(address indexed player);

    constructor(uint256 fee) {
        require(fee > 0, Raffle__FeeIsTooLow());

        i_entranceFee = fee;
    }

    function enter() public payable {
        require(msg.value >= i_entranceFee, Raffle__SendMoreToEnterRaffle());

        s_players.push(payable(msg.sender));

        emit Entered(msg.sender);
    }

    function pickWinner() public {}

    /**
     * Getter functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }
}
