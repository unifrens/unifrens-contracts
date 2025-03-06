// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnifrensCore {
    // Core functions
    function getPendingRewards(uint256 tokenId) external view returns (uint256);
    function updateGlobalRewards(uint256 fee, bool isNewMoney) external;
    function totalSupply() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    
    // Name management
    function unifrenNames(uint256 tokenId) external view returns (string memory);
    function _normalizedNameTaken(string memory name) external view returns (bool);
    function overrideName(uint256 tokenId, string memory newName) external;
    
    // Burn registry functions
    function setBurnAddress(address addr) external;
    function isBurnAddress(address addr) external view returns (bool);
    
    // Weight management
    function MIN_REDISTRIBUTE() external view returns (uint256);
    function MIN_SOFT_WITHDRAW() external view returns (uint256);
    function MAX_WEIGHT() external view returns (uint256);
    function BASE_WEIGHT_INCREASE() external view returns (uint256);
    function getPositionWeight(uint256 tokenId) external view returns (uint256);
    function getPositionWeightPoints(uint256 tokenId) external view returns (uint256);
    function updatePositionWeight(uint256 tokenId, uint256 newWeight, uint256 newWeightPoints) external;
} 