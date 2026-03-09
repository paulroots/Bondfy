// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBondFiMunicipalBonds {
    enum BuyerType {
        Unspecified,
        Citizen,
        Organization
    }

    function buyBondsFor(address beneficiary, uint256 seriesId, uint256 quantity) external payable;
    function setBuyerTypeFor(address buyer, BuyerType buyerType) external;
}

/**
 * @title BondFiDigitalPlatform
 * @notice Platform-facing contract for managed/KYC investor purchases.
 */
contract BondFiDigitalPlatform {
    struct InvestorProfile {
        bool active;
        bool kycVerified;
        IBondFiMunicipalBonds.BuyerType buyerType;
    }

    address public owner;
    mapping(address => bool) public operators;
    mapping(address => InvestorProfile) public investors;
    IBondFiMunicipalBonds public immutable municipalBonds;

    uint256 private _lock = 1;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event OperatorUpdated(address indexed operator, bool enabled);
    event InvestorUpdated(
        address indexed investor,
        bool active,
        bool kycVerified,
        IBondFiMunicipalBonds.BuyerType buyerType
    );
    event ManagedPurchase(
        uint256 indexed seriesId,
        address indexed investor,
        uint256 quantity,
        uint256 amountPaid,
        address indexed operator
    );
    event NativeWithdrawn(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyOperatorOrOwner() {
        require(msg.sender == owner || operators[msg.sender], "Not operator");
        _;
    }

    modifier nonReentrant() {
        require(_lock == 1, "Reentrancy");
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(address initialOwner, address municipalBondsAddress) {
        require(initialOwner != address(0), "Invalid owner");
        require(municipalBondsAddress != address(0), "Invalid bonds");
        owner = initialOwner;
        municipalBonds = IBondFiMunicipalBonds(municipalBondsAddress);
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setOperator(address operator, bool enabled) external onlyOwner {
        require(operator != address(0), "Invalid operator");
        operators[operator] = enabled;
        emit OperatorUpdated(operator, enabled);
    }

    function upsertInvestor(
        address investor,
        bool active,
        bool kycVerified,
        IBondFiMunicipalBonds.BuyerType buyerType
    ) external onlyOperatorOrOwner {
        require(investor != address(0), "Invalid investor");
        investors[investor] = InvestorProfile({active: active, kycVerified: kycVerified, buyerType: buyerType});
        municipalBonds.setBuyerTypeFor(investor, buyerType);
        emit InvestorUpdated(investor, active, kycVerified, buyerType);
    }

    function purchaseMunicipalBonds(address investor, uint256 seriesId, uint256 quantity)
        external
        payable
        onlyOperatorOrOwner
        nonReentrant
    {
        InvestorProfile memory profile = investors[investor];
        require(profile.active, "Investor inactive");
        require(profile.kycVerified, "KYC required");
        require(quantity > 0, "Quantity is zero");

        municipalBonds.buyBondsFor{value: msg.value}(investor, seriesId, quantity);

        emit ManagedPurchase(seriesId, investor, quantity, msg.value, msg.sender);
    }

    function withdrawNative(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid receiver");
        require(amount <= address(this).balance, "Insufficient balance");
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "Withdraw failed");
        emit NativeWithdrawn(to, amount);
    }
}
