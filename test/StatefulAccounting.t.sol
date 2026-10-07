// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmopolyFixture} from "./Swarmopoly.t.sol";
import {AccountingHandler} from "./helpers/AccountingHandler.sol";
import {DeedVault} from "src/DeedVault.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract StatefulAccountingTest is SwarmopolyFixture {
    AccountingHandler internal handler;
    address[] internal users;

    function setUp() public override {
        super.setUp();
        users.push(alice);
        users.push(bob);
        for (uint160 i = 1; i <= 10; ++i) {
            address who = address(0x100000 + i);
            users.push(who);
            _join(who);
        }
        _buy(alice, 2 ether, 0);
        _roll(bob, 9, 99);
        vm.prank(bob);
        game.buyDeed(9, 2 ether, 4 ether, 90);
        handler = new AccountingHandler(game, cash, token, users);
        handler.sponsor(0, 5 ether);
        handler.sponsor(1, 5 ether);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = handler.depositOrWithdraw.selector;
        selectors[1] = handler.commit.selector;
        selectors[2] = handler.resolve.selector;
        selectors[3] = handler.rollAndBuy.selector;
        selectors[4] = handler.claimOrRedeem.selector;
        selectors[5] = handler.sponsor.selector;
        selectors[6] = handler.claimSponsorOrRemainder.selector;
        selectors[7] = handler.newSeason.selector;
        selectors[8] = handler.prize.selector;
        selectors[9] = handler.pause.selector;
        selectors[10] = handler.donate.selector;
        selectors[11] = handler.fund.selector;
        // Weight rolls twice to exercise landing economics as well as season boundaries.
        selectors[12] = handler.rollAndBuy.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariantAllCustodyAndLiabilitiesReconcile() public view {
        uint256 balances;
        for (uint256 i; i < users.length; ++i) {
            balances += game.player(users[i]).balance;
            (,,, uint256 exposure,) = game.rolls(users[i]);
            assertLe(exposure, game.player(users[i]).balance, "unbacked roll reservation");
        }
        assertEq(game.totalPlayBalance(), balances);
        assertEq(cash.balanceOf(address(game)), balances + handler.donatedGame());
        uint256 prizes;
        for (uint256 season = 1; season <= game.currentSeason(); ++season) {
            for (uint256 i; i < users.length; ++i) {
                prizes += game.prizes(season, users[i]);
            }
        }
        assertEq(pot.reserved(), prizes, "pot reservations differ from pull claims");
        assertEq(cash.balanceOf(address(pot)), pot.available() + prizes + handler.donatedPot());
        assertEq(cash.balanceOf(address(vault)), vault.rentReceived() - vault.rentClaimed() + handler.donatedRent());
        assertLe(vault.rentClaimed(), vault.rentReceived());
        assertEq(vault.rentReceived(), game.totalRentCredited());
        assertLe(game.totalRentCredited(), game.totalRentPaid());

        uint256 pending;
        for (uint256 id = 1; id < vault.nextDeed(); ++id) {
            pending += vault.pendingRent(id);
        }
        assertLe(pending + vault.rentClaimed(), vault.rentReceived(), "unfunded accrued rent");
        uint256 assets = _checkTile(6) + _checkTile(9);
        assertEq(token.balanceOf(address(vault)), assets + handler.donatedToken());
    }

    function _checkTile(uint8 slot) private view returns (uint256 liabilities) {
        DeedVault.Tile memory t = vault.tile(slot);
        uint256 shares;
        uint256 weight;
        for (uint256 id = 1; id < vault.nextDeed(); ++id) {
            (, uint8 deedSlot, uint256 s, uint256 w,,,,,) = vault.deeds(id);
            if (deedSlot == slot) {
                shares += s;
                weight += w;
            }
        }
        assertEq(t.shares, shares, "aggregate shares");
        assertEq(t.weight, weight, "aggregate weights");
        assertEq(
            t.assets + handler.redeemedAssets(slot), handler.boughtAssets(slot), "bought/redeemed asset conservation"
        );
        uint256 sponsorDebt;
        for (uint256 season = 1; season <= game.currentSeason(); ++season) {
            (, uint256 remaining,) = vault.sponsors(season, slot);
            sponsorDebt += remaining;
        }
        for (uint256 i; i < users.length; ++i) {
            sponsorDebt += vault.sponsorClaims(slot, users[i]);
        }
        assertEq(vault.sponsorLiability(slot), sponsorDebt, "sponsors plus unclaimed awards");
        assertEq(sponsorDebt + handler.sponsorPaid(slot), handler.sponsored(slot), "sponsor conservation");
        return t.assets + sponsorDebt;
    }

    function invariantLeaderboardContainsExactlyTheBestTen() public view {
        uint256 season = game.currentSeason();
        address[10] memory leaders = game.leaders(season);
        uint256 positiveScores;
        for (uint256 u; u < users.length; ++u) {
            if (game.scores(season, users[u]) != 0) ++positiveScores;
        }
        uint256 occupied = positiveScores < 10 ? positiveScores : 10;
        for (uint256 i; i < 10; ++i) {
            if (i >= occupied) {
                assertEq(leaders[i], address(0), "zero-score player occupies leaderboard");
                continue;
            }
            assertNotEq(leaders[i], address(0));
            assertGt(game.scores(season, leaders[i]), 0);
            bool known;
            for (uint256 u; u < users.length; ++u) {
                if (leaders[i] == users[u]) known = true;
            }
            assertTrue(known);
            for (uint256 j; j < i; ++j) {
                assertNotEq(leaders[i], leaders[j]);
            }
            if (i > 0) assertTrue(_outranks(leaders[i - 1], leaders[i], season));
        }
        for (uint256 u; u < users.length; ++u) {
            if (game.scores(season, users[u]) == 0) continue;
            bool listed;
            for (uint256 i; i < 10; ++i) {
                if (leaders[i] == users[u]) listed = true;
            }
            if (!listed) {
                assertEq(occupied, 10, "scoring player omitted from available slot");
                assertTrue(_outranks(leaders[9], users[u], season), "better player omitted");
            }
        }
    }

    function _outranks(address a, address b, uint256 season) private view returns (bool) {
        uint256 sa = game.scores(season, a);
        uint256 sb = game.scores(season, b);
        return sa > sb || (sa == sb && uint160(a) < uint160(b));
    }

    function testLeaderboardOracleCoversEmptyPartialAndOverflowingRankings() public {
        invariantLeaderboardContainsExactlyTheBestTen();
        for (uint256 i; i < users.length; ++i) {
            // Seeded deed holders start at 6 and 9; everyone else starts at GO.
            _roll(users[i], i == 0 ? 11 : i == 1 ? 8 : 7, 0);
            assertGt(game.scores(1, users[i]), 0);
            invariantLeaderboardContainsExactlyTheBestTen();
        }
        // A scorer omitted from a full board can subsequently take first place.
        address challenger = users[users.length - 1];
        _roll(challenger, 7, 0);
        assertEq(game.leaders(1)[0], challenger);
        invariantLeaderboardContainsExactlyTheBestTen();
        invariantAllCustodyAndLiabilitiesReconcile();
    }

    // Deterministic reachability check: the campaign must do more than return/revert.
    function testHandlerExercisesRollBuyExpireRedeemAndRollover() public {
        for (uint256 i; i < 100; ++i) {
            handler.rollAndBuy(i, 2 ether, 0);
        }
        assertGt(handler.resolved(), 0);
        assertGt(handler.purchases(), 0);
        handler.newSeason();
        handler.pause(false, false);
        handler.commit(0);
        handler.resolve(0, true, 1, 0);
        assertGt(handler.expired(), 0);
        handler.claimOrRedeem(0, true);
        assertGt(handler.redemptions(), 0);
        handler.prize(0, 0);
        handler.claimSponsorOrRemainder(0, 0, true);
        invariantAllCustodyAndLiabilitiesReconcile();
        invariantLeaderboardContainsExactlyTheBestTen();
    }
}
