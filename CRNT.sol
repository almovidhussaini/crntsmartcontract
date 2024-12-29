// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";

contract CRNT is ERC20, Ownable, ReentrancyGuard {

    uint256 public burnThreshold; // Previously hardcoded BURN_THRESHOLD

    uint256 public buyTax = 1;
    uint256 public sellTax = 1;

    address public constant TEAM = 0xc5F2f8B00Fe2C268e4b4b59B52c826848dc7022F;
    address public constant MARKETING = 0xcC0048BB3c401A9E232696286d516bbB8780608b;
    address public constant RESERVE = 0x46A8979d11189131b86D11866dB013A00d6FB625;
    address public constant CREATOR = 0x3db416f48c0935Af35BD098E9ad4499bf462c47c;
    address public constant LIQUIDITY = 0x3D36Ed0B3B19b1d0c22d9AB45cd928309462BBe0;
    address public constant AIRDROP = 0x4aaCbe0A37283CA9622602249d8203e586026d20;
    
    address public immutable stakingContract;
    address public immutable icoContract;

    uint256 public taxUpdateTime;
    uint256 public constant TIMELOCK_DELAY = 7 days;
    uint256 public  lockTimestamp;
    uint8 public marketingIndex = 0;
    uint256 public marketingTimeStamp;
    bool public teamTokenSold = false;

    address public dexContract;
    address public liquidityPool;

    mapping(address => bool) public isTaxExempt;

    address public immutable multiSigWallet;

    event TaxRateUpdated(uint256 newBuyTax, uint256 newSellTax);
    event TaxExemptUpdated(address indexed account, bool isExempt);
    event BurnThresholdUpdated(uint256 newBurnThreshold);
    event BurnedTokens(uint256 amount);
    event RewardSent(address indexed stakingContract, address indexed recipient, uint256 amount);

    constructor(
        address _icoContract,
        address _stakingContract,
        address _multiSigWallet
    ) Ownable() ERC20("CRNT Token", "CRNT") {
        require(_stakingContract != address(0), "CRNT: Invalid staking contract address");
        require(_icoContract != address(0), "CRNT: Invalid ICO contract address");
        require(_multiSigWallet != address(0), "CRNT: Invalid MultiSigWallet address");

        stakingContract = _stakingContract;
        icoContract = _icoContract;
        multiSigWallet = _multiSigWallet;

        taxUpdateTime = block.timestamp;
        burnThreshold = 36_900_000 * (10 ** 18); // Initial burn threshold

       
        
        uint256 reserveAmount = 36_900_000 * (10 ** 18);
        uint256 creatorAmount = 11_070_000 * (10 ** 18);
        uint256 liquidityAmount = 73_800_000 * (10 ** 18);
        uint256 airdropAmount = 7_380_000 * (10 ** 18);
        uint256 icoAmount = 121_770_000 * (10 ** 18);

        // _mint(TEAM, teamAmount);
        // _mint(MARKETING, marketingAmount);
        _mint(RESERVE, reserveAmount);
        _mint(CREATOR, creatorAmount);
        _mint(LIQUIDITY, liquidityAmount);
        _mint(AIRDROP, airdropAmount);
        _mint(_icoContract, icoAmount);

        lockTimestamp = block.timestamp;
        marketingTimeStamp = block.timestamp;
    }

    function mintTeamCrnt() external {
        // require(balanceOf(TEAM) == 0,"Team has minted his token");
        require(!teamTokenSold,"team token already soled");
        require((lockTimestamp + 2*365 days ) <= block.timestamp,"mint time not reached" );
         uint256 teamAmount = 44_280_000 * (10 ** 18);
        _mint(TEAM, teamAmount);
        teamTokenSold = true;
    }

    function mintMarketingCrnt() external {
        require((marketingTimeStamp + 365 days) <=block.timestamp,"mint time not reached");
        require(marketingIndex < 4,"all the tokens has been sold for the markeing team");
        uint256 marketingAmount =  (73_800_000 * (10 ** 18) * 25)/100;
        _mint(MARKETING, marketingAmount);
        marketingIndex ++;
        marketingTimeStamp = block.timestamp;
    }

    function setTax(uint256 newBuyTax, uint256 newSellTax) external {
        require(msg.sender == multiSigWallet, "CRNT: Only MultiSigWallet can set taxes");
        require(newBuyTax <= 5 && newSellTax <= 5, "CRNT: Tax rate too high");
        require(block.timestamp >= taxUpdateTime + TIMELOCK_DELAY, "CRNT: Timelock not expired");

        buyTax = newBuyTax;
        sellTax = newSellTax;
        taxUpdateTime = block.timestamp;

        emit TaxRateUpdated(buyTax, sellTax);
    }

    function updateBurnThreshold(uint256 newBurnThreshold) external {
        require(msg.sender == multiSigWallet, "CRNT: Only MultiSigWallet can update burn threshold");
        require(newBurnThreshold > 0, "CRNT: Burn threshold must be greater than zero");

        burnThreshold = newBurnThreshold;
        emit BurnThresholdUpdated(newBurnThreshold);
    }

    function updateTaxExemption(address account, bool exempt) external {
        require(msg.sender == multiSigWallet, "CRNT: Only MultiSigWallet can update tax exemptions");
        require(account != address(0), "CRNT: Invalid address");

        isTaxExempt[account] = exempt;
        emit TaxExemptUpdated(account, exempt);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        uint256 taxAmount = 0;

        if (!isTaxExempt[sender] && !isTaxExempt[recipient]) {
            if (isDexAddress(recipient)) {
                taxAmount = (amount * sellTax) / 100;
            } else if (isDexAddress(sender)) {
                taxAmount = (amount * buyTax) / 100;
            }
        }

        if (totalSupply() - taxAmount <= burnThreshold) {
            taxAmount = 0;
        }

        super._transfer(sender, recipient, amount - taxAmount);

        if (taxAmount > 0) {
            _burn(sender, taxAmount);
            emit BurnedTokens(taxAmount);
        }
    }

    function burnFrom(uint256 amount) external {
        require(msg.sender == stakingContract, "CRNT: Only staking contract can burn tokens");
        _burn(msg.sender, amount);
        emit BurnedTokens(amount);
    }
    function sendReward(address recipient, uint256 amount) external {
        require(msg.sender == stakingContract,"CRNT: Only staking contract is authorized to send reward");
        _transfer(RESERVE, recipient, amount);
         emit RewardSent(RESERVE, recipient, amount); 
    }

    function setDexContract(address newDexContract) external {
        require(msg.sender == multiSigWallet, "CRNT: Only MultiSigWallet can set DEX address");
        require(newDexContract != address(0), "CRNT: DEX address cannot be zero");
        dexContract = newDexContract;
    }

    function setLiquidityPool(address newLiquidityPool) external {
        require(msg.sender == multiSigWallet, "CRNT: Only MultiSigWallet can set liquidity pool");
        require(newLiquidityPool != address(0), "CRNT: Liquidity pool cannot be zero address");
        liquidityPool = newLiquidityPool;
    }

    function isDexAddress(address account) internal view returns (bool) {
        return account == dexContract || account == liquidityPool;
    }
}
