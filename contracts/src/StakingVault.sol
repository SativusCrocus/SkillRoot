// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StakingVault — validator bonding, unbonding, slashing
/// @notice Tracks a dense validator array for O(k·n) stake-weighted sortition.
///         Slashed tokens burn to 0xdead (deflationary). 14-day unbond delay.
contract StakingVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MIN_STAKE = 1_000 ether;
    uint256 public constant UNBOND_DELAY = 14 days;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable token;
    address public governance;
    address public engine;
    address public forgeGuard;

    struct UnbondRequest {
        uint256 amount;
        uint64 unlockAt;
    }

    mapping(address => uint256) public stakeOf;
    mapping(address => UnbondRequest) public unbondOf;

    /// @dev Dense validator list for sortition. `validatorIdx[v]` is 1-indexed
    ///      (0 = not a validator) so lookups are O(1) on removal.
    address[] public validators;
    mapping(address => uint256) public validatorIdx; // 1-indexed

    uint256 public totalStake;
    uint256 public yieldBoostBps;

    event Bonded(address indexed validator, uint256 amount, uint256 newStake);
    event UnbondRequested(address indexed validator, uint256 amount, uint64 unlockAt);
    event Withdrawn(address indexed validator, uint256 amount);
    event Slashed(address indexed validator, uint256 amount, uint256 newStake);
    event EngineSet(address indexed engine);
    event ForgeGuardSet(address indexed forgeGuard);
    event YieldBoostIncreased(uint256 addedBps, uint256 totalBps);
    event GovernanceTransferred(address indexed from, address indexed to);

    error NotGovernance();
    error NotEngine();
    error NotForgeGuard();
    error ForgeGuardAlreadySet();
    error BelowMinStake();
    error ZeroAmount();
    error InsufficientStake();
    error NothingToWithdraw();
    error StillLocked();
    error EngineAlreadySet();
    error ZeroAddress();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    modifier onlyEngine() {
        if (msg.sender != engine) revert NotEngine();
        _;
    }

    modifier onlyForgeGuard() {
        if (msg.sender != forgeGuard) revert NotForgeGuard();
        _;
    }

    constructor(IERC20 _token, address _governance) {
        if (address(_token) == address(0) || _governance == address(0)) revert ZeroAddress();
        token = _token;
        governance = _governance;
    }

    function setEngine(address _engine) external onlyGovernance {
        if (engine != address(0)) revert EngineAlreadySet();
        if (_engine == address(0)) revert ZeroAddress();
        engine = _engine;
        emit EngineSet(_engine);
    }

    function setForgeGuard(address _forgeGuard) external onlyGovernance {
        if (forgeGuard != address(0)) revert ForgeGuardAlreadySet();
        if (_forgeGuard == address(0)) revert ZeroAddress();
        forgeGuard = _forgeGuard;
        emit ForgeGuardSet(_forgeGuard);
    }

    function addYieldBoost(uint256 bps) external onlyForgeGuard {
        yieldBoostBps += bps;
        emit YieldBoostIncreased(bps, yieldBoostBps);
    }

    function transferGovernance(address newGov) external onlyGovernance {
        if (newGov == address(0)) revert ZeroAddress();
        address old = governance;
        governance = newGov;
        emit GovernanceTransferred(old, newGov);
    }

    function bond(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 newStake = stakeOf[msg.sender] + amount;
        if (newStake < MIN_STAKE) revert BelowMinStake();

        token.safeTransferFrom(msg.sender, address(this), amount);

        stakeOf[msg.sender] = newStake;
        totalStake += amount;

        if (validatorIdx[msg.sender] == 0) {
            validators.push(msg.sender);
            validatorIdx[msg.sender] = validators.length; // 1-indexed
        }

        emit Bonded(msg.sender, amount, newStake);
    }

    function requestUnbond(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 current = stakeOf[msg.sender];
        if (amount > current) revert InsufficientStake();

        uint256 remaining = current - amount;
        // Must either fully exit (remaining == 0) or stay above MIN_STAKE
        if (remaining != 0 && remaining < MIN_STAKE) revert BelowMinStake();

        stakeOf[msg.sender] = remaining;
        totalStake -= amount;

        UnbondRequest storage r = unbondOf[msg.sender];
        r.amount += amount;
        r.unlockAt = uint64(block.timestamp + UNBOND_DELAY);

        if (remaining == 0) _removeValidator(msg.sender);

        emit UnbondRequested(msg.sender, amount, r.unlockAt);
    }

    function withdraw() external nonReentrant {
        UnbondRequest memory r = unbondOf[msg.sender];
        if (r.amount == 0) revert NothingToWithdraw();
        if (block.timestamp < r.unlockAt) revert StillLocked();

        delete unbondOf[msg.sender];
        token.safeTransfer(msg.sender, r.amount);

        emit Withdrawn(msg.sender, r.amount);
    }

    /// @notice Slash a validator's bonded stake; burns to 0xdead.
    function slash(address validator, uint256 amount) external onlyEngine {
        uint256 current = stakeOf[validator];
        uint256 actual = amount > current ? current : amount;
        if (actual == 0) return;

        uint256 remaining = current - actual;
        stakeOf[validator] = remaining;
        totalStake -= actual;

        token.safeTransfer(BURN_ADDRESS, actual);

        if (remaining < MIN_STAKE && validatorIdx[validator] != 0) {
            _removeValidator(validator);
        }

        emit Slashed(validator, actual, remaining);
    }

    function _removeValidator(address validator) internal {
        uint256 idx1 = validatorIdx[validator];
        if (idx1 == 0) return;
        uint256 lastIdx = validators.length;
        if (idx1 != lastIdx) {
            address last = validators[lastIdx - 1];
            validators[idx1 - 1] = last;
            validatorIdx[last] = idx1;
        }
        validators.pop();
        delete validatorIdx[validator];
    }

    function validatorCount() external view returns (uint256) {
        return validators.length;
    }

    function getValidators() external view returns (address[] memory) {
        return validators;
    }
}
