// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SwarmopolyFixture} from "./Swarmopoly.t.sol";
import {SwarmopolyGame} from "../src/SwarmopolyGame.sol";
import {DeedVault} from "../src/DeedVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract GameHandler is Test {
    SwarmopolyGame public game;
    DeedVault public vault;
    MockERC20 public cash;
    MockERC20 public token;
    address[2] public actors;

    constructor(SwarmopolyGame g, DeedVault v, MockERC20 c, MockERC20 t, address a, address b) {
        game = g;
        vault = v;
        cash = c;
        token = t;
        actors = [a, b];
    }

    function depositWithdraw(uint256 seed, uint96 raw, bool withdrawing) external {
        address who = actors[seed % 2];
        if (withdrawing) {
            (,,, uint256 locked,) = game.rolls(who);
            uint256 available = game.player(who).balance - locked;
            if (available == 0) return;
            vm.prank(who);
            game.withdraw(bound(raw, 1, available));
        } else {
            uint256 amount = bound(raw, 1, 100 ether);
            cash.mint(who, amount);
            vm.prank(who);
            game.deposit(amount);
        }
    }

    function rollBuy(uint256 seed) external {
        address who = actors[seed % 2];
        SwarmopolyGame.Player memory p = game.player(who);
        (, uint256 end, uint256 bond,, bool finalized) = game.seasons(game.currentSeason());
        if (p.bankrupt || finalized || vm.getBlockTimestamp() + 1 days >= end) return;
        if (p.nextRoll > vm.getBlockTimestamp()) vm.warp(p.nextRoll);
        if (p.jailed) {
            vm.prank(who);
            game.skipJailRoll();
            return;
        }
        if (p.balance < bond) {
            cash.mint(who, bond);
            vm.prank(who);
            game.deposit(bond);
        }
        bytes32 secret = keccak256(abi.encode(seed, p.nonce));
        bytes32 c = game.commitmentFor(who, secret);
        vm.prank(who);
        game.commitRoll(c);
        uint256 entropyBlock = vm.getBlockNumber() + 1;
        if (seed % 11 == 0) {
            vm.roll(vm.getBlockNumber() + 202);
            game.expireRoll(who);
            return;
        }
        vm.roll(vm.getBlockNumber() + 2);
        vm.setBlockhash(entropyBlock, keccak256(abi.encode(seed, entropyBlock)));
        vm.prank(who);
        game.revealRoll(secret);
        p = game.player(who);
        if (p.canBuy) {
            vm.prank(who);
            game.buyDeed(p.position, 1 ether + seed % 1 ether, 1, seed % 3 == 0 ? 30 : 0);
        }
    }

    function claimRedeem(uint256 seed, bool redeeming) external {
        uint256 next = vault.nextDeed();
        if (next == 1) return;
        uint256 id = 1 + seed % (next - 1);
        (address holder,, uint256 shares,, uint256 unlock,,,,) = vault.deeds(id);
        vm.prank(holder);
        game.claimRent(id);
        if (redeeming && shares != 0 && vm.getBlockTimestamp() >= unlock) {
            vm.prank(holder);
            vault.redeem(id);
        }
    }

    function sponsorAndClaim(uint256 seed, uint96 raw) external {
        uint256 amount = bound(raw, 1, 10 ether);
        (, uint256 end,,,) = game.seasons(game.currentSeason());
        if (vm.getBlockTimestamp() >= end) return;
        address who = actors[0];
        token.mint(who, amount);
        vm.startPrank(who);
        token.approve(address(vault), amount);
        vault.sponsorTile(6, amount, 1 ether);
        vm.stopPrank();
        who = actors[seed % 2];
        if (vault.sponsorClaims(6, who) != 0) {
            vm.prank(who);
            vault.claimSponsor(6);
        }
    }

    function newSeason() external {
        uint256 season = game.currentSeason();
        (, uint256 end,,,) = game.seasons(season);
        vm.warp(end + 1);
        game.finalizeSeason();
        address controller = game.owner();
        vm.prank(controller);
        game.startSeason(10 ether, 30 days, 1 ether, 100 ether);
        for (uint256 i; i < 2; ++i) {
            vm.prank(actors[i]);
            game.joinSeason();
            uint256 prize = game.prizes(season, actors[i]);
            if (prize != 0) {
                vm.prank(actors[i]);
                game.claimPrize(season);
            }
        }
        (address sponsor, uint256 remaining,) = vault.sponsors(season, 6);
        if (remaining != 0) {
            vm.prank(sponsor);
            vault.withdrawSponsor(season, 6);
        }
    }
}

contract AccountingInvariants is StdInvariant, SwarmopolyFixture {
    GameHandler private handler;

    function setUp() public override {
        super.setUp();
        _buy(alice, 2 ether, 0);
        handler = new GameHandler(game, vault, cash, token, alice, bob);
        targetContract(address(handler));
    }

    function invariant_gamePotRentAndVaultSolvent() public view {
        _checkSolvent();
    }

    function invariant_rentNeverCreatesMoney() public view {
        assertLe(vault.rentClaimed(), vault.rentReceived());
        assertEq(vault.rentReceived(), game.totalRentCredited());
        assertLe(game.totalRentCredited(), game.totalRentPaid());
    }

    function invariant_sharesAndWeightsMatchDeeds() public view {
        uint256 shares;
        uint256 weight;
        for (uint256 i = 1; i < vault.nextDeed(); ++i) {
            (, uint8 slot, uint256 s, uint256 w,,,,,) = vault.deeds(i);
            if (slot == 6) {
                shares += s;
                weight += w;
            }
        }
        assertEq(vault.tile(6).shares, shares);
        assertEq(vault.tile(6).weight, weight);
    }

    function invariant_topTenUniqueAndSorted() public view {
        uint256 season = game.currentSeason();
        address[10] memory list = game.leaders(season);
        for (uint256 i; i < 10; ++i) {
            if (list[i] == address(0)) continue;
            assertGt(game.scores(season, list[i]), 0);
            for (uint256 j = i + 1; j < 10; ++j) {
                assertTrue(list[i] != list[j]);
            }
            if (i > 0) assertGe(game.scores(season, list[i - 1]), game.scores(season, list[i]));
        }
    }
}
