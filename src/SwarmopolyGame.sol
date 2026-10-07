// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Owned} from "./Owned.sol";
import {SeasonPot} from "./SeasonPot.sol";
import {DeedVault} from "./DeedVault.sol";
import {PoolKey} from "./interfaces/IV4.sol";

contract SwarmopolyGame is Owned, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable currency;
    DeedVault public immutable vault;
    SeasonPot public immutable pot;
    uint256 public constant REVEAL_BLOCKS = 200;
    uint256 public constant REVEAL_SECONDS = 1 hours;
    uint256 public constant TAX = 5 ether;
    uint256 public constant BAIL = 5 ether;
    uint256 public salaryBps = 10;
    uint256 public cooldown = 20 hours;
    uint256[8] public tierRent = [uint256(1 ether), 2 ether, 3 ether, 5 ether, 8 ether, 12 ether, 20 ether, 30 ether];
    bool public rollsPaused;
    bool public buysPaused;
    uint256 public currentSeason;
    uint256 public totalPlayBalance;
    uint256 public totalRentPaid;
    uint256 public totalRentCredited;

    struct Season {
        uint256 buyIn;
        uint256 end;
        uint256 rollBond;
        uint256 maxBuy;
        bool finalized;
    }

    struct Player {
        uint256 season;
        uint256 balance;
        uint256 nextRoll;
        uint256 nonce;
        uint256 parkingDay;
        uint8 position;
        bool jailed;
        bool bankrupt;
        bool canBuy;
    }

    struct Roll {
        bytes32 commitment;
        uint256 entropyBlock;
        uint256 deadline;
        uint256 exposure;
        uint256 season;
    }
    mapping(uint256 => Season) public seasons;
    mapping(address => Player) private _players;
    mapping(address => Roll) public rolls;
    mapping(uint256 => mapping(address => uint256)) public scores;
    mapping(uint256 => address[10]) private _leaders;
    mapping(uint256 => mapping(address => uint256)) public prizes;
    event SeasonStarted(uint256 indexed season, uint256 buyIn, uint256 end, uint256 rollBond, uint256 maxBuy);
    event Joined(uint256 indexed season, address indexed player);
    event BalanceChanged(address indexed player, uint256 balance);
    event RollCommitted(address indexed player, uint256 nonce, uint256 entropyBlock, uint256 deadline);
    event Rolled(address indexed player, uint8 die1, uint8 die2, uint8 position);
    event RollExpired(address indexed player, uint256 penalty);
    event JailLeft(address indexed player, bool paid);
    event ScoreChanged(uint256 indexed season, address indexed player, uint256 score);
    event SeasonFinalized(uint256 indexed season, uint256 reserved);
    event PrizeClaimed(uint256 indexed season, address indexed player, uint256 amount);
    event Paused(bool rolls, bool buys);
    event ParametersSet(uint256 salaryBps, uint256 cooldown, uint256[8] rents);
    error Inactive();
    error PendingRoll();
    error TooEarly();

    constructor(address owner_, address currency_, address vault_, address pot_) Owned(owner_) {
        if (currency_ == address(0) || vault_ == address(0) || pot_ == address(0)) revert Invalid();
        currency = IERC20(currency_);
        vault = DeedVault(vault_);
        pot = SeasonPot(pot_);
        if (
            address(vault.currency()) != currency_ || address(pot.currency()) != currency_ || vault.owner() != owner_
                || pot.owner() != owner_
        ) revert Invalid();
    }

    function player(address who) external view returns (Player memory) {
        return _players[who];
    }

    function leaders(uint256 id) external view returns (address[10] memory) {
        return _leaders[id];
    }

    /// @notice The EVM block clock, which differs from the RPC's L2 height on Nitro.
    function chainBlockNumber() external view returns (uint256) {
        return block.number;
    }

    function _active() private view {
        if (currentSeason == 0 || block.timestamp >= seasons[currentSeason].end || seasons[currentSeason].finalized) {
            revert Inactive();
        }
    }

    function _playing(address who) private view {
        _active();
        if (_players[who].season != currentSeason || _players[who].bankrupt) revert Inactive();
    }

    function listTile(uint8 slot, PoolKey calldata key, uint8 tier) external onlyOwner nonReentrant {
        vault.listTile(slot, key, tier);
    }

    function startSeason(uint256 buyIn, uint256 duration, uint256 rollBond, uint256 maxBuy)
        external
        onlyOwner
        nonReentrant
    {
        if (vault.game() != address(this) || pot.game() != address(this)) revert Invalid();
        if (currentSeason != 0 && !seasons[currentSeason].finalized) revert Inactive();
        if (
            duration < 1 days || duration > 365 days || rollBond == 0 || maxBuy == 0
                || maxBuy > uint256(uint128(type(int128).max))
        ) revert Invalid();
        ++currentSeason;
        uint256 end = block.timestamp + duration;
        seasons[currentSeason] = Season(buyIn, end, rollBond, maxBuy, false);
        vault.beginSeason(currentSeason, end);
        emit SeasonStarted(currentSeason, buyIn, end, rollBond, maxBuy);
    }

    /// @notice Economics are fixed for each season, including all pending commitments.
    function setParams(uint256 salary, uint256 cooldown_, uint256[8] calldata rents) external onlyOwner {
        if (currentSeason != 0 && !seasons[currentSeason].finalized) revert Inactive();
        if (salary > 50 || cooldown_ < 1 hours || cooldown_ > 48 hours) revert Invalid();
        for (uint256 i; i < 8; ++i) {
            if (rents[i] > 1000 ether) revert Invalid();
            tierRent[i] = rents[i];
        }
        salaryBps = salary;
        cooldown = cooldown_;
        emit ParametersSet(salary, cooldown_, rents);
    }

    function setPaused(bool rolls_, bool buys_) external onlyOwner {
        rollsPaused = rolls_;
        buysPaused = buys_;
        emit Paused(rolls_, buys_);
    }

    function joinSeason() external nonReentrant {
        _active();
        Player storage p = _players[msg.sender];
        if (p.season == currentSeason) revert Invalid();
        if (rolls[msg.sender].commitment != bytes32(0)) revert PendingRoll();
        p.season = currentSeason;
        p.position = 0;
        p.jailed = false;
        p.bankrupt = false;
        p.canBuy = false;
        // nextRoll, parkingDay and nonce persist across season boundaries.
        uint256 amount = seasons[currentSeason].buyIn;
        if (amount != 0) {
            currency.safeTransferFrom(msg.sender, address(pot), amount);
            pot.credit(amount);
        }
        _score(msg.sender, 0);
        emit Joined(currentSeason, msg.sender);
    }

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert Invalid();
        _players[msg.sender].balance += amount;
        totalPlayBalance += amount;
        currency.safeTransferFrom(msg.sender, address(this), amount);
        emit BalanceChanged(msg.sender, _players[msg.sender].balance);
    }

    function withdraw(uint256 amount) external nonReentrant {
        Player storage p = _players[msg.sender];
        if (amount == 0 || amount > p.balance - rolls[msg.sender].exposure) revert Invalid();
        p.balance -= amount;
        totalPlayBalance -= amount;
        currency.safeTransfer(msg.sender, amount);
        emit BalanceChanged(msg.sender, p.balance);
    }

    function fundPot(uint256 amount) external nonReentrant {
        if (amount == 0) revert Invalid();
        currency.safeTransferFrom(msg.sender, address(pot), amount);
        pot.credit(amount);
    }

    function commitmentFor(address who, bytes32 secret) external view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), who, _players[who].nonce + 1, secret));
    }

    function commitRoll(bytes32 commitment) external nonReentrant {
        _playing(msg.sender);
        Player storage p = _players[msg.sender];
        if (rollsPaused || commitment == bytes32(0) || p.jailed || p.balance < seasons[currentSeason].rollBond) {
            revert Invalid();
        }
        if (rolls[msg.sender].commitment != bytes32(0)) revert PendingRoll();
        if (block.timestamp < p.nextRoll) revert TooEarly();
        // Leave a full reveal window before the scoring cutoff.
        if (block.timestamp + REVEAL_SECONDS >= seasons[currentSeason].end) revert Inactive();
        uint256 exposure = TAX;
        for (uint256 i; i < 8; ++i) {
            if (tierRent[i] > exposure) exposure = tierRent[i];
        }
        if (exposure > p.balance) exposure = p.balance;
        p.canBuy = false;
        p.nextRoll = block.timestamp + cooldown;
        ++p.nonce;
        rolls[msg.sender] =
            Roll(commitment, block.number + 1, block.timestamp + REVEAL_SECONDS, exposure, currentSeason);
        emit RollCommitted(msg.sender, p.nonce, block.number + 1, block.timestamp + REVEAL_SECONDS);
    }

    function revealRoll(bytes32 secret) external nonReentrant {
        Roll memory r = rolls[msg.sender];
        if (r.commitment == bytes32(0) || r.season != currentSeason) revert Invalid();
        if (block.number <= r.entropyBlock) revert TooEarly();
        if (block.number > r.entropyBlock + REVEAL_BLOCKS || block.timestamp > r.deadline) revert Inactive();
        Player storage p = _players[msg.sender];
        if (keccak256(abi.encode(block.chainid, address(this), msg.sender, p.nonce, secret)) != r.commitment) {
            revert Invalid();
        }
        bytes32 futureHash = blockhash(r.entropyBlock);
        if (futureHash == bytes32(0)) revert Invalid();
        delete rolls[msg.sender];
        uint256 entropy = uint256(keccak256(abi.encode(secret, futureHash, msg.sender, p.nonce)));
        uint8 die1 = uint8(entropy % 6 + 1);
        uint8 die2 = uint8((entropy / 6) % 6 + 1);
        uint256 destination = uint256(p.position) + die1 + die2;
        bool salaryPaid = destination >= 40;
        if (salaryPaid) _reward(msg.sender, salaryBps);
        p.position = uint8(destination % 40);
        _land(msg.sender, entropy, salaryPaid);
        emit Rolled(msg.sender, die1, die2, p.position);
    }

    /// @notice Withholding forfeits maximum committed exposure, gives no rewards, and jails/bankrupts until next season.
    function expireRoll(address who) external nonReentrant {
        Roll memory r = rolls[who];
        if (r.commitment == bytes32(0)) revert Invalid();
        if (block.number <= r.entropyBlock + REVEAL_BLOCKS && block.timestamp <= r.deadline) revert TooEarly();
        delete rolls[who];
        Player storage p = _players[who];
        p.position = 10;
        p.jailed = true;
        p.bankrupt = true;
        p.canBuy = false;
        _toPot(who, r.exposure);
        emit RollExpired(who, r.exposure);
    }

    function _land(address who, uint256 entropy, bool salaryPaid) private {
        Player storage p = _players[who];
        uint8 slot = p.position;
        if (slot == 30) {
            _jail(p);
            return;
        }
        if (slot == 4 || slot == 38) {
            _tax(who);
            return;
        }
        if (slot == 20) {
            uint256 day = block.timestamp / 1 days + 1;
            if (p.parkingDay != day) {
                p.parkingDay = day;
                _reward(who, 50);
            }
            return;
        }
        // Community Chest shares the Chance table; all six card squares are deterministic from the roll entropy.
        if (slot == 2 || slot == 7 || slot == 17 || slot == 22 || slot == 33 || slot == 36) {
            uint256 card = (entropy >> 16) % 5;
            if (card == 0) {
                p.position = 0;
                if (!salaryPaid) _reward(who, salaryBps);
            } else if (card == 1) {
                _jail(p);
            } else if (card == 2) {
                _reward(who, 5);
            } else if (card == 3) {
                _tax(who);
            }
            return;
        }
        (address token, uint8 tier, uint256 weight) = vault.tileInfo(slot);
        if (token == address(0)) return;
        uint256 rent = tierRent[tier - 1];
        uint256 paid = rent > p.balance ? p.balance : rent;
        if (paid < rent) p.bankrupt = true;
        if (paid != 0) {
            p.balance -= paid;
            totalPlayBalance -= paid;
            totalRentPaid += paid;
            uint256 holders = weight == 0 ? 0 : Math.mulDiv(paid, 80, 100);
            totalRentCredited += holders;
            if (holders != 0) {
                currency.safeTransfer(address(vault), holders);
                vault.creditRent(slot, holders);
            }
            uint256 potAmount = paid - holders;
            currency.safeTransfer(address(pot), potAmount);
            pot.credit(potAmount);
        }
        vault.awardSponsor(slot, who);
        p.canBuy = !p.bankrupt;
    }

    function _jail(Player storage p) private {
        p.position = 10;
        p.jailed = true;
        p.canBuy = false;
    }

    function _tax(address who) private {
        uint256 balance = _players[who].balance;
        _toPot(who, balance < TAX ? balance : TAX);
    }

    function _toPot(address who, uint256 amount) private {
        _players[who].balance -= amount;
        totalPlayBalance -= amount;
        if (amount != 0) {
            currency.safeTransfer(address(pot), amount);
            pot.credit(amount);
        }
    }

    function _reward(address who, uint256 bps) private {
        uint256 amount = Math.mulDiv(pot.available(), bps, 10_000);
        if (amount == 0) return;
        _players[who].balance += amount;
        totalPlayBalance += amount;
        pot.pay(address(this), amount);
        _score(who, amount);
    }

    function skipJailRoll() external nonReentrant {
        _playing(msg.sender);
        Player storage p = _players[msg.sender];
        if (rollsPaused || !p.jailed || block.timestamp < p.nextRoll) revert Invalid();
        p.jailed = false;
        p.nextRoll = block.timestamp + cooldown;
        emit JailLeft(msg.sender, false);
    }

    function payBail() external nonReentrant {
        _playing(msg.sender);
        Player storage p = _players[msg.sender];
        if (!p.jailed || p.balance < BAIL) revert Invalid();
        p.jailed = false;
        _toPot(msg.sender, BAIL);
        emit JailLeft(msg.sender, true);
    }

    function buyDeed(uint8 slot, uint256 amount, uint256 minOut) external nonReentrant returns (uint256) {
        return _buy(slot, amount, minOut, 0);
    }

    function buyDeed(uint8 slot, uint256 amount, uint256 minOut, uint8 lockDays)
        external
        nonReentrant
        returns (uint256)
    {
        return _buy(slot, amount, minOut, lockDays);
    }

    function _buy(uint8 slot, uint256 amount, uint256 minOut, uint8 lockDays) private returns (uint256) {
        _playing(msg.sender);
        Player storage p = _players[msg.sender];
        if (buysPaused || !p.canBuy || p.position != slot || amount == 0 || amount > seasons[currentSeason].maxBuy) {
            revert Invalid();
        }
        if (rolls[msg.sender].commitment != bytes32(0)) revert PendingRoll();
        p.canBuy = false;
        currency.safeTransferFrom(msg.sender, address(vault), amount);
        return vault.buy(slot, msg.sender, amount, minOut, lockDays);
    }

    function claimRent(uint256 id) external nonReentrant returns (uint256 amount) {
        uint256 scoreAmount;
        (amount, scoreAmount) = vault.claimRent(id, msg.sender);
        if (
            _players[msg.sender].season == currentSeason && block.timestamp < seasons[currentSeason].end
                && !seasons[currentSeason].finalized
        ) _score(msg.sender, scoreAmount);
    }

    function _score(address who, uint256 amount) private {
        uint256 score = scores[currentSeason][who] + amount;
        if (score == 0) return;
        scores[currentSeason][who] = score;
        address[10] storage list = _leaders[currentSeason];
        uint256 index = 10;
        for (uint256 i; i < 10; ++i) {
            if (list[i] == who) {
                index = i;
                break;
            }
        }
        if (index == 10) {
            address last = list[9];
            if (last != address(0) && !_better(who, last)) {
                emit ScoreChanged(currentSeason, who, score);
                return;
            }
            index = 9;
        }
        while (index > 0 && (list[index - 1] == address(0) || _better(who, list[index - 1]))) {
            list[index] = list[index - 1];
            --index;
        }
        list[index] = who;
        emit ScoreChanged(currentSeason, who, score);
    }

    function _better(address a, address b) private view returns (bool) {
        uint256 sa = scores[currentSeason][a];
        uint256 sb = scores[currentSeason][b];
        return sa > sb || (sa == sb && uint160(a) < uint160(b));
    }

    function finalizeSeason() external nonReentrant {
        Season storage s = seasons[currentSeason];
        if (currentSeason == 0 || block.timestamp < s.end || s.finalized) revert Inactive();
        s.finalized = true;
        uint256 budget = Math.mulDiv(pot.available(), 60, 100);
        uint8[10] memory weights = [25, 18, 13, 10, 8, 7, 6, 5, 4, 4];
        uint256 total;
        for (uint256 i; i < 10; ++i) {
            address winner = _leaders[currentSeason][i];
            if (winner == address(0) || scores[currentSeason][winner] == 0) continue;
            uint256 amount = Math.mulDiv(budget, weights[i], 100);
            prizes[currentSeason][winner] = amount;
            total += amount;
        }
        pot.reserve(total);
        emit SeasonFinalized(currentSeason, total);
    }

    function claimPrize(uint256 id) external nonReentrant {
        uint256 amount = prizes[id][msg.sender];
        if (amount == 0) revert Invalid();
        prizes[id][msg.sender] = 0;
        pot.payReserved(msg.sender, amount);
        emit PrizeClaimed(id, msg.sender, amount);
    }
}
