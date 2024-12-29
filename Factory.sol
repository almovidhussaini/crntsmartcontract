// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "./Pair.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";

contract Factory is Ownable {

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair);

    constructor() Ownable() { }

    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");
        require(getPair[tokenA][tokenB] == address(0) && getPair[tokenB][tokenA] == address(0), "Factory: PAIR_EXISTS");

        pair = address(new Pair(tokenA, tokenB));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        allPairs.push(pair);

        emit PairCreated(tokenA, tokenB, pair);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

}
