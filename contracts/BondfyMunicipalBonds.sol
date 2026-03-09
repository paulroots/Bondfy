// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721A} from "erc721a/contracts/ERC721A.sol";

/**
 * @title BondfyMunicipalBonds
 * @notice ERC721A bond NFTs for municipality projects issued through Bondfy.
 */
contract BondfyMunicipalBonds is ERC721A {
    enum BuyerType {
        Unspecified,
        Citizen,
        Organization
    }

    struct Municipality {
        string name;
        string jurisdiction;
        address treasury;
        bool active;
    }

    struct BondSeries {
        uint256 municipalityId;
        string projectName;
        string metadataURI;
        uint256 priceWei;
        uint256 parValueWei;
        uint256 couponBps;
        uint256 maturityTimestamp;
        uint256 maxSupply;
        uint256 sold;
        bool active;
    }

    address public bondfyOperator;
    address public owner;
    uint256 public platformFeeBps = 100; // 1.00%
    uint256 public accruedPlatformFees;
    uint256 private _lock = 1;

    uint256 public nextMunicipalityId = 1;
    uint256 public nextBondSeriesId = 1;

    mapping(uint256 => Municipality) public municipalities;
    mapping(uint256 => BondSeries) public bondSeries;
    mapping(uint256 => uint256) public tokenToBondSeries;
    mapping(address => BuyerType) public buyerTypes;
    mapping(address => bool) public approvedPlatformContracts;

    event BondfyOperatorUpdated(address indexed oldOperator, address indexed newOperator);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event MunicipalityRegistered(uint256 indexed municipalityId, string name, address indexed treasury);
    event MunicipalityStatusUpdated(uint256 indexed municipalityId, bool active);
    event BondSeriesIssued(
        uint256 indexed bondSeriesId,
        uint256 indexed municipalityId,
        string projectName,
        uint256 maxSupply,
        uint256 priceWei
    );
    event BondPurchased(
        uint256 indexed bondSeriesId,
        address indexed buyer,
        BuyerType buyerType,
        uint256 quantity,
        uint256 amountPaid
    );
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event PlatformFeesWithdrawn(address indexed to, uint256 amount);
    event PlatformContractApprovalUpdated(address indexed platformContract, bool approved);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyBondfyOrOwner() {
        require(msg.sender == owner || msg.sender == bondfyOperator, "Not Bondfy");
        _;
    }

    modifier onlyMunicipalityTreasury(uint256 municipalityId) {
        Municipality memory m = municipalities[municipalityId];
        require(m.active, "Municipality inactive");
        require(msg.sender == m.treasury, "Not municipality treasury");
        _;
    }

    modifier nonReentrant() {
        require(_lock == 1, "Reentrancy");
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(address initialBondfyOperator, address initialOwner) ERC721A("Bondfy Municipal Bond", "BOND") {
        require(initialOwner != address(0), "Invalid owner");
        owner = initialOwner;
        bondfyOperator = initialBondfyOperator;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setBondfyOperator(address newOperator) external onlyOwner {
        emit BondfyOperatorUpdated(bondfyOperator, newOperator);
        bondfyOperator = newOperator;
    }

    function setPlatformFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 2_000, "Fee too high"); // max 20%
        emit PlatformFeeUpdated(platformFeeBps, newFeeBps);
        platformFeeBps = newFeeBps;
    }

    function setApprovedPlatformContract(address platformContract, bool approved) external onlyOwner {
        require(platformContract != address(0), "Invalid platform");
        approvedPlatformContracts[platformContract] = approved;
        emit PlatformContractApprovalUpdated(platformContract, approved);
    }

    function registerMunicipality(string calldata name, string calldata jurisdiction, address treasury)
        external
        onlyBondfyOrOwner
        returns (uint256 municipalityId)
    {
        require(treasury != address(0), "Invalid treasury");

        municipalityId = nextMunicipalityId++;
        municipalities[municipalityId] = Municipality({
            name: name,
            jurisdiction: jurisdiction,
            treasury: treasury,
            active: true
        });

        emit MunicipalityRegistered(municipalityId, name, treasury);
    }

    function setMunicipalityActive(uint256 municipalityId, bool active) external onlyBondfyOrOwner {
        require(municipalityId > 0 && municipalityId < nextMunicipalityId, "Municipality not found");
        municipalities[municipalityId].active = active;
        emit MunicipalityStatusUpdated(municipalityId, active);
    }

    function issueBondSeries(
        uint256 municipalityId,
        string calldata projectName,
        string calldata metadataURI,
        uint256 priceWei,
        uint256 parValueWei,
        uint256 couponBps,
        uint256 maturityTimestamp,
        uint256 maxSupply
    ) external onlyMunicipalityTreasury(municipalityId) returns (uint256 seriesId) {
        require(maxSupply > 0, "Max supply is zero");
        require(priceWei > 0, "Price is zero");
        require(maturityTimestamp > block.timestamp, "Invalid maturity");

        seriesId = nextBondSeriesId++;
        bondSeries[seriesId] = BondSeries({
            municipalityId: municipalityId,
            projectName: projectName,
            metadataURI: metadataURI,
            priceWei: priceWei,
            parValueWei: parValueWei,
            couponBps: couponBps,
            maturityTimestamp: maturityTimestamp,
            maxSupply: maxSupply,
            sold: 0,
            active: true
        });

        emit BondSeriesIssued(seriesId, municipalityId, projectName, maxSupply, priceWei);
    }

    function setBondSeriesActive(uint256 seriesId, bool active) external {
        BondSeries storage s = bondSeries[seriesId];
        require(s.maxSupply > 0, "Series not found");

        Municipality memory m = municipalities[s.municipalityId];
        require(msg.sender == owner || msg.sender == bondfyOperator || msg.sender == m.treasury, "Not authorized");

        s.active = active;
    }

    function setBuyerType(BuyerType buyerType) external {
        buyerTypes[msg.sender] = buyerType;
    }

    function setBuyerTypeFor(address buyer, BuyerType buyerType) external onlyBondfyOrOwner {
        require(buyer != address(0), "Invalid buyer");
        buyerTypes[buyer] = buyerType;
    }

    /**
     * @notice Citizens and organizations buy municipal bond NFTs via Bondfy.
     */
    function buyBonds(uint256 seriesId, uint256 quantity) external payable nonReentrant {
        _buyBonds(seriesId, quantity, msg.sender);
    }

    /**
     * @notice Approved Bondfy platform contracts can route purchases for beneficiaries.
     */
    function buyBondsFor(address beneficiary, uint256 seriesId, uint256 quantity) external payable nonReentrant {
        require(approvedPlatformContracts[msg.sender], "Platform not approved");
        require(beneficiary != address(0), "Invalid beneficiary");
        _buyBonds(seriesId, quantity, beneficiary);
    }

    function _buyBonds(uint256 seriesId, uint256 quantity, address beneficiary) internal {
        BondSeries storage s = bondSeries[seriesId];
        require(s.maxSupply > 0, "Series not found");
        require(s.active, "Series inactive");
        require(quantity > 0, "Quantity is zero");
        require(s.sold + quantity <= s.maxSupply, "Insufficient inventory");

        uint256 totalPrice = s.priceWei * quantity;
        require(msg.value == totalPrice, "Incorrect payment");

        Municipality memory m = municipalities[s.municipalityId];
        require(m.active, "Municipality inactive");

        uint256 startTokenId = _nextTokenId();
        s.sold += quantity;
        _mint(beneficiary, quantity);

        for (uint256 i = 0; i < quantity; i++) {
            tokenToBondSeries[startTokenId + i] = seriesId;
        }

        uint256 fee = (totalPrice * platformFeeBps) / 10_000;
        uint256 proceeds = totalPrice - fee;
        accruedPlatformFees += fee;

        (bool ok, ) = payable(m.treasury).call{value: proceeds}("");
        require(ok, "Municipality transfer failed");

        emit BondPurchased(seriesId, beneficiary, buyerTypes[beneficiary], quantity, totalPrice);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        uint256 seriesId = tokenToBondSeries[tokenId];
        return bondSeries[seriesId].metadataURI;
    }

    function withdrawPlatformFees(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid receiver");
        require(amount <= accruedPlatformFees, "Amount exceeds fees");

        accruedPlatformFees -= amount;
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "Fee withdrawal failed");

        emit PlatformFeesWithdrawn(to, amount);
    }
}
