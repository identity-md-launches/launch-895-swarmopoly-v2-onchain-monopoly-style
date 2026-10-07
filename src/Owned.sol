// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

abstract contract Owned {
    address public immutable owner;
    error Unauthorized();
    error Invalid();

    constructor(address owner_) {
        if (owner_ == address(0)) revert Invalid();
        owner = owner_;
    }
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
}
