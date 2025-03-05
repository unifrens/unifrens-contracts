// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Unichain Frens
 * @dev A dynamic NFT ecosystem where Unifrens compete in a unique economic game.
 * 
 * Game Mechanics:
 * 1. Each Unifren earns rewards from new mints and redistributions
 * 2. Earlier positions earn more through square root decay (1/sqrt(position))
 * 3. Players have three core strategies:
 *    - "Stay & Play": Withdraw 25% rewards, redistribute 75%
 *    - "Power-Up": Convert rewards to weight (max 1000×)
 *    - "Cash Out": Withdraw 75%, redistribute 25%, retire position
 * 
 * Victory Condition:
 * When only one active Fren remains (all others have weight 0),
 * that player can claim victory and receive the entire contract balance
 * as the ultimate winner of the game.
 * 
 * V5 Update: Added victory claim mechanic and standardized error handling
 */
 
contract UnichainFrens is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ============ Error Messages ============
    
    /// @dev Standard error messages for common conditions
    string constant ERR_NOT_OWNER = "UNIFRENS: Not the owner";
    string constant ERR_MAX_WEIGHT = "UNIFRENS: Max weight reached";
    string constant ERR_NO_REWARDS = "UNIFRENS: No rewards available";
    string constant ERR_MIN_REWARDS = "UNIFRENS: Insufficient rewards for redistribution";
    string constant ERR_INSUFFICIENT_BALANCE = "UNIFRENS: Insufficient contract balance";
    string constant ERR_POSITION_INACTIVE = "UNIFRENS: Position is inactive";
    string constant ERR_POSITION_ALREADY_INACTIVE = "UNIFRENS: Position already inactive";
    string constant ERR_INVALID_WEIGHT = "UNIFRENS: Weight must be between 1 and 100";
    string constant ERR_INCORRECT_PRICE = "UNIFRENS: Incorrect mint price";
    string constant ERR_NAME_LENGTH = "UNIFRENS: Name length must be between 1 and 16";
    string constant ERR_NAME_FORMAT = "UNIFRENS: Name must be alphanumeric only";
    string constant ERR_NAME_TAKEN = "UNIFRENS: Name already taken";
    string constant ERR_WITHDRAWAL_TOO_SMALL = "UNIFRENS: Withdrawal amount too small";
    string constant ERR_NO_FUNDS = "UNIFRENS: No funds available";
    string constant ERR_NOT_LAST_ACTIVE = "UNIFRENS: Not the last active position";

    // ============ State Variables ============

    /// @dev Base cost to mint a new position (will be multiplied by weight)
    uint256 public mintPrice = 0.001 ether;

    /// @dev Maximum weight a position can have (1000)
    uint256 public constant MAX_WEIGHT = 1000;

    /// @dev Maximum weight that can be minted (100)
    uint256 public constant MAX_MINT_WEIGHT = 100;

    /// @dev Base amount of rewards needed for one weight point increase
    uint256 public constant BASE_WEIGHT_INCREASE = 0.001 ether;

    /// @dev Minimum rewards required for redistribution (0.0009 ETH)
    uint256 public constant MIN_REDISTRIBUTE_AMOUNT = 0.0009 ether;

    /// @dev Total rewards distributed in the system
    uint256 public totalRewards;

    /// @dev Global accumulator for rewards per weight point
    uint256 public rewardsPerWeightPoint;

    /// @dev Total weight points across all active positions
    uint256 public totalWeightPoints;

    /// @dev Mapping of position ID to its weight (1-100)
    mapping(uint256 => uint256) public positionWeights;

    /// @dev Mapping of position ID to its calculated weight points
    mapping(uint256 => uint256) public positionWeightPoints;

    /// @dev Mapping of position ID to the rewardsPerWeightPoint at last claim
    mapping(uint256 => uint256) public lastRewardsPerWeightPoint;

    /// @dev Mapping of position ID to claimed rewards
    mapping(uint256 => uint256) public claimedRewards;

    /// @dev Mapping of token ID to custom name (display version)
    mapping(uint256 => string) public unifrenNames;

    /// @dev Mapping of normalized (lowercase) name to whether it's taken
    mapping(string => bool) private _normalizedNameTaken;

    /// @dev Emergency pause flag
    bool public paused;

    // ============ Events ============
    
    /// @dev Emitted when a new position is minted with a weight
    event PositionMinted(uint256 indexed tokenId, uint256 weight, string name, address owner);
    
    /// @dev Emitted when rewards are claimed
    /// @param tokenId The ID of the position
    /// @param amount The amount of rewards claimed
    /// @param withdrawalType 0 for soft withdraw, 1 for hard withdraw, 2 for redistribute, 3 for victory
    event RewardsClaimed(uint256 indexed tokenId, uint256 amount, uint8 withdrawalType);

    /// @dev Emitted when a position's weight changes
    event WeightUpdated(uint256 indexed tokenId, uint256 oldWeight, uint256 newWeight);

    /// @dev Emitted when global rewards are updated
    event GlobalRewardsUpdated(uint256 fee, uint256 newRewardsPerWeightPoint, bool isNewMoney);

    /// @dev Emitted when emergency pause state changes
    event EmergencyPauseSet(bool paused);

    // ============ Modifiers ============

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    // ============ Constructor ============

    /**
     * @dev Initializes the contract and mints position #1 to the deployer with max weight
     */
    constructor() ERC721("Unichain Frens", "UNIFRENS") Ownable(msg.sender) {
        // Mint the first position to the deployer with weight 100 and name "Dev"
        _mintWithWeight(msg.sender, 1, 100, "Dev", _toLower("Dev"));
    }

    /**
     * @dev Converts a string to lowercase for name comparison
     * @param str The string to convert
     * @return The lowercase version of the string
     */
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        
        for (uint i = 0; i < bStr.length; i++) {
            // Convert uppercase to lowercase
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    /**
     * @dev Validates that a name contains only alphanumeric characters and is within length limits
     * Also checks that the normalized version is unique
     * @param name The name to validate
     * @return bool Whether the name is valid
     */
    function _isValidName(string memory name) internal view returns (bool) {
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

        // Check if normalized version of name is already taken
        string memory normalizedName = _toLower(name);
        if (_normalizedNameTaken[normalizedName]) return false;

        return true;
    }

    /**
     * @dev Mints a new position with specified weight and name, and distributes rewards
     * @param weight The weight for the position (1-100)
     * @param name The name for the Unifren (alphanumeric, 1-16 chars)
     */
    function mint(uint256 weight, string memory name) external payable nonReentrant whenNotPaused {
        require(weight >= 1 && weight <= MAX_MINT_WEIGHT, ERR_INVALID_WEIGHT);
        require(msg.value == mintPrice * weight, ERR_INCORRECT_PRICE);
        
        // Split name validation for better error messages
        bytes memory nameBytes = bytes(name);
        require(nameBytes.length > 0 && nameBytes.length <= 16, ERR_NAME_LENGTH);
        
        // Check characters
        for (uint i = 0; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            require(
                (char >= 0x30 && char <= 0x39) || // 0-9
                (char >= 0x41 && char <= 0x5A) || // A-Z
                (char >= 0x61 && char <= 0x7A),   // a-z
                ERR_NAME_FORMAT
            );
        }
        
        // Check uniqueness
        string memory normalizedName = _toLower(name);
        require(!_normalizedNameTaken[normalizedName], ERR_NAME_TAKEN);

        uint256 newPosition = totalSupply() + 1;
        _mintWithWeight(msg.sender, newPosition, weight, name, normalizedName);

        // Update global rewards state (this is new money)
        updateGlobalRewards(msg.value, true);
    }

    /**
     * @dev Internal function to mint a position with a weight and name
     * V4: Updated to use square root decay for more balanced distribution
     */
    function _mintWithWeight(
        address to, 
        uint256 tokenId, 
        uint256 weight, 
        string memory name,
        string memory normalizedName
    ) internal {
        _mint(to, tokenId);
        
        // Calculate and store position's weight points using square root decay
        uint256 positionWeight = 1e18 / sqrt(tokenId);
        uint256 weightPoints = positionWeight * weight;
        
        positionWeights[tokenId] = weight;
        positionWeightPoints[tokenId] = weightPoints;
        totalWeightPoints += weightPoints;
        
        // Store both display name and mark normalized name as taken
        unifrenNames[tokenId] = name;
        _normalizedNameTaken[normalizedName] = true;
        
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        emit PositionMinted(tokenId, weight, name, to);
    }

    /**
     * @dev Updates global rewards state
     * @param fee The amount to distribute as rewards
     * @param isNewMoney Whether this is new money (true) or redistribution (false)
     */
    function updateGlobalRewards(uint256 fee, bool isNewMoney) private {
        require(fee > 0, "Fee must be greater than 0");
        require(fee <= address(this).balance, "Fee exceeds contract balance");

        if (totalWeightPoints > 0) {
            // Use total weight points directly since position is already excluded
            uint256 adjustedTotalWeightPoints = totalWeightPoints;
            if (adjustedTotalWeightPoints == 0) return;
            
            // Calculate rewards per weight point based on the actual fee amount
            uint256 increase = (fee * 1e18) / adjustedTotalWeightPoints;
            
            // Add a safety cap to prevent excessive rewards
            uint256 maxIncrease = (address(this).balance * 1e18) / adjustedTotalWeightPoints;
            if (increase > maxIncrease) {
                increase = maxIncrease;
            }
            
            // Round down to prevent dust accumulation
            increase = (increase / 1e2) * 1e2;
            rewardsPerWeightPoint += increase;
        }
        
        // Only add to totalRewards if this is new money
        if (isNewMoney) {
            totalRewards += fee;
        }
        
        emit GlobalRewardsUpdated(fee, rewardsPerWeightPoint, isNewMoney);
    }

    /**
     * @dev Calculates pending rewards for a position
     * @param tokenId The position ID to calculate rewards for
     * @return The amount of pending rewards
     */
    function getPendingRewards(uint256 tokenId) public view returns (uint256) {
        if (!_exists(tokenId)) return 0;
        if (positionWeightPoints[tokenId] == 0) return 0;
        
        // Calculate rewards and ensure they don't exceed contract balance
        uint256 rewardsAccrued = (positionWeightPoints[tokenId] * 
            (rewardsPerWeightPoint - lastRewardsPerWeightPoint[tokenId])) / 1e18;
        
        // Round down last two decimals in wei
        rewardsAccrued = (rewardsAccrued / 1e2) * 1e2;
        
        // Cap rewards at the contract's actual balance
        uint256 maxRewards = address(this).balance;
        if (rewardsAccrued > maxRewards) {
            rewardsAccrued = maxRewards;
        }
        
        return rewardsAccrued;
    }

    /**
     * @dev Redistributes 75% of rewards back to the pool and increases position weight
     * The remaining 25% stays with the position (no ETH withdrawal)
     * Position weight is increased based on the reward amount
     * @param tokenId The position ID to redistribute rewards from
     * @return newWeight The new weight of the position after increase
     */
    function redistribute(uint256 tokenId) external nonReentrant whenNotPaused returns (uint256 newWeight) {
        require(ownerOf(tokenId) == msg.sender, ERR_NOT_OWNER);
        require(positionWeights[tokenId] < MAX_WEIGHT, ERR_MAX_WEIGHT);
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards > 0, ERR_NO_REWARDS);
        require(pendingRewards >= MIN_REDISTRIBUTE_AMOUNT, ERR_MIN_REWARDS);

        // Calculate redistribution amount (75%) and kept amount (25%)
        uint256 redistributeAmount = (pendingRewards * 75) / 100;
        uint256 keptAmount = pendingRewards - redistributeAmount;
        
        // Calculate and update weight increase based on total pending rewards
        uint256 weightIncrease = calculateWeightIncrease(pendingRewards);
        uint256 oldWeight = positionWeights[tokenId];
        newWeight = oldWeight + weightIncrease;
        if (newWeight > MAX_WEIGHT) {
            newWeight = MAX_WEIGHT;
        }

        // Update position's weight and weight points
        uint256 oldWeightPoints = positionWeightPoints[tokenId];
        uint256 newWeightPoints = (1e18 / (tokenId**2)) * newWeight;
        
        // Update position state
        positionWeights[tokenId] = newWeight;
        positionWeightPoints[tokenId] = newWeightPoints;
        
        // Temporarily reduce total weight points to exclude this position
        totalWeightPoints -= oldWeightPoints;
        
        // Update checkpoint to current global rewards
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        // Redistribute 75% back to the reward pool (not new money)
        if (redistributeAmount > 0 && totalSupply() > 1) {
            updateGlobalRewards(redistributeAmount, false);
        }
        
        // Add back the position's new weight points
        totalWeightPoints += newWeightPoints;
        
        // Calculate the rewards per point for the kept amount
        if (keptAmount > 0) {
            uint256 keptRewardsPerPoint = (keptAmount * 1e18) / newWeightPoints;
            // Subtract from the checkpoint to effectively keep 25% of rewards
            lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint - keptRewardsPerPoint;
        }
        
        emit RewardsClaimed(tokenId, 0, 2); // 2 for redistribute, amount is 0 since nothing is claimed
        emit WeightUpdated(tokenId, oldWeight, newWeight);
        return newWeight;
    }

    /**
     * @dev Calculates the weight increase based on pending rewards
     * Formula creates a logarithmic curve making it harder to reach max weight
     * @param pendingRewards The amount of pending rewards
     * @return The weight increase amount (always an integer)
     */
    function calculateWeightIncrease(uint256 pendingRewards) public pure returns (uint256) {
        // First divide by BASE_WEIGHT_INCREASE to get equivalent weight points
        // This maintains the same ratio as minting (0.001 ETH per weight point)
        uint256 baseIncrease = pendingRewards / BASE_WEIGHT_INCREASE;
        
        // Apply 50% curve but ensure we round up to nearest integer
        // Add 1e4-1 to round up division
        uint256 scaledIncrease = ((baseIncrease * 1e4) + (2e4 - 1)) / 2e4;
        
        // Ensure minimum increase of 1 if there are any rewards
        if (pendingRewards > 0 && scaledIncrease == 0) {
            return 1;
        }

        return scaledIncrease;
    }

    /**
     * @dev Calculates the square root of a number
     * @param x The number to calculate the square root of
     * @return y The square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    // ============ Reward Withdrawal Functions ============

    /**
     * @dev Allows position owner to withdraw 25% of accumulated rewards
     * The remaining 75% is redistributed to active positions
     * This is a "soft" withdrawal that maintains the position's weight for future earnings
     * @param tokenId The position ID to withdraw rewards from
     */
    function softWithdraw(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, ERR_NOT_OWNER);
        require(positionWeights[tokenId] > 0, ERR_POSITION_INACTIVE);
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards > 0, ERR_NO_REWARDS);

        // Calculate withdrawal and redistribution amounts
        uint256 withdrawAmount = (pendingRewards * 25) / 100;
        uint256 redistributeAmount = pendingRewards - withdrawAmount;

        require(address(this).balance >= withdrawAmount, ERR_INSUFFICIENT_BALANCE);
        require(withdrawAmount > 0, ERR_WITHDRAWAL_TOO_SMALL);

        // Update position's reward tracking
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        claimedRewards[tokenId] += pendingRewards;
        
        // Redistribute 75% back to the reward pool (not new money)
        if (redistributeAmount > 0 && totalSupply() > 1) {
            updateGlobalRewards(redistributeAmount, false);
        }
        
        emit RewardsClaimed(tokenId, withdrawAmount, 0);
        // Use call instead of transfer for better compatibility
        (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Sets position weight to 0 and withdraws 75% of accumulated rewards
     * The remaining 25% is redistributed to active positions
     * This is a "hard" withdrawal that permanently deactivates the position
     * @param tokenId The position ID to deactivate and withdraw from
     */
    function hardWithdraw(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, ERR_NOT_OWNER);
        require(positionWeights[tokenId] > 0, ERR_POSITION_ALREADY_INACTIVE);
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards > 0, ERR_NO_REWARDS);

        // Calculate withdrawal and redistribution amounts
        uint256 withdrawAmount = (pendingRewards * 75) / 100;
        uint256 redistributeAmount = pendingRewards - withdrawAmount;

        require(address(this).balance >= withdrawAmount, ERR_INSUFFICIENT_BALANCE);
        require(withdrawAmount > 0, ERR_WITHDRAWAL_TOO_SMALL);

        // Update total weight points before setting weight to 0
        totalWeightPoints -= positionWeightPoints[tokenId];
        positionWeightPoints[tokenId] = 0;
        positionWeights[tokenId] = 0;
        
        claimedRewards[tokenId] += pendingRewards;
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        // Redistribute 25% back to the reward pool (not new money)
        if (redistributeAmount > 0 && totalSupply() > 1) {
            updateGlobalRewards(redistributeAmount, false);
        }
        
        emit RewardsClaimed(tokenId, withdrawAmount, 1);
        // Use call instead of transfer for better compatibility
        (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
        require(success, "Transfer failed");
    }

    // ============ Admin Functions ============

    /// @dev Sets the emergency pause state
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit EmergencyPauseSet(_paused);
    }

    /**
     * @dev Allows contract owner to withdraw excess balance
     * This should only be used for funds not allocated as rewards
     */
    function withdrawContractBalance() external onlyOwner whenNotPaused {
        uint256 balance = address(this).balance;
        require(balance > 0, ERR_NO_FUNDS);
        // Use call instead of transfer for better compatibility
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
    }

    // ============ View Functions ============

    /**
     * @dev View function to calculate the mint price for a given weight
     * @param weight The desired weight (1-100)
     * @return The price in wei to mint with this weight
     */
    function getMintPrice(uint256 weight) public view returns (uint256) {
        require(weight >= 1 && weight <= MAX_MINT_WEIGHT, ERR_INVALID_WEIGHT);
        return mintPrice * weight;
    }

    /**
     * @dev Gets contract health metrics including dust buffer
     * @return contractBalance Current ETH balance
     * @return totalRewardsDistributed Total rewards in system
     * @return pendingRewards Total unclaimed rewards
     * @return dustBuffer Accumulated safety buffer from rounding
     * @return isSolvent Whether contract can cover all rewards
     */
    function getContractHealth() public view returns (
        uint256 contractBalance,
        uint256 totalRewardsDistributed,
        uint256 pendingRewards,
        uint256 dustBuffer,
        bool isSolvent
    ) {
        contractBalance = address(this).balance;
        totalRewardsDistributed = totalRewards;
        
        // Calculate total pending rewards (already rounded down)
        pendingRewards = 0;
        uint256 supply = totalSupply();
        for (uint256 i = 1; i <= supply; i++) {
            if (positionWeightPoints[i] > 0) {
                pendingRewards += getPendingRewards(i);
            }
        }
        
        // Calculate dust buffer (difference between actual balance and rounded rewards)
        dustBuffer = contractBalance > pendingRewards ? contractBalance - pendingRewards : 0;
        isSolvent = contractBalance >= pendingRewards;
    }

    /**
     * @dev Gets comprehensive reward information for a token
     * @param tokenId The position ID to get info for
     * @return weight The token's weight (1-100)
     * @return positionMultiplier The position's base multiplier (1/position^2)
     * @return pendingRewards Current unclaimed rewards
     * @return totalClaimed Total rewards claimed so far
     * @return isActive Whether the token still exists
     */
    function getTokenInfo(uint256 tokenId) public view returns (
        uint256 weight,
        uint256 positionMultiplier,
        uint256 pendingRewards,
        uint256 totalClaimed,
        bool isActive
    ) {
        isActive = _exists(tokenId);
        if (!isActive) return (0, 0, 0, claimedRewards[tokenId], false);

        weight = positionWeights[tokenId];
        positionMultiplier = 1e18 / (tokenId**2);
        pendingRewards = getPendingRewards(tokenId);
        totalClaimed = claimedRewards[tokenId];
    }

    // ============ NFT Metadata ============

    /**
     * @dev Generates the attributes portion of the metadata
     */
    function _generateAttributes(
        uint256 weight,
        uint256 positionMultiplier,
        uint256 pendingRewards,
        uint256 totalClaimed,
        bool isActive
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '{"trait_type": "Weight", "value": "',
                weight.toString(),
                '", "max_value": ',
                MAX_WEIGHT.toString(),
                '}, ',
                '{"trait_type": "Position Multiplier", "value": "',
                (positionMultiplier / 1e16).toString(),
                '%"}, ',
                '{"trait_type": "Pending Rewards", "value": "',
                (pendingRewards / 1e18).toString(),
                ' ETH"}, ',
                '{"trait_type": "Total Claimed", "value": "',
                (totalClaimed / 1e18).toString(),
                ' ETH"}, ',
                '{"trait_type": "Status", "value": "',
                isActive ? "Active" : "Inactive",
                '"}'
            )
        );
    }

    /**
     * @dev Returns the URI for a given token's metadata
     * @param tokenId The ID of the token to get the URI for
     * @return string The URI for the token's metadata
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert("ERC721: URI query for nonexistent token");
        
        (uint256 weight, uint256 positionMultiplier, uint256 pendingRewards, uint256 totalClaimed, bool isActive) = getTokenInfo(tokenId);
        
        string memory name = bytes(unifrenNames[tokenId]).length > 0 
            ? unifrenNames[tokenId] 
            : string(abi.encodePacked("Unifren #", tokenId.toString()));

        string memory attributes = _generateAttributes(
            weight,
            positionMultiplier,
            pendingRewards,
            totalClaimed,
            isActive
        );

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        name,
                        '", "description": "Unifrens live in every wallet. Unlock them and name them. They feed on ones and zeros leaving behind dust for their owner. Visit Unifrens.com to learn more.", ',
                        '"image": "',
                        string(abi.encodePacked("https://imgs.unifrens.com/", unifrenNames[tokenId])),
                        '", "attributes": [',
                        attributes,
                        ']}'
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    // Helper function to check if a token exists
    function _exists(uint256 tokenId) internal view returns (bool) {
        return ownerOf(tokenId) != address(0);
    }

    // ============ Receive Functions ============

    /// @dev Required to receive ETH
    receive() external payable {}
    
    /// @dev Fallback function in case receive() is not matched
    fallback() external payable {}

    // ============ Victory Claim Function ============

    /**
     * @dev Allows the owner of the last active position to claim all remaining funds
     * This is only possible when all other positions have weight 0
     * @param tokenId The position ID claiming victory
     */
    function claimVictory(uint256 tokenId) external nonReentrant whenNotPaused {
        require(ownerOf(tokenId) == msg.sender, ERR_NOT_OWNER);
        require(positionWeights[tokenId] > 0, ERR_POSITION_INACTIVE);
        
        // Check if this is the only active position
        uint256 activeCount = 0;
        uint256 supply = totalSupply();
        
        for (uint256 i = 1; i <= supply; i++) {
            if (positionWeights[i] > 0) {
                activeCount++;
                if (activeCount > 1) {
                    revert(ERR_NOT_LAST_ACTIVE);
                }
            }
        }
        
        // If we got here, this is the only active position
        uint256 balance = address(this).balance;
        require(balance > 0, ERR_NO_FUNDS);
        
        // Update state before transfer
        positionWeights[tokenId] = 0;
        positionWeightPoints[tokenId] = 0;
        totalWeightPoints = 0;
        
        // Transfer entire balance
        emit RewardsClaimed(tokenId, balance, 3); // 3 for victory claim
        // Use call instead of transfer for better compatibility
        (bool success, ) = payable(msg.sender).call{value: balance}("");
        require(success, "Transfer failed");
    }
}