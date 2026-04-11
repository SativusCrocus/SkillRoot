// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title SKRToken — fixed-supply governance token for SkillRoot v0
/// @notice 100,000,000 SKR minted once at genesis to the deployer (who
///         transfers to the Governance contract in Deploy.s.sol). There
///         is intentionally NO mint() function. Supply is monotonically
///         non-increasing: it only decreases via slashing burns to 0xdead.
contract SKRToken is ERC20, ERC20Permit, ERC20Votes {
    uint256 public constant INITIAL_SUPPLY = 100_000_000 ether;

    /// @notice Governance address — can be transferred but holds no mint rights.
    address public governance;

    event GovernanceTransferred(address indexed from, address indexed to);

    error NotGovernance();
    error ZeroAddress();

    constructor(address _governance)
        ERC20("SkillRoot", "SKR")
        ERC20Permit("SkillRoot")
    {
        if (_governance == address(0)) revert ZeroAddress();
        governance = _governance;
        _mint(_governance, INITIAL_SUPPLY);
        emit GovernanceTransferred(address(0), _governance);
    }

    function transferGovernance(address newGov) external {
        if (msg.sender != governance) revert NotGovernance();
        if (newGov == address(0)) revert ZeroAddress();
        address old = governance;
        governance = newGov;
        emit GovernanceTransferred(old, newGov);
    }

    /// @notice Use timestamp-mode clock (OZ v5) so checkpoints are time-based.
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // --- required multi-inheritance overrides ---

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
