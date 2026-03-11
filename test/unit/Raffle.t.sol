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
    bytes32 gasLane;
    uint32 callbackGasLimit;
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
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function testRaffleRevertsWhenFeeIsZero() public {
        vm.expectRevert(Raffle.Raffle__FeeIsTooLow.selector);
        new Raffle(0, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit);
    }

    function testRaffleRevertsWhenIntervalIsZero() public {
        vm.expectRevert(Raffle.Raffle__IntervalIsTooLow.selector);
        new Raffle(interval, 0, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit);
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
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
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

    function testEnterRevertsWhenPlayerPaysLessThanEntranceFee() public player {
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enter{value: entranceFee - 1}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public timePassed {
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

    function testEnterEmitsEvent() public player {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit Raffle.Entered(PLAYER);
        raffle.enter{value: entranceFee}();
    }

    function testEnterIncreasesContractBalance() public player {
        uint256 raffleStartingBalance = address(raffle).balance;
        uint256 playerStartingBalance = PLAYER.balance;
        raffle.enter{value: entranceFee}();

        assertEq(address(raffle).balance, raffleStartingBalance + entranceFee);
        assertEq(PLAYER.balance, playerStartingBalance - entranceFee);
    }

    function testEnterKeepsSentFeeEvenIfItsMoreThanEntranceFee() public player {
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
    function testCheckUpkeepReturnsFalseIfBalanceIsZero() public timePassed {
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen() public player timePassed {
        raffle.enter{value: entranceFee}();
        raffle.performUpkeep("");

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertEq(upkeepNeeded, false);
    }

    /*//////////////////////////////////////////////////////////////
                             PEFRORM UPKEEP
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

        Raffle.RaffleState state = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(state == Raffle.RaffleState.CALCULATING_WINNER);
    }

    /*//////////////////////////////////////////////////////////////
                          FULFILL RANDOM WORDS
    //////////////////////////////////////////////////////////////*/
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

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

    function testFulfillRandomWordsPicksAWinnerResetsAndSetsMoney() public player timePassed skipFork {
        raffle.enter{value: entranceFee}();

        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, STARTING_PLAYER_BALANCE);
            raffle.enter{value: entranceFee}();
        }
        uint256 startingTimestamp = raffle.getLastTimestamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState state = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimestamp = raffle.getLastTimestamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(state == Raffle.RaffleState.OPEN);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimestamp > startingTimestamp);
    }
}
