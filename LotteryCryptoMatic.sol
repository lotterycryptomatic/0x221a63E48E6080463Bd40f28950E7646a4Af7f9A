// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LotteryCryptomatic {
    address public owner;
    uint256 public totalBalance;
    uint256 public totalBets;
    uint256 public totalPrizesPaid;
    uint256 public totalParticipantPayouts;
    uint256 public totalOwnerPayouts;
    uint256 public constant threshold = 1 ether;
    uint256 public constant prizeWinnerAmount = 2 ether;
    uint256 public constant participantAmount = 0.75 ether;
    uint256 public constant numParticipants = 10;
    uint256 public numGroups;
    uint256 public currentGroup;
    uint256 public transactionIndex;
    bool public paused;
    uint256 public constant contractFeeAmount = 1.25 ether;
    uint256 public excessAmount;

    mapping(address => uint256) public winnings;

    struct Lottery {
        address winner;
        address[] participants;
    }

    mapping(uint256 => Lottery) public lotteries;
    mapping(uint256 => bool) public transactionProcessed;

    event TransferReceived(address indexed sender, uint256 amount, bytes32 indexed transactionHash, uint256 indexed transactionCount, uint256 groupNumber, uint256 timestamp);
    event BetPlaced(address indexed bettor, uint256 amount, bytes32 indexed transactionHash, uint256 indexed transactionCount, uint256 groupNumber, uint256 timestamp);
    event LotteryCreated(address indexed owner, uint256 indexed groupNumber, address winner, address[] participants, uint256 timestamp);
    event PrizeDistributed(address indexed winner, uint256 amountReceived, bytes32 indexed transactionHash, uint256 indexed transactionCount, uint256 groupNumber, uint256 prizeAmount, uint256 timestamp, bytes32 paymentHash);
    event WinnerSelected(uint256 indexed groupNumber, uint256 transactionCount, address winner, uint256 prizeAmountReceived, uint256 winnerTransactionNumber, uint256 totalPrizesPaidInEther, uint256 totalConsolationPrizeAmountInEther, uint256 timestamp);
    event Withdrawal(address indexed owner, uint256 amount, uint256 timestamp);
    event Paused(address indexed toggledBy, bool isPaused, uint256 timestamp);
    event ParticipantAdded(uint256 indexed groupNumber, address participant, uint256 currentParticipants, uint256 remainingNeeded, uint256 timestamp); // Modificado para incluir informações numéricas
    event PrizePaid(address indexed recipient, uint256 amount, bytes32 indexed transactionHash, uint256 indexed transactionCount, uint256 groupNumber, uint256 timestamp);
    event LotteryClosed(uint256 indexed groupNumber, address winner, uint256 totalPrizeAmount, uint256 timestamp);
    event ContractFeePayment(address indexed owner, uint256 amount, bytes32 indexed transactionHash, uint256 timestamp); // Evento renomeado
    event ThresholdChanged(uint256 newThreshold, uint256 timestamp);
    event PrizeThresholdReached(uint256 indexed groupNumber, uint256 numParticipants, uint256 timestamp);
    event WinningBet(address indexed winner, uint256 numWins, uint256 timestamp);
    event RankUpdated(address indexed participant, uint256 numWins, uint256 timestamp);
    event TransferCompleted(address indexed recipient, uint256 amount, bytes32 indexed transactionHash);
    event ExcessReturned(address indexed recipient, uint256 amount); // Evento para registrar a devolução do valor excedente
    event ExcessWithdrawn(address indexed owner, uint256 amount, uint256 timestamp); // Evento para registrar a retirada do saldo excedente

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused.");
        _;
    }

    modifier whenPaused() {
        require(paused, "Contract is not paused.");
        _;
    }

    constructor() {
        owner = msg.sender;
        numGroups = 0;
        currentGroup = 0;
        transactionIndex = 0;
        paused = false;
        excessAmount = 0; // Initialize excessAmount
    }

    function pause() external onlyOwner whenNotPaused {
        paused = true;
        emit Paused(msg.sender, true, block.timestamp);
    }

    function unpause() external onlyOwner whenPaused {
        paused = false;
        emit Paused(msg.sender, false, block.timestamp);
    }

    receive() external payable whenNotPaused {
        transfer();
    }

    function transfer() private whenNotPaused {
        if (msg.value > threshold) {
            // Calculate the difference between the sent value and the minimum required
            excessAmount += msg.value - threshold;
            // Update the totalBalance value to reflect the minimum required
            totalBalance += threshold;
            // Emit an event to record the return of the excess amount
            emit ExcessReturned(msg.sender, excessAmount);
        } else {
            require(msg.value == threshold, "Transfer must be at least 1 ether.");
            totalBalance += msg.value;
        }

        totalBets++;
        transactionIndex++;

        emit TransferReceived(msg.sender, msg.value, bytes32(0), transactionIndex, currentGroup, block.timestamp);
        emit BetPlaced(msg.sender, msg.value, bytes32(0), transactionIndex, currentGroup, block.timestamp);

        if (transactionIndex > 1 && (transactionIndex - 1) % numParticipants == 0) {
            createLotteryGroup();
            currentGroup++;
        }

        addParticipantToLottery(msg.sender);
    }

    function createLotteryGroup() private {
        address[] memory participants = new address[](0); // Initialize empty array
        lotteries[currentGroup] = Lottery(address(0), participants);
        emit LotteryCreated(owner, currentGroup, address(0), participants, block.timestamp);
        emit ThresholdChanged(threshold, block.timestamp);
        numGroups++;
    }

    function addParticipantToLottery(address participant) private {
        uint256 currentTransactionGroup = (transactionIndex - 1) / numParticipants;
        Lottery storage lottery = lotteries[currentTransactionGroup];

        require(lottery.participants.length < numParticipants, "Lottery group is full.");

        lottery.participants.push(participant);

        emit ParticipantAdded(
            currentTransactionGroup, // Número do grupo
            participant, 
            lottery.participants.length, // Número atual de participantes no grupo
            numParticipants - lottery.participants.length, // Número de participantes restantes necessários para preencher o grupo
            block.timestamp
        );

        if (lottery.participants.length == numParticipants) {
            if (!transactionProcessed[currentTransactionGroup]) {
                distributePrizes(currentTransactionGroup);
                transactionProcessed[currentTransactionGroup] = true;
            }
        } else if (lottery.participants.length == numParticipants - 1) {
            emit PrizeThresholdReached(currentTransactionGroup, numParticipants, block.timestamp);
        }
    }

    function random(uint256 seed, uint256 maxValue) private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), seed ))) % maxValue;
    }

    function chooseWinner(address[] memory participants) private view returns (address) {
        uint256 randomIndex = random(block.number, participants.length);
        return participants[randomIndex];
    }

    function distributePrizes(uint256 groupNumber) private {
        require(groupNumber <= numGroups, "Invalid group number.");
        Lottery storage lottery = lotteries[groupNumber];
        address winner = chooseWinner(lottery.participants);
        lotteries[groupNumber].winner = winner;

        uint256 totalPrizeAmount = prizeWinnerAmount + (participantAmount * (numParticipants - 1));
        uint256 consolationPrizeAmount = participantAmount * (numParticipants - 1);

        // Payment of prize to the winner
        payable(winner).transfer(prizeWinnerAmount);
        bytes32 winnerTxHash = keccak256(abi.encodePacked(block.timestamp, winner, prizeWinnerAmount));
        emit PrizePaid(winner, prizeWinnerAmount, winnerTxHash, transactionIndex, groupNumber, block.timestamp);
        emit TransferCompleted(winner, prizeWinnerAmount, winnerTxHash);

        // Payment of contract fees
        payable(owner).transfer(contractFeeAmount);
        bytes32 feeTxHash = keccak256(abi.encodePacked(block.timestamp, owner, contractFeeAmount));
        emit ContractFeePayment(owner, contractFeeAmount, feeTxHash, block.timestamp);
        emit TransferCompleted(owner, contractFeeAmount, feeTxHash);

        for (uint256 i = 0; i < lottery.participants.length; i++) {
            if (lottery.participants[i] != winner) {
                // Payment of participant prizes
                payable(lottery.participants[i]).transfer(participantAmount);
                bytes32 participantTxHash = keccak256(abi.encodePacked(block.timestamp, lottery.participants[i], participantAmount));
                emit PrizePaid(lottery.participants[i], participantAmount, participantTxHash, transactionIndex, groupNumber, block.timestamp);
                emit TransferCompleted(lottery.participants[i], participantAmount, participantTxHash);
            }
        }

        totalPrizesPaid += prizeWinnerAmount;
        totalParticipantPayouts += participantAmount * (numParticipants - 1);
        totalOwnerPayouts += contractFeeAmount;

        // Emit events
        emit WinnerSelected(
            groupNumber,
            transactionIndex,
            winner,
            prizeWinnerAmount,
            transactionIndex, // Winner's transaction number
            totalPrizesPaid,
            consolationPrizeAmount,
            block.timestamp
        );

        emit PrizeDistributed(
            winner,
            prizeWinnerAmount,
            winnerTxHash, // Winner's transaction hash
            transactionIndex,
            groupNumber,
            totalPrizeAmount,
            block.timestamp,
            bytes32(0) // Placeholder for payment hash
        );

        winnings[winner]++;
        emit WinningBet(winner, winnings[winner], block.timestamp);

        emit RankUpdated(winner, winnings[winner], block.timestamp);
    }

    function withdrawAll() external onlyOwner whenNotPaused {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw.");
        payable(owner).transfer(balance);
        emit Withdrawal(owner, balance, block.timestamp);
    }

    function withdrawExcess() external onlyOwner whenNotPaused {
        require(excessAmount > 0, "No excess balance available.");
        uint256 amountToWithdraw = excessAmount;
        excessAmount = 0; // Reset excessAmount
        payable(owner).transfer(amountToWithdraw);
        emit ExcessWithdrawn(owner, amountToWithdraw, block.timestamp);
    }

    function getWinnings(address participant) external view returns (uint256) {
        return winnings[participant];
    }

    // Security function to check contract balance
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Security function to check if the contract is paused
    function isPaused() external view returns (bool) {
        return paused;
    }

    // Security function to check if a lottery group has been processed
    function isTransactionProcessed(uint256 groupNumber) external view returns (bool) {
        return transactionProcessed[groupNumber];
    }

    // Security function to check participants of a lottery group
    function getParticipants(uint256 groupNumber) external view returns (address[] memory) {
        return lotteries[groupNumber].participants;
    }
}

