// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "./Factory.sol";
import "./Pair.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";

contract Router is ReentrancyGuard, Ownable {
    Factory public factory;

    event LiquidityAdded(address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB);
    event LiquidityRemoved(address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB);
    event SwapExecuted(address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut);

    constructor(address _factory) Ownable() {
        factory = Factory(_factory);
    }

    function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired) external nonReentrant {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Router: Pair does not exist");

        Pair(pair).addLiquidity(msg.sender, amountADesired, amountBDesired);
        emit LiquidityAdded(tokenA, tokenB, amountADesired, amountBDesired);
    }

    function removeLiquidity(address tokenA, address tokenB, uint256 liquidity) external nonReentrant {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Router: Pair does not exist");

        (uint256 amount0, uint256 amount1) = Pair(pair).removeLiquidity(liquidity, msg.sender);
        emit LiquidityRemoved(tokenA, tokenB, amount0, amount1);
    }

    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 minAmountOut) external nonReentrant {
        address pair = factory.getPair(tokenIn, tokenOut);
        require(pair != address(0), "Router: Pair does not exist");

        uint256 amountOut = Pair(pair).swap(msg.sender, amountIn, minAmountOut, tokenIn, tokenOut);
        emit SwapExecuted(tokenIn, amountIn, tokenOut, amountOut);
    }

    function claimReward(address tokenA, address tokenB) external nonReentrant {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Router: Pair does not exist");
        Pair(pair).claimReward(msg.sender);
    }

    function amount1Expected(address tokenA, address tokenB, uint256 amount0) external view returns (uint256 amount1) {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Router: Pair does not exist");

        amount1 = Pair(pair).amount1Expected(amount0);
    }

    function getOutputAmount(address tokenA, address tokenB, uint256 amountIn, address tokenIn) external view returns (uint256 outputAmount) {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Router: Pair does not exist");

        outputAmount = Pair(pair).getOutputAmount(tokenIn, amountIn);
    }

    // Allow the owner to withdraw accidentally sent Ether
    function withdrawEther() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No Ether to withdraw");

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Ether withdrawal failed");
    }

    fallback() external payable {}
    receive() external payable {}
}
