// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RefundablePreorder.sol";                            // Import interface

contract RefundablePreorderImp is RefundablePreorder {

    // struct holding each buyer’s preorder details
    struct BuyerInfo {
        uint256 quantity;                                      // Units ordered
        uint256 amountPaid;                                    // ETH paid
        bool confirmed;                                        // Buyer confirmed delivery
        bool refunded;                                         // Buyer refunded already?
    }

    // state variables storing product & campaign info
    string private _productName;                               // Product name
    uint256 private _unitPrice;                                // Price per unit
    uint256 private _deadline;                                 // Delivery deadline
    address private _seller;                                   // Seller address

    bool private _delivered;                                   // Seller marked delivered?
    bool private _fundsWithdrawn;                              // Seller already withdrew funds?

    uint256 private _totalQuantity;                            // Total units ordered
    uint256 private _totalCollected;                           // Current ETH held
    uint256 private _deliveryTimestamp;                        // When delivery was marked
    bool private _anyBuyerConfirmed;                           // Did at least one buyer confirm?

    uint256 private constant CONFIRMATION_PERIOD = 7 days;     // Buyer confirmation window

    mapping(address => BuyerInfo) private _buyers;             // Buyer records

    mapping(address => bytes32) private _codeHash;             // Activation-code hash per buyer
    mapping(address => bool) private _codeSet;                 // Hashed code set for buyer?

// Unique salt used in hashing codes (prevents dictionary attacks)
    bytes32 private immutable _salt;

    event ReceiptConfirmed(address indexed buyer, uint256 timestamp);
    event ActivationCodeHashSet(address indexed buyer, bytes32 codeHash);

    // only allow seller to call certain functions
    modifier onlySeller() {
        require(msg.sender == _seller, "Only seller can call this"); 
        _;
    }

    // enforce deadline rules
    modifier beforeDeadline() {
        require(block.timestamp <= _deadline, "Past preorder deadline");
        _;
    }

    // ensure product is not yet marked delivered
    modifier notDelivered() {
        require(!_delivered, "Product already delivered");
        _;
    }

    // constructor sets initial product info
    constructor(
        string memory productName_,
        uint256 unitPrice_,
        uint256 deadline_
    ) {
        require(bytes(productName_).length > 0, "Product name required");
        require(unitPrice_ > 0, "Unit price > 0");
        require(deadline_ > block.timestamp, "Deadline must be future");

        _productName = productName_;
        _unitPrice = unitPrice_;
        _deadline = deadline_;
        _seller = msg.sender;
        // create a unique salt for this contract deployment
        _salt = keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }

    // buyers place preorder and send ETH; ETH gets locked inside contract
    function placePreorder(uint256 quantity)
        external
        payable
        override
        beforeDeadline
        notDelivered
    {
        require(quantity > 0, "Quantity must be > 0");

        uint256 expectedAmount = _unitPrice * quantity;
        require(msg.value == expectedAmount, "Incorrect ETH sent");

        BuyerInfo storage buyer = _buyers[msg.sender];
        buyer.quantity += quantity;
        buyer.amountPaid += msg.value;

        _totalQuantity += quantity;
        _totalCollected += msg.value;

        emit PreorderPlaced(msg.sender, quantity, msg.value, block.timestamp);
    }

    // seller marks product as delivered, starting confirmation window
    function markProductDelivered()
        external
        override
        onlySeller
        beforeDeadline
        notDelivered
    {
        _delivered = true;
        _deliveryTimestamp = block.timestamp;

        emit ProductDelivered(block.timestamp);
    }

    // seller sets activation-code hash for a buyer
    function setActivationCodeHash(address buyerAddr, bytes32 hash)
        external
        onlySeller
    {
        require(_buyers[buyerAddr].amountPaid > 0, "No preorder found"); // Ensure the buyer actually placed a preorder
        require(!_codeSet[buyerAddr], "Already set");  // Ensure the code hasn’t already been set for this buyer

       // store salted hash: keccak256(hash + salt)
        _codeHash[buyerAddr] = keccak256(abi.encodePacked(hash, _salt));
        _codeSet[buyerAddr] = true;

        emit ActivationCodeHashSet(buyerAddr, hash);
    }

    // buyers confirm receipt using activation code
    function confirmReceiptWithCode(string calldata code) external {
        require(_delivered, "Not delivered yet");        // Ensure the product has been delivered

        BuyerInfo storage buyer = _buyers[msg.sender];
        require(buyer.amountPaid > 0, "No preorder found"); // Buyer must have placed a preorder
        require(!buyer.confirmed, "Already confirmed"); // Prevent double confirmation
        require(!buyer.refunded, "Refunded buyer can't confirm"); // Prevent refunded buyers from confirming
        require(_codeSet[msg.sender], "Code not set"); // Ensure seller has set a code for this buyer


    // hash plaintext code → hash(code)
        bytes32 unhashed = keccak256(abi.encodePacked(code));

        // salted hash: hash(hash(code) + salt)
        bytes32 finalHash = keccak256(abi.encodePacked(unhashed, _salt));
        require(submitted == _codeHash[msg.sender], "Invalid activation code");

      // Mark buyer as confirmed and update overall state
        buyer.confirmed = true;
        _anyBuyerConfirmed = true;

        emit ReceiptConfirmed(msg.sender, block.timestamp);
    }

    // buyers confirm receipt (simple version kept for compatibility)
    function confirmReceipt() external {
        require(_delivered, "Not delivered yet");

        BuyerInfo storage buyer = _buyers[msg.sender];
        require(buyer.amountPaid > 0, "No preorder found");
        require(!buyer.confirmed, "Already confirmed");
        require(!buyer.refunded, "Refunded buyer can't confirm");

        buyer.confirmed = true;
        _anyBuyerConfirmed = true;

        emit ReceiptConfirmed(msg.sender, block.timestamp);
    }

    // buyers claim refund if: deadline passed AND product not delivered
    function claimRefund() external override {
        require(block.timestamp > _deadline, "Deadline not reached");
        require(!_delivered, "Product delivered - refunds disabled");

        BuyerInfo storage buyer = _buyers[msg.sender];
        require(buyer.amountPaid > 0, "No preorder found");
        require(!buyer.refunded, "Already refunded");

        buyer.refunded = true;
        uint256 refundAmount = buyer.amountPaid;
        buyer.amountPaid = 0;
        buyer.quantity = 0;

        _totalCollected -= refundAmount;

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund failed");

        emit RefundClaimed(msg.sender, refundAmount);
    }

    // seller withdraws funds IF: delivered AND (buyer confirmed OR timeout passed)
    function withdrawFunds() external override onlySeller {
        require(_delivered, "Not delivered yet");
        require(!_fundsWithdrawn, "Already withdrawn");

        bool waitPassed = block.timestamp >= _deliveryTimestamp + CONFIRMATION_PERIOD;

        require(
            _anyBuyerConfirmed || waitPassed,
            "Need confirmation or wait period"
        );

        _fundsWithdrawn = true;

        uint256 amount = address(this).balance;
        require(amount > 0, "No funds available");

        (bool success, ) = _seller.call{value: amount}("");
        require(success, "Withdraw failed");

        emit FundsWithdrawn(_seller, amount);
    }

    // return buyer info
    
    function getBuyerInfo(address buyer)
        external
        view
        override
        returns (uint256 quantity, uint256 amountPaid, bool refunded)
    {
        BuyerInfo memory info = _buyers[buyer];
        return (info.quantity, info.amountPaid, info.refunded);
    }

    // return overall preorder campaign info
    function getPreorderInfo()
        external
        view
        override
        returns (
            string memory productName,
            uint256 unitPrice,
            uint256 deadline,
            uint256 totalQuantity,
            uint256 totalCollected,
            address seller,
            bool delivered,
            bool fundsWithdrawn
        )
    {
        return (
            _productName,
            _unitPrice,
            _deadline,
            _totalQuantity,
            _totalCollected,
            _seller,
            _delivered,
            _fundsWithdrawn
        );
    }
}
