pragma solidity ^0.8.0;

interface RefundablePreorder {
    event PreorderPlaced(
        address indexed buyer,
        uint256 quantity,
        uint256 amountPaid,
        uint256 timestamp
    );

    event ProductDelivered(
        uint256 timestamp
    );

    event RefundClaimed(
        address indexed buyer,
        uint256 amount
    );

    event FundsWithdrawn(
        address indexed seller,
        uint256 amount
    );

    // Place a preorder by sending ETH.
    // msg.value must equal unitPrice * quantity.
    // Only allowed before the deadline and before delivery is marked.
    function placePreorder(uint256 quantity) external payable;

    // Claim a refund if the product was not delivered
    // by the deadline. Each buyer can only refund
    // their own contribution.
    function claimRefund() external;

    // Called by the seller to mark the product as delivered.
    // After this, refunds are disabled and funds can be withdrawn.
    function markProductDelivered() external;

    // Called by the seller to withdraw all collected funds
    // after the product has been marked as delivered.
    function withdrawFunds() external;

    // View how much a buyer has preordered.
    function getBuyerInfo(address buyer)
        external
        view
        returns (
            uint256 quantity,
            uint256 amountPaid,
            bool refunded
        );

    // View basic info about the preorder campaign.
    function getPreorderInfo()
        external
        view
        returns (
            string memory productName,
            uint256 unitPrice,
            uint256 deadline,
            uint256 totalQuantity,
            uint256 totalCollected,
            address seller,
            bool delivered,
            bool fundsWithdrawn
        );
}
