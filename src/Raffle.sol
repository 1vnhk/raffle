// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @title Raffle
/// @author Ivan Hrekov (1vnhk)
/// @notice A trustless, automated raffle contract powered by Chainlink VRF and Automation
/// @dev Implements Chainlink VRFv2.5 for randomness and Chainlink Automation for upkeep.
/// Uses a round-based architecture to avoid O(n) storage deletion in the VRF callback,
/// and a pull pattern for prize withdrawal to prevent DoS by reverting winners.
contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle__IncorrectEntranceFee();
    error Raffle__FeeIsTooLow();
    error Raffle__IntervalIsTooLow();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 numPlayers, uint256 raffleState);
    error Raffle__NoPrize();
    error Raffle__TransferFailed();

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

    /// @dev Current round number, incremented each time a winner is picked.
    /// Players and their count are keyed by round, so advancing the round
    /// effectively resets the player list in O(1) without deleting storage.
    uint256 private s_currentRound;
    mapping(uint256 round => mapping(uint256 index => address payable)) private s_players;
    mapping(uint256 round => uint256) private s_playersCount;

    uint256 private s_lastTimestamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /// @dev Tracks unclaimed prizes per address (pull pattern)
    mapping(address => uint256) private s_pendingPrizes;
    /// @dev Running total of all unclaimed prizes, used to derive the current round's prize pool
    uint256 private s_totalPendingPrizes;

    event Entered(address indexed player, uint256 indexed round);
    event WinnerPicked(address indexed winner, uint256 indexed round, uint256 prize);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event PrizeClaimed(address indexed winner, uint256 amount);

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

    /// @notice Enter the raffle by sending exactly the entrance fee.
    /// Duplicate entries are allowed — entering multiple times increases odds proportionally.
    function enter() external payable {
        require(msg.value == i_entranceFee, Raffle__IncorrectEntranceFee());
        require(s_raffleState == RaffleState.OPEN, Raffle__RaffleNotOpen());

        uint256 round = s_currentRound;
        uint256 playerIndex = s_playersCount[round];
        s_players[round][playerIndex] = payable(msg.sender);
        s_playersCount[round] = playerIndex + 1;

        emit Entered(msg.sender, round);
    }

    /// @notice Checks whether the raffle is ready to pick a winner
    /// @dev Called by Chainlink Automation nodes off-chain.
    /// Returns true when: raffle is OPEN, interval has elapsed, and at least one player has entered.
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
        uint256 round = s_currentRound;
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasPlayers = s_playersCount[round] > 0;
        return (timeHasPassed && isOpen && hasPlayers, "");
    }

    /// @notice Triggers winner selection by requesting randomness from Chainlink VRF
    /// @dev Called by Chainlink Automation when checkUpkeep returns true
    function performUpkeep(
        bytes memory /* performData */
    )
        external
    {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance, s_playersCount[s_currentRound], uint256(s_raffleState)
            );
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

    /// @notice Callback from VRF Coordinator with the random result
    /// @dev O(1) gas cost regardless of player count: picks a winner by index,
    /// credits the prize to the winner's pending balance (pull pattern),
    /// and advances the round counter instead of deleting storage.
    function fulfillRandomWords(
        uint256,
        /* requestId */
        uint256[] calldata randomWords
    )
        internal
        override
    {
        uint256 round = s_currentRound;
        uint256 numPlayers = s_playersCount[round];
        uint256 winnerIndex = randomWords[0] % numPlayers;
        address payable winner = s_players[round][winnerIndex];
        uint256 prize = address(this).balance - s_totalPendingPrizes;

        s_recentWinner = winner;
        s_pendingPrizes[winner] += prize;
        s_totalPendingPrizes += prize;
        s_currentRound = round + 1;
        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;

        emit WinnerPicked(winner, round, prize);
    }

    /// @notice Withdraw unclaimed prize winnings
    function claimPrize() external {
        uint256 amount = s_pendingPrizes[msg.sender];
        if (amount == 0) {
            revert Raffle__NoPrize();
        }

        s_pendingPrizes[msg.sender] = 0;
        s_totalPendingPrizes -= amount;

        emit PrizeClaimed(msg.sender, amount);

        (bool success,) = payable(msg.sender).call{value: amount}("");
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

    function getCurrentRound() external view returns (uint256) {
        return s_currentRound;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[s_currentRound][index];
    }

    function getPlayerByRound(uint256 round, uint256 index) external view returns (address) {
        return s_players[round][index];
    }

    function getPlayersCount() external view returns (uint256) {
        return s_playersCount[s_currentRound];
    }

    function getPlayersCountByRound(uint256 round) external view returns (uint256) {
        return s_playersCount[round];
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

    function getPendingPrize(address player) external view returns (uint256) {
        return s_pendingPrizes[player];
    }
}
