// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public crntToken;
    uint256 public immutable totalAllocation;
    uint256 public immutable monthlyRelease;
    uint256 public immutable startTimestamp;
    uint256 public lastReleaseTimestamp;
    uint256 public releasedAmount;

    uint256 public beneficiaryUpdateTime;
    uint256 public constant TIMELOCK_DELAY = 7 days;

    address public beneficiary;
    address public immutable multiSigWallet;

    event TokensReleased(address indexed beneficiary, uint256 amount);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);

    constructor(
        address _crntToken,
        uint256 _totalAllocation,
        uint256 _monthlyRelease,
        uint256 _startTimestamp,
        address _multiSigWallet
    ) {
        require(_multiSigWallet != address(0), "Invalid MultiSigWallet address");

        crntToken = IERC20(_crntToken);
        totalAllocation = _totalAllocation;
        monthlyRelease = _monthlyRelease;
        startTimestamp = _startTimestamp;
        lastReleaseTimestamp = _startTimestamp;
        beneficiary = msg.sender;
        multiSigWallet = _multiSigWallet;

        beneficiaryUpdateTime = block.timestamp;
    }

    function updateBeneficiary(address newBeneficiary) external {
        require(msg.sender == multiSigWallet, "Only MultiSigWallet can update beneficiary");
        require(block.timestamp >= beneficiaryUpdateTime + TIMELOCK_DELAY, "Timelock not expired");
        require(newBeneficiary != address(0), "Invalid beneficiary address");

        emit BeneficiaryUpdated(beneficiary, newBeneficiary);
        beneficiary = newBeneficiary;
        beneficiaryUpdateTime = block.timestamp;
    }

    function releaseTokens() external nonReentrant {
        require(msg.sender == beneficiary, "Only the beneficiary can release tokens");
        require(block.timestamp >= lastReleaseTimestamp + 30 days, "30-day interval not met");

        uint256 releaseAmount = monthlyRelease;
        require(releasedAmount + releaseAmount <= totalAllocation, "Allocation exceeded");

        lastReleaseTimestamp = block.timestamp;
        releasedAmount += releaseAmount;

        require(crntToken.balanceOf(address(this)) >= releaseAmount, "Insufficient token balance");
        crntToken.safeTransfer(beneficiary, releaseAmount);

        emit TokensReleased(beneficiary, releaseAmount);
    }
}
