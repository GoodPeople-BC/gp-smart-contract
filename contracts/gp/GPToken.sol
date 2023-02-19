// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./IGPToken.sol";

contract GPToken is IGPToken, ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant GOVR_ROLE = keccak256("GOVR_ROLE");
    constructor()
        ERC20("GoodPeopleToken", "GPT")
        ERC20Permit("GPToken")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function addGovernanceRole(address governance) 
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(GOVR_ROLE, governance);
    }

    function mint(address to, uint256 amount)
        external
        onlyRole(GOVR_ROLE)
        returns (bool)
    {
        _mint(to, amount);
        _delegate(to, to);
        return true;
    }

    function burn(address to, uint256 amount)
        external
        onlyRole(GOVR_ROLE)
        returns (bool)
    {
        _burn(to, amount);
        return true;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}