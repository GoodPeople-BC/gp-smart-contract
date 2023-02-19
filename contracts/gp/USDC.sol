// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// dummy usdc contract for testing.
contract USDC is ERC20, Ownable {
    constructor() 
        ERC20("USDC", "USDC") 
    {}

    function mint(address to, uint256 amount) 
        public
        onlyOwner
    {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount)
        public
        onlyOwner
    {
        _burn(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}