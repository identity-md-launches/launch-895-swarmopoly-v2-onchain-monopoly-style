// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {PoolKey, SwapParams, IUnlockCallback} from "../../src/interfaces/IV4.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Models v4's signed packed delta, single unlock callback, sync/settle and take accounting.
contract MockPoolManager {
    address public locker;
    address private input;
    address private output;
    uint256 private debt;
    uint256 private credit;
    uint256 private syncedBalance;
    bool private synced;
    bool public partialFill;
    bool public badSettle;

    function configure(bool partialFill_, bool badSettle_) external {
        partialFill = partialFill_;
        badSettle = badSettle_;
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        require(locker == address(0), "locked");
        locker = msg.sender;
        result = IUnlockCallback(msg.sender).unlockCallback(data);
        require(debt == 0 && credit == 0, "unsettled");
        locker = address(0);
    }

    function swap(PoolKey calldata key, SwapParams calldata p, bytes calldata) external returns (int256 delta) {
        require(msg.sender == locker && p.amountSpecified < 0, "not exact input");
        uint256 amount = uint256(-p.amountSpecified);
        if (partialFill) amount /= 2;
        debt = amount;
        credit = amount * 2;
        input = p.zeroForOne ? key.currency0 : key.currency1;
        output = p.zeroForOne ? key.currency1 : key.currency0;
        int128 inDelta = -int128(int256(amount));
        int128 outDelta = int128(int256(credit));
        int128 d0 = p.zeroForOne ? inDelta : outDelta;
        int128 d1 = p.zeroForOne ? outDelta : inDelta;
        delta = (int256(d0) << 128) | int256(uint256(uint128(d1)));
    }

    function sync(address token) external {
        require(msg.sender == locker && token == input, "sync");
        syncedBalance = MockERC20(token).balanceOf(address(this));
        synced = true;
    }

    function settle() external payable returns (uint256 amount) {
        require(msg.sender == locker && synced, "settle");
        amount = MockERC20(input).balanceOf(address(this)) - syncedBalance;
        require(amount == debt, "debt");
        debt = 0;
        synced = false;
        if (badSettle) return amount - 1;
    }

    function take(address token, address to, uint256 amount) external {
        require(msg.sender == locker && token == output && amount == credit, "take");
        credit = 0;
        require(MockERC20(token).transfer(to, amount));
    }
}
