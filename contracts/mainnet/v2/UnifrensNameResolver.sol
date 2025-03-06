// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//                 _ ____                    
//    __  ______  (_) __/_______  ____  _____
//   / / / / __ \/ / /_/ ___/ _ \/ __ \/ ___/
//  / /_/ / / / / / __/ /  /  __/ / / (__  ) 
//  \__,_/_/ /_/_/_/ /_/   \___/_/ /_/____/  
//                                         

/**
 * @title Unifrens Name Resolver Interface
 * @dev Interface for resolving .fren names to addresses and token IDs
 */
interface IUnifrens {
    /**
     * @dev Resolves a .fren name to its owner address
     * @param name The .fren name to resolve (e.g., "alice.fren")
     * @return owner The address that owns the name
     */
    function getName(string memory name) external view returns (address owner);

    /**
     * @dev Resolves a .fren name to its owner address and token ID
     * @param name The .fren name to resolve (e.g., "alice.fren")
     * @return owner The address that owns the name
     * @return tokenId The token ID associated with the name
     */
    function getNameWithId(string memory name) external view returns (address owner, uint256 tokenId);
}

/**
 * @title Unifrens Name Resolver
 * @dev A contract that manages multiple versions of Unifrens contracts and provides
 * a unified interface for resolving .fren names across all versions.
 * 
 * This contract is essential for:
 * 1. Supporting multiple versions of the Unifrens protocol
 * 2. Providing a single entry point for name resolution
 * 3. Enabling seamless upgrades while maintaining backward compatibility
 * 4. Allowing other protocols to integrate .fren names easily
 */
contract UnifrensNameResolver {
    /**
     * @dev Structure to track contract versions
     * @param contractAddress The address of the contract implementation
     * @param isActive Whether this version is currently active
     */
    struct Version {
        address contractAddress;
        bool isActive;
    }
    
    /// @dev Mapping of version numbers to their contract details
    mapping(uint8 => Version) public versions;
    
    /// @dev Total number of versions that have been added
    uint8 public versionCount;
    
    /// @dev Emitted when a new version is added
    event VersionAdded(uint8 indexed version, address contractAddress);
    
    /// @dev Emitted when a version is deactivated
    event VersionRemoved(uint8 indexed version);
    
    /// @dev Emitted when a version's contract address is updated
    event VersionUpdated(uint8 indexed version, address newAddress);
    
    /**
     * @dev Initializes the resolver with the first version
     * @param _v1Contract The address of the v1 Unifrens contract
     */
    constructor(address _v1Contract) {
        require(_v1Contract != address(0), "Invalid v1 address");
        versions[1] = Version(_v1Contract, true);
        versionCount = 1;
    }
    
    /**
     * @dev Adds a new version of the Unifrens contract
     * @param _contract The address of the new contract version
     */
    function addVersion(address _contract) external {
        require(_contract != address(0), "Invalid contract address");
        versionCount++;
        versions[versionCount] = Version(_contract, true);
        emit VersionAdded(versionCount, _contract);
    }
    
    /**
     * @dev Deactivates a specific version
     * @param _version The version number to deactivate
     */
    function removeVersion(uint8 _version) external {
        require(_version > 0 && _version <= versionCount, "Invalid version");
        versions[_version].isActive = false;
        emit VersionRemoved(_version);
    }
    
    /**
     * @dev Updates the contract address for a specific version
     * @param _version The version number to update
     * @param _newContract The new contract address
     */
    function updateVersion(uint8 _version, address _newContract) external {
        require(_version > 0 && _version <= versionCount, "Invalid version");
        require(_newContract != address(0), "Invalid contract address");
        versions[_version].contractAddress = _newContract;
        emit VersionUpdated(_version, _newContract);
    }
    
    /**
     * @dev Resolves a .fren name across all active versions
     * @param name The .fren name to resolve (e.g., "alice.fren")
     * @return owner The address that owns the name
     * @return tokenId The token ID associated with the name
     * @return version The version number where the name was found
     * 
     * This function searches through all active versions in order
     * and returns the first match found. This allows for seamless
     * upgrades while maintaining backward compatibility.
     */
    function resolveName(string memory name) external view returns (
        address owner,
        uint256 tokenId,
        uint8 version
    ) {
        // Check each version in order
        for (uint8 i = 1; i <= versionCount; i++) {
            if (!versions[i].isActive) continue;
            
            IUnifrens unifrensContract = IUnifrens(versions[i].contractAddress);
            (owner, tokenId) = unifrensContract.getNameWithId(name);
            if (owner != address(0)) {
                return (owner, tokenId, i);
            }
        }
        
        return (address(0), 0, 0);
    }
    
    /**
     * @dev Resolves an address to its associated .fren name
     * @return name The .fren name associated with the address
     * @return tokenId The token ID associated with the name
     * @return version The version number where the name was found
     * 
     * Note: This is a placeholder for future implementation.
     * Reverse resolution would require additional storage in the core contracts.
     */
    function resolveAddress(address /* addr */) external pure returns (
        string memory name,
        uint256 tokenId,
        uint8 version
    ) {
        // Implementation for reverse resolution
        // This would need to be implemented in the core contracts
        return ("", 0, 0);
    }
} 