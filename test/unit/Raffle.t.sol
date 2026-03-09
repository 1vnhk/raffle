// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";

contract RaffleTest is Test {
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

    function testEnterRevertsWhenPlayerPaysLessThanEntranceFee() public player {
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enter{value: entranceFee - 1}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        raffle.enter{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
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

    // function testPickWinnerRevertsWhenIntervalHasNotPassed() public {
    //     vm.warp(block.timestamp + INTERVAL - 1);
    //     vm.expectRevert(Raffle.Raffle__IntervalHasNotPassed.selector);
    //     raffle.pickWinner();
    // }

    // TODO: fix
    // function testPickWinnerUpdatesLastTimestamp() public {
    //     uint256 lastTimestamp = raffle.getLastTimestamp();

    //     vm.warp(block.timestamp + INTERVAL);
    //     raffle.pickWinner();

    //     assertEq(raffle.getLastTimestamp(), lastTimestamp + INTERVAL);
    // }

    // function testEnterRevertsWhenRaffleIsNotOpen() public {
    //     vm.warp(block.timestamp + INTERVAL);
    //     raffle.pickWinner();
    //     vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
    //     raffle.enter{value: ENTRANCE_FEE}();
    // }

    // ih: TODO: add test for resetting state to open when winner is picked
}
