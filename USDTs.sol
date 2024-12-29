// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";

contract USDTs is ERC20, Ownable, ReentrancyGuard {
    event Minted(address indexed to, uint256 amount);

    constructor() Ownable() ERC20("Custom Tether Token", "CTT") {
        _mint(msg.sender, 1_000_000 * (10 ** decimals())); // Initial mint of 1 million CTT
    }
}
