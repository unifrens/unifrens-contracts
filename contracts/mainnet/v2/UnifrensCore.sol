// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//                 _ ____                    
//    __  ______  (_) __/_______  ____  _____
//   / / / / __ \/ / /_/ ___/ _ \/ __ \/ ___/
//  / /_/ / / / / / __/ /  /  __/ / / (__  ) 
//  \__,_/_/ /_/_/_/ /_/   \___/_/ /_/____/  
//   

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./UnifrensMetadataResolver.sol";
import "./UnifrensFeeManager.sol";
import "./UnifrensBurnRegistry.sol";
import "./IUnifrensDuster.sol";

/**
 * @title Unifrens
 * @dev A web3 username system where each Unifren is a unique, resolvable identity.
 * Names are globally unique and can be resolved by any protocol or wallet.
 * Unifrens accumulate dust over time.
 */
 
contract Unifrens is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ============ State Variables ============

    /// @dev Address of the resolver contract
    address public resolver;

    /// @dev Address of the duster contract
    IUnifrensDuster public duster;

    /// @dev Address of the fee manager contract
    address public feeManager;

    /// @dev Address of the burn registry contract
    address public burnRegistry;

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

    /// @dev Mapping of position ID to its weight (initial: 1-100, max: 1000)
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
    
    /// @dev Emitted when dust is claimed
    /// @param tokenId The ID of the position
    /// @param amount The amount of dust claimed
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

    /// @dev Emitted when the resolver is updated
    event ResolverUpdated(address indexed oldResolver, address indexed newResolver);

    /// @dev Emitted when the duster is updated
    event DusterUpdated(address indexed oldDuster, address indexed newDuster);

    /// @dev Emitted when the fee manager is updated
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);

    /// @dev Emitted when the burn registry is updated
    event BurnRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // ============ Modifiers ============

    modifier onlyDuster() {
        require(msg.sender == address(duster), "Only duster contract can call");
        _;
    }

    modifier onlyFeeManager() {
        require(msg.sender == feeManager, "Only fee manager contract can call");
        _;
    }

    modifier onlyBurnRegistry() {
        require(msg.sender == burnRegistry, "Only burn registry contract can call");
        _;
    }

    // ============ Constructor ============

    /**
     * @dev Initializes the contract and mints position #1 to the deployer
     */
    constructor() ERC721("Unifrens", "UNIFRENS") Ownable(msg.sender) {
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
     * @dev Sets a new resolver contract
     * @param _resolver The address of the new resolver
     */
    function setResolver(address _resolver) external onlyOwner {
        require(_resolver != address(0), "Invalid resolver address");
        address oldResolver = resolver;
        resolver = _resolver;
        emit ResolverUpdated(oldResolver, _resolver);
    }

    /**
     * @dev Sets a new duster contract
     * @param _duster The address of the new duster
     */
    function setDuster(address _duster) external onlyOwner {
        require(_duster != address(0), "Invalid duster address");
        address oldDuster = address(duster);
        duster = IUnifrensDuster(_duster);
        emit DusterUpdated(oldDuster, _duster);
    }

    /**
     * @dev Sets a new fee manager contract
     * @param _feeManager The address of the new fee manager
     */
    function setFeeManager(address _feeManager) external onlyOwner {
        require(_feeManager != address(0), "Invalid fee manager address");
        address oldFeeManager = feeManager;
        feeManager = _feeManager;
        emit FeeManagerUpdated(oldFeeManager, _feeManager);
    }

    /**
     * @dev Sets a new burn registry contract
     * @param _burnRegistry The address of the new burn registry
     */
    function setBurnRegistry(address _burnRegistry) external onlyOwner {
        require(_burnRegistry != address(0), "Invalid burn registry address");
        address oldRegistry = burnRegistry;
        burnRegistry = _burnRegistry;
        emit BurnRegistryUpdated(oldRegistry, _burnRegistry);
    }

    /**
     * @dev Validates that a name contains only alphanumeric characters and is within length limits
     * Also checks that the normalized version is unique
     * @param name The name to validate
     * @return bool Whether the name is valid
     */
    function _isValidName(string memory name) internal view returns (bool) {
        // If resolver is set, use it for validation
        if (resolver != address(0)) {
            return IUnifrensMetadataResolver(resolver).isValidName(name);
        }
        
        // Fallback to original validation
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
        
        uint256 basePrice = mintPrice * weight;
        uint256 totalPrice = basePrice;
        
        // Calculate additional fee if fee manager is set
        if (feeManager != address(0)) {
            uint256 additionalFee = (basePrice * IUnifrensFeeManager(feeManager).feePercentage()) / 10000;
            totalPrice += additionalFee;
        }
        
        require(msg.value == totalPrice, "Incorrect mint price");
        
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

        // Handle additional fee if fee manager is set
        if (feeManager != address(0)) {
            uint256 additionalFee = (basePrice * IUnifrensFeeManager(feeManager).feePercentage()) / 10000;
            if (additionalFee > 0) {
                IUnifrensFeeManager(feeManager).handleMintFee(newPosition, weight, additionalFee);
            }
        }

        // Update global rewards state (this is new money)
        updateGlobalRewards(basePrice, true);
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
        if (address(duster) != address(0)) {
            IUnifrensDuster(duster).updateGlobalRewards(fee, isNewMoney);
        } else {
            if (totalWeightPoints > 0) {
                uint256 adjustedTotalWeightPoints = totalWeightPoints;
                if (adjustedTotalWeightPoints == 0) return;
                
                uint256 increase = (fee / adjustedTotalWeightPoints) * 1e18;
                uint256 remainder = (fee % adjustedTotalWeightPoints) * 1e18 / adjustedTotalWeightPoints;
                increase += remainder;
                
                uint256 maxPossibleIncrease = type(uint256).max - rewardsPerWeightPoint;
                if (increase > maxPossibleIncrease) {
                    increase = maxPossibleIncrease;
                }
                
                rewardsPerWeightPoint += increase;
            }
            
            if (isNewMoney) {
                totalRewards += fee;
            }
        }
    }

    /**
     * @dev Calculates pending rewards for a position
     * @param tokenId The position ID to calculate rewards for
     * @return The amount of pending rewards
     */
    function getPendingRewards(uint256 tokenId) public view returns (uint256) {
        if (!_exists(tokenId) || ownerOf(tokenId) == address(0)) return 0;
        if (positionWeightPoints[tokenId] == 0) return 0;
        
        if (address(duster) != address(0)) {
            return IUnifrensDuster(duster).getPendingRewards(tokenId);
        }
        
        uint256 rewardsAccrued = positionWeightPoints[tokenId] * 
            (rewardsPerWeightPoint - lastRewardsPerWeightPoint[tokenId]);
        
        rewardsAccrued = rewardsAccrued / 1e18;
        rewardsAccrued = (rewardsAccrued / 1e2) * 1e2;
        
        uint256 maxRewards = address(this).balance;
        if (rewardsAccrued > maxRewards) {
            rewardsAccrued = maxRewards;
        }
        
        return rewardsAccrued;
    }

    /**
     * @dev Redistributes 75% of dust back to the pool and increases position weight
     * The remaining 25% stays with the position (no withdrawal)
     * Position weight is increased based on the reward amount
     * @param tokenId The position ID to redistribute rewards from
     * @return newWeight The new weight of the position after increase
     */
    function redistribute(uint256 tokenId) external nonReentrant returns (uint256 newWeight) {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(positionWeights[tokenId] < MAX_WEIGHT, "Max weight reached");
        
        if (address(duster) != address(0)) {
            return IUnifrensDuster(duster).redistribute(tokenId);
        }
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards >= MIN_REDISTRIBUTE, "Insufficient dust to redistribute");

        uint256 redistributeAmount = (pendingRewards * 75) / 100;
        uint256 keptAmount = pendingRewards - redistributeAmount;
        
        uint256 weightIncrease = calculateWeightIncrease(pendingRewards, positionWeights[tokenId]);
        if (weightIncrease == 0) weightIncrease = 1;
        
        uint256 oldWeight = positionWeights[tokenId];
        newWeight = oldWeight + weightIncrease;
        if (newWeight > MAX_WEIGHT) {
            newWeight = MAX_WEIGHT;
        }

        uint256 oldWeightPoints = positionWeightPoints[tokenId];
        uint256 newWeightPoints = (1e18 / (tokenId**2)) * newWeight;
        
        positionWeights[tokenId] = newWeight;
        positionWeightPoints[tokenId] = newWeightPoints;
        
        totalWeightPoints -= oldWeightPoints;
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        if (redistributeAmount > 0 && totalSupply() > 1) {
            updateGlobalRewards(redistributeAmount, false);
        }
        
        totalWeightPoints += newWeightPoints;
        
        if (keptAmount > 0) {
            uint256 keptRewardsPerPoint = (keptAmount * 1e18) / newWeightPoints;
            lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint - keptRewardsPerPoint;
        }
        
        emit WeightUpdated(tokenId, oldWeight, newWeight, 1);
        emit RewardsClaimed(tokenId, 0, 2);
        
        return newWeight;
    }

    /**
     * @dev Calculates the weight increase based on pending rewards
     * Formula creates a logarithmic curve making it harder to reach max weight
     * Higher weights result in smaller increases
     * @param pendingRewards The amount of pending dust
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

    // ============ Dust Withdrawal Functions ============

    /**
     * @dev Allows position owner to withdraw 25% of accumulated dust
     * The remaining 75% is redistributed to active positions
     * This is a "soft" withdrawal that maintains activity
     * Additionally increases weight appropriatly
     * @param tokenId The position ID to withdraw the dust
     * @return newWeight The new weight of the position after increase
     */
    function softWithdraw(uint256 tokenId) external nonReentrant returns (uint256 newWeight) {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        
        if (address(duster) != address(0)) {
            return IUnifrensDuster(duster).softWithdraw(tokenId);
        }
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards >= MIN_SOFT_WITHDRAW, "Position not matured");

        uint256 softWithdrawAmount = (pendingRewards * 25) / 100;
        uint256 redistributeAmount = pendingRewards - softWithdrawAmount;

        require(address(this).balance >= softWithdrawAmount, "Insufficient contract balance");

        uint256 oldWeight = positionWeights[tokenId];
        newWeight = oldWeight;

        if (oldWeight < MAX_WEIGHT) {
            uint256 weightIncrease = calculateWeightIncrease(pendingRewards, oldWeight) / 2;
            if (weightIncrease == 0) weightIncrease = 1;
            
            newWeight = oldWeight + weightIncrease;
            if (newWeight > MAX_WEIGHT) {
                newWeight = MAX_WEIGHT;
            }

            uint256 oldWeightPoints = positionWeightPoints[tokenId];
            uint256 newWeightPoints = (1e18 / (tokenId**2)) * newWeight;
            
            positionWeights[tokenId] = newWeight;
            positionWeightPoints[tokenId] = newWeightPoints;
            
            totalWeightPoints -= oldWeightPoints;
            lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
            
            if (redistributeAmount > 0 && totalSupply() > 1) {
                updateGlobalRewards(redistributeAmount, false);
            }
            
            totalWeightPoints += newWeightPoints;

            emit WeightUpdated(tokenId, oldWeight, newWeight, 0);
        }
        
        claimedRewards[tokenId] += softWithdrawAmount;
        emit RewardsClaimed(tokenId, softWithdrawAmount, 0);
        
        payable(msg.sender).transfer(softWithdrawAmount);
        return newWeight;
    }

    /**
     * @dev Sets position weight to 0 and withdraws 75% of accumulated rewards
     * The remaining 25% is redistributed to active positions
     * This is a "hard" withdrawal that permanently halts dust accumulation forever
     * @param tokenId The position ID to deactivate and withdraw from
     */
    function hardWithdraw(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        
        if (address(duster) != address(0)) {
            IUnifrensDuster(duster).hardWithdraw(tokenId);
            return;
        }
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards > 0, "No rewards available");

        uint256 hardWithdrawAmount = (pendingRewards * 75) / 100;
        uint256 redistributeAmount = pendingRewards - hardWithdrawAmount;

        require(address(this).balance >= hardWithdrawAmount, "Insufficient contract balance");

        totalWeightPoints -= positionWeightPoints[tokenId];
        positionWeightPoints[tokenId] = 0;
        positionWeights[tokenId] = 0;
        
        claimedRewards[tokenId] += pendingRewards;
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
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
     * Required for contract upgrades, migrations or emergencies
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
     * @return totalRewardsDistributed Total dust in system
     * @return pendingRewards Total unclaimed dust
     */
    function getContractHealth() public view returns (
        uint256 totalRewardsDistributed,
        uint256 pendingRewards
    ) {
        if (address(duster) != address(0)) {
            return IUnifrensDuster(duster).getContractHealth();
        }
        
        totalRewardsDistributed = totalRewards;
        
        // Calculate total pending rewards
        pendingRewards = 0;
        uint256 supply = totalSupply();
        uint256 contractBalance = address(this).balance;
        
        for (uint256 i = 1; i <= supply; i++) {
            if (positionWeightPoints[i] > 0) {
                uint256 positionRewards = getPendingRewards(i);
                // Ensure we don't exceed contract balance
                if (pendingRewards + positionRewards > contractBalance) {
                    pendingRewards = contractBalance;
                    break;
                }
                pendingRewards += positionRewards;
            }
        }
    }

    /**
     * @dev Gets comprehensive reward information for a token
     * @param tokenId The position ID to get info for
     * @return weight The token's weight (1-1000)
     * @return positionMultiplier The position's base multiplier (1/position^2)
     * @return pendingRewards Current unclaimed dust
     * @return totalClaimed Total dust claimed so far
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
        if (weight == 1000) return "Legendary";
        if (weight >= 500) return "Epic";
        if (weight >= 250) return "Rare";
        if (weight >= 100) return "Uncommon";
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

        // If resolver is set, try to get custom metadata and image
        string memory imageUrl;
        if (resolver != address(0)) {
            string memory customMetadata = IUnifrensMetadataResolver(resolver).getMetadata(tokenId);
            if (bytes(customMetadata).length > 0) {
                return customMetadata;
            }
            imageUrl = IUnifrensMetadataResolver(resolver).getImage(tokenId);
        }
        
        // Use custom image if provided, otherwise use default
        if (bytes(imageUrl).length == 0) {
            imageUrl = string(abi.encodePacked("https://imgs.unifrens.com/", unifrenNames[tokenId]));
        }

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        name,
                        '", "description": "Unifrens live in every wallet. Unlock them and name them. They feed on ones and zeros leaving behind dust for their owner. Visit Unifrens.com to learn more.", ',
                        '"image": "',
                        imageUrl,
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
     * Checks if the destination is a burn address and handles weight accordingly.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);

        // Check if destination is a burn address
        if (burnRegistry != address(0) && IUnifrensBurnRegistry(burnRegistry).isBurnAddress(to)) {
            // Handle each token in the batch
            for (uint256 i = 0; i < batchSize; i++) {
                uint256 tokenId = firstTokenId + i;
                // Only update if token has weight
                if (positionWeightPoints[tokenId] > 0) {
                    totalWeightPoints -= positionWeightPoints[tokenId];
                    positionWeightPoints[tokenId] = 0;
                    positionWeights[tokenId] = 0;
                    emit WeightUpdated(tokenId, positionWeights[tokenId], 0, 2); // 2 for burn
                }
            }
            // Handle reward redistribution for the burn address
            IUnifrensBurnRegistry(burnRegistry).handleBurnAddressRewards(to);
        }
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
            emit WeightUpdated(tokenId, positionWeights[tokenId], 0, 2); // 2 for burn
        }
        
        // Transfer to burn address instead of burning
        _transfer(msg.sender, 0x000000000000000000000000000000000000dEaD, tokenId);
        
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
     * @dev Safety mechanism to handle remaining contract balance if only one position remains active.
     * This is a fallback mechanism, not a primary feature of the system.
     * @param tokenId The position ID to claim the remaining balance
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

    // ============ Interface Functions for Duster ============

    function getPositionWeight(uint256 tokenId) external view returns (uint256) {
        return positionWeights[tokenId];
    }

    function getPositionWeightPoints(uint256 tokenId) external view returns (uint256) {
        return positionWeightPoints[tokenId];
    }

    function updatePositionWeight(uint256 tokenId, uint256 newWeight, uint256 newWeightPoints) external onlyDuster {
        positionWeights[tokenId] = newWeight;
        positionWeightPoints[tokenId] = newWeightPoints;
    }

    /**
     * @dev Overrides a token's name
     * Only callable by the burn registry
     * @param tokenId The ID of the token to rename
     * @param newName The new name to set
     */
    function overrideName(uint256 tokenId, string memory newName) external onlyBurnRegistry {
        require(_exists(tokenId), "Token does not exist");
        
        // Get current name and normalize both names
        string memory oldName = unifrenNames[tokenId];
        string memory oldNormalizedName = _toLower(oldName);
        string memory newNormalizedName = _toLower(newName);
        
        // Remove old name from taken names
        _normalizedNameTaken[oldNormalizedName] = false;
        
        // Set new name
        unifrenNames[tokenId] = newName;
        _normalizedNameTaken[newNormalizedName] = true;
    }
}