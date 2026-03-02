// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Raffle} from "../src/Raffle.sol";

contract RaffleTest is Test {
    Raffle raffle;

    uint256 constant ENTRANCE_FEE = 100 gwei;
    uint256 constant STARTING_PLAYER_BALANCE = 1 ether;
    address PLAYER = makeAddr("player");

    function setUp() public {
        raffle = new Raffle(ENTRANCE_FEE);

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
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
        emit Raffle.Raffle__Entered(PLAYER);
        raffle.enter{value: ENTRANCE_FEE}();
    }
}
