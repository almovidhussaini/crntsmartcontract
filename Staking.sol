// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

interface ICRNT {
    function burnFrom(uint256 amount) external;

    function sendReward(address recipient, uint256 amount) external;
}

contract Staking is  Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public crntToken;
    uint256 public constant REWARD_RATE = 15;
    uint256 public constant SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
    uint256 public constant LOCK_PERIOD = 21 days;
    uint256 public constant CLAIM_PERIOD = 1 days;
    uint256 public constant MIN_STAKE_DURATION = 1 days;
    uint256 public totalStaked;
    uint256 public totalRevenueShared;

    address public crntAddress;
    address public immutable multiSigWallet;
    bool public isActive = true;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public stakedFromTimestamp;
    mapping(address => bool) public isStaker;
    mapping(address => uint256) private stakerIndex;
    mapping(address => uint256) public lockEndTimestamp;

    address[] public stakers;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event RevenueDistributed(uint256 totalDistributed);
    event StakerRemoved(address indexed staker, uint256 index);
    event CrntAddressUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event PenaltyBurned(address indexed user, uint256 penaltyAmount);

    modifier crntAddressSet() {
        require(crntAddress != address(0), "CRNT address not set");
        _;
    }
    modifier onlyIfActive() {
        require(isActive, "Contract is ceased");
        _;
    }

    constructor(address _multiSigWallet) Ownable()  {
        require(
            _multiSigWallet != address(0),
            "Invalid MultiSigWallet address"
        );
        multiSigWallet = _multiSigWallet;
    }

    function stake(uint256 amount)
        external
        nonReentrant
        crntAddressSet
        onlyIfActive
    {
        crntToken = IERC20(crntAddress);
        require(amount >= 1000, "Amount below minimum staking threshold");

        crntToken.safeTransferFrom(msg.sender, address(this), amount);

        if (!isStaker[msg.sender]) {
            stakerIndex[msg.sender] = stakers.length;
            stakers.push(msg.sender);
            isStaker[msg.sender] = true;
        }

        if (stakedFromTimestamp[msg.sender] == 0) {
            stakedFromTimestamp[msg.sender] = block.timestamp;
        } else if (
            balances[msg.sender] > 0 &&
            (lockEndTimestamp[msg.sender] + CLAIM_PERIOD) <= block.timestamp
        ) {
            if (lockEndTimestamp[msg.sender] != 0) {
                claimRewards();
            }
        }

        balances[msg.sender] += amount;
        totalStaked += amount;
        lockEndTimestamp[msg.sender] = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external crntAddressSet onlyIfActive {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        uint256 penaltyAmount = 0;

        if (block.timestamp < stakedFromTimestamp[msg.sender] + LOCK_PERIOD) {
            penaltyAmount = (amount * 10) / 100;
            balances[msg.sender] -= penaltyAmount;
            ICRNT(crntAddress).burnFrom(penaltyAmount);
            emit PenaltyBurned(msg.sender, penaltyAmount);
        }

        balances[msg.sender] -= (amount - penaltyAmount);
        crntToken.safeTransfer(msg.sender, amount - penaltyAmount);
        totalStaked -= amount;

        if (balances[msg.sender] == 0) {
            stakedFromTimestamp[msg.sender] = 0;
            isStaker[msg.sender] = false;
            removeStaker(msg.sender);
        }

        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() public nonReentrant onlyIfActive {
        require(balances[msg.sender] > 0, "Insufficient balance");
        uint256 secondsStaked = block.timestamp -
            stakedFromTimestamp[msg.sender];
        require(
            secondsStaked >= MIN_STAKE_DURATION,
            "Stake duration too short"
        );

        uint256 reward = (balances[msg.sender] * REWARD_RATE * secondsStaked) /
            (100 * SECONDS_IN_YEAR);
        require(reward > 0, "No rewards to claim");

        // _mint(msg.sender, reward);
        ICRNT(crntAddress).sendReward(msg.sender, reward);
        stakedFromTimestamp[msg.sender] = block.timestamp;

        emit RewardsClaimed(msg.sender, reward);
    }

    function ceaseContract() external onlyOwner {
        crntToken = IERC20(crntAddress);
        address RESERVE = 0x46A8979d11189131b86D11866dB013A00d6FB625;
        require(
            crntToken.balanceOf(RESERVE) == 0,
            "Reserve balance is not zero"
        );
        isActive = false;
    }

    function unceaseContract() external onlyOwner {
        isActive = true;
    }

    function distributeRevenue(uint256 revenueAmount) external onlyIfActive {
        require(
            msg.sender == multiSigWallet,
            "Only MultiSigWallet can distribute revenue"
        );
        require(totalStaked > 0, "No staked tokens");
        require(revenueAmount > 0, "Invalid revenue amount");

        crntToken = IERC20(crntAddress);
        require(
            crntToken.balanceOf(msg.sender) >= revenueAmount,
            "Insufficient balance"
        );

        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            uint256 stakerRevenue = (balances[staker] * revenueAmount) /
                totalStaked;
            crntToken.safeTransferFrom(msg.sender, staker, stakerRevenue);
        }

        totalRevenueShared += revenueAmount;
        emit RevenueDistributed(revenueAmount);
    }

    function removeStaker(address staker) internal {
        uint256 index = stakerIndex[staker];
        uint256 lastIndex = stakers.length - 1;

        if (index != lastIndex) {
            address lastStaker = stakers[lastIndex];
            stakers[index] = lastStaker;
            stakerIndex[lastStaker] = index;
        }

        stakers.pop();
        delete stakerIndex[staker];
        emit StakerRemoved(staker, index);
    }

    function setCrntAddress(address crnt) external onlyOwner {
        require(crnt != address(0), "Invalid CRNT address");
        address oldAddress = crntAddress;
        crntAddress = crnt;
        emit CrntAddressUpdated(oldAddress, crnt);
    }
}
