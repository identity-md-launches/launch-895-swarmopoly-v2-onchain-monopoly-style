// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwarmopolyGame} from "src/SwarmopolyGame.sol";
import {DeedVault} from "src/DeedVault.sol";
import {SeasonPot} from "src/SeasonPot.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @dev Calls the real game as players/owner, never impersonates the bound game.
/// Clocks and hashes are controlled; production storage is never overwritten.
contract AccountingHandler is Test {
    SwarmopolyGame public immutable game;
    DeedVault public immutable vault;
    SeasonPot public immutable pot;
    MockERC20 public immutable cash;
    MockERC20 public immutable token;
    address[] public actors;
    mapping(address => bytes32) private secrets;
    mapping(uint8 => uint256) public boughtAssets;
    mapping(uint8 => uint256) public redeemedAssets;
    mapping(uint8 => uint256) public sponsored;
    mapping(uint8 => uint256) public sponsorPaid;
    uint256 public donatedToken;
    uint256 public donatedGame;
    uint256 public donatedPot;
    uint256 public donatedRent;
    uint256 public resolved;
    uint256 public expired;
    uint256 public purchases;
    uint256 public redemptions;
    uint256 public seasonsFinished;

    constructor(SwarmopolyGame g, MockERC20 c, MockERC20 t, address[] memory users) {
        game = g;
        vault = g.vault();
        pot = g.pot();
        cash = c;
        token = t;
        actors = users;
        // The fixture seeds one two-IMD deed on each of these tiles.
        boughtAssets[6] = 4 ether;
        boughtAssets[9] = 4 ether;
    }

    function depositOrWithdraw(uint256 seed, uint96 raw, bool withdraw_) external {
        address who = actors[seed % actors.length];
        if (withdraw_) {
            (,,, uint256 locked,) = game.rolls(who);
            uint256 free = game.player(who).balance - locked;
            if (free == 0) return;
            uint256 amount = bound(raw, 1, free);
            uint256 before = cash.balanceOf(who);
            vm.prank(who);
            game.withdraw(amount);
            assertEq(cash.balanceOf(who) - before, amount);
        } else {
            _deposit(who, bound(raw, 1, 100 ether));
        }
    }

    function _deposit(address who, uint256 amount) private {
        cash.mint(who, amount);
        vm.prank(who);
        game.deposit(amount);
    }

    function commit(uint256 seed) public {
        address who = actors[seed % actors.length];
        SwarmopolyGame.Player memory p = game.player(who);
        (bytes32 pending,,,,) = game.rolls(who);
        if (pending != 0 || game.rollsPaused()) return;
        (, uint256 end, uint256 bond,,) = game.seasons(game.currentSeason());
        uint256 time = p.nextRoll > vm.getBlockTimestamp() ? p.nextRoll : vm.getBlockTimestamp();
        if (time + 1 hours >= end || p.bankrupt) return;
        vm.warp(time);
        if (p.jailed) {
            vm.prank(who);
            game.skipJailRoll();
            return;
        }
        if (p.balance < bond) _deposit(who, bond);
        bytes32 secret = keccak256(abi.encode(seed, p.nonce, who));
        secrets[who] = secret;
        bytes32 commitment = game.commitmentFor(who, secret);
        vm.prank(who);
        game.commitRoll(commitment);
    }

    function resolve(uint256 seed, bool withhold, uint96 buyRaw, uint8 lockRaw) public {
        address who = actors[seed % actors.length];
        (bytes32 pending, uint256 entropyBlock, uint256 deadline,,) = game.rolls(who);
        if (pending == 0) return;
        if (vm.getBlockTimestamp() > deadline || vm.getBlockNumber() > entropyBlock + 200) {
            _expire(who);
            return;
        }
        if (vm.getBlockNumber() <= entropyBlock) vm.roll(entropyBlock + 1);
        bytes32 hash = keccak256(abi.encode(entropyBlock, "accounting campaign"));
        vm.setBlockhash(entropyBlock, hash);
        if (withhold) {
            // Compare the SAME commitment in two branches from the same state.
            // Include pending rent and sponsor awards, so balance alone is not the oracle.
            uint256 snapshot = vm.snapshotState();
            vm.prank(who);
            game.revealRoll(secrets[who]);
            uint256 revealedBalance = game.player(who).balance;
            uint256 revealedScore = game.scores(game.currentSeason(), who);
            uint256 revealedRent = _rentOf(who);
            uint256 revealedSponsor = vault.sponsorClaims(6, who) + vault.sponsorClaims(9, who);
            assertTrue(vm.revertToStateAndDelete(snapshot));
            vm.warp(deadline + 1);
            _expire(who);
            assertLe(game.player(who).balance, revealedBalance, "withholding improves play balance");
            assertLe(game.scores(game.currentSeason(), who), revealedScore, "withholding improves score");
            assertLe(_rentOf(who), revealedRent, "withholding improves rent");
            assertLe(vault.sponsorClaims(6, who) + vault.sponsorClaims(9, who), revealedSponsor);
        } else {
            vm.prank(who);
            game.revealRoll(secrets[who]);
            ++resolved;
            _buy(who, buyRaw, lockRaw);
        }
    }

    function _rentOf(address who) private view returns (uint256 amount) {
        for (uint256 id = 1; id < vault.nextDeed(); ++id) {
            (address holder,,,,,,,,) = vault.deeds(id);
            if (holder == who) amount += vault.pendingRent(id);
        }
    }

    function _expire(address who) private {
        uint256 before = game.player(who).balance;
        uint256 score = game.scores(game.currentSeason(), who);
        (,,, uint256 exposure,) = game.rolls(who);
        vm.prank(actors[(uint160(who) + 1) % actors.length]);
        game.expireRoll(who);
        ++expired;
        assertEq(game.player(who).balance, before - exposure);
        assertEq(game.scores(game.currentSeason(), who), score);
        assertTrue(game.player(who).bankrupt);
        assertTrue(game.player(who).jailed);
        assertFalse(game.player(who).canBuy);
    }

    // Atomic roll/resolve keeps the random campaign productive alongside pending-roll interleavings.
    function rollAndBuy(uint256 seed, uint96 raw, uint8 lockRaw) external {
        commit(seed);
        resolve(seed, false, raw, lockRaw);
    }

    function _buy(address who, uint96 raw, uint8 lockRaw) private {
        SwarmopolyGame.Player memory p = game.player(who);
        if (!p.canBuy || game.buysPaused()) return;
        uint256 amount = bound(raw, 1, 100 ether);
        uint8 lockDays = lockRaw % 3 == 0 ? 0 : lockRaw % 3 == 1 ? 30 : 90;
        uint256 quote = vault.quote(p.position, amount);
        uint256 before = token.balanceOf(address(vault));
        vm.prank(who);
        game.buyDeed(p.position, amount, quote, lockDays);
        assertEq(token.balanceOf(address(vault)) - before, quote);
        boughtAssets[p.position] += quote;
        ++purchases;
    }

    function claimOrRedeem(uint256 seed, bool redeem_) public {
        uint256 id = 1 + seed % (vault.nextDeed() - 1);
        (address holder, uint8 slot, uint256 shares,, uint256 unlock,,,,) = vault.deeds(id);
        uint256 pending = vault.pendingRent(id);
        uint256 before = cash.balanceOf(holder);
        vm.prank(holder);
        uint256 claimed = game.claimRent(id);
        assertEq(claimed, pending);
        assertEq(cash.balanceOf(holder) - before, pending);
        vm.prank(holder);
        assertEq(game.claimRent(id), 0, "double claim");
        if (redeem_ && shares != 0 && vm.getBlockTimestamp() >= unlock) {
            before = token.balanceOf(holder);
            vm.prank(holder);
            uint256 received = vault.redeem(id);
            assertEq(token.balanceOf(holder) - before, received);
            redeemedAssets[slot] += received;
            ++redemptions;
        }
    }

    function sponsor(uint256 seed, uint96 raw) public {
        uint8 slot = seed % 2 == 0 ? 6 : 9;
        (, uint256 end,,,) = game.seasons(game.currentSeason());
        if (vm.getBlockTimestamp() >= end) return;
        address who = actors[slot == 6 ? 0 : 1];
        uint256 amount = bound(raw, 1, 10 ether);
        token.mint(who, amount);
        vm.startPrank(who);
        token.approve(address(vault), amount);
        vault.sponsorTile(slot, amount, 3 ether);
        vm.stopPrank();
        sponsored[slot] += amount;
    }

    function claimSponsorOrRemainder(uint256 seed, uint256 seasonSeed, bool remainder) public {
        uint8 slot = seed % 2 == 0 ? 6 : 9;
        if (remainder) {
            uint256 season = 1 + seasonSeed % game.currentSeason();
            (address who, uint256 remaining,) = vault.sponsors(season, slot);
            if (remaining == 0 || vm.getBlockTimestamp() < vault.seasonEnd(season)) return;
            vm.prank(who);
            vault.withdrawSponsor(season, slot);
            sponsorPaid[slot] += remaining;
        } else {
            address who = actors[seed % actors.length];
            uint256 amount = vault.sponsorClaims(slot, who);
            if (amount == 0) return;
            vm.prank(who);
            vault.claimSponsor(slot);
            sponsorPaid[slot] += amount;
        }
    }

    function newSeason() public {
        uint256 season = game.currentSeason();
        (, uint256 end,,,) = game.seasons(season);
        vm.warp(end);
        for (uint256 i; i < actors.length; ++i) {
            (bytes32 pending,,,,) = game.rolls(actors[i]);
            if (pending != 0) _expire(actors[i]);
        }
        // Finalization must not need the owner or any winner's cooperation.
        vm.prank(actors[2]);
        game.finalizeSeason();
        ++seasonsFinished;
        address owner = game.owner();
        vm.prank(owner);
        game.startSeason(10 ether, 30 days, 1 ether, 100 ether);
        for (uint256 i; i < actors.length; ++i) {
            vm.prank(actors[i]);
            game.joinSeason();
        }
    }

    function prize(uint256 seed, uint256 seasonSeed) public {
        address who = actors[seed % actors.length];
        uint256 season = 1 + seasonSeed % game.currentSeason();
        uint256 amount = game.prizes(season, who);
        if (amount == 0) return;
        uint256 before = cash.balanceOf(who);
        vm.prank(who);
        game.claimPrize(season);
        assertEq(cash.balanceOf(who) - before, amount);
        assertEq(game.prizes(season, who), 0);
    }

    function pause(bool rolls, bool buys) public {
        address owner = game.owner();
        vm.prank(owner);
        game.setPaused(rolls, buys);
    }

    function donate(uint256 seed, uint96 raw) public {
        uint256 amount = bound(raw, 1, 10 ether);
        if (seed % 4 == 0) {
            token.mint(address(vault), amount);
            donatedToken += amount;
        } else if (seed % 4 == 1) {
            cash.mint(address(game), amount);
            donatedGame += amount;
        } else if (seed % 4 == 2) {
            cash.mint(address(pot), amount);
            donatedPot += amount;
        } else {
            cash.mint(address(vault), amount);
            donatedRent += amount;
        }
    }

    function fund(uint256 seed, uint96 raw) public {
        address who = actors[seed % actors.length];
        uint256 amount = bound(raw, 1, 100 ether);
        cash.mint(who, amount);
        vm.prank(who);
        game.fundPot(amount);
    }
}
