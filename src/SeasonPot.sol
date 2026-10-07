// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Owned} from "./Owned.sol";
import {IBoundGame} from "./interfaces/IV4.sol";

/// @notice Only the immutable, once-bound game may account for or move funds.
contract SeasonPot is Owned, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable currency;
    address public game;
    uint256 public available;
    uint256 public reserved;
    event GameBound(address indexed game);
    event PotChanged(uint256 available, uint256 reserved);

    constructor(address owner_, address currency_) Owned(owner_) {
        if (currency_ == address(0)) revert Invalid();
        currency = IERC20(currency_);
    }
    modifier onlyGame() {
        if (msg.sender != game) revert Unauthorized();
        _;
    }

    function bindGame(address game_) external onlyOwner {
        if (game != address(0) || game_.code.length == 0) revert Invalid();
        if (IBoundGame(game_).currency() != address(currency) || IBoundGame(game_).pot() != address(this)) {
            revert Invalid();
        }
        game = game_;
        emit GameBound(game_);
    }

    /// @dev Game transfers standard currency in before crediting. Direct donations are not accounted.
    function credit(uint256 amount) external onlyGame {
        available += amount;
        emit PotChanged(available, reserved);
    }

    function pay(address to, uint256 amount) external onlyGame nonReentrant {
        available -= amount;
        currency.safeTransfer(to, amount);
        emit PotChanged(available, reserved);
    }

    function reserve(uint256 amount) external onlyGame {
        available -= amount;
        reserved += amount;
        emit PotChanged(available, reserved);
    }

    function payReserved(address to, uint256 amount) external onlyGame nonReentrant {
        reserved -= amount;
        currency.safeTransfer(to, amount);
        emit PotChanged(available, reserved);
    }
}
