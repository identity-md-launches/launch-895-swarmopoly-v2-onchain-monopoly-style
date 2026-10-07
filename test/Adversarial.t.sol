// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmopolyFixture} from "./Swarmopoly.t.sol";
import {Owned} from "src/Owned.sol";
import {SeasonPot} from "src/SeasonPot.sol";
import {DeedVault} from "src/DeedVault.sol";
import {SwarmopolyGame} from "src/SwarmopolyGame.sol";
import {PoolKey, IPoolManager} from "src/interfaces/IV4.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AdversarialTest is SwarmopolyFixture {
    function _reject(address caller, address target, bytes memory data, bytes4 reason) private {
        vm.prank(caller);
        (bool ok, bytes memory result) = target.call(data);
        assertFalse(ok, "unauthorized call succeeded");
        assertEq(bytes4(result), reason, "wrong failure reason");
    }

    function testOwnerCannotMoveCustodyThroughGameOnlyEntrypoints() public {
        address[2] memory callers = [address(this), alice];
        for (uint256 i; i < callers.length; ++i) {
            address caller = callers[i];
            _reject(caller, address(pot), abi.encodeCall(pot.credit, (1)), Owned.Unauthorized.selector);
            _reject(caller, address(pot), abi.encodeCall(pot.pay, (caller, 1)), Owned.Unauthorized.selector);
            _reject(caller, address(pot), abi.encodeCall(pot.reserve, (1)), Owned.Unauthorized.selector);
            _reject(caller, address(pot), abi.encodeCall(pot.payReserved, (caller, 1)), Owned.Unauthorized.selector);
            _reject(caller, address(vault), abi.encodeCall(vault.listTile, (8, key, 1)), Owned.Unauthorized.selector);
            _reject(
                caller, address(vault), abi.encodeCall(vault.beginSeason, (2, 99 days)), Owned.Unauthorized.selector
            );
            _reject(
                caller, address(vault), abi.encodeCall(vault.buy, (6, caller, 1, 1, 0)), Owned.Unauthorized.selector
            );
            _reject(caller, address(vault), abi.encodeCall(vault.creditRent, (6, 1)), Owned.Unauthorized.selector);
            _reject(caller, address(vault), abi.encodeCall(vault.claimRent, (1, caller)), Owned.Unauthorized.selector);
            _reject(
                caller, address(vault), abi.encodeCall(vault.awardSponsor, (6, caller)), Owned.Unauthorized.selector
            );
        }
        uint256[8] memory rents;
        _reject(alice, address(game), abi.encodeCall(game.setParams, (0, 1 hours, rents)), Owned.Unauthorized.selector);
        _checkSolvent();
    }

    function testBindingRejectsEOAUnauthorizedAndWrongDependencies() public {
        SeasonPot freshPot = new SeasonPot(address(this), address(cash));
        DeedVault freshVault = new DeedVault(address(this), address(cash), address(manager));
        SwarmopolyGame freshGame =
            new SwarmopolyGame(address(this), address(cash), address(freshVault), address(freshPot));
        _reject(
            alice,
            address(freshPot),
            abi.encodeCall(freshPot.bindGame, (address(freshGame))),
            Owned.Unauthorized.selector
        );
        _reject(
            alice,
            address(freshVault),
            abi.encodeCall(freshVault.bindGame, (address(freshGame))),
            Owned.Unauthorized.selector
        );
        vm.expectRevert(Owned.Invalid.selector);
        freshPot.bindGame(alice);
        vm.expectRevert(Owned.Invalid.selector);
        freshVault.bindGame(address(0));
        vm.expectRevert(Owned.Invalid.selector);
        freshPot.bindGame(address(game));
        vm.expectRevert(Owned.Invalid.selector);
        freshVault.bindGame(address(game));
        vm.expectRevert(Owned.Invalid.selector);
        freshGame.startSeason(0, 1 days, 1, 1);
        freshPot.bindGame(address(freshGame));
        vm.expectRevert(Owned.Invalid.selector);
        freshGame.startSeason(0, 1 days, 1, 1);
        freshVault.bindGame(address(freshGame));
        freshGame.startSeason(0, 1 days, 1, 1);
        vm.expectRevert(Owned.Invalid.selector);
        freshPot.bindGame(address(freshGame));
        vm.expectRevert(Owned.Invalid.selector);
        freshVault.bindGame(address(freshGame));
    }

    function testConstructorRejectsZeroOwnerAndMismatchedDependencies() public {
        vm.expectRevert(Owned.Invalid.selector);
        new SeasonPot(address(0), address(cash));
        vm.expectRevert(Owned.Invalid.selector);
        new SeasonPot(address(this), address(0));
        vm.expectRevert(Owned.Invalid.selector);
        new DeedVault(address(this), address(cash), address(0));
        SeasonPot wrongOwner = new SeasonPot(alice, address(cash));
        vm.expectRevert(Owned.Invalid.selector);
        new SwarmopolyGame(address(this), address(cash), address(vault), address(wrongOwner));
        SeasonPot wrongCurrency = new SeasonPot(address(this), address(token));
        vm.expectRevert(Owned.Invalid.selector);
        new SwarmopolyGame(address(this), address(cash), address(vault), address(wrongCurrency));
    }

    function testEveryBoardSlotMatchesClassicBoardAndStartsVacant() public {
        DeedVault fresh = new DeedVault(address(this), address(cash), address(manager));
        uint8[28] memory properties =
            [
            uint8(1),
            3,
            5,
            6,
            8,
            9,
            11,
            12,
            13,
            14,
            15,
            16,
            18,
            19,
            21,
            23,
            24,
            25,
            26,
            27,
            28,
            29,
            31,
            32,
            34,
            35,
            37,
            39
        ];
        for (uint256 i; i < 256; ++i) {
            bool expected;
            for (uint256 j; j < properties.length; ++j) {
                if (i == properties[j]) expected = true;
            }
            assertEq(fresh.isProperty(uint8(i)), expected);
            assertEq(fresh.tile(uint8(i)).token, address(0));
        }
    }

    function testPoolValidationRejectsInvalidKeysAtomically() public {
        for (uint256 i; i < 8; ++i) {
            PoolKey memory bad = key;
            if (i == 0) bad.currency0 = address(0);
            if (i == 1) bad.currency1 = bad.currency0;
            if (i == 2) (bad.currency0, bad.currency1) = (bad.currency1, bad.currency0);
            if (i == 3) bad.tickSpacing = 0;
            if (i == 4) bad.tickSpacing = -1;
            if (i == 5) bad.tickSpacing = 32768;
            if (i == 6) bad.fee = 1_000_001;
            if (i == 7) bad.hooks = alice;
            vm.expectRevert(Owned.Invalid.selector);
            game.listTile(8, bad, 1);
            assertEq(vault.tile(8).token, address(0));
        }
        vm.expectRevert(Owned.Invalid.selector);
        game.listTile(8, key, 9);
        PoolKey memory dynamicFee = key;
        dynamicFee.fee = 0x800000;
        game.listTile(8, dynamicFee, 8);
    }

    function testWrongHolderCannotClaimRedeemOrTransferDeed() public {
        uint256 id = _buy(alice, 1 ether, 0);
        _roll(bob, 6, 99);
        vm.prank(bob);
        vm.expectRevert(Owned.Unauthorized.selector);
        game.claimRent(id);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(bob);
        vm.expectRevert(Owned.Unauthorized.selector);
        vault.redeem(id);
        vm.prank(alice);
        (bool ok,) =
            address(vault).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", alice, bob, id));
        assertFalse(ok);
        (address holder,,,,,,,,) = vault.deeds(id);
        assertEq(holder, alice);
        assertEq(vault.pendingRent(id), 2.4 ether);
    }

    function test_RevertedBuyRestoresWalletAllowanceAndLandingRight() public {
        _roll(alice, 6, 99);
        uint256 wallet = cash.balanceOf(alice);
        uint256 allowance = cash.allowance(alice, address(game));
        uint256 poolCash = cash.balanceOf(address(manager));
        uint256 poolToken = token.balanceOf(address(manager));
        vm.startPrank(alice);
        vm.expectRevert(Owned.Invalid.selector);
        game.buyDeed(6, 1 ether, 1, 29);
        vm.expectRevert(DeedVault.SwapFailed.selector);
        game.buyDeed(6, 1 ether, 2 ether + 1);
        vm.expectRevert(Owned.Invalid.selector);
        game.buyDeed(9, 1 ether, 1);
        vm.expectRevert(Owned.Invalid.selector);
        game.buyDeed(6, 0, 1);
        vm.stopPrank();
        assertEq(cash.balanceOf(alice), wallet);
        assertEq(cash.allowance(alice, address(game)), allowance);
        assertEq(cash.balanceOf(address(manager)), poolCash);
        assertEq(token.balanceOf(address(manager)), poolToken);
        assertEq(vault.nextDeed(), 1);
        assertTrue(game.player(alice).canBuy);
        _checkSolvent();
    }

    function testInternalAccountingNeverReadsVaultTokenBalance() public {
        vm.mockCallRevert(address(token), abi.encodeCall(token.balanceOf, (address(vault))), "forbidden balance read");
        vm.mockCallRevert(address(cash), abi.encodeCall(cash.balanceOf, (address(vault))), "forbidden balance read");
        uint256 id = _buy(alice, 1, 0);
        _roll(bob, 6, 99);
        vm.prank(alice);
        assertGt(game.claimRent(id), 0);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(alice);
        assertEq(vault.redeem(id), 2);
        vm.clearMockedCalls();
        _checkSolvent();
    }

    function test_RevertedRedemptionAndSponsorWithdrawalPreserveClaims() public {
        uint256 id = _buy(alice, 2 ether, 0);
        token.mint(alice, 7 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 7 ether);
        vault.sponsorTile(6, 7 ether, 3 ether);
        vm.stopPrank();
        _roll(bob, 6, 99);
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        token.configure(true, address(0), "");
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(id);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdrawSponsor(1, 6);
        assertEq(vault.tile(6).assets, 4 ether);
        assertEq(vault.sponsorLiability(6), 7 ether);
        (, uint256 remaining,) = vault.sponsors(1, 6);
        assertEq(remaining, 4 ether);
        token.configure(false, address(0), "");
        game.setPaused(true, true);
        vm.prank(alice);
        vault.redeem(id);
        vm.prank(alice);
        vault.withdrawSponsor(1, 6);
        assertEq(vault.sponsorLiability(6), 3 ether);
        vm.prank(bob);
        vault.claimSponsor(6);
        vm.prank(bob);
        vm.expectRevert(Owned.Invalid.selector);
        vault.claimSponsor(6);
        _checkSolvent();
    }

    function testSponsorTopupCompetitionPartialLastAwardAndExactEnd() public {
        token.mint(alice, 5 ether);
        token.mint(bob, 5 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 5 ether);
        vm.expectRevert(Owned.Invalid.selector);
        vault.sponsorTile(6, 0, 1);
        vm.expectRevert(Owned.Invalid.selector);
        vault.sponsorTile(6, 1, 0);
        vault.sponsorTile(6, 2 ether, 3 ether);
        vm.expectRevert(Owned.Invalid.selector);
        vault.sponsorTile(6, 1, 2 ether);
        vault.sponsorTile(6, 3 ether, 3 ether);
        vm.stopPrank();
        vm.startPrank(bob);
        token.approve(address(vault), 5 ether);
        vm.expectRevert(Owned.Invalid.selector);
        vault.sponsorTile(6, 5 ether, 3 ether);
        vm.expectRevert(Owned.Unauthorized.selector);
        vault.withdrawSponsor(1, 6);
        vm.stopPrank();
        _roll(alice, 6, 99);
        _roll(bob, 6, 99);
        assertEq(vault.sponsorClaims(6, alice), 3 ether);
        assertEq(vault.sponsorClaims(6, bob), 2 ether);
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        vm.prank(alice);
        vm.expectRevert(Owned.Invalid.selector);
        vault.sponsorTile(6, 1, 3 ether);
        vm.prank(alice);
        vault.claimSponsor(6);
        vm.prank(bob);
        vault.claimSponsor(6);
        _checkSolvent();
    }

    function testCommitDomainSeparationAndNonceReplay() public {
        vm.chainId(4663);
        bytes32 secret = _secret(alice, 6, 99);
        bytes32 oldCommit = game.commitmentFor(alice, secret);
        assertNotEq(oldCommit, game.commitmentFor(bob, secret));
        vm.chainId(4664);
        assertNotEq(oldCommit, game.commitmentFor(alice, secret));
        vm.chainId(4663);
        SwarmopolyGame other = new SwarmopolyGame(address(this), address(cash), address(vault), address(pot));
        assertNotEq(oldCommit, other.commitmentFor(alice, secret));
        _roll(alice, 6, 99);
        assertNotEq(oldCommit, game.commitmentFor(alice, secret));
        vm.warp(game.player(alice).nextRoll);
        vm.prank(alice);
        game.commitRoll(oldCommit);
        vm.roll(vm.getBlockNumber() + 2);
        vm.setBlockhash(vm.getBlockNumber() - 1, FUTURE);
        vm.prank(alice);
        vm.expectRevert(Owned.Invalid.selector);
        game.revealRoll(secret);
    }

    function testRevealExactlyAtDeadlineAndMissingBlockhash() public {
        bytes32 secret = _secret(alice, 6, 99);
        bytes32 commitment = game.commitmentFor(alice, secret);
        vm.prank(alice);
        game.commitRoll(commitment);
        (, uint256 entropyBlock, uint256 deadline,,) = game.rolls(alice);
        vm.roll(entropyBlock + 1);
        vm.setBlockhash(entropyBlock, bytes32(0));
        vm.prank(alice);
        vm.expectRevert(Owned.Invalid.selector);
        game.revealRoll(secret);
        vm.setBlockhash(entropyBlock, FUTURE);
        vm.warp(deadline);
        vm.expectRevert(SwarmopolyGame.TooEarly.selector);
        game.expireRoll(alice);
        vm.prank(alice);
        game.revealRoll(secret);
        assertEq(game.player(alice).position, 6);
    }

    function testPendingCommitZeroCommitAndInsufficientBond() public {
        vm.startPrank(alice);
        vm.expectRevert(Owned.Invalid.selector);
        game.commitRoll(bytes32(0));
        game.withdraw(99 ether + 1);
        vm.expectRevert(Owned.Invalid.selector);
        game.commitRoll(bytes32(uint256(1)));
        game.deposit(1);
        game.commitRoll(bytes32(uint256(1)));
        vm.expectRevert(SwarmopolyGame.PendingRoll.selector);
        game.commitRoll(bytes32(uint256(2)));
        vm.stopPrank();
    }

    function testRentExactlyCoveredDoesNotBankruptAndOneWeiShortDoes() public {
        vm.prank(alice);
        game.withdraw(70 ether);
        vm.prank(bob);
        game.withdraw(70 ether + 1);
        _roll(alice, 9, 99);
        _roll(bob, 9, 99);
        assertFalse(game.player(alice).bankrupt);
        assertTrue(game.player(alice).canBuy);
        assertTrue(game.player(bob).bankrupt);
        assertFalse(game.player(bob).canBuy);
        assertEq(game.player(alice).balance, 0);
        assertEq(game.player(bob).balance, 0);
        _checkSolvent();
    }

    function testRolloverPreservesOldPrizesAndOutstandingSponsorAwards() public {
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);
        vault.sponsorTile(6, 10 ether, 2 ether);
        vm.stopPrank();
        _roll(bob, 6, 99);
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        game.finalizeSeason();
        uint256 oldReserved = pot.reserved();
        uint256 prize = game.prizes(1, bob);
        game.startSeason(0, 5 days, 1, 100 ether);
        vm.prank(bob);
        game.joinSeason();
        _roll(bob, 7, 0);
        assertEq(pot.reserved(), oldReserved);
        game.setPaused(true, true);
        cash.configure(true, address(0), "");
        vm.prank(bob);
        vm.expectRevert();
        game.claimPrize(1);
        assertEq(game.prizes(1, bob), prize);
        assertEq(pot.reserved(), oldReserved);
        cash.configure(false, address(0), "");
        vm.prank(bob);
        game.claimPrize(1);
        assertEq(pot.reserved(), oldReserved - prize);
        vm.prank(alice);
        vault.withdrawSponsor(1, 6);
        assertEq(vault.sponsorLiability(6), 2 ether);
        vm.prank(bob);
        vault.claimSponsor(6);
        _checkSolvent();
    }

    function testEmptySeasonDoesNotReserveUnassignedPrizes() public {
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        game.finalizeSeason();
        game.startSeason(0, 1 days, 1, 1);
        uint256 available = pot.available();
        uint256 reserved = pot.reserved();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        game.finalizeSeason();
        assertEq(pot.available(), available);
        assertEq(pot.reserved(), reserved);
        _checkSolvent();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzDepositWithdrawRoundtripBeforeJoining(uint128 raw, uint8 cyclesRaw) public {
        address outsider = address(0xD00D);
        uint256 amount = bound(raw, 1, type(uint128).max);
        uint256 cycles = bound(cyclesRaw, 1, 8);
        cash.mint(outsider, amount);
        vm.startPrank(outsider);
        cash.approve(address(game), type(uint256).max);
        for (uint256 i; i < cycles; ++i) {
            game.deposit(amount);
            game.withdraw(amount);
        }
        vm.stopPrank();
        assertEq(cash.balanceOf(outsider), amount);
        assertEq(game.player(outsider).balance, 0);
        _checkSolvent();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzQuoteIsReadOnlyAndMatchesPurchase(uint96 raw) public {
        uint256 amount = bound(raw, 1, 100 ether);
        uint256 poolCash = cash.balanceOf(address(manager));
        uint256 poolToken = token.balanceOf(address(manager));
        uint256 quote = vault.quote(6, amount);
        assertEq(vault.quote(6, amount), quote);
        assertEq(cash.balanceOf(address(manager)), poolCash);
        assertEq(token.balanceOf(address(manager)), poolToken);
        assertEq(vault.nextDeed(), 1);
        assertEq(manager.locker(), address(0));
        _roll(alice, 6, 99);
        vm.prank(alice);
        uint256 id = game.buyDeed(6, amount, quote);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(alice);
        assertEq(vault.redeem(id), quote);
        _checkSolvent();
    }

    function testReentrantWithdrawalHasFundsButIsBlockedDuringDeposit() public {
        // The nested caller is the token itself. Give it a real, withdrawable
        // balance so an authorization/balance failure cannot masquerade as a guard.
        cash.mint(address(cash), 2 ether);
        vm.startPrank(address(cash));
        cash.approve(address(game), type(uint256).max);
        game.deposit(2 ether);
        vm.stopPrank();
        cash.configure(false, address(game), abi.encodeCall(game.withdraw, (1 ether)));
        vm.prank(alice);
        game.deposit(1 ether);
        assertFalse(cash.reentered());
        assertEq(game.player(address(cash)).balance, 2 ether);
        // Outside the callback the identical caller and withdrawal succeed.
        vm.prank(address(cash));
        game.withdraw(1 ether);
        _checkSolvent();
    }

    function testCallbackFromManagerWithoutAnActiveSwapIsRejected() public {
        vm.prank(address(manager));
        vm.expectRevert(Owned.Unauthorized.selector);
        vault.unlockCallback(abi.encode(uint8(6), 1 ether, false));
    }

    function testManagerReturningWithoutCallbackCannotMintDeeds() public {
        _roll(alice, 6, 99);
        vm.mockCall(
            address(manager),
            abi.encodeWithSelector(IPoolManager.unlock.selector),
            abi.encode(abi.encode(uint256(2 ether)))
        );
        vm.prank(alice);
        vm.expectRevert(DeedVault.SwapFailed.selector);
        game.buyDeed(6, 1 ether, 1);
        vm.expectRevert(DeedVault.SwapFailed.selector);
        vault.quote(6, 1 ether);
        vm.clearMockedCalls();
        assertEq(vault.nextDeed(), 1);
        assertTrue(game.player(alice).canBuy);
        _checkSolvent();
    }

    function testInvalidSignedSwapDeltasRevertBeforeAnySettlement() public {
        _roll(alice, 6, 99);
        for (uint256 i; i < 5; ++i) {
            int128 input = -int128(1 ether);
            int128 output = int128(2 ether);
            if (i == 0) input = 1;
            if (i == 1) input = 0;
            if (i == 2) input = -int128(1 ether + 1);
            if (i == 3) output = 0;
            if (i == 4) output = -1;
            int128 d0 = key.currency0 == address(cash) ? input : output;
            int128 d1 = key.currency0 == address(cash) ? output : input;
            int256 delta = (int256(d0) << 128) | int256(uint256(uint128(d1)));
            vm.mockCall(address(manager), abi.encodeWithSelector(IPoolManager.swap.selector), abi.encode(delta));
            vm.prank(alice);
            vm.expectRevert(DeedVault.SwapFailed.selector);
            game.buyDeed(6, 1 ether, 1);
            vm.clearMockedCalls();
            assertEq(vault.nextDeed(), 1);
            assertTrue(game.player(alice).canBuy);
            _checkSolvent();
        }
        // A rejected callback must not poison the next valid swap context.
        vm.prank(alice);
        game.buyDeed(6, 1 ether, 2 ether);
        _checkSolvent();
    }

    function testQuoteRejectsZeroUnlistedAndOverInt128Amounts() public {
        vm.expectRevert(Owned.Invalid.selector);
        vault.quote(6, 0);
        vm.expectRevert(Owned.Invalid.selector);
        vault.quote(8, 1);
        vm.expectRevert(Owned.Invalid.selector);
        vault.quote(6, uint256(uint128(type(int128).max)) + 1);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzWeightedRentConservationAndExactMaturities(uint96 rawA, uint96 rawB, uint8 lockRaw) public {
        uint256 amountA = bound(rawA, 1, 100 ether);
        uint256 amountB = bound(rawB, 1, 100 ether);
        uint8 lockDays = lockRaw % 3 == 0 ? 0 : lockRaw % 3 == 1 ? 30 : 90;
        uint256 a = _buy(alice, amountA, lockDays);
        uint256 b = _buy(bob, amountB, 0);
        uint256 oldA = vault.pendingRent(a);
        address lander = address(0xFEED);
        _join(lander);
        _roll(lander, 6, 99);
        uint256 aRent = vault.pendingRent(a) - oldA;
        uint256 bRent = vault.pendingRent(b);
        uint256 wa = amountA * (lockDays == 90 ? 4 : lockDays == 30 ? 3 : 2);
        uint256 wb = amountB * 2;
        // A proportional oracle from the specified 80% allocation, independent
        // of the implementation's 1e27 accumulator. At these bounds each deed's
        // accumulator rounding contributes at most one wei per landing.
        assertApproxEqAbs(aRent, uint256(2.4 ether) * wa / (wa + wb), 1);
        assertApproxEqAbs(bRent, uint256(2.4 ether) * wb / (wa + wb), 1);
        assertLe(vault.pendingRent(a) + vault.pendingRent(b), vault.rentReceived());
        (,,,, uint256 maturity,,,,) = vault.deeds(a);
        vm.warp(maturity - 1);
        vm.prank(alice);
        vm.expectRevert(Owned.Invalid.selector);
        vault.redeem(a);
        vm.warp(maturity);
        vm.prank(alice);
        assertEq(vault.redeem(a), amountA * 2);
        vm.prank(alice);
        game.claimRent(a);
        vm.prank(bob);
        game.claimRent(b);
        _checkSolvent();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzEveryPrizeRankMatchesFixedWeightsAndRounding(uint96 raw) public {
        for (uint160 i = 1; i <= 10; ++i) {
            _join(address(0x200000 + i));
        }
        uint256 funding = bound(raw, 1, 1e24);
        cash.mint(alice, funding);
        vm.prank(alice);
        game.fundPot(funding);
        uint256 available = pot.available();
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end);
        vm.prank(address(0xBAD));
        game.finalizeSeason();
        address[10] memory winners = game.leaders(1);
        uint256[10] memory weights = [uint256(25), 18, 13, 10, 8, 7, 6, 5, 4, 4];
        uint256 budget = available * 60 / 100;
        uint256 distributed;
        for (uint256 i; i < 10; ++i) {
            uint256 expected = budget * weights[i] / 100;
            assertEq(game.prizes(1, winners[i]), expected, "incorrect rank weight");
            uint256 wallet = cash.balanceOf(winners[i]);
            vm.prank(winners[i]);
            game.claimPrize(1);
            assertEq(cash.balanceOf(winners[i]) - wallet, expected);
            distributed += expected;
        }
        assertLe(budget - distributed, 9, "excess rounding loss");
        assertEq(pot.available(), available - distributed);
        assertEq(pot.reserved(), 0);
        _checkSolvent();
    }
}
