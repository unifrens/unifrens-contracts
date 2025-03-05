// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//                 _ ____                    
//    __  ______  (_) __/_______  ____  _____
//   / / / / __ \/ / /_/ ___/ _ \/ __ \/ ___/
//  / /_/ / / / / / __/ /  /  __/ / / (__  ) 
//  \__,_/_/ /_/_/_/ /_/   \___/_/ /_/____/  
//   

/**
 * @title Unifrens Metadata Resolver Interface
 * @dev Interface for resolving Unifrens metadata and validation
 */
interface IUnifrensMetadataResolver {
    /**
     * @dev Validates a name according to custom rules
     * @param name The name to validate
     * @return bool Whether the name is valid
     */
    function isValidName(string memory name) external view returns (bool);

    /**
     * @dev Gets custom metadata for a token
     * @param tokenId The token ID to get metadata for
     * @return string The custom metadata JSON
     */
    function getMetadata(uint256 tokenId) external view returns (string memory);

    /**
     * @dev Gets the image URL for a token
     * @param tokenId The token ID to get image for
     * @return string The image URL
     */
    function getImage(uint256 tokenId) external view returns (string memory);
}

/**
 * @title Unifrens Metadata Resolver
 * @dev Implementation of the Unifrens metadata resolver interface
 */
contract UnifrensMetadataResolver is IUnifrensMetadataResolver {
    address public immutable unifrens;
    
    constructor(address _unifrens) {
        require(_unifrens != address(0), "Invalid Unifrens address");
        unifrens = _unifrens;
    }
    
    function isValidName(string memory name) external pure override returns (bool) {
        bytes memory nameBytes = bytes(name);
        if (nameBytes.length == 0 || nameBytes.length > 16) return false;
        
        for (uint i = 0; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            if (
                !(char >= 0x30 && char <= 0x39) && // 0-9
                !(char >= 0x41 && char <= 0x5A) && // A-Z
                !(char >= 0x61 && char <= 0x7A)    // a-z
            ) return false;
        }
        
        return true;
    }
    
    function getMetadata(uint256 /* tokenId */) external pure override returns (string memory) {
        return "";
    }
    
    function getImage(uint256 /* tokenId */) external pure override returns (string memory) {
        return "";
    }
} 