// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

contract MultiSigWallet {

    address[] public owners;
    uint256 public immutable required;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 approvals;
    }

    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public approvals;

    event TransactionCreated(uint256 indexed txId, address indexed to, uint256 value, bytes data);
    event TransactionApproved(uint256 indexed txId, address indexed approver);
    event TransactionExecuted(uint256 indexed txId);

    modifier onlyOwner() {
        require(isOwner(msg.sender), "Not an owner");
        _;
    }

    receive() external payable {}
    fallback() external payable {}

    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "Owners required");
        require(_required > 0 && _required <= _owners.length, "Invalid required approvals");

        owners = _owners;
        required = _required;
    }

    function isOwner(address account) public view returns (bool) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == account) return true;
        }
        return false;
    }

    function submitTransaction(address to, uint256 value, bytes calldata data) external onlyOwner {
        transactions.push(Transaction({
            to: to,
            value: value,
            data: data,
            executed: false,
            approvals: 0
        }));
        emit TransactionCreated(transactions.length - 1, to, value, data);
    }

    function approveTransaction(uint256 txId) external payable onlyOwner {
        require(txId < transactions.length, "Invalid transaction ID");
        require(!approvals[txId][msg.sender], "Already approved");
        require(!transactions[txId].executed, "Already executed");

        approvals[txId][msg.sender] = true;
        transactions[txId].approvals++;

        emit TransactionApproved(txId, msg.sender);

        if (transactions[txId].approvals >= required) {
            executeTransaction(txId);
        }
    }

    function executeTransaction(uint256 txId) public payable onlyOwner {
        Transaction storage transaction = transactions[txId];
        require(!transaction.executed, "Already executed");

        transaction.executed = true;
        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Transaction execution failed");

        emit TransactionExecuted(txId);
    }

}
