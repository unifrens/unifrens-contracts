// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//                 _ ____                    
//    __  ______  (_) __/_______  ____  _____
//   / / / / __ \/ / /_/ ___/ _ \/ __ \/ ___/
//  / /_/ / / / / / __/ /  /  __/ / / (__  ) 
//  \__,_/_/ /_/_/_/ /_/   \___/_/ /_/____/  
//   

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./IUnifrensCore.sol";

/**
 * @title UnifrensDuster
 * @dev Optional upgradeable component for handling dust rewards and withdrawals.
 * If not set, the core contract will use its built-in logic.
 */
interface IUnifrensDuster {
    function updateGlobalRewards(uint256 fee, bool isNewMoney) external;
    function getPendingRewards(uint256 tokenId) external view returns (uint256);
    function redistribute(uint256 tokenId) external returns (uint256);
    function softWithdraw(uint256 tokenId) external returns (uint256);
    function hardWithdraw(uint256 tokenId) external;
    function getContractHealth() external view returns (uint256, uint256);
}

contract UnifrensDuster is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable,
    IUnifrensDuster 
{
    // ============ State Variables ============

    /// @dev Reference to the core contract
    IUnifrensCore public core;

    /// @dev Total rewards distributed in the system
    uint256 public totalRewards;

    /// @dev Global accumulator for rewards per weight point
    uint256 public rewardsPerWeightPoint;

    /// @dev Total weight points across all active positions
    uint256 public totalWeightPoints;

    /// @dev Mapping of position ID to the rewardsPerWeightPoint at last claim
    mapping(uint256 => uint256) public lastRewardsPerWeightPoint;

    /// @dev Mapping of position ID to claimed rewards
    mapping(uint256 => uint256) public claimedRewards;

    // ============ Events ============
    
    /// @dev Emitted when dust is claimed
    event RewardsClaimed(uint256 indexed tokenId, uint256 amount, uint8 withdrawalType);

    /// @dev Emitted when a position's weight changes
    event WeightUpdated(uint256 indexed tokenId, uint256 oldWeight, uint256 newWeight, uint8 reason);

    /// @dev Emitted when the core contract is updated
    event CoreUpdated(address indexed oldCore, address indexed newCore);

    // ============ Modifiers ============

    modifier onlyCore() {
        require(msg.sender == address(core), "Only core contract can call");
        _;
    }

    // ============ Initialization ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _core) public initializer {
        require(_core != address(0), "Invalid core address");
        core = IUnifrensCore(_core);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    // ============ Core Functions ============

    function setCore(address _core) external onlyOwner {
        require(_core != address(0), "Invalid core address");
        IUnifrensCore oldCore = core;
        core = IUnifrensCore(_core);
        emit CoreUpdated(address(oldCore), _core);
    }

    // ============ Rewards Functions ============

    function updateGlobalRewards(uint256 fee, bool isNewMoney) external override {
        require(msg.sender == address(core), "Only core can update rewards");
        if (isNewMoney) {
            totalRewards += fee;
        }
        if (totalWeightPoints > 0) {
            rewardsPerWeightPoint += fee / totalWeightPoints;
        }
    }

    function getPendingRewards(uint256 tokenId) external view returns (uint256) {
        // This will be called by the core contract
        // Core contract will check if token exists and has weight points
        uint256 rewardsAccrued = IUnifrensCore(address(core)).getPositionWeightPoints(tokenId) * 
            (rewardsPerWeightPoint - lastRewardsPerWeightPoint[tokenId]);
        
        rewardsAccrued = rewardsAccrued / 1e18;
        rewardsAccrued = (rewardsAccrued / 1e2) * 1e2;
        
        uint256 maxRewards = address(core).balance;
        if (rewardsAccrued > maxRewards) {
            rewardsAccrued = maxRewards;
        }
        
        return rewardsAccrued;
    }

    function redistribute(uint256 tokenId) external onlyCore nonReentrant returns (uint256) {
        uint256 pendingRewards = this.getPendingRewards(tokenId);
        require(pendingRewards >= IUnifrensCore(address(core)).MIN_REDISTRIBUTE(), "Insufficient dust to redistribute");

        uint256 redistributeAmount = (pendingRewards * 75) / 100;
        uint256 keptAmount = pendingRewards - redistributeAmount;
        
        uint256 weightIncrease = calculateWeightIncrease(pendingRewards, IUnifrensCore(address(core)).getPositionWeight(tokenId));
        if (weightIncrease == 0) weightIncrease = 1;
        
        uint256 oldWeight = IUnifrensCore(address(core)).getPositionWeight(tokenId);
        uint256 newWeight = oldWeight + weightIncrease;
        if (newWeight > IUnifrensCore(address(core)).MAX_WEIGHT()) {
            newWeight = IUnifrensCore(address(core)).MAX_WEIGHT();
        }

        uint256 oldWeightPoints = IUnifrensCore(address(core)).getPositionWeightPoints(tokenId);
        uint256 newWeightPoints = (1e18 / (tokenId**2)) * newWeight;
        
        // Update position state through core contract
        IUnifrensCore(address(core)).updatePositionWeight(tokenId, newWeight, newWeightPoints);
        
        // Temporarily reduce total weight points
        totalWeightPoints -= oldWeightPoints;
        
        // Update checkpoint
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        // Redistribute 75% back to the reward pool
        if (redistributeAmount > 0 && IUnifrensCore(address(core)).totalSupply() > 1) {
            IUnifrensCore(address(core)).updateGlobalRewards(redistributeAmount, false);
        }
        
        // Add back the position's new weight points
        totalWeightPoints += newWeightPoints;
        
        // Handle kept amount
        if (keptAmount > 0) {
            uint256 keptRewardsPerPoint = (keptAmount * 1e18) / newWeightPoints;
            lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint - keptRewardsPerPoint;
        }
        
        emit WeightUpdated(tokenId, oldWeight, newWeight, 1);
        emit RewardsClaimed(tokenId, 0, 2);
        
        return newWeight;
    }

    function softWithdraw(uint256 tokenId) external onlyCore nonReentrant returns (uint256) {
        uint256 pendingRewards = this.getPendingRewards(tokenId);
        require(pendingRewards >= IUnifrensCore(address(core)).MIN_SOFT_WITHDRAW(), "Position not matured");

        uint256 softWithdrawAmount = (pendingRewards * 25) / 100;
        uint256 redistributeAmount = pendingRewards - softWithdrawAmount;

        require(address(core).balance >= softWithdrawAmount, "Insufficient contract balance");

        uint256 oldWeight = IUnifrensCore(address(core)).getPositionWeight(tokenId);
        uint256 newWeight = oldWeight;

        if (oldWeight < IUnifrensCore(address(core)).MAX_WEIGHT()) {
            uint256 weightIncrease = calculateWeightIncrease(pendingRewards, oldWeight) / 2;
            if (weightIncrease == 0) weightIncrease = 1;
            
            newWeight = oldWeight + weightIncrease;
            if (newWeight > IUnifrensCore(address(core)).MAX_WEIGHT()) {
                newWeight = IUnifrensCore(address(core)).MAX_WEIGHT();
            }

            uint256 oldWeightPoints = IUnifrensCore(address(core)).getPositionWeightPoints(tokenId);
            uint256 newWeightPoints = (1e18 / (tokenId**2)) * newWeight;
            
            IUnifrensCore(address(core)).updatePositionWeight(tokenId, newWeight, newWeightPoints);
            
            totalWeightPoints -= oldWeightPoints;
            lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
            
            if (redistributeAmount > 0 && IUnifrensCore(address(core)).totalSupply() > 1) {
                IUnifrensCore(address(core)).updateGlobalRewards(redistributeAmount, false);
            }
            
            totalWeightPoints += newWeightPoints;

            emit WeightUpdated(tokenId, oldWeight, newWeight, 0);
        }
        
        claimedRewards[tokenId] += softWithdrawAmount;
        emit RewardsClaimed(tokenId, softWithdrawAmount, 0);
        
        payable(IUnifrensCore(address(core)).ownerOf(tokenId)).transfer(softWithdrawAmount);
        return newWeight;
    }

    function hardWithdraw(uint256 tokenId) external onlyCore nonReentrant {
        uint256 pendingRewards = this.getPendingRewards(tokenId);
        require(pendingRewards > 0, "No rewards available");

        uint256 hardWithdrawAmount = (pendingRewards * 75) / 100;
        uint256 redistributeAmount = pendingRewards - hardWithdrawAmount;

        require(address(core).balance >= hardWithdrawAmount, "Insufficient contract balance");

        uint256 oldWeightPoints = IUnifrensCore(address(core)).getPositionWeightPoints(tokenId);
        totalWeightPoints -= oldWeightPoints;
        
        IUnifrensCore(address(core)).updatePositionWeight(tokenId, 0, 0);
        
        claimedRewards[tokenId] += pendingRewards;
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        if (redistributeAmount > 0 && IUnifrensCore(address(core)).totalSupply() > 1) {
            IUnifrensCore(address(core)).updateGlobalRewards(redistributeAmount, false);
        }
        
        emit RewardsClaimed(tokenId, hardWithdrawAmount, 1);
        payable(IUnifrensCore(address(core)).ownerOf(tokenId)).transfer(hardWithdrawAmount);
    }

    function getContractHealth() external view returns (uint256, uint256) {
        uint256 totalRewardsDistributed = totalRewards;
        uint256 pendingRewards = 0;
        uint256 supply = IUnifrensCore(address(core)).totalSupply();
        uint256 contractBalance = address(core).balance;
        
        for (uint256 i = 1; i <= supply; i++) {
            if (IUnifrensCore(address(core)).getPositionWeightPoints(i) > 0) {
                uint256 positionRewards = this.getPendingRewards(i);
                if (pendingRewards + positionRewards > contractBalance) {
                    pendingRewards = contractBalance;
                    break;
                }
                pendingRewards += positionRewards;
            }
        }
        
        return (totalRewardsDistributed, pendingRewards);
    }

    // ============ Helper Functions ============

    function calculateWeightIncrease(uint256 pendingRewards, uint256 currentWeight) public view returns (uint256) {
        uint256 ratio = (pendingRewards * 1e18) / IUnifrensCore(address(core)).BASE_WEIGHT_INCREASE();
        uint256 increase = sqrt(ratio) / 1e9;

        if (pendingRewards > 0 && increase == 0) {
            return 1;
        }

        uint256 reductionFactor = (currentWeight * 90) / 1000;
        increase = (increase * (100 - reductionFactor)) / 100;

        if (pendingRewards > 0 && increase == 0) {
            return 1;
        }

        return increase;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    // ============ UUPS Upgradeable ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
} 