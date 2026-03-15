// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @title Raffle
/// @author Ivan Hrekov (1vnhk)
/// @notice A trustless, automated raffle contract powered by Chainlink VRF and Automation
/// @dev Implements Chainlink VRFv2.5 for randomness and Chainlink Automation for upkeep
contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__FeeIsTooLow();
    error Raffle__IntervalIsTooLow();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 numPlayers, uint256 raffleState);

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
    uint256 private immutable i_subscriptionId;
    /// @dev The callback gas limit for the VRF
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimestamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    event Entered(address indexed player);
    event WinnerPicked(address indexed winner, uint256 prize);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 fee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
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

    /// @notice Enter the raffle by sending at least the entrance fee
    /// @dev Reverts if the raffle is not open or insufficient ETH is sent
    function enter() external payable {
        require(msg.value >= i_entranceFee, Raffle__SendMoreToEnterRaffle());
        require(s_raffleState == RaffleState.OPEN, Raffle__RaffleNotOpen());

        s_players.push(payable(msg.sender));

        emit Entered(msg.sender);
    }

    /// @notice Checks whether the raffle is ready to pick a winner
    /// @dev Called by Chainlink Automation nodes off-chain to determine if performUpkeep should be called.
    /// All of the following must be true for upkeepNeeded to return true:
    /// 1. The raffle is in OPEN state
    /// 2. The interval has passed since the last winner was picked
    /// 3. The contract has ETH (i.e. at least one player has entered)
    /// 4. There is at least one player
    /// @return upkeepNeeded True if it is time to pick a winner
    /// @return performData Unused — empty bytes
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        return (timeHasPassed && isOpen && hasBalance && hasPlayers, "");
    }

    /// @notice Triggers winner selection by requesting randomness from Chainlink VRF
    /// @dev Called by Chainlink Automation when checkUpkeep returns true.
    /// Reverts with Raffle__UpkeepNotNeeded if conditions are not met.
    function performUpkeep(
        bytes memory /* performData */
    )
        external
    {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING_WINNER;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );

        emit RequestedRaffleWinner(requestId);
    }

    /// @notice Callback function called by the VRF Coordinator with the random words
    /// @dev Selects a winner, resets the raffle, and transfers the prize.
    /// Follows the checks-effects-interactions pattern.
    function fulfillRandomWords(
        uint256,
        /* requestId */
        uint256[] calldata randomWords
    )
        internal
        override
    {
        uint256 winnerIndex = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[winnerIndex];
        uint256 prize = address(this).balance;

        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        delete s_players;
        s_lastTimestamp = block.timestamp;

        emit WinnerPicked(recentWinner, prize);

        (bool success,) = recentWinner.call{value: prize}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getPlayersCount() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimestamp;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
