// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title UnifrensBurnRegistry
 * @dev Manages a list of addresses that are considered "burned" positions.
 * Positions transferred to these addresses will have their weights set to 0
 * and their rewards fully redistributed to the reward pool.
 */
interface IUnifrensBurnRegistry {
    function isBurnAddress(address addr) external view returns (bool);
    function handleBurnAddressRewards(address addr) external;
}

interface IUnifrensCore {
    function getPendingRewards(uint256 tokenId) external view returns (uint256);
    function updateGlobalRewards(uint256 fee, bool isNewMoney) external;
    function totalSupply() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function unifrenNames(uint256 tokenId) external view returns (string memory);
    function _normalizedNameTaken(string memory name) external view returns (bool);
    function setEmergencyName(uint256 tokenId, string memory newName) external;
    function overrideName(uint256 tokenId, string memory newName) external;
}

contract UnifrensBurnRegistry is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable,
    IUnifrensBurnRegistry 
{
    // ============ State Variables ============

    /// @dev Reference to the core contract
    address public core;

    /// @dev Mapping of burn addresses
    mapping(address => bool) private _burnAddresses;

    /// @dev Mapping of token IDs to override name changes
    mapping(uint256 => string) private _overrideNames;

    // ============ Events ============

    /// @dev Emitted when the core contract is updated
    event CoreUpdated(address indexed oldCore, address indexed newCore);

    /// @dev Emitted when a burn address is added
    event BurnAddressAdded(address indexed addr);

    /// @dev Emitted when a burn address is removed
    event BurnAddressRemoved(address indexed addr);

    /// @dev Emitted when rewards are redistributed from a burn address
    event BurnRewardsRedistributed(address indexed addr, uint256 amount);

    /// @dev Emitted when a token's name is overridden
    event NameOverridden(uint256 indexed tokenId, string oldName, string newName);

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

        // Add known burn addresses
        _addBurnAddress(0x000000000000000000000000000000000000dEaD);
        _addBurnAddress(0x0000000000000000000000000000000000000000);
    }

    // ============ Core Functions ============

    function setCore(address _core) external onlyOwner {
        require(_core != address(0), "Invalid core address");
        address oldCore = core;
        core = _core;
        emit CoreUpdated(oldCore, _core);
    }

    // ============ Burn Address Management ============

    function addBurnAddress(address addr) external onlyOwner {
        require(addr != address(0), "Invalid address");
        _addBurnAddress(addr);
        // Handle any existing tokens at this address
        _handleAddressRewards(addr);
    }

    function removeBurnAddress(address addr) external onlyOwner {
        require(addr != address(0), "Invalid address");
        _removeBurnAddress(addr);
    }

    function isBurnAddress(address addr) external view returns (bool) {
        return _burnAddresses[addr];
    }

    function handleBurnAddressRewards(address addr) external onlyCore {
        _handleAddressRewards(addr);
    }

    // ============ Name Management ============

    /**
     * @dev Overrides a token's name
     * Only works for tokens owned by burn addresses
     * @param tokenId The ID of the token to rename
     * @param newName The new name to set
     */
    function overrideName(uint256 tokenId, string memory newName) external onlyOwner {
        IUnifrensCore coreContract = IUnifrensCore(core);
        address owner = coreContract.ownerOf(tokenId);
        
        // Verify token is owned by a burn address
        require(_burnAddresses[owner], "Token not owned by burn address");
        
        // Get current name
        string memory oldName = coreContract.unifrenNames(tokenId);
        
        // Set new name in core contract
        coreContract.overrideName(tokenId, newName);
        
        // Store override name change
        _overrideNames[tokenId] = newName;
        
        emit NameOverridden(tokenId, oldName, newName);
    }

    /**
     * @dev Gets the override name for a token if it exists
     * @param tokenId The ID of the token to check
     * @return The override name if set, empty string otherwise
     */
    function getOverrideName(uint256 tokenId) external view returns (string memory) {
        return _overrideNames[tokenId];
    }

    // ============ Internal Functions ============

    function _addBurnAddress(address addr) internal {
        require(!_burnAddresses[addr], "Address already in burn list");
        _burnAddresses[addr] = true;
        emit BurnAddressAdded(addr);
    }

    function _removeBurnAddress(address addr) internal {
        require(_burnAddresses[addr], "Address not in burn list");
        _burnAddresses[addr] = false;
        emit BurnAddressRemoved(addr);
    }

    function _handleAddressRewards(address addr) internal {
        IUnifrensCore coreContract = IUnifrensCore(core);
        uint256 totalSupply = coreContract.totalSupply();
        uint256 totalRewards = 0;

        // Check all tokens owned by the address
        for (uint256 i = 1; i <= totalSupply; i++) {
            if (coreContract.ownerOf(i) == addr) {
                uint256 pendingRewards = coreContract.getPendingRewards(i);
                if (pendingRewards > 0) {
                    totalRewards += pendingRewards;
                }
            }
        }

        // If there are rewards to redistribute, do so
        if (totalRewards > 0) {
            coreContract.updateGlobalRewards(totalRewards, false);
            emit BurnRewardsRedistributed(addr, totalRewards);
        }
    }

    // ============ UUPS Upgradeable ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
} 