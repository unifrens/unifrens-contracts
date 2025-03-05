// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title UnifrensFeeManager
 * @dev Optional upgradeable component for handling additional fees from minting.
 * If not set, the core contract will not collect any additional fees.
 */
interface IUnifrensFeeManager {
    function handleMintFee(uint256 tokenId, uint256 weight, uint256 fee) external;
}

contract UnifrensFeeManager is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable,
    IUnifrensFeeManager 
{
    // ============ State Variables ============

    /// @dev Reference to the core contract
    address public core;

    /// @dev Fee percentage in basis points (1% = 100)
    uint256 public feePercentage;

    // ============ Events ============

    /// @dev Emitted when the core contract is updated
    event CoreUpdated(address indexed oldCore, address indexed newCore);

    /// @dev Emitted when the fee percentage is updated
    event FeePercentageUpdated(uint256 oldFee, uint256 newFee);

    /// @dev Emitted when fees are collected
    event FeesCollected(uint256 indexed tokenId, uint256 amount);

    // ============ Modifiers ============

    modifier onlyCore() {
        require(msg.sender == core, "Only core contract can call");
        _;
    }

    // ============ Initialization ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _core) public initializer {
        require(_core != address(0), "Invalid core address");
        core = _core;
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    // ============ Core Functions ============

    function setCore(address _core) external onlyOwner {
        require(_core != address(0), "Invalid core address");
        address oldCore = core;
        core = _core;
        emit CoreUpdated(oldCore, _core);
    }

    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 10000, "Fee too high"); // Max 100%
        uint256 oldFee = feePercentage;
        feePercentage = _feePercentage;
        emit FeePercentageUpdated(oldFee, _feePercentage);
    }

    // ============ Fee Handling ============

    function handleMintFee(uint256 tokenId, uint256 weight, uint256 fee) external onlyCore {
        require(fee > 0, "No fee to handle");
        emit FeesCollected(tokenId, fee);
        // Here you can implement custom fee distribution logic
        // For example, sending to a treasury, staking pool, etc.
    }

    // ============ UUPS Upgradeable ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
} 