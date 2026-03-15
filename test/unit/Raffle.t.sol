// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    uint256 subscriptionId;

    address PLAYER = makeAddr("player");
    uint256 constant STARTING_PLAYER_BALANCE = 10 ether;

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployRaffle();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function testRaffleRevertsWhenFeeIsZero() public {
        vm.expectRevert(Raffle.Raffle__FeeIsTooLow.selector);
        new Raffle(0, interval, vrfCoordinator, bytes32(0), subscriptionId, 500_000);
    }

    function testRaffleRevertsWhenIntervalIsZero() public {
        vm.expectRevert(Raffle.Raffle__IntervalIsTooLow.selector);
        new Raffle(entranceFee, 0, vrfCoordinator, bytes32(0), subscriptionId, 500_000);
    }

    function testRaffleIsInitializedWithCorrectEntranceFee() public view {
        assertEq(raffle.getEntranceFee(), entranceFee);
    }

    function testRaffleIsInitializedWithCorrectInterval() public view {
        assertEq(raffle.getInterval(), interval);
    }

    function testRaffleIsInitializedWithCorrectLastTimestamp() public view {
        assertEq(raffle.getLastTimestamp(), block.timestamp);
    }

    function testRaffleIsInitializedInOpenState() public view {
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
    }

    function testRaffleStartsAtRoundZero() public view {
        assertEq(raffle.getCurrentRound(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                             ENTER RAFFLE
    //////////////////////////////////////////////////////////////*/
    modifier player() {
        vm.prank(PLAYER);
        _;
    }

    modifier timePassed() {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testEnterRevertsWhenPlayerPaysLessThanEntranceFee() public player {
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enter{value: entranceFee - 1}();
    }

    function testEnterRevertsWhenRaffleIsCalculating() public timePassed {
        raffle.enter{value: entranceFee}();
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enter{value: entranceFee}();
    }

    function testEnterAddsPlayerToPlayersArray() public player {
        raffle.enter{value: entranceFee}();

        assertEq(raffle.getPlayer(0), PLAYER);
    }

    function testEnterIncrementsPlayersCount() public player {
        raffle.enter{value: entranceFee}();

        assertEq(raffle.getPlayersCount(), 1);
    }

    function testEnterEmitsEnteredEvent() public player {
        vm.expectEmit(true, true, false, false, address(raffle));
        emit Raffle.Entered(PLAYER, 0);
        raffle.enter{value: entranceFee}();
    }

    function testEnterIncreasesContractBalance() public player {
        uint256 raffleStartingBalance = address(raffle).balance;
        uint256 playerStartingBalance = PLAYER.balance;
        raffle.enter{value: entranceFee}();

        assertEq(address(raffle).balance, raffleStartingBalance + entranceFee);
        assertEq(PLAYER.balance, playerStartingBalance - entranceFee);
    }

    function testEnterKeepsExcessFee() public player {
        uint256 raffleStartingBalance = address(raffle).balance;
        uint256 playerStartingBalance = PLAYER.balance;
        uint256 extraFee = 100 gwei;
        raffle.enter{value: entranceFee + extraFee}();

        assertEq(address(raffle).balance, raffleStartingBalance + entranceFee + extraFee);
        assertEq(PLAYER.balance, playerStartingBalance - entranceFee - extraFee);
    }

    /*//////////////////////////////////////////////////////////////
                              CHECK UPKEEP
    //////////////////////////////////////////////////////////////*/
    function testCheckUpkeepReturnsFalseIfIntervalHasNotPassed() public player {
        raffle.enter{value: entranceFee}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepReturnsFalseIfNoPlayers() public timePassed {
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsCalculating() public player timePassed {
        raffle.enter{value: entranceFee}();
        raffle.performUpkeep("");

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepReturnsTrueWhenAllConditionsMet() public player timePassed {
        raffle.enter{value: entranceFee}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertEq(upkeepNeeded, true);
    }

    /*//////////////////////////////////////////////////////////////
                             PERFORM UPKEEP
    //////////////////////////////////////////////////////////////*/
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public player timePassed {
        raffle.enter{value: entranceFee}();

        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 balance = address(raffle).balance;
        uint256 numPlayers = 0;
        Raffle.RaffleState state = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enter{value: entranceFee}();
        balance += entranceFee;
        numPlayers += 1;

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, balance, numPlayers, state));
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public player timePassed {
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        assertGt(uint256(requestId), 0);
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.CALCULATING_WINNER));
    }

    /*//////////////////////////////////////////////////////////////
                          FULFILL RANDOM WORDS
    //////////////////////////////////////////////////////////////*/
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        player
        timePassed
        skipFork
    {
        raffle.enter{value: entranceFee}();

        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksWinnerAndCreditsPrize() public player timePassed skipFork {
        raffle.enter{value: entranceFee}();

        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            address newPlayer = address(uint160(i));
            hoax(newPlayer, STARTING_PLAYER_BALANCE);
            raffle.enter{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);
        uint256 startingTimestamp = raffle.getLastTimestamp();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        vm.expectEmit(true, true, false, true, address(raffle));
        emit Raffle.WinnerPicked(expectedWinner, 0, prize);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assertEq(raffle.getRecentWinner(), expectedWinner);
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
        assertGt(raffle.getLastTimestamp(), startingTimestamp);
        assertEq(raffle.getPendingPrize(expectedWinner), prize);
    }

    function testFulfillRandomWordsAdvancesRound() public player timePassed skipFork {
        raffle.enter{value: entranceFee}();

        assertEq(raffle.getCurrentRound(), 0);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assertEq(raffle.getCurrentRound(), 1);
        assertEq(raffle.getPlayersCount(), 0);
    }

    function testNewRoundPlayersAreIsolatedFromPreviousRound() public timePassed skipFork {
        address player1 = makeAddr("player1");
        vm.deal(player1, STARTING_PLAYER_BALANCE);
        vm.prank(player1);
        raffle.enter{value: entranceFee}();

        assertEq(raffle.getPlayersCountByRound(0), 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assertEq(raffle.getCurrentRound(), 1);
        assertEq(raffle.getPlayersCount(), 0);
        assertEq(raffle.getPlayersCountByRound(0), 1);

        address player2 = makeAddr("player2");
        vm.deal(player2, STARTING_PLAYER_BALANCE);
        vm.warp(block.timestamp + 1);
        vm.prank(player2);
        raffle.enter{value: entranceFee}();

        assertEq(raffle.getPlayersCount(), 1);
        assertEq(raffle.getPlayer(0), player2);
        assertEq(raffle.getPlayerByRound(0, 0), player1);
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIM PRIZE
    //////////////////////////////////////////////////////////////*/
    function testClaimPrizeRevertsIfNoPrize() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NoPrize.selector);
        raffle.claimPrize();
    }

    function testClaimPrizeTransfersETHToWinner() public player timePassed skipFork {
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address winner = raffle.getRecentWinner();
        uint256 prize = raffle.getPendingPrize(winner);
        uint256 winnerBalanceBefore = winner.balance;

        assertGt(prize, 0);

        vm.prank(winner);
        raffle.claimPrize();

        assertEq(winner.balance, winnerBalanceBefore + prize);
        assertEq(raffle.getPendingPrize(winner), 0);
    }

    function testClaimPrizeEmitsEvent() public player timePassed skipFork {
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address winner = raffle.getRecentWinner();
        uint256 prize = raffle.getPendingPrize(winner);

        vm.expectEmit(true, false, false, true, address(raffle));
        emit Raffle.PrizeClaimed(winner, prize);
        vm.prank(winner);
        raffle.claimPrize();
    }

    function testClaimPrizeCannotBeCalledTwice() public player timePassed skipFork {
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address winner = raffle.getRecentWinner();

        vm.startPrank(winner);
        raffle.claimPrize();

        vm.expectRevert(Raffle.Raffle__NoPrize.selector);
        raffle.claimPrize();
        vm.stopPrank();
    }

    function testPrizeIsCorrectWhenMultipleWinnersDoNotClaim() public timePassed skipFork {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address charlie = makeAddr("charlie");
        vm.deal(alice, STARTING_PLAYER_BALANCE);
        vm.deal(bob, STARTING_PLAYER_BALANCE);
        vm.deal(charlie, STARTING_PLAYER_BALANCE);

        // Round 0: Alice enters and wins, does NOT claim
        vm.prank(alice);
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assertEq(raffle.getRecentWinner(), alice);
        assertEq(raffle.getPendingPrize(alice), entranceFee);

        // Round 1: Bob enters and wins, does NOT claim
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.prank(bob);
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        entries = vm.getRecordedLogs();
        requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assertEq(raffle.getRecentWinner(), bob);
        assertEq(raffle.getPendingPrize(bob), entranceFee);
        assertEq(raffle.getPendingPrize(alice), entranceFee);

        // Round 2: Charlie enters and wins — prize must be exactly entranceFee, not more
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.prank(charlie);
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        entries = vm.getRecordedLogs();
        requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assertEq(raffle.getRecentWinner(), charlie);
        assertEq(raffle.getPendingPrize(charlie), entranceFee);
        assertEq(raffle.getPendingPrize(alice), entranceFee);
        assertEq(raffle.getPendingPrize(bob), entranceFee);

        assertEq(address(raffle).balance, entranceFee * 3);
    }

    function testMultipleRoundWinsAccumulatePrize() public timePassed skipFork {
        vm.prank(PLAYER);
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address winner = raffle.getRecentWinner();
        uint256 firstPrize = raffle.getPendingPrize(winner);

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.deal(winner, STARTING_PLAYER_BALANCE);
        vm.prank(winner);
        raffle.enter{value: entranceFee}();

        vm.recordLogs();
        raffle.performUpkeep("");
        entries = vm.getRecordedLogs();
        requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assertEq(raffle.getPendingPrize(winner), firstPrize + entranceFee);
    }
}
