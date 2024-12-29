// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract ICO is Ownable, ReentrancyGuard {

    using SafeERC20 for IERC20;

    IERC20 public crntToken;

    enum StageName {
        Ignition,
        Acceleration,
        Momentum,
        Expansion,
        Pinnacle
    }

    struct Stage {
        StageName name;
        uint256 allocation;
        uint256 price;
        uint256 duration;
        uint256 startTime;
        uint256 tokensSold;
    }

    Stage[3] public stages;
    mapping(address => uint256) public purchases;
    mapping(address => mapping(uint8 => uint256)) public stagePurchases;
    mapping(address => mapping(uint8 => uint256)) public purchasesInStablecoinForCurrentStage;
    mapping(address => mapping(address => uint256)) public tokenPurchasesInStablecoin;
    uint8 public currentStage;
    mapping(address => mapping(uint8 => uint256)) public lastClaimTimestamp;
    mapping(address => bool) public whitelistedTokens;
    mapping(address => uint8) public tokenDecimals;
    mapping(address => mapping(uint8 => uint256)) public originalStagePurchases;
    address public crntAddress;

    event TokensPurchased(address indexed buyer, uint256 amount);
    event TokensClaimed(address indexed buyer, uint256 amount);
    event StageAdvanced(uint8 newStageIndex);
    event ServicePaid(address indexed payer, uint256 amount);
    event FundsWithdrawn(address indexed stablecoin, uint256 amount, uint8 indexed purchasedStage, address indexed owner);
    event CrntAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event WhitelistedTokenUpdated(address indexed token, bool status, uint8 decimals);

    constructor() Ownable() {
        stages[0] = Stage(StageName.Ignition, 33_369_000 * 10**18, 0.01 * 10**18, 23 days, block.timestamp, 0);
        stages[1] = Stage(StageName.Acceleration, 44_200_500 * 10**18, 0.0125 * 10**18, 15 days, 0, 0);
        stages[2] = Stage(StageName.Momentum, 44_200_500 * 10**18, 0.015 * 10**18, 15 days, 0, 0);
    }

    modifier crntAddressSet() {
        require(crntAddress != address(0), "crntAddress not set");
        _;
    }

    function buyTokens(uint256 amount, address stablecoin) external nonReentrant {
        require(currentStage < stages.length, "ICO stages completed");
        require(block.timestamp >= stages[currentStage].startTime, "Stage not started");
        require(amount > 0, "Invalid purchase amount");
        require(whitelistedTokens[stablecoin], "Token not authorized");

        if (stages[currentStage].tokensSold >= stages[currentStage].allocation ||
            block.timestamp >= stages[currentStage].startTime + stages[currentStage].duration) {
            currentStage++;
            require(currentStage < stages.length, "ICO stages completed");
            stages[currentStage].startTime = block.timestamp;
            emit StageAdvanced(currentStage);
        }

        uint256 stablecoinDecimals = tokenDecimals[stablecoin];
        require(stablecoinDecimals > 0, "Stablecoin not registered");

        uint256 normalizedAmount = amount * (10**(18 - stablecoinDecimals));
        // Corrected line below:
        uint256 crntAmount = normalizedAmount / stages[currentStage].price;

        IERC20(stablecoin).safeTransferFrom(msg.sender, address(this), amount);
        stagePurchases[msg.sender][currentStage] += crntAmount;
        stages[currentStage].tokensSold += crntAmount;

        originalStagePurchases[msg.sender][currentStage] = stagePurchases[msg.sender][currentStage];
        purchasesInStablecoinForCurrentStage[msg.sender][currentStage] += amount;
        tokenPurchasesInStablecoin[msg.sender][stablecoin] += amount;

        emit TokensPurchased(msg.sender, crntAmount);
    }

    function claimTokens(uint8 claimedStage) external nonReentrant crntAddressSet {
        uint256 originalPurchaseAmount = originalStagePurchases[msg.sender][claimedStage];

        uint256 releaseAmount = (originalPurchaseAmount * 25) / 100;

        require(releaseAmount > 0, "No tokens available for release");
        require(block.timestamp >= lastClaimTimestamp[msg.sender][claimedStage] + 30 days, "Claim period not reached");

        crntToken = IERC20(crntAddress);
        require(releaseAmount <= stagePurchases[msg.sender][claimedStage], "All tokens claimed");

        stagePurchases[msg.sender][claimedStage] -= releaseAmount;
        lastClaimTimestamp[msg.sender][claimedStage] = block.timestamp;

        crntToken.safeTransfer(msg.sender, releaseAmount);
        emit TokensClaimed(msg.sender, releaseAmount);
    }

    function payForService(uint256 amount) external crntAddressSet {
        require(amount > 0, "Invalid service amount");
        crntToken = IERC20(crntAddress);
        crntToken.safeTransferFrom(msg.sender, address(this), amount);
        emit ServicePaid(msg.sender, amount);
    }

    function withdrawFunds(address stablecoin, uint256 amount, uint8 purchasedStage) external onlyOwner {
        require(whitelistedTokens[stablecoin], "Token not authorized");
        require(purchasesInStablecoinForCurrentStage[msg.sender][purchasedStage] >= amount, "Insufficient funds for withdrawal");
        require(tokenPurchasesInStablecoin[msg.sender][stablecoin] >= amount, "Insufficient stablecoin balance");

        purchasesInStablecoinForCurrentStage[msg.sender][purchasedStage] -= amount;
        tokenPurchasesInStablecoin[msg.sender][stablecoin] -= amount;

        IERC20(stablecoin).safeTransfer(msg.sender, amount);
        emit FundsWithdrawn(stablecoin, amount, purchasedStage, msg.sender);
    }

    function setCrntAddress(address _crnt) external onlyOwner {
        require(_crnt != address(0), "Invalid crnt address");
        address oldAddress = crntAddress;
        crntAddress = _crnt;
        emit CrntAddressUpdated(oldAddress, _crnt);
    }

    function setWhitelistedToken(address token, bool status, uint8 decimals) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(decimals > 0 && decimals <= 18, "Invalid decimals");

        whitelistedTokens[token] = status;
        tokenDecimals[token] = decimals;

        emit WhitelistedTokenUpdated(token, status, decimals);
    }
}
