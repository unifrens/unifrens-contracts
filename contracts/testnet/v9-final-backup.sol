// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Unichain Frens
 * @dev A dynamic NFT ecosystem where Unifrens collect and distribute dust over time.
 * Each Unifren earns rewards from new mints, with earlier frens accumulating more
 * through a quadratic distribution formula. Mint, name, and watch your Unifren thrive!
 */
 
contract Unifrens is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ============ State Variables ============

    /// @dev Base cost to mint a new position (will be multiplied by weight)
    uint256 public mintPrice = 0.001 ether;

    /// @dev Maximum weight a position can have (1000)
    uint256 public constant MAX_WEIGHT = 1000;

    /// @dev Maximum weight that can be minted (100)
    uint256 public constant MAX_MINT_WEIGHT = 100;

    /// @dev Base amount of rewards needed for one weight point increase
    uint256 public constant BASE_WEIGHT_INCREASE = 0.001 ether;

    /// @dev Minimum rewards required for soft withdraw (0.0001 ETH)
    uint256 public constant MIN_SOFT_WITHDRAW = 0.0001 ether;

    /// @dev Minimum rewards required for redistribute (0.00001 ETH)
    uint256 public constant MIN_REDISTRIBUTE = 0.00001 ether;

    /// @dev Total rewards distributed in the system
    uint256 public totalRewards;

    /// @dev Whether minting is paused
    bool public mintingPaused;

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

    // ============ Events ============
    
    /// @dev Emitted when a new position is minted with a weight
    event PositionMinted(uint256 indexed tokenId, uint256 weight, string name, address owner);
    
    /// @dev Emitted when rewards are claimed
    /// @param tokenId The ID of the position
    /// @param amount The amount of rewards claimed
    /// @param withdrawalType 0 for soft withdraw, 1 for hard withdraw
    event RewardsClaimed(uint256 indexed tokenId, uint256 amount, uint8 withdrawalType);

    /// @dev Emitted when a position is burned
    event PositionBurned(uint256 indexed tokenId);

    /// @dev Emitted when victory is claimed
    event VictoryClaimed(uint256 indexed tokenId, uint256 amount);

    /// @dev Emitted when a position's weight changes
    /// @param tokenId The ID of the position
    /// @param oldWeight Previous weight of the position
    /// @param newWeight New weight of the position
    /// @param reason 0 for soft withdraw, 1 for redistribute
    event WeightUpdated(uint256 indexed tokenId, uint256 oldWeight, uint256 newWeight, uint8 reason);

    /// @dev Emitted when minting is paused or unpaused
    event MintingPaused(bool paused);

    // ============ Constructor ============

    /**
     * @dev Initializes the contract and mints position #1 to the deployer with max weight
     */
    constructor() ERC721("Unichain Frens", "UNIFRENS") Ownable(msg.sender) {
        // Mint the first position to the deployer with weight 1 and name "Dev"
        _mintWithWeight(msg.sender, 1, 1, "Dev", _toLower("Dev"));
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
    function mint(uint256 weight, string memory name) external payable nonReentrant {
        require(!mintingPaused, "Minting is paused");
        require(weight >= 1 && weight <= MAX_MINT_WEIGHT, "Weight must be between 1 and 100");
        require(msg.value == mintPrice * weight, "Incorrect mint price");
        
        // Split name validation for better error messages
        bytes memory nameBytes = bytes(name);
        require(nameBytes.length > 0 && nameBytes.length <= 16, "Name length must be between 1 and 16");
        
        // Check characters
        for (uint i = 0; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            require(
                (char >= 0x30 && char <= 0x39) || // 0-9
                (char >= 0x41 && char <= 0x5A) || // A-Z
                (char >= 0x61 && char <= 0x7A),   // a-z
                "Name must be alphanumeric only"
            );
        }
        
        // Check uniqueness
        string memory normalizedName = _toLower(name);
        require(!_normalizedNameTaken[normalizedName], "Name already taken");

        uint256 newPosition = totalSupply() + 1;
        _mintWithWeight(msg.sender, newPosition, weight, name, normalizedName);

        // Update global rewards state (this is new money)
        updateGlobalRewards(msg.value, true);
    }

    /**
     * @dev Internal function to mint a position with a weight and name
     */
    function _mintWithWeight(
        address to, 
        uint256 tokenId, 
        uint256 weight, 
        string memory name,
        string memory normalizedName
    ) internal {
        _mint(to, tokenId);
        
        // Calculate and store position's weight points
        uint256 positionWeight = 1e18 / (tokenId**2);
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
    }

    /**
     * @dev Calculates pending rewards for a position
     * @param tokenId The position ID to calculate rewards for
     * @return The amount of pending rewards
     */
    function getPendingRewards(uint256 tokenId) public view returns (uint256) {
        // Check if token exists and hasn't been burned
        if (!_exists(tokenId) || ownerOf(tokenId) == address(0)) return 0;
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
    function redistribute(uint256 tokenId) external nonReentrant returns (uint256 newWeight) {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(positionWeights[tokenId] < MAX_WEIGHT, "Max weight reached");
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards >= MIN_REDISTRIBUTE, "Insufficient rewards to redistribute");

        // Calculate redistribution amount (75%) and kept amount (25%)
        uint256 redistributeAmount = (pendingRewards * 75) / 100;
        uint256 keptAmount = pendingRewards - redistributeAmount;
        
        // Calculate and update weight increase based on total pending rewards
        uint256 weightIncrease = calculateWeightIncrease(pendingRewards, positionWeights[tokenId]);
        if (weightIncrease == 0) weightIncrease = 1; // Ensure minimum increase of 1
        
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
        
        // Emit events
        emit WeightUpdated(tokenId, oldWeight, newWeight, 1); // 1 for redistribute
        emit RewardsClaimed(tokenId, 0, 2); // 2 for redistribute, amount is 0 since nothing is claimed
        
        return newWeight;
    }

    /**
     * @dev Calculates the weight increase based on pending rewards
     * Formula creates a logarithmic curve making it harder to reach max weight
     * Higher weights result in smaller increases
     * @param pendingRewards The amount of pending rewards
     * @param currentWeight The current weight of the position
     * @return The weight increase amount
     */
    function calculateWeightIncrease(uint256 pendingRewards, uint256 currentWeight) public pure returns (uint256) {
        // We use a logarithmic formula to make it increasingly harder to gain weight
        // sqrt(pendingRewards / BASE_WEIGHT_INCREASE)
        uint256 ratio = (pendingRewards * 1e18) / BASE_WEIGHT_INCREASE;
        uint256 increase = sqrt(ratio) / 1e9; // Divide by 1e9 to get a reasonable increase

        // Ensure minimum increase of 1 if there are any rewards
        if (pendingRewards > 0 && increase == 0) {
            return 1;
        }

        // Apply weight-based reduction factor
        // As weight increases, the increase amount is reduced
        // At weight 1000, increases are reduced by 90%
        // At weight 500, increases are reduced by 45%
        // At weight 100, increases are reduced by 9%
        uint256 reductionFactor = (currentWeight * 90) / 1000; // 90% max reduction at 1000 weight
        increase = (increase * (100 - reductionFactor)) / 100;

        // Ensure minimum increase of 1 if there are any rewards
        if (pendingRewards > 0 && increase == 0) {
            return 1;
        }

        return increase;
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
     * Additionally increases weight by half the amount that redistribute would provide
     * @param tokenId The position ID to withdraw rewards from
     * @return newWeight The new weight of the position after increase
     */
    function softWithdraw(uint256 tokenId) external nonReentrant returns (uint256 newWeight) {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards >= MIN_SOFT_WITHDRAW, "Position not matured");

        // Calculate withdrawal and redistribution amounts
        uint256 softWithdrawAmount = (pendingRewards * 25) / 100; // 25% to withdrawer
        uint256 redistributeAmount = pendingRewards - softWithdrawAmount; // 75% to redistribute

        // Add solvency check
        require(address(this).balance >= softWithdrawAmount, "Insufficient contract balance");

        uint256 oldWeight = positionWeights[tokenId];
        newWeight = oldWeight;

        // Only increase weight if not at MAX_WEIGHT
        if (oldWeight < MAX_WEIGHT) {
            // Calculate and update weight increase (half of what redistribute would give)
            uint256 weightIncrease = calculateWeightIncrease(pendingRewards, oldWeight) / 2;
            if (weightIncrease == 0) weightIncrease = 1; // Ensure minimum increase of 1
            
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
            
            // Add back the position's new weight points
            totalWeightPoints += newWeightPoints;

            emit WeightUpdated(tokenId, oldWeight, newWeight, 0); // 0 for soft withdraw
        }
        
        // Update checkpoint to current global rewards
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        // Redistribute 75% back to the reward pool (not new money)
        if (redistributeAmount > 0 && totalSupply() > 1) {
            updateGlobalRewards(redistributeAmount, false);
        }

        emit RewardsClaimed(tokenId, softWithdrawAmount, 0);
        
        payable(msg.sender).transfer(softWithdrawAmount);
        return newWeight;
    }

    /**
     * @dev Sets position weight to 0 and withdraws 75% of accumulated rewards
     * The remaining 25% is redistributed to active positions
     * This is a "hard" withdrawal that permanently deactivates the position
     * @param tokenId The position ID to deactivate and withdraw from
     */
    function hardWithdraw(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards > 0, "No rewards available");

        // Calculate withdrawal and redistribution amounts
        uint256 hardWithdrawAmount = (pendingRewards * 75) / 100;
        uint256 redistributeAmount = pendingRewards - hardWithdrawAmount;

        // Add solvency check
        require(address(this).balance >= hardWithdrawAmount, "Insufficient contract balance");

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
        
        emit RewardsClaimed(tokenId, hardWithdrawAmount, 1);
        payable(msg.sender).transfer(hardWithdrawAmount);
    }

    // ============ Admin Functions ============

    /**
     * @dev Allows contract owner to recover all ERC20 tokens of a specific type
     * @param token The address of the ERC20 token to recover
     */
    function recoverAllERC20(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to recover");
        
        bool success = IERC20(token).transfer(owner(), balance);
        require(success, "Transfer failed");
    }

    /**
     * @dev Allows contract owner to recover ERC20 tokens that might be accidentally sent to the contract
     * @param token The address of the ERC20 token to recover
     * @param amount The amount of tokens to recover
     */
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer the tokens to the owner
        bool success = IERC20(token).transfer(owner(), amount);
        require(success, "Transfer failed");
    }

    /**
     * @dev Allows contract owner to withdraw a specific amount from the contract
     * @param amount The amount in wei to withdraw
     */
    function withdrawAmount(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient contract balance");
        payable(owner()).transfer(amount);
    }

    /**
     * @dev Allows contract owner to set a new mint price
     * @param newPrice The new price in wei for base weight minting
     */
    function setMintPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        mintPrice = newPrice;
    }

    /**
     * @dev Allows contract owner to withdraw excess balance
     * This should only be used for funds not allocated as rewards
     */
    function withdrawContractBalance() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds available");
        payable(owner()).transfer(balance);
    }

    /**
     * @dev Allows contract owner to pause minting
     */
    function pauseMinting() external onlyOwner {
        require(!mintingPaused, "Minting already paused");
        mintingPaused = true;
        emit MintingPaused(true);
    }

    /**
     * @dev Allows contract owner to unpause minting
     */
    function unpauseMinting() external onlyOwner {
        require(mintingPaused, "Minting not paused");
        mintingPaused = false;
        emit MintingPaused(false);
    }

    // ============ View Functions ============

    /**
     * @dev Checks if a position can claim victory by verifying it's the last active position
     * @param tokenId The position ID to check for victory eligibility
     * @return canClaim Whether victory can be claimed
     * @return activePositions Number of positions with non-zero weight
     * @return totalPositions Total number of positions in existence
     */
    function canClaimVictory(uint256 tokenId) public view returns (
        bool canClaim,
        uint256 activePositions,
        uint256 totalPositions
    ) {
        require(_exists(tokenId), "Token does not exist");
        
        // Position must have non-zero weight to claim
        if (positionWeights[tokenId] == 0) {
            return (false, 0, totalSupply());
        }
        
        // Count active positions
        activePositions = 0;
        totalPositions = totalSupply();
        for (uint256 i = 1; i <= totalPositions; i++) {
            if (positionWeights[i] > 0) {
                activePositions++;
                // If we find more than one active position, victory cannot be claimed
                if (activePositions > 1) {
                    return (false, activePositions, totalPositions);
                }
            }
        }
        
        // Victory can be claimed if this is the only active position
        canClaim = (activePositions == 1 && positionWeights[tokenId] > 0);
        return (canClaim, activePositions, totalPositions);
    }

    /**
     * @dev View function to calculate the mint price for a given weight
     * @param weight The desired weight (1-100)
     * @return The price in wei to mint with this weight
     */
    function getMintPrice(uint256 weight) public view returns (uint256) {
        require(weight >= 1 && weight <= MAX_MINT_WEIGHT, "Weight must be between 1 and 100");
        return mintPrice * weight;
    }

    /**
     * @dev Gets contract health metrics
     * @return totalRewardsDistributed Total rewards in system
     * @return pendingRewards Total unclaimed rewards
     */
    function getContractHealth() public view returns (
        uint256 totalRewardsDistributed,
        uint256 pendingRewards
    ) {
        totalRewardsDistributed = totalRewards;
        
        // Calculate total pending rewards (already rounded down)
        pendingRewards = 0;
        uint256 supply = totalSupply();
        for (uint256 i = 1; i <= supply; i++) {
            if (positionWeightPoints[i] > 0) {
                pendingRewards += getPendingRewards(i);
            }
        }
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

    /**
     * @dev Gets the owner address of a token by its name
     * @param name The name to look up
     * @return owner The owner address of the token with this name
     */
    function getName(string memory name) public view returns (address owner) {
        // Convert name to lowercase for comparison
        string memory normalizedName = _toLower(name);
        
        // Check if name exists
        if (!_normalizedNameTaken[normalizedName]) {
            return address(0);
        }
        
        // Search through all tokens to find matching name
        uint256 supply = totalSupply();
        for (uint256 i = 1; i <= supply; i++) {
            if (keccak256(bytes(_toLower(unifrenNames[i]))) == keccak256(bytes(normalizedName))) {
                return ownerOf(i);
            }
        }
        
        return address(0);
    }

    /**
     * @dev Gets the owner address and token ID of a token by its name
     * @param name The name to look up
     * @return owner The owner address of the token with this name
     * @return tokenId The token ID with this name
     */
    function getNameWithId(string memory name) public view returns (address owner, uint256 tokenId) {
        // Convert name to lowercase for comparison
        string memory normalizedName = _toLower(name);
        
        // Check if name exists
        if (!_normalizedNameTaken[normalizedName]) {
            return (address(0), 0);
        }
        
        // Search through all tokens to find matching name
        uint256 supply = totalSupply();
        for (uint256 i = 1; i <= supply; i++) {
            if (keccak256(bytes(_toLower(unifrenNames[i]))) == keccak256(bytes(normalizedName))) {
                return (ownerOf(i), i);
            }
        }
        
        return (address(0), 0);
    }

    // ============ NFT Metadata ============

    /**
     * @dev Calculates the rarity tier based on weight
     */
    function _getRarityTier(uint256 weight) internal pure returns (string memory) {
        if (weight >= 101) return "Legendary";
        if (weight >= 75) return "Epic";
        if (weight >= 50) return "Rare";
        if (weight >= 25) return "Uncommon";
        return "Common";
    }

    /**
     * @dev Generates all attributes for the token metadata
     */
    function _generateAttributes(
        uint256 weight,
        uint256 positionMultiplier,
        bool isActive
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '[{"display_type": "number", "trait_type": "Weight", "value": ',
                weight.toString(),
                ', "max_value": ',
                MAX_WEIGHT.toString(),
                '}, {"display_type": "boost_percentage", "trait_type": "Position Multiplier", "value": ',
                (positionMultiplier / 1e16).toString(),
                '}, {"trait_type": "Rarity Tier", "value": "',
                _getRarityTier(weight),
                '"}, {"trait_type": "Status", "value": "',
                isActive ? "Active" : "Retired",
                '"}]'
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
        
        (uint256 weight, uint256 positionMultiplier, , , bool isActive) = getTokenInfo(tokenId);
        
        string memory name = bytes(unifrenNames[tokenId]).length > 0 
            ? unifrenNames[tokenId] 
            : string(abi.encodePacked("Unifren #", tokenId.toString()));

        string memory attributes = _generateAttributes(weight, positionMultiplier, isActive);

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        name,
                        '", "description": "Unifrens live in every wallet. Unlock them and name them. They feed on ones and zeros leaving behind dust for their owner. Visit Unifrens.com to learn more.", ',
                        '"image": "',
                        string(abi.encodePacked("https://imgs.unifrens.com/", unifrenNames[tokenId])),
                        '", "attributes": ',
                        attributes,
                        '}'
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

    /**
     * @dev Hook that is called before any token transfer. This includes minting.
     */
    function _beforeTokenTransfer(
        address /* from */,
        address /* to */,
        uint256 /* firstTokenId */,
        uint256 /* batchSize */
    ) internal virtual {
        // No special handling needed anymore since burn is handled separately
    }

    /**
     * @dev "Burns" a position by transferring it to the burn address and setting its weight to 0
     * The token still exists but can no longer earn rewards
     * @param tokenId The ID of the position to burn
     */
    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender || msg.sender == owner(), "Not authorized");
        
        // Update total weight points before setting weight to 0
        uint256 oldWeightPoints = positionWeightPoints[tokenId];
        if (oldWeightPoints > 0) {
            totalWeightPoints -= oldWeightPoints;
            positionWeightPoints[tokenId] = 0;
            positionWeights[tokenId] = 0;
        }
        
        // Transfer to burn address instead of burning
        _transfer(msg.sender, address(1), tokenId);
        
        emit PositionBurned(tokenId);
    }

    /**
     * @dev Checks if a position is the last active position
     * @param tokenId The position ID to check
     * @return bool Whether this position is victorious
     */
    function _checkVictoryCondition(uint256 tokenId) internal view returns (bool) {
        if (positionWeights[tokenId] == 0) return false;
        
        uint256 supply = totalSupply();
        for (uint256 i = 1; i <= supply; i++) {
            // Skip the position we're checking
            if (i == tokenId) continue;
            // If any other position has weight, victory condition not met
            if (positionWeights[i] > 0) return false;
        }
        return true;
    }

    /**
     * @dev Claims victory rewards when all other positions have weight 0
     * This allows the last active position to claim the entire contract balance
     * @param tokenId The position ID to claim victory for
     */
    function claimVictory(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(_checkVictoryCondition(tokenId), "Victory condition not met");
        
        // Get contract balance
        uint256 balance = address(this).balance;
        require(balance > 0, "No rewards to claim");
        
        // Zero out the position's state
        uint256 oldWeightPoints = positionWeightPoints[tokenId];
        if (oldWeightPoints > 0) {
            totalWeightPoints -= oldWeightPoints;
            positionWeightPoints[tokenId] = 0;
            positionWeights[tokenId] = 0;
        }
        
        // Update claimed rewards
        claimedRewards[tokenId] += balance;
        
        // Emit victory event
        emit VictoryClaimed(tokenId, balance);
        
        // Transfer entire balance to final player
        payable(msg.sender).transfer(balance);
    }
}