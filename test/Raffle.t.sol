// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Raffle} from "../src/Raffle.sol";

contract RaffleTest is Test {
    Raffle raffle;

    uint256 constant ENTRANCE_FEE = 100 gwei;
    uint256 constant STARTING_PLAYER_BALANCE = 1 ether;
    address PLAYER = makeAddr("player");
    uint256 constant INTERVAL = 1 days;

    function setUp() public {
        raffle = new Raffle(ENTRANCE_FEE, INTERVAL);

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleRevertsWhenFeeIsZero() public {
        vm.expectRevert(Raffle.Raffle__FeeIsTooLow.selector);
        new Raffle(0, INTERVAL);
    }

    function testRaffleRevertsWhenIntervalIsZero() public {
        vm.expectRevert(Raffle.Raffle__IntervalIsTooLow.selector);
        new Raffle(ENTRANCE_FEE, 0);
    }

    function testRaffleIsInitializedWithCorrectEntranceFee() public view {
        assertEq(raffle.getEntranceFee(), ENTRANCE_FEE);
    }

    function testRaffleIsInitializedWithCorrectInterval() public view {
        assertEq(raffle.getInterval(), INTERVAL);
    }

    modifier player() {
        vm.prank(PLAYER);
        _;
    }

    function testEnterRevertsWhenPlayerPaysLessThanEntranceFee() public player {
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enter{value: ENTRANCE_FEE - 1}();
    }

    function testEnterAddsPlayerToPlayersArray() public player {
        raffle.enter{value: ENTRANCE_FEE}();

        assertEq(raffle.getPlayer(0), PLAYER);
    }

    function testEnterEmitsEvent() public player {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit Raffle.Entered(PLAYER);
        raffle.enter{value: ENTRANCE_FEE}();
    }

    function testEnterIncreasesContractBalance() public player {
        uint256 raffleStartingBalance = address(raffle).balance;
        uint256 playerStartingBalance = PLAYER.balance;
        raffle.enter{value: ENTRANCE_FEE}();

        assertEq(address(raffle).balance, raffleStartingBalance + ENTRANCE_FEE);
        assertEq(PLAYER.balance, playerStartingBalance - ENTRANCE_FEE);
    }

    function testEnterKeepsSentFeeEvenIfItsMoreThanEntranceFee() public player {
        uint256 raffleStartingBalance = address(raffle).balance;
        uint256 playerStartingBalance = PLAYER.balance;
        uint256 extraFee = 100 gwei;
        raffle.enter{value: ENTRANCE_FEE + extraFee}();

        assertEq(address(raffle).balance, raffleStartingBalance + ENTRANCE_FEE + extraFee);
        assertEq(PLAYER.balance, playerStartingBalance - ENTRANCE_FEE - extraFee);
    }
}
