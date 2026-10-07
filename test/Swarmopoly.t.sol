// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {SeasonPot} from "../src/SeasonPot.sol";
import {DeedVault} from "../src/DeedVault.sol";
import {SwarmopolyGame} from "../src/SwarmopolyGame.sol";
import {PoolKey} from "../src/interfaces/IV4.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";

abstract contract SwarmopolyFixture is Test {
    SeasonPot internal pot;
    DeedVault internal vault;
    SwarmopolyGame internal game;
    MockERC20 internal cash;
    MockERC20 internal token;
    MockPoolManager internal manager;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    PoolKey internal key;
    bytes32 internal constant FUTURE = keccak256("future block");

    function setUp() public virtual {
        vm.warp(10 days);
        vm.roll(100);
        cash = new MockERC20();
        token = new MockERC20();
        manager = new MockPoolManager();
        pot = new SeasonPot(address(this), address(cash));
        vault = new DeedVault(address(this), address(cash), address(manager));
        game = new SwarmopolyGame(address(this), address(cash), address(vault), address(pot));
        pot.bindGame(address(game));
        vault.bindGame(address(game));
        key = PoolKey(
            address(cash) < address(token) ? address(cash) : address(token),
            address(cash) < address(token) ? address(token) : address(cash),
            3000,
            60,
            address(0)
        );
        game.listTile(6, key, 3);
        game.listTile(9, key, 8);
        token.mint(address(manager), 1e30);
        game.startSeason(10 ether, 30 days, 1 ether, 100 ether);
        _join(alice);
        _join(bob);
    }

    function _join(address who) internal {
        cash.mint(who, 1e25);
        vm.startPrank(who);
        cash.approve(address(game), type(uint256).max);
        game.joinSeason();
        game.deposit(100 ether);
        vm.stopPrank();
    }

    function _secret(address who, uint8 distance, uint256 card) internal view returns (bytes32 secret) {
        uint256 nonce = game.player(who).nonce + 1;
        for (uint256 i = 1;; ++i) {
            secret = bytes32(i);
            uint256 entropy = uint256(keccak256(abi.encode(secret, FUTURE, who, nonce)));
            if (entropy % 6 + 1 + (entropy / 6) % 6 + 1 == distance && (card == 99 || (entropy >> 16) % 5 == card)) {
                return secret;
            }
        }
    }

    function _roll(address who, uint8 distance, uint256 card) internal {
        uint256 next = game.player(who).nextRoll;
        if (vm.getBlockTimestamp() < next) vm.warp(next);
        bytes32 secret = _secret(who, distance, card);
        bytes32 commitment = game.commitmentFor(who, secret);
        vm.prank(who);
        game.commitRoll(commitment);
        uint256 entropyBlock = vm.getBlockNumber() + 1;
        vm.roll(vm.getBlockNumber() + 2);
        vm.setBlockhash(entropyBlock, FUTURE);
        vm.prank(who);
        game.revealRoll(secret);
    }

    function _buy(address who, uint256 amount, uint8 lockDays) internal returns (uint256 id) {
        _roll(who, 6, 99);
        vm.prank(who);
        id = game.buyDeed(6, amount, amount * 2, lockDays);
    }

    function _checkSolvent() internal view {
        assertEq(cash.balanceOf(address(game)), game.totalPlayBalance());
        assertEq(cash.balanceOf(address(pot)), pot.available() + pot.reserved());
        assertEq(cash.balanceOf(address(vault)), vault.rentReceived() - vault.rentClaimed());
        assertGe(game.totalRentPaid(), game.totalRentCredited());
        DeedVault.Tile memory t6 = vault.tile(6);
        DeedVault.Tile memory t9 = vault.tile(9);
        assertEq(
            token.balanceOf(address(vault)),
            t6.assets + t9.assets + vault.sponsorLiability(6) + vault.sponsorLiability(9)
        );
    }
}

