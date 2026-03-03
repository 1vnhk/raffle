// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @title Raffle
/// @author Ivan Hrekov (1vnhk)
/// @notice This contract is for creating a sample raffle (lottery)
/// @dev Implements Chainlink VRFv2.5
contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__FeeIsTooLow();
    error Raffle__IntervalIsTooLow();
    error Raffle__IntervalHasNotPassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();

    enum RaffleState {
        OPEN,
        CALCULATING_WINNER
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    /// @dev The duration of the raffle in seconds
    uint256 private immutable i_interval;
    /// @dev The key hash for the VRF
    bytes32 private immutable i_keyHash;
    /// @dev The subscription ID for the VRF
    uint64 private immutable i_subscriptionId;
    /// @dev The callback gas limit for the VRF
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimestamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    event Entered(address indexed player);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 fee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        require(fee > 0, Raffle__FeeIsTooLow());
        require(interval > 0, Raffle__IntervalIsTooLow());

        i_entranceFee = fee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimestamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enter() external payable {
        require(msg.value >= i_entranceFee, Raffle__SendMoreToEnterRaffle());
        require(s_raffleState == RaffleState.OPEN, Raffle__RaffleNotOpen());

        s_players.push(payable(msg.sender));

        emit Entered(msg.sender);
    }

    // Use random number to pick a winner
    // Should be called automatically: when?
    function pickWinner() external {
        require(block.timestamp - s_lastTimestamp >= i_interval, Raffle__IntervalHasNotPassed());

        s_raffleState = RaffleState.CALCULATING_WINNER;

        // uint256 requestId = s_vrfCoordinator.requestRandomWords(
        //     VRFV2PlusClient.RandomWordsRequest({
        //         keyHash: i_keyHash,
        //         subId: i_subscriptionId,
        //         requestConfirmations: REQUEST_CONFIRMATIONS,
        //         callbackGasLimit: i_callbackGasLimit,
        //         numWords: NUM_WORDS,
        //         // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
        //         extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        //     })
        // );

        s_lastTimestamp = block.timestamp;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 winnerIndex = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[winnerIndex];

        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;

        emit WinnerPicked(s_recentWinner);

        // TODO: move to pull pattern
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

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

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimestamp;
    }
}
