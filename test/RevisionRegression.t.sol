// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmopolyFixture} from "./Swarmopoly.t.sol";
import {SwarmopolyGame} from "../src/SwarmopolyGame.sol";
import {PoolKey} from "../src/interfaces/IV4.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RevisionRegressionTest is SwarmopolyFixture {
    function testEmptyListingCanBeCorrected() public {
        PoolKey memory corrected = key;
        corrected.fee = 10000;
        game.listTile(6, corrected, 3);
        assertEq(vault.tile(6).key.fee, 10000);
        game.listTile(6, key, 3);
        assertEq(vault.tile(6).key.fee, 3000);
        game.listTile(6, key, 4);
        assertEq(vault.tile(6).tier, 4);
        assertEq(vault.quote(6, 1 ether), 2 ether);
        _buy(alice, 1 ether, 0);
        vm.expectRevert();
        game.listTile(6, corrected, 4);
        vm.expectRevert();
        game.listTile(6, key, 5);
        _checkSolvent();
    }

    function testExhaustedDustSponsorCanBeReplaced() public {
        token.mint(alice, 1);
        vm.startPrank(alice);
        token.approve(address(vault), 1);
        vault.sponsorTile(6, 1, 1);
        vm.stopPrank();
        _roll(bob, 6, 99);
        assertEq(vault.sponsorClaims(6, bob), 1);
        token.mint(bob, 100 ether);
        vm.startPrank(bob);
        token.approve(address(vault), 100 ether);
        vault.sponsorTile(6, 100 ether, 1 ether);
        vm.stopPrank();
        (address sponsor, uint256 remaining, uint256 rate) = vault.sponsors(1, 6);
        assertEq(sponsor, bob);
        assertEq(remaining, 100 ether);
        assertEq(rate, 1 ether);
        assertEq(vault.sponsorClaims(6, bob), 1);
        assertEq(vault.sponsorLiability(6), 100 ether + 1);
        vm.prank(bob);
        vault.claimSponsor(6);
        _roll(alice, 6, 99);
        assertEq(vault.sponsorClaims(6, alice), 1 ether);
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdrawSponsor(1, 6);
        vm.prank(bob);
        vault.withdrawSponsor(1, 6);
        vm.prank(alice);
        vault.claimSponsor(6);
        assertEq(vault.sponsorLiability(6), 0);
        _checkSolvent();
    }

    function testCooldownPersistsWhenJoiningNewSeason() public {
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end - 3601);
        _roll(alice, 6, 99);
        uint256 next = game.player(alice).nextRoll;
        vm.warp(end);
        game.finalizeSeason();
        game.startSeason(0, 1 days, 1 ether, 100 ether);
        vm.prank(alice);
        game.joinSeason();
        assertEq(game.player(alice).nextRoll, next, "joining cleared cooldown");
        bytes32 commitment = game.commitmentFor(alice, bytes32(uint256(1)));
        vm.prank(alice);
        vm.expectRevert(SwarmopolyGame.TooEarly.selector);
        game.commitRoll(commitment);
        vm.warp(next - 1);
        vm.prank(alice);
        vm.expectRevert(SwarmopolyGame.TooEarly.selector);
        game.commitRoll(commitment);
        vm.warp(next);
        vm.prank(alice);
        game.commitRoll(commitment);
        assertEq(game.player(alice).nextRoll, next + 20 hours);
        assertEq(game.player(alice).nonce, 2);
    }

    function testObservedDustDeedReceivesHolderShare() public {
        uint256 id = _buy(alice, 1, 0);
        uint256 before = pot.available();
        _roll(bob, 6, 99);
        assertEq(vault.pendingRent(id), 2.4 ether);
        assertEq(pot.available() - before, 0.6 ether);
        _checkSolvent();
    }

    function testObservedMissedRevealPenalty() public {
        bytes32 commitment = game.commitmentFor(alice, bytes32(uint256(1)));
        vm.prank(alice);
        game.commitRoll(commitment);
        uint256 before = pot.available();
        vm.roll(vm.getBlockNumber() + 202);
        vm.prank(bob);
        game.expireRoll(alice);
        SwarmopolyGame.Player memory p = game.player(alice);
        assertEq(p.position, 10);
        assertTrue(p.jailed);
        assertTrue(p.bankrupt);
        assertEq(p.balance, 70 ether);
        assertEq(pot.available() - before, 30 ether);
        _checkSolvent();
    }

    function testObservedParkingPaysEachPlayerAndDownsideIsBalance() public {
        cash.mint(address(this), 10000 ether);
        cash.approve(address(game), 10000 ether);
        game.fundPot(10000 ether);
        vm.prank(alice);
        game.withdraw(99 ether);
        vm.prank(bob);
        game.withdraw(99 ether);
        _roll(alice, 10, 99);
        _roll(bob, 10, 99);
        uint256 before = pot.available();
        _roll(alice, 10, 99);
        assertEq(game.player(alice).balance, 1 ether + before * 50 / 10000);
        before = pot.available();
        _roll(bob, 10, 99);
        assertEq(game.player(bob).balance, 1 ether + before * 50 / 10000);
        assertEq(game.player(alice).parkingDay, game.player(bob).parkingDay);
        address charlie = address(0xCA11);
        _join(charlie);
        vm.prank(charlie);
        game.withdraw(99 ether);
        _roll(charlie, 9, 99);
        assertEq(game.player(charlie).balance, 0);
        assertTrue(game.player(charlie).bankrupt);
        _checkSolvent();
    }

    function testZeroScoreJoinersLeaveAllPrizeBudgetAvailable() public {
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        game.finalizeSeason();
        game.startSeason(0, 1 days, 1 ether, 1 ether);
        cash.mint(address(this), 1000 ether);
        cash.approve(address(game), 1000 ether);
        game.fundPot(1000 ether);
        uint256 before = pot.available();
        for (uint160 i; i < 10; ++i) {
            vm.prank(address(uint160(0x1000 + i)));
            game.joinSeason();
        }
        address[10] memory list = game.leaders(2);
        for (uint256 i; i < 10; ++i) {
            assertEq(list[i], address(0));
        }
        vm.warp(vm.getBlockTimestamp() + 1 days);
        game.finalizeSeason();
        assertEq(pot.available(), before);
        assertEq(pot.reserved(), 0);
        for (uint160 i; i < 10; ++i) {
            address who = address(uint160(0x1000 + i));
            assertEq(game.scores(2, who), 0);
            assertEq(game.prizes(2, who), 0);
            vm.prank(who);
            vm.expectRevert();
            game.claimPrize(2);
        }
        _checkSolvent();
    }

    function testZeroRentClaimDoesNotRankButPositiveScoreDoes() public {
        uint256 id = _buy(alice, 1 ether, 0);
        vm.prank(alice);
        assertEq(game.claimRent(id), 0);
        assertEq(game.leaders(1)[0], address(0));
        for (uint160 i; i < 12; ++i) {
            _join(address(uint160(0x1000 + i)));
        }
        _roll(bob, 6, 99);
        vm.prank(alice);
        assertEq(game.claimRent(id), 2.4 ether);
        address[10] memory list = game.leaders(1);
        assertEq(list[0], alice);
        for (uint256 i = 1; i < 10; ++i) {
            assertEq(list[i], address(0));
        }
        uint256 before = pot.available();
        uint256 prize = (before * 60 / 100) * 25 / 100;
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        game.finalizeSeason();
        assertEq(game.prizes(1, alice), prize);
        assertEq(pot.reserved(), prize);
        assertEq(pot.available(), before - prize);
        vm.prank(alice);
        game.claimPrize(1);
        _checkSolvent();
    }

    function testRelistAfterRedemptionPreservesOldRentAndNewDeedBaseline() public {
        uint256 id = _buy(alice, 1 ether, 0);
        _roll(bob, 6, 99);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(alice);
        vault.redeem(id);
        uint256 accumulator = vault.tile(6).accRent;
        uint256 baseline = vault.tile(6).seasonStartAcc;
        MockERC20 replacement = new MockERC20();
        PoolKey memory replacementKey = PoolKey(
            address(cash) < address(replacement) ? address(cash) : address(replacement),
            address(cash) < address(replacement) ? address(replacement) : address(cash),
            3000,
            60,
            address(0)
        );
        replacement.mint(address(manager), 100 ether);
        game.listTile(6, replacementKey, 4);
        assertEq(vault.tile(6).token, address(replacement));
        assertEq(vault.tile(6).accRent, accumulator);
        assertEq(vault.tile(6).seasonStartAcc, baseline);
        address charlie = address(0xCA11);
        _join(charlie);
        uint256 newId = _buy(charlie, 2 ether, 0);
        assertEq(vault.pendingRent(newId), 0);
        address dave = address(0xDA7E);
        _join(dave);
        _roll(dave, 6, 99);
        assertEq(vault.pendingRent(newId), 4 ether);
        assertEq(vault.pendingRent(id), 2.4 ether);
        vm.prank(alice);
        assertEq(game.claimRent(id), 2.4 ether);
        vm.prank(charlie);
        assertEq(game.claimRent(newId), 4 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(charlie);
        assertEq(vault.redeem(newId), 4 ether);
        assertEq(replacement.balanceOf(charlie), 4 ether);
        assertEq(replacement.balanceOf(address(vault)), 0);
        _checkSolvent();
    }

    function testSponsorLiabilitiesBlockRelistingAcrossSeasons() public {
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);
        vault.sponsorTile(6, 10 ether, 3 ether);
        vm.stopPrank();
        vm.expectRevert();
        game.listTile(6, key, 4);
        _roll(bob, 6, 99);
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        game.finalizeSeason();
        game.startSeason(0, 1 days, 1, 1);
        vm.expectRevert();
        game.listTile(6, key, 4);
        vm.prank(alice);
        vault.withdrawSponsor(1, 6);
        assertEq(vault.sponsorLiability(6), 3 ether);
        vm.expectRevert();
        game.listTile(6, key, 4);
        game.setPaused(true, true);
        vm.prank(bob);
        vault.claimSponsor(6);
        game.listTile(6, key, 4);
        assertEq(vault.tile(6).tier, 4);
        _checkSolvent();
    }

    function testFundedSponsorCannotBeReplacedOrRateChanged() public {
        token.mint(alice, 20 ether);
        token.mint(bob, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 20 ether);
        vault.sponsorTile(6, 5 ether, 1 ether);
        vault.sponsorTile(6, 5 ether, 1 ether);
        vm.expectRevert();
        vault.sponsorTile(6, 1 ether, 2 ether);
        vm.stopPrank();
        vm.startPrank(bob);
        token.approve(address(vault), 10 ether);
        vm.expectRevert();
        vault.sponsorTile(6, 10 ether, 1 ether);
        vm.stopPrank();
        (address sponsor, uint256 remaining, uint256 rate) = vault.sponsors(1, 6);
        assertEq(sponsor, alice);
        assertEq(remaining, 10 ether);
        assertEq(rate, 1 ether);
        _checkSolvent();
    }
}