contract SwarmopolyTest is SwarmopolyFixture {
    function testBindingsAndOwnerRestrictions() public {
        vm.expectRevert();
        pot.bindGame(address(game));
        vm.expectRevert();
        vault.bindGame(address(game));
        vm.startPrank(alice);
        vm.expectRevert();
        pot.pay(alice, 1);
        vm.expectRevert();
        pot.credit(1);
        vm.expectRevert();
        vault.creditRent(6, 100);
        vm.expectRevert();
        game.startSeason(0, 1 days, 1, 1);
        vm.expectRevert();
        game.listTile(8, key, 1);
        vm.expectRevert();
        game.setPaused(true, true);
        vm.stopPrank();
    }

    function testBoardAndFundedListingRestrictions() public {
        uint256 count;
        for (uint8 i; i < 40; ++i) {
            if (vault.isProperty(i)) ++count;
        }
        assertEq(count, 28);
        vm.expectRevert();
        game.listTile(0, key, 1);
        _buy(alice, 1 ether, 0);
        vm.expectRevert();
        game.listTile(6, key, 2);
        vm.expectRevert();
        game.listTile(8, key, 0);
        PoolKey memory wrong = key;
        wrong.currency0 = address(1);
        wrong.currency1 = address(token);
        vm.expectRevert();
        game.listTile(8, wrong, 1);
    }

    function testJoinDepositWithdrawalAndFailedTokenRollback() public {
        vm.startPrank(alice);
        vm.expectRevert();
        game.joinSeason();
        game.withdraw(100 ether);
        cash.configure(true, address(0), "");
        vm.expectRevert();
        game.deposit(1 ether);
        assertEq(game.player(alice).balance, 0);
        cash.configure(false, address(0), "");
        vm.stopPrank();
        _checkSolvent();
    }

    function testCommitFutureHashWrongSecretReplayAndCooldown() public {
        bytes32 secret = bytes32(uint256(11));
        bytes32 commitment = game.commitmentFor(alice, secret);
        vm.prank(alice);
        game.commitRoll(commitment);
        vm.prank(alice);
        vm.expectRevert();
        game.revealRoll(secret);
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(alice);
        vm.expectRevert();
        game.revealRoll(secret);
        vm.roll(vm.getBlockNumber() + 1);
        vm.setBlockhash(vm.getBlockNumber() - 1, FUTURE);
        vm.prank(alice);
        vm.expectRevert();
        game.revealRoll(bytes32(uint256(12)));
        vm.prank(alice);
        game.revealRoll(secret);
        vm.prank(alice);
        vm.expectRevert();
        game.revealRoll(secret);
        vm.prank(alice);
        vm.expectRevert();
        game.commitRoll(commitment);
        _checkSolvent();
    }

    function testExpiryLocksWorstCostAllowsExcessAndAnyoneResolves() public {
        bytes32 c = game.commitmentFor(alice, bytes32(uint256(7)));
        vm.prank(alice);
        game.commitRoll(c);
        vm.startPrank(alice);
        vm.expectRevert();
        game.withdraw(71 ether);
        game.withdraw(70 ether);
        game.deposit(1 ether);
        game.withdraw(1 ether);
        vm.stopPrank();
        vm.expectRevert();
        game.expireRoll(alice);
        vm.roll(vm.getBlockNumber() + 202);
        vm.prank(bob);
        game.expireRoll(alice);
        SwarmopolyGame.Player memory p = game.player(alice);
        assertEq(p.balance, 0);
        assertTrue(p.jailed);
        assertTrue(p.bankrupt);
        assertEq(p.position, 10);
        vm.prank(alice);
        vm.expectRevert();
        game.commitRoll(c);
        _checkSolvent();
    }

    function testBuyQuoteSlippageAndOnePurchasePerLanding() public {
        assertEq(vault.quote(6, 4 ether), 8 ether);
        assertEq(token.balanceOf(address(vault)), 0);
        vm.prank(alice);
        vm.expectRevert();
        game.buyDeed(6, 1 ether, 1);
        _roll(alice, 6, 99);
        vm.startPrank(alice);
        vm.expectRevert();
        game.buyDeed(6, 101 ether, 1);
        vm.expectRevert();
        game.buyDeed(6, 4 ether, 9 ether);
        vm.expectRevert();
        game.buyDeed(6, 4 ether, 0);
        uint256 id = game.buyDeed(6, 4 ether, 8 ether);
        vm.expectRevert();
        game.buyDeed(6, 4 ether, 8 ether);
        vm.stopPrank();
        assertEq(id, 1);
        assertEq(vault.tile(6).assets, 8 ether);
        _checkSolvent();
    }

    function testPartialInputAndInvalidSettlementRevertAtomically() public {
        _roll(alice, 6, 99);
        manager.configure(true, false);
        vm.prank(alice);
        vm.expectRevert();
        game.buyDeed(6, 4 ether, 1);
        manager.configure(false, true);
        vm.prank(alice);
        vm.expectRevert();
        game.buyDeed(6, 4 ether, 1);
        assertEq(vault.nextDeed(), 1);
        assertTrue(game.player(alice).canBuy);
        vm.expectRevert();
        vault.unlockCallback(abi.encode(uint8(6), 4 ether, false));
        _checkSolvent();
    }

    function testRentEightyTwentyClaimAndRedeemWhilePaused() public {
        uint256 id = _buy(alice, 4 ether, 0);
        uint256 before = pot.available();
        _roll(bob, 6, 99);
        assertEq(pot.available() - before, 0.6 ether);
        assertEq(vault.pendingRent(id), 2.4 ether);
        game.setPaused(true, true);
        vm.prank(alice);
        game.claimRent(id);
        assertEq(game.scores(1, alice), 2.4 ether);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(id);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(alice);
        assertEq(vault.redeem(id), 8 ether);
        uint256 remainingBalance = game.player(alice).balance;
        vm.prank(alice);
        game.withdraw(remainingBalance);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(id);
        _checkSolvent();
    }

    function testDonationCannotChangeSharesAndLockWeights() public {
        uint256 id = _buy(alice, 10 ether, 30);
        token.mint(address(vault), 500 ether);
        uint256 id2 = _buy(bob, 10 ether, 90);
        (,, uint256 shares, uint256 weight, uint256 unlock,,,,) = vault.deeds(id);
        (,, uint256 shares2, uint256 weight2,,,,,) = vault.deeds(id2);
        assertEq(shares, shares2);
        assertEq(weight, shares * 3);
        assertEq(weight2, shares2 * 4);
        vm.warp(unlock - 1);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(id);
        vm.warp(unlock);
        vm.prank(alice);
        assertEq(vault.redeem(id), 20 ether);
        vm.prank(bob);
        vm.expectRevert();
        vault.redeem(id2);
    }

    function testRentBankruptcyAndNextSeasonReset() public {
        vm.prank(bob);
        game.withdraw(99 ether);
        _roll(bob, 9, 99);
        assertTrue(game.player(bob).bankrupt);
        assertEq(game.player(bob).balance, 0);
        vm.warp(vm.getBlockTimestamp() + 31 days);
        game.finalizeSeason();
        game.startSeason(0, 2 days, 1 ether, 100 ether);
        vm.prank(bob);
        game.joinSeason();
        assertFalse(game.player(bob).bankrupt);
    }

    function testSponsorFundsSeparateFromAssetsAndPullClaims() public {
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);
        vault.sponsorTile(6, 10 ether, 3 ether);
        vm.expectRevert();
        vault.withdrawSponsor(1, 6);
        vm.stopPrank();
        _roll(bob, 6, 99);
        assertEq(vault.sponsorClaims(6, bob), 3 ether);
        assertEq(vault.tile(6).assets, 0);
        vm.prank(bob);
        vault.claimSponsor(6);
        assertEq(token.balanceOf(bob), 3 ether);
        vm.warp(vm.getBlockTimestamp() + 31 days);
        vm.prank(alice);
        vault.withdrawSponsor(1, 6);
        assertEq(token.balanceOf(alice), 7 ether);
        _checkSolvent();
    }

    function testTaxJailBailAndSkip() public {
        _roll(alice, 4, 99);
        assertEq(game.player(alice).balance, 95 ether);
        _roll(bob, 7, 1);
        assertTrue(game.player(bob).jailed);
        vm.prank(bob);
        game.payBail();
        assertFalse(game.player(bob).jailed);
        assertEq(game.player(bob).balance, 95 ether);
        _roll(bob, 12, 1); // 10 -> 22 chance -> jail
        vm.warp(game.player(bob).nextRoll);
        vm.prank(bob);
        game.skipJailRoll();
        assertFalse(game.player(bob).jailed);
        assertEq(game.player(bob).nextRoll, vm.getBlockTimestamp() + 20 hours);
        _checkSolvent();
    }

    function testGoSalaryOnceChanceAndParkingDaily() public {
        _roll(alice, 7, 0); // chance GO
        assertEq(game.player(alice).position, 0);
        assertEq(game.scores(1, alice), 0.02 ether);
        _roll(alice, 10, 99); // visiting
        uint256 before = pot.available();
        _roll(alice, 10, 99); // parking
        assertEq(game.scores(1, alice), 0.02 ether + before * 50 / 10000);
        _roll(alice, 12, 99); //32
        before = pot.available();
        uint256 score = game.scores(1, alice);
        _roll(alice, 10, 0); // pass GO -> chance -> GO, only one salary
        assertEq(game.scores(1, alice) - score, before * 10 / 10000);
        _checkSolvent();
    }

    function testFinalizeFullTopTenPullPrizesAndCarry() public {
        for (uint160 i = 1; i <= 10; ++i) {
            _join(address(i));
        }
        for (uint160 i = 1; i <= 10; ++i) {
            _roll(address(i), 7, 0); // Chance GO gives each winner a positive score.
        }
        uint256 before = pot.available();
        uint256 budget = before * 60 / 100;
        uint8[10] memory weights = [25, 18, 13, 10, 8, 7, 6, 5, 4, 4];
        uint256 expectedReserved;
        for (uint256 i; i < 10; ++i) {
            expectedReserved += budget * weights[i] / 100;
        }
        vm.expectRevert();
        game.finalizeSeason();
        vm.warp(vm.getBlockTimestamp() + 31 days);
        game.finalizeSeason();
        assertEq(pot.reserved(), expectedReserved);
        assertEq(pot.available(), before - expectedReserved);
        vm.expectRevert();
        game.finalizeSeason();
        address[10] memory leaders = game.leaders(1);
        for (uint256 i; i < 10; ++i) {
            assertEq(leaders[i], address(uint160(i + 1)));
            assertGt(game.scores(1, leaders[i]), 0);
            assertEq(game.prizes(1, leaders[i]), budget * weights[i] / 100);
            vm.prank(leaders[i]);
            game.claimPrize(1);
            vm.prank(leaders[i]);
            vm.expectRevert();
            game.claimPrize(1);
        }
        assertEq(pot.reserved(), 0);
        _checkSolvent();
    }

    function testOldRentCannotScoreInNewSeasonAndClaimSurvivesRedeem() public {
        uint256 id = _buy(alice, 5 ether, 0);
        _roll(bob, 6, 99);
        vm.warp(vm.getBlockTimestamp() + 31 days);
        game.finalizeSeason();
        game.startSeason(0, 2 days, 1, 1 ether);
        vm.prank(alice);
        game.joinSeason();
        vm.prank(alice);
        vault.redeem(id);
        vm.prank(alice);
        assertEq(game.claimRent(id), 2.4 ether);
        assertEq(game.scores(2, alice), 0);
        _checkSolvent();
    }

    function testReentrantTokenCannotWithdrawOrJoinDuringDeposit() public {
        cash.mint(address(cash), 1 ether);
        cash.configure(false, address(game), abi.encodeCall(game.withdraw, (1 ether)));
        vm.prank(alice);
        game.deposit(1 ether);
        assertFalse(cash.reentered());
        _checkSolvent();
    }

    function testPausedRollCanRevealAndNoETH() public {
        bytes32 secret = _secret(alice, 6, 99);
        bytes32 c = game.commitmentFor(alice, secret);
        vm.prank(alice);
        game.commitRoll(c);
        game.setPaused(true, true);
        vm.roll(vm.getBlockNumber() + 2);
        vm.setBlockhash(vm.getBlockNumber() - 1, FUTURE);
        vm.prank(alice);
        game.revealRoll(secret);
        vm.prank(alice);
        vm.expectRevert();
        game.buyDeed(6, 1 ether, 1);
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(game).call{value: 1}("");
        assertFalse(ok);
        (ok,) = address(pot).call{value: 1}("");
        assertFalse(ok);
        (ok,) = address(vault).call{value: 1}("");
        assertFalse(ok);
    }

    function testFuzzRentAccounting(uint96 raw) public {
        uint256 amount = bound(raw, 1, 100 ether);
        uint256 id = _buy(alice, amount, 0);
        _roll(bob, 6, 99);
        vm.prank(alice);
        uint256 claimed = game.claimRent(id);
        assertLe(claimed, 2.4 ether);
        vm.prank(alice);
        assertEq(game.claimRent(id), 0);
        _checkSolvent();
    }

    function testFuzzWithholdingNeverImprovesBalance(uint96 raw) public {
        uint256 starting = bound(raw, 1 ether, 100 ether);
        vm.prank(alice);
        game.withdraw(100 ether - starting == 0 ? 1 : 100 ether - starting);
        if (starting == 100 ether) {
            vm.prank(alice);
            game.deposit(1);
        }
        bytes32 secret = bytes32(uint256(raw));
        bytes32 c = game.commitmentFor(alice, secret);
        vm.prank(alice);
        game.commitRoll(c);
        uint256 snapshot = vm.snapshotState();
        vm.roll(vm.getBlockNumber() + 2);
        vm.setBlockhash(vm.getBlockNumber() - 1, FUTURE);
        vm.prank(alice);
        game.revealRoll(secret);
        uint256 revealedBalance = game.player(alice).balance;
        vm.revertToState(snapshot);
        vm.roll(vm.getBlockNumber() + 202);
        game.expireRoll(alice);
        assertLe(game.player(alice).balance, revealedBalance);
        assertEq(game.scores(1, alice), 0);
        assertTrue(game.player(alice).bankrupt);
        _checkSolvent();
    }

    function testNoReturnERC20AndFailureIsolation() public {
        cash.setNoReturn(true);
        vm.prank(alice);
        game.deposit(2 ether);
        vm.prank(alice);
        game.withdraw(2 ether);
        cash.setNoReturn(false);
        uint256 id = _buy(alice, 1 ether, 0);
        _roll(bob, 6, 99);
        cash.configure(true, address(0), "");
        vm.prank(alice);
        vm.expectRevert();
        game.claimRent(id);
        assertEq(vault.pendingRent(id), 2.4 ether);
        cash.configure(false, address(0), "");
        vm.prank(alice);
        game.claimRent(id);
        _checkSolvent();
    }

    function testWeightedRentAndNoRetroactiveRewards() public {
        uint256 a = _buy(alice, 10 ether, 30);
        uint256 b = _buy(bob, 10 ether, 90);
        assertEq(vault.pendingRent(b), 0);
        vm.prank(alice);
        game.claimRent(a);
        address charlie = address(0xCA11);
        _join(charlie);
        _roll(charlie, 6, 99);
        uint256 aRent = vault.pendingRent(a);
        uint256 bRent = vault.pendingRent(b);
        assertApproxEqAbs(aRent, uint256(2.4 ether) * 3 / 7, 1);
        assertApproxEqAbs(bRent, uint256(2.4 ether) * 4 / 7, 1);
        assertLe(aRent + bRent, 2.4 ether);
        vm.warp(vm.getBlockTimestamp() + 90 days);
        vm.prank(alice);
        vault.redeem(a);
        vm.prank(bob);
        vault.redeem(b);
        vm.prank(alice);
        game.claimRent(a);
        vm.prank(bob);
        game.claimRent(b);
        _checkSolvent();
    }

    function testParameterCapsAndSeasonImmutability() public {
        uint256[8] memory rents = [uint256(1 ether), 2 ether, 3 ether, 5 ether, 8 ether, 12 ether, 20 ether, 30 ether];
        vm.expectRevert();
        game.setParams(10, 20 hours, rents);
        vm.warp(vm.getBlockTimestamp() + 31 days);
        game.finalizeSeason();
        vm.expectRevert();
        game.setParams(51, 20 hours, rents);
        vm.expectRevert();
        game.setParams(10, 49 hours, rents);
        vm.expectRevert();
        game.setParams(10, 3599, rents);
        rents[7] = 1001 ether;
        vm.expectRevert();
        game.setParams(10, 20 hours, rents);
        rents[7] = 1000 ether;
        game.setParams(50, 48 hours, rents);
        assertEq(game.salaryBps(), 50);
        assertEq(game.cooldown(), 48 hours);
        vm.expectRevert();
        game.startSeason(0, 23 hours, 1, 1);
        vm.expectRevert();
        game.startSeason(0, 366 days, 1, 1);
        vm.expectRevert();
        game.startSeason(0, 1 days, 0, 1);
    }

    function testRevealBlockWindowLastBlockAndTimestampExpiry() public {
        bytes32 secret = _secret(alice, 6, 99);
        bytes32 c = game.commitmentFor(alice, secret);
        vm.prank(alice);
        game.commitRoll(c);
        uint256 entropyBlock = vm.getBlockNumber() + 1;
        vm.roll(entropyBlock + 200);
        vm.setBlockhash(entropyBlock, FUTURE);
        vm.prank(alice);
        game.revealRoll(secret);
        c = game.commitmentFor(bob, secret);
        vm.prank(bob);
        game.commitRoll(c);
        vm.warp(vm.getBlockTimestamp() + 3601);
        vm.prank(bob);
        vm.expectRevert();
        game.revealRoll(secret);
        game.expireRoll(bob);
        assertTrue(game.player(bob).bankrupt);
        _checkSolvent();
    }

    function testPendingRollCannotHoldSeasonOpenOrAffectFinalScores() public {
        (, uint256 end,,,) = game.seasons(1);
        vm.warp(end - 3601);
        bytes32 c = game.commitmentFor(alice, bytes32(uint256(8)));
        vm.prank(alice);
        game.commitRoll(c);
        vm.warp(end - 3600);
        vm.prank(bob);
        vm.expectRevert();
        game.commitRoll(c);
        vm.warp(end);
        game.finalizeSeason();
        game.expireRoll(alice);
        game.startSeason(0, 1 days, 1, 1);
        vm.prank(alice);
        game.joinSeason();
        assertFalse(game.player(alice).bankrupt);
        assertEq(game.scores(1, alice), 0);
        _checkSolvent();
    }

    function testApplicationRuntimeBoundsAndNoEscapeOpcodes() public view {
        _checkCode(address(game));
        _checkCode(address(vault));
        _checkCode(address(pot));
    }

    function _checkCode(address target) private view {
        bytes memory code = target.code;
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testSwapOppositeCurrencyOrdering() public {
        address otherAddress = key.currency0 == address(cash) ? address(0x10000) : address(type(uint160).max);
        vm.etch(otherAddress, address(token).code);
        MockERC20 other = MockERC20(otherAddress);
        other.mint(address(manager), 100 ether);
        PoolKey memory otherKey = PoolKey(
            address(cash) < otherAddress ? address(cash) : otherAddress,
            address(cash) < otherAddress ? otherAddress : address(cash),
            3000,
            60,
            address(0)
        );
        assertTrue((key.currency0 == address(cash)) != (otherKey.currency0 == address(cash)));
        game.listTile(8, otherKey, 1);
        assertEq(vault.quote(8, 2 ether), 4 ether);
        _roll(alice, 8, 99);
        vm.prank(alice);
        game.buyDeed(8, 2 ether, 4 ether);
        assertEq(other.balanceOf(address(vault)), 4 ether);
        assertEq(vault.tile(8).assets, 4 ether);
    }

    function testParkingCannotPayTwiceSameDay() public {
        vm.warp(41 days);
        game.finalizeSeason();
        uint256[8] memory rents = [uint256(1 ether), 2 ether, 3 ether, 5 ether, 8 ether, 12 ether, 20 ether, 30 ether];
        game.setParams(10, 1 hours, rents);
        game.startSeason(10 ether, 30 days, 1, 100 ether);
        vm.prank(alice);
        game.joinSeason();
        _roll(alice, 10, 99);
        _roll(alice, 10, 99);
        uint256 day = game.player(alice).parkingDay;
        _roll(alice, 12, 99);
        _roll(alice, 11, 99);
        _roll(alice, 8, 99);
        uint256 balance = game.player(alice).balance;
        uint256 score = game.scores(2, alice);
        _roll(alice, 9, 99);
        assertEq(game.player(alice).position, 20);
        assertEq(game.player(alice).parkingDay, day);
        assertEq(game.player(alice).balance, balance);
        assertEq(game.scores(2, alice), score);
        _checkSolvent();
    }

    function testSponsorTokenFailureDoesNotBlockLanding() public {
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);
        vault.sponsorTile(6, 10 ether, 2 ether);
        vm.stopPrank();
        token.configure(true, address(0), "");
        _roll(bob, 6, 99);
        assertEq(game.player(bob).position, 6);
        vm.prank(bob);
        vm.expectRevert();
        vault.claimSponsor(6);
        assertEq(vault.sponsorClaims(6, bob), 2 ether);
        token.configure(false, address(0), "");
        vm.prank(bob);
        vault.claimSponsor(6);
        _checkSolvent();
    }
}
