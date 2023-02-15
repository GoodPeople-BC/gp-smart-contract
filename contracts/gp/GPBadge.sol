// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// for donation award
contract GPBadge is ERC1155, Ownable {
    constructor(string memory _uri) 
        ERC1155(_uri) 
    {}

    function mint(address user, uint id, uint amount) 
        external
        onlyOwner
    {
        super._mint(user, id, amount, "");
    }

    function uri(uint id) 
        public
        view
        override
        returns (string memory) 
    {
        return string(abi.encodePacked(super.uri(id), "/", Strings.toString(id)));
    }
}