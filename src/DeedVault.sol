// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Owned} from "./Owned.sol";
import {PoolKey, SwapParams, IPoolManager, IBoundGame} from "./interfaces/IV4.sol";

contract DeedVault is Owned, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 private constant PRECISION = 1e27;
    IERC20 public immutable currency;
    IPoolManager public immutable poolManager;
    address public game;
    uint256 public currentSeason;
    uint256 public nextDeed = 1;
    uint256 public rentReceived;
    uint256 public rentClaimed;
    bytes32 private swapContext;

    struct Tile {
        PoolKey key;
        address token;
        uint8 tier;
        uint256 assets;
        uint256 shares;
        uint256 weight;
        uint256 accRent;
        uint256 seasonStartAcc;
    }

    struct Deed {
        address holder;
        uint8 tile;
        uint256 shares;
        uint256 weight;
        uint256 redeemAt;
        uint256 paidAcc;
        uint256 pending;
        uint256 pendingScore;
        uint256 scoreSeason;
    }

    struct Sponsorship {
        address sponsor;
        uint256 remaining;
        uint256 perLanding;
    }
    mapping(uint8 => Tile) private _tiles;
    mapping(uint256 => Deed) public deeds;
    mapping(uint256 => uint256) public seasonEnd;
    mapping(uint256 => mapping(uint8 => Sponsorship)) public sponsors;
    mapping(uint8 => mapping(address => uint256)) public sponsorClaims;
    mapping(uint8 => uint256) public sponsorLiability;
    event GameBound(address indexed game);
    event TileListed(uint8 indexed tile, PoolKey key, uint8 tier);
    event DeedBought(uint256 indexed id, address indexed holder, uint8 indexed tile, uint256 assets, uint256 shares);
    event Redeemed(uint256 indexed id, uint256 assets);
    event RentCredited(uint8 indexed tile, uint256 amount);
    event RentClaimed(uint256 indexed id, uint256 amount);
    event Sponsored(uint256 indexed season, uint8 indexed tile, address indexed sponsor, uint256 amount);
    event SponsorAward(uint8 indexed tile, address indexed player, uint256 amount);
    event SponsorClaimed(uint8 indexed tile, address indexed player, uint256 amount);
    event SponsorWithdrawn(uint256 indexed season, uint8 indexed tile, uint256 amount);
    error QuoteResult(uint256 amountOut);
    error SwapFailed();

    constructor(address owner_, address currency_, address poolManager_) Owned(owner_) {
        if (currency_ == address(0) || poolManager_ == address(0)) revert Invalid();
        currency = IERC20(currency_);
        poolManager = IPoolManager(poolManager_);
    }
    modifier onlyGame() {
        if (msg.sender != game) revert Unauthorized();
        _;
    }

    function bindGame(address game_) external onlyOwner {
        if (game != address(0) || game_.code.length == 0) revert Invalid();
        if (IBoundGame(game_).currency() != address(currency) || IBoundGame(game_).vault() != address(this)) {
            revert Invalid();
        }
        game = game_;
        emit GameBound(game_);
    }

    function isProperty(uint8 slot) public pure returns (bool) {
        if (slot >= 40) return false;
        return slot != 0 && slot != 2 && slot != 4 && slot != 7 && slot != 10 && slot != 17 && slot != 20 && slot != 22
            && slot != 30 && slot != 33 && slot != 36 && slot != 38;
    }

    function tile(uint8 slot) external view returns (Tile memory) {
        return _tiles[slot];
    }

    function tileInfo(uint8 slot) external view returns (address token, uint8 tier, uint256 weight) {
        Tile storage t = _tiles[slot];
        return (t.token, t.tier, t.weight);
    }

    /// @notice Listings are permanent, including after the last deed is redeemed.
    function listTile(uint8 slot, PoolKey calldata key, uint8 tier) external onlyGame {
        if (!isProperty(slot) || _tiles[slot].token != address(0) || tier < 1 || tier > 8) revert Invalid();
        if (
            key.currency0 == address(0) || key.currency0 >= key.currency1 || key.tickSpacing <= 0
                || key.tickSpacing > 32767 || (key.fee > 1_000_000 && key.fee != 0x800000)
        ) revert Invalid();
        if (key.currency0 != address(currency) && key.currency1 != address(currency)) revert Invalid();
        address token = key.currency0 == address(currency) ? key.currency1 : key.currency0;
        if (token.code.length == 0 || (key.hooks != address(0) && key.hooks.code.length == 0)) revert Invalid();
        _tiles[slot].key = key;
        _tiles[slot].token = token;
        _tiles[slot].tier = tier;
        emit TileListed(slot, key, tier);
    }

    function beginSeason(uint256 id, uint256 end) external onlyGame {
        currentSeason = id;
        seasonEnd[id] = end;
        for (uint8 i; i < 40; ++i) {
            _tiles[i].seasonStartAcc = _tiles[i].accRent;
        }
    }

    /// @dev Game has transferred exact currency input to this vault. No ERC20 balance reads.
    function buy(uint8 slot, address holder, uint256 amount, uint256 minOut, uint8 lockDays)
        external
        onlyGame
        nonReentrant
        returns (uint256 id)
    {
        if (lockDays != 0 && lockDays != 30 && lockDays != 90) revert Invalid();
        if (minOut == 0) revert Invalid();
        uint256 out = _swap(slot, amount, false);
        if (out < minOut) revert SwapFailed();
        Tile storage t = _tiles[slot];
        uint256 shares = t.shares == 0 ? out : Math.mulDiv(out, t.shares, t.assets);
        if (shares == 0) revert Invalid();
        uint256 weight = shares * (lockDays == 90 ? 4 : lockDays == 30 ? 3 : 2);
        id = nextDeed++;
        deeds[id] = Deed(
            holder,
            slot,
            shares,
            weight,
            block.timestamp + (lockDays == 0 ? 1 days : uint256(lockDays) * 1 days),
            t.accRent,
            0,
            0,
            currentSeason
        );
        t.assets += out;
        t.shares += shares;
        t.weight += weight;
        emit DeedBought(id, holder, slot, out, shares);
    }

    /// @notice Simulates the actual swap, rolls it back before settlement, and returns its output.
    function quote(uint8 slot, uint256 amount) external nonReentrant returns (uint256) {
        return _swap(slot, amount, true);
    }

    function _swap(uint8 slot, uint256 amount, bool quoting) private returns (uint256) {
        if (_tiles[slot].token == address(0) || amount == 0 || amount > uint256(uint128(type(int128).max))) {
            revert Invalid();
        }
        bytes memory data = abi.encode(slot, amount, quoting);
        swapContext = keccak256(data);
        try poolManager.unlock(data) returns (bytes memory result) {
            if (quoting || swapContext != bytes32(0)) revert SwapFailed();
            return abi.decode(result, (uint256));
        } catch (bytes memory reason) {
            swapContext = bytes32(0);
            if (quoting && reason.length == 36 && bytes4(reason) == QuoteResult.selector) {
                uint256 out;
                assembly ("memory-safe") { out := mload(add(reason, 36)) }
                return out;
            }
            assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager) || swapContext == bytes32(0) || keccak256(data) != swapContext) {
            revert Unauthorized();
        }
        swapContext = bytes32(0);
        (uint8 slot, uint256 amount, bool quoting) = abi.decode(data, (uint8, uint256, bool));
        Tile storage t = _tiles[slot];
        bool zeroForOne = t.key.currency0 == address(currency);
        int256 delta = poolManager.swap(
            t.key,
            SwapParams(
                zeroForOne, -int256(amount), zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341
            ),
            ""
        );
        int128 d0 = int128(delta >> 128);
        int128 d1 = int128(delta);
        int256 input = zeroForOne ? int256(d0) : int256(d1);
        int256 output = zeroForOne ? int256(d1) : int256(d0);
        if (input != -int256(amount) || output <= 0) revert SwapFailed();
        uint256 out = uint256(output);
        if (quoting) revert QuoteResult(out);
        poolManager.sync(address(currency));
        currency.safeTransfer(address(poolManager), amount);
        if (poolManager.settle() != amount) revert SwapFailed();
        poolManager.take(t.token, address(this), out);
        return abi.encode(out);
    }

    function creditRent(uint8 slot, uint256 amount) external onlyGame {
        Tile storage t = _tiles[slot];
        if (t.weight == 0) revert Invalid();
        rentReceived += amount;
        t.accRent += Math.mulDiv(amount, PRECISION, t.weight);
        emit RentCredited(slot, amount);
    }

    function _accrue(Deed storage d) private {
        Tile storage t = _tiles[d.tile];
        if (d.scoreSeason != currentSeason) {
            d.scoreSeason = currentSeason;
            d.pendingScore = 0;
        }
        uint256 amount = Math.mulDiv(d.weight, t.accRent - d.paidAcc, PRECISION);
        d.pending += amount;
        uint256 baseline = d.paidAcc > t.seasonStartAcc ? d.paidAcc : t.seasonStartAcc;
        d.pendingScore += Math.mulDiv(d.weight, t.accRent - baseline, PRECISION);
        d.paidAcc = t.accRent;
    }

    function pendingRent(uint256 id) external view returns (uint256) {
        Deed storage d = deeds[id];
        return d.pending + Math.mulDiv(d.weight, _tiles[d.tile].accRent - d.paidAcc, PRECISION);
    }

    function claimRent(uint256 id, address holder)
        external
        onlyGame
        nonReentrant
        returns (uint256 amount, uint256 scoreAmount)
    {
        Deed storage d = deeds[id];
        if (d.holder != holder) revert Unauthorized();
        _accrue(d);
        amount = d.pending;
        scoreAmount = d.pendingScore;
        d.pending = 0;
        d.pendingScore = 0;
        rentClaimed += amount;
        if (amount != 0) currency.safeTransfer(holder, amount);
        emit RentClaimed(id, amount);
    }

    function redeem(uint256 id) external nonReentrant returns (uint256 assets) {
        Deed storage d = deeds[id];
        if (d.holder != msg.sender) revert Unauthorized();
        if (d.shares == 0 || block.timestamp < d.redeemAt) revert Invalid();
        _accrue(d);
        Tile storage t = _tiles[d.tile];
        assets = Math.mulDiv(d.shares, t.assets, t.shares);
        t.assets -= assets;
        t.shares -= d.shares;
        t.weight -= d.weight;
        d.shares = 0;
        d.weight = 0;
        IERC20(t.token).safeTransfer(msg.sender, assets);
        emit Redeemed(id, assets);
    }

    /// @dev One sponsor per tile per season, so landing never iterates a user-grown list.
    function sponsorTile(uint8 slot, uint256 amount, uint256 perLanding) external nonReentrant {
        if (
            currentSeason == 0 || block.timestamp >= seasonEnd[currentSeason] || _tiles[slot].token == address(0)
                || amount == 0 || perLanding == 0
        ) revert Invalid();
        Sponsorship storage s = sponsors[currentSeason][slot];
        if (s.sponsor != address(0) && (s.sponsor != msg.sender || s.perLanding != perLanding)) revert Invalid();
        s.sponsor = msg.sender;
        s.remaining += amount;
        s.perLanding = perLanding;
        sponsorLiability[slot] += amount;
        IERC20(_tiles[slot].token).safeTransferFrom(msg.sender, address(this), amount);
        emit Sponsored(currentSeason, slot, msg.sender, amount);
    }

    function awardSponsor(uint8 slot, address player) external onlyGame {
        Sponsorship storage s = sponsors[currentSeason][slot];
        uint256 amount = s.remaining < s.perLanding ? s.remaining : s.perLanding;
        s.remaining -= amount;
        sponsorClaims[slot][player] += amount;
        if (amount != 0) emit SponsorAward(slot, player, amount);
    }

    function claimSponsor(uint8 slot) external nonReentrant {
        uint256 amount = sponsorClaims[slot][msg.sender];
        if (amount == 0) revert Invalid();
        sponsorClaims[slot][msg.sender] = 0;
        sponsorLiability[slot] -= amount;
        IERC20(_tiles[slot].token).safeTransfer(msg.sender, amount);
        emit SponsorClaimed(slot, msg.sender, amount);
    }

    function withdrawSponsor(uint256 id, uint8 slot) external nonReentrant {
        Sponsorship storage s = sponsors[id][slot];
        if (s.sponsor != msg.sender) revert Unauthorized();
        if (block.timestamp < seasonEnd[id] || s.remaining == 0) revert Invalid();
        uint256 amount = s.remaining;
        s.remaining = 0;
        sponsorLiability[slot] -= amount;
        IERC20(_tiles[slot].token).safeTransfer(msg.sender, amount);
        emit SponsorWithdrawn(id, slot, amount);
    }
}
