// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Pair is ERC20, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address public immutable token0;
    address public immutable token1;

    uint256 public reserve0; // Token0 reserves
    uint256 public reserve1; // Token1 reserves

    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;

    uint256 public constant FEE_DENOMINATOR = 1000; // Fee divisor (0.3% fee)
    uint256 public constant FEE_NUMERATOR = 997;    // Net amount after fee (1000 - 3)

    // Reward-related variables
    mapping(address => uint256) public liquidityAddedTime;
    mapping(address => uint256) public lockEndTime;
    mapping(address => uint256) public rewardDebt;
    uint256 public accRewardPerLiquidity; // Accumulated reward per liquidity unit
    uint256 public constant CLAIM_PERIOD = 1 days;
    uint256 public constant rewardRate = 5; // Rate of reward per liquidity unit

    event Mint(address indexed provider, uint256 amount0, uint256 amount1);
    event Burn(address indexed provider, uint256 amount0, uint256 amount1, address to);
    event Swap(address indexed sender, uint256 amountIn, uint256 amountOut, address indexed tokenIn, address indexed tokenOut);
    event Sync(uint256 reserve0, uint256 reserve1);
    event RewardClaimed(address indexed user, uint256 rewardAmount);

    constructor(address _token0, address _token1) ERC20("Pair LP Token", "PLP") {
        require(_token0 != _token1, "Pair: IDENTICAL_ADDRESSES");
        require(_token0 != address(0) && _token1 != address(0), "Pair: ZERO_ADDRESS");

        token0 = _token0;
        token1 = _token1;

        token0Decimals = IERC20Metadata(_token0).decimals();
        token1Decimals = IERC20Metadata(_token1).decimals();
    }

    function swap(address sender, uint256 amountIn, uint256 minAmountOut, address tokenIn, address tokenOut) external nonReentrant returns (uint256 amountOut) {
        require(tokenIn == token0 || tokenIn == token1, "Pair: INVALID_INPUT_TOKEN");
        require(tokenOut == token0 || tokenOut == token1, "Pair: INVALID_OUTPUT_TOKEN");
        require(tokenIn != tokenOut, "Pair: IDENTICAL_TOKENS");

        (uint256 reserveInput, uint256 reserveOutput) = tokenIn == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        require(amountIn > 0, "Pair: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveInput > 0 && reserveOutput > 0, "Pair: INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amountOut = (amountInWithFee * reserveOutput) / (reserveInput * FEE_DENOMINATOR + amountInWithFee);

        require(amountOut >= minAmountOut, "Pair: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer tokens in
        IERC20(tokenIn).safeTransferFrom(sender, address(this), amountIn);

        // Transfer tokens out
        IERC20(tokenOut).safeTransfer(sender, amountOut);

        // Update reserves
        if (tokenIn == token0) {
            reserve0 += amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += amountIn;
            reserve0 -= amountOut;
        }

        emit Swap(sender, amountIn, amountOut, tokenIn, tokenOut);
        emit Sync(reserve0, reserve1);
    }

    function addLiquidity(address to, uint256 amount0, uint256 amount1) external nonReentrant returns (uint256 liquidity) {
        updateReward(to); // Update rewards before any change to liquidity

        require(amount0 > 0 && amount1 > 0, "Pair: INVALID_AMOUNTS");

        uint256 normalizedAmount0 = normalize(amount0, token0Decimals);
        uint256 normalizedAmount1 = normalize(amount1, token1Decimals);

        if (reserve0 > 0 && reserve1 > 0) {
            uint256 normalizedReserve0 = normalize(reserve0, token0Decimals);
            uint256 normalizedReserve1 = normalize(reserve1, token1Decimals);

            uint256 amount1Expect = (normalizedAmount0 * normalizedReserve1) / normalizedReserve0;
            require(
                normalizedAmount1 >= (amount1Expect * 99) / 100 &&
                normalizedAmount1 <= (amount1Expect * 101) / 100,
                "Pair: PRICE_MANIPULATION_DETECTED"
            );
        }

        uint256 balanceBefore0 = IERC20(token0).balanceOf(address(this));
        IERC20(token0).safeTransferFrom(to, address(this), amount0);
        uint256 actualAmount0 = IERC20(token0).balanceOf(address(this)) - balanceBefore0;

        uint256 balanceBefore1 = IERC20(token1).balanceOf(address(this));
        IERC20(token1).safeTransferFrom(to, address(this), amount1);
        uint256 actualAmount1 = IERC20(token1).balanceOf(address(this)) - balanceBefore1;

        require(actualAmount0 > 0 && actualAmount1 > 0, "Pair: INVALID_AMOUNT_DEPOSITS");

        if (reserve0 == 0 || reserve1 == 0) {
            liquidity = sqrt(actualAmount0 * actualAmount1);
        } else {
            uint256 liquidity0 = (actualAmount0 * totalSupply()) / reserve0;
            uint256 liquidity1 = (actualAmount1 * totalSupply()) / reserve1;
            liquidity = min(liquidity0, liquidity1);
        }
        require(liquidity > 0, "Pair: INSUFFICIENT_LIQUIDITY");

        reserve0 += actualAmount0;
        reserve1 += actualAmount1;

        liquidityAddedTime[to] = block.timestamp;
        lockEndTime[to] = block.timestamp;
        rewardDebt[to] += (liquidity * accRewardPerLiquidity) / 1e18;

        _mint(to, liquidity);

        emit Mint(to, actualAmount0, actualAmount1);
        _update(reserve0, reserve1);
    }

    function claimReward(address user) external nonReentrant {
        require(lockEndTime[user] != 0 && lockEndTime[user] + CLAIM_PERIOD <= block.timestamp, "PAIR: CLAIM_PERIOD_NOT_MET");
        updateReward(user);

        uint256 owed = (balanceOf(user) * accRewardPerLiquidity) / 1e18;
        require(owed > rewardDebt[user], "Pair: NO_REWARD_AVAILABLE");
        owed -= rewardDebt[user];
        rewardDebt[user] += owed;

        IERC20(token0).safeTransfer(user, owed);
        lockEndTime[user] = block.timestamp;
        emit RewardClaimed(user, owed);
    }

    function updateReward(address user) internal {
        uint256 totalLiquidity = totalSupply();
        if (totalLiquidity > 0) {
            uint256 duration = block.timestamp - liquidityAddedTime[user];
            accRewardPerLiquidity += (rewardRate * duration) / totalLiquidity;
        }
    }

    function _update(uint256 _reserve0, uint256 _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        emit Sync(reserve0, reserve1);
    }

    function normalize(uint256 value, uint8 decimals) internal pure returns (uint256) {
        require(decimals <= 18, "Decimals need to be <= 18");
        return value * 10**(18 - decimals);
    }

    function denormalize(uint256 value, uint8 decimals) internal pure returns (uint256) {
        require(decimals <= 18, "Decimals need to be <= 18");
        return value / 10**(18 - decimals);
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function removeLiquidity(uint256 liquidity, address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(liquidity > 0, "Pair: INVALID_LIQUIDITY_AMOUNT");
        require(balanceOf(to) >= liquidity, "Pair: INSUFFICIENT_LIQUIDITY_BALANCE");

        uint256 totalSupply = totalSupply();
        amount0 = (liquidity * reserve0) / totalSupply;
        amount1 = (liquidity * reserve1) / totalSupply;

        require(amount0 > 0 && amount1 > 0, "Pair: INSUFFICIENT_AMOUNT");

        _burn(to, liquidity);

        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        reserve0 -= amount0;
        reserve1 -= amount1;

        emit Burn(to, amount0, amount1, to);
        emit Sync(reserve0, reserve1);
    }

    function amount1Expected(uint256 amount0) external view returns (uint256 amount1) {
        require(reserve0 > 0 && reserve1 > 0, "Pair: INSUFFICIENT_LIQUIDITY");

        uint256 normalizedAmount0 = normalize(amount0, token0Decimals);
        uint256 normalizedReserve0 = normalize(reserve0, token0Decimals);
        uint256 normalizedReserve1 = normalize(reserve1, token1Decimals);

        amount1 = (normalizedAmount0 * normalizedReserve1) / normalizedReserve0;
    }

    function getOutputAmount(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        require(tokenIn == token0 || tokenIn == token1, "Pair: INVALID_INPUT_TOKEN");
        
        (uint256 reserveInput, uint256 reserveOutput) = tokenIn == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

        require(amountIn > 0, "Pair: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveInput > 0 && reserveOutput > 0, "Pair: INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amountOut = (amountInWithFee * reserveOutput) / (reserveInput * FEE_DENOMINATOR + amountInWithFee);
    }
}
