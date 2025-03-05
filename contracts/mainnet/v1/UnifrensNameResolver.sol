// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnifrens {
    function getName(string memory name) external view returns (address owner);
    function getNameWithId(string memory name) external view returns (address owner, uint256 tokenId);
}

contract UnifrensNameResolver {
    struct Version {
        address contractAddress;
        bool isActive;
    }
    
    mapping(uint8 => Version) public versions;
    uint8 public versionCount;
    
    event VersionAdded(uint8 indexed version, address contractAddress);
    event VersionRemoved(uint8 indexed version);
    event VersionUpdated(uint8 indexed version, address newAddress);
    
    constructor(address _v1Contract) {
        require(_v1Contract != address(0), "Invalid v1 address");
        versions[1] = Version(_v1Contract, true);
        versionCount = 1;
    }
    
    function addVersion(address _contract) external {
        require(_contract != address(0), "Invalid contract address");
        versionCount++;
        versions[versionCount] = Version(_contract, true);
        emit VersionAdded(versionCount, _contract);
    }
    
    function removeVersion(uint8 _version) external {
        require(_version > 0 && _version <= versionCount, "Invalid version");
        versions[_version].isActive = false;
        emit VersionRemoved(_version);
    }
    
    function updateVersion(uint8 _version, address _newContract) external {
        require(_version > 0 && _version <= versionCount, "Invalid version");
        require(_newContract != address(0), "Invalid contract address");
        versions[_version].contractAddress = _newContract;
        emit VersionUpdated(_version, _newContract);
    }
    
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