// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGPToken is IERC20 {
    function mint(address to, uint256 amount) external returns (bool);
    function burn(address to, uint256 amount) external returns (bool);
}