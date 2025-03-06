// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnifrensDuster {
    // Core functions
    function updateGlobalRewards(uint256 fee, bool isNewMoney) external;
    function getPendingRewards(uint256 tokenId) external view returns (uint256);
    function redistribute(uint256 tokenId) external returns (uint256);
    function softWithdraw(uint256 tokenId) external returns (uint256);
    function hardWithdraw(uint256 tokenId) external;
    function getContractHealth() external view returns (uint256, uint256);
} 