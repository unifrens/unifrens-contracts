// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// @title Unifrens
// @dev Web3 identities that accumulate dust
 
contract Unifrens is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public mintPrice = 0.001 ether;
    address public feeRecipient;
    uint256 public extraMintFee = 0;
    bool public extraMintFeeEnabled;
    uint256 public renameFee = 0.005 ether;
    uint256 public constant MAX_WEIGHT = 1000;
    uint256 public constant MAX_MINT_WEIGHT = 100;
    uint256 public constant BASE_WEIGHT_INCREASE = 0.001 ether;
    uint256 public constant MIN_SOFT_WITHDRAW = 0.0001 ether;
    uint256 public constant MIN_REDISTRIBUTE = 0.00001 ether;
    uint256 public totalRewards;
    bool public mintingPaused;
    bool public hardWithdrawPaused;
    uint256 public rewardsPerWeightPoint;
    uint256 public totalWeightPoints;
    mapping(uint256 => uint256) public positionWeights;
    mapping(uint256 => uint256) public positionWeightPoints;
    mapping(uint256 => uint256) public lastRewardsPerWeightPoint;
    mapping(uint256 => uint256) public claimedRewards;
    mapping(uint256 => string) public unifrenNames;
    mapping(string => bool) private _normalizedNameTaken;
    mapping(address => bool) public burnAddresses;
    mapping(uint256 => uint256) public claimCount;

    /// @dev Position state changes
    event PositionStateChanged(
        uint256 indexed tokenId,
        uint8 stateType,
        uint256 value1,
        uint256 value2,
        string name
    );
    
    /// @dev Dust processing events
    event RewardsProcessed(
        uint256 indexed tokenId,
        uint256 amount,
        uint8 claimType
    );

    /// @dev Initialize first position
    constructor() ERC721("Unifrens", "UNIFRENS") Ownable(msg.sender) {
        _mintWithWeight(msg.sender, 1, 1, "Dev", _toLower("Dev"), 0);
    }

    /// @dev Convert to lowercase
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        
        for (uint i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    /// @dev Validate name
    function _isValidName(string memory name, string memory normalizedName) internal view returns (bool) {
        bytes memory nameBytes = bytes(name);
        if (nameBytes.length == 0 || nameBytes.length > 21) return false;
        
        for (uint i = 0; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            if (
                !(char >= 0x30 && char <= 0x39) && // 0-9
                !(char >= 0x41 && char <= 0x5A) && // A-Z
                !(char >= 0x61 && char <= 0x7A)    // a-z
            ) return false;
        }

        return !_normalizedNameTaken[normalizedName];
    }

    /// @dev Mint position
    function mint(uint256 weight, string memory name) external payable nonReentrant {
        require(!mintingPaused, "Paused");
        require(weight >= 1 && weight <= MAX_MINT_WEIGHT, "Bad weight");
        
        uint256 basePrice = mintPrice * weight;
        uint256 extraFee = extraMintFeeEnabled ? extraMintFee : 0;
        uint256 totalPrice = basePrice + extraFee;
        require(msg.value == totalPrice, "Bad price");
        
        string memory normalizedName = _toLower(name);
        require(_isValidName(name, normalizedName), "Invalid name");

        uint256 newPosition = totalSupply() + 1;
        _mintWithWeight(msg.sender, newPosition, weight, name, normalizedName, basePrice);
        
        if (extraFee > 0) {
            if (feeRecipient != address(0)) {
                payable(feeRecipient).transfer(extraFee);
            } else {
                payable(owner()).transfer(extraFee);
            }
        }
    }

    /// @dev Internal mint
    function _mintWithWeight(
        address to, 
        uint256 tokenId, 
        uint256 weight, 
        string memory name,
        string memory normalizedName,
        uint256 basePrice
    ) internal {
        // Core minting functionality
        _mint(to, tokenId);
        
        require(tokenId <= 1e9, "Big ID");
        uint256 positionWeight = 1e18 / (tokenId**2);
        
        uint256 weightPoints = positionWeight * weight;
        require(weightPoints >= positionWeight && weightPoints >= weight, "Overflow");
        
        positionWeights[tokenId] = weight;
        positionWeightPoints[tokenId] = weightPoints;
        
        require(totalWeightPoints + weightPoints >= totalWeightPoints, "Overflow");
        totalWeightPoints += weightPoints;
        
        unifrenNames[tokenId] = name;
        _normalizedNameTaken[normalizedName] = true;
        
        // Only handle rewards if there's a base price
        if (basePrice > 0) {
            // Add to total rewards first to ensure it's counted
            totalRewards += basePrice;
            
            // Try to distribute rewards, but continue if it fails
            try this.updateGlobalRewardsExternal(basePrice, true, tokenId) {
                // Distribution succeeded
            } catch {
                // Silently continue if rewards distribution fails
            }
        }
        
        // Always set the last rewards point to prevent claiming historical rewards
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        emit PositionStateChanged(tokenId, 0, weight, 0, name);
    }

    /// @dev External wrapper for updateGlobalRewards to allow try/catch
    function updateGlobalRewardsExternal(uint256 fee, bool isNewMoney, uint256 newTokenId) external {
        require(msg.sender == address(this), "Only self");
        updateGlobalRewards(fee, isNewMoney, newTokenId);
    }

    /// @dev Update global dust
    function updateGlobalRewards(uint256 fee, bool isNewMoney, uint256 newTokenId) private {
        if (totalWeightPoints > 0) {
            // For new mints, we want to distribute based on existing weight points only
            uint256 adjustedTotalWeightPoints = isNewMoney ? 
                (totalWeightPoints - positionWeightPoints[newTokenId]) : 
                totalWeightPoints;
                
            if (adjustedTotalWeightPoints == 0) return;
            
            uint256 increase = (fee / adjustedTotalWeightPoints) * 1e18;
            require(increase >= fee / adjustedTotalWeightPoints, "Overflow");
            
            uint256 remainder = (fee % adjustedTotalWeightPoints) * 1e18 / adjustedTotalWeightPoints;
            require(remainder <= fee, "Overflow");
            
            increase += remainder;
            require(increase >= remainder, "Overflow");
            
            uint256 maxPossibleIncrease = type(uint256).max - rewardsPerWeightPoint;
            if (increase > maxPossibleIncrease) {
                increase = maxPossibleIncrease;
            }
            
            rewardsPerWeightPoint += increase;
        }
        
        if (isNewMoney) {
            require(totalRewards + fee >= totalRewards, "Overflow");
            totalRewards += fee;
        }
    }

    /// @dev Get pending dust
    function getPendingRewards(uint256 tokenId) public view returns (uint256) {
        if (!_exists(tokenId) || ownerOf(tokenId) == address(0)) return 0;
        if (positionWeightPoints[tokenId] == 0) return 0;
        
        // Check for overflow in rewards calculation
        uint256 rewardsAccrued = positionWeightPoints[tokenId] * 
            (rewardsPerWeightPoint - lastRewardsPerWeightPoint[tokenId]);
            
        // Only check overflow if we actually have rewards
        if (rewardsAccrued > 0) {
            require(rewardsAccrued >= positionWeightPoints[tokenId], "Reward overflow");
        }
        
        rewardsAccrued = rewardsAccrued / 1e18;
        
        uint256 maxRewards = address(this).balance;
        if (rewardsAccrued > maxRewards) {
            rewardsAccrued = maxRewards;
        }
        
        rewardsAccrued = (rewardsAccrued / 1e2) * 1e2;
        
        return rewardsAccrued;
    }

    /// @dev Redistribute 75% dust
    function redistribute(uint256 tokenId) external nonReentrant returns (uint256 newWeight) {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(positionWeights[tokenId] < MAX_WEIGHT, "Max");
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards >= MIN_REDISTRIBUTE, "Low");

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
            // Exclude the redistributing token from receiving its own redistributed dust
            try this.updateGlobalRewardsExternal(redistributeAmount, false, tokenId) {
                // Distribution succeeded
            } catch {
                // Silently continue if rewards distribution fails
            }
        }
        
        totalWeightPoints += newWeightPoints;
        
        if (keptAmount > 0) {
            uint256 keptRewardsPerPoint = (keptAmount * 1e18) / newWeightPoints;
            lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint - keptRewardsPerPoint;
        }
        
        emit PositionStateChanged(tokenId, 1, newWeight, oldWeight, "");
        emit RewardsProcessed(tokenId, 0, 2);
        
        return newWeight;
    }

    /// @dev Calc weight increase
    function calculateWeightIncrease(uint256 pendingRewards, uint256 currentWeight) public pure returns (uint256) {
        require(pendingRewards <= type(uint256).max / 1e18, "Big");
        // Calculate ratio without overflow by dividing first
        uint256 ratio = (pendingRewards / BASE_WEIGHT_INCREASE) * 1e18;
        require(ratio >= pendingRewards / BASE_WEIGHT_INCREASE, "Overflow");
        
        uint256 increase = sqrt(ratio) / 1e9;

        if (pendingRewards > 0 && increase == 0) {
            return 1;
        }

        uint256 reductionFactor = (currentWeight * 90) / 1000;
        require(reductionFactor <= currentWeight, "Overflow");
        
        increase = (increase * (100 - reductionFactor)) / 100;
        require(increase <= type(uint256).max / 100, "Overflow");

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

    /// @dev Soft withdraw 25% dust
    function softWithdraw(uint256 tokenId) external nonReentrant returns (uint256 newWeight) {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards >= MIN_SOFT_WITHDRAW, "Low");

        uint256 softWithdrawAmount = (pendingRewards * 25) / 100;
        uint256 redistributeAmount = pendingRewards - softWithdrawAmount;

        require(address(this).balance >= softWithdrawAmount, "No ETH");

        uint256 oldWeight = positionWeights[tokenId];
        newWeight = oldWeight;

        // Only try to increase weight if we're not at max and have enough rewards
        if (oldWeight < MAX_WEIGHT) {
            uint256 weightIncrease = calculateWeightIncrease(pendingRewards, oldWeight) / 2;
            
            // Only increase weight if we get at least 1 point
            if (weightIncrease > 0) {
                newWeight = oldWeight + weightIncrease;
                if (newWeight > MAX_WEIGHT) {
                    newWeight = MAX_WEIGHT;
                }

                // Only update weight points if we actually increased the weight
                if (newWeight > oldWeight) {
                    uint256 oldWeightPoints = positionWeightPoints[tokenId];
                    uint256 newWeightPoints = (1e18 / (tokenId**2)) * newWeight;
                    
                    positionWeights[tokenId] = newWeight;
                    positionWeightPoints[tokenId] = newWeightPoints;
                    
                    totalWeightPoints -= oldWeightPoints;
                    totalWeightPoints += newWeightPoints;

                    emit PositionStateChanged(tokenId, 1, newWeight, oldWeight, "");
                }
            }
        }
        
        // Always update rewards tracking
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        // Try to process the redistribution
        if (redistributeAmount > 0 && totalSupply() > 1) {
            try this.updateGlobalRewardsExternal(redistributeAmount, false, tokenId) {
                // Distribution succeeded
            } catch {
                // Silently continue if rewards distribution fails
            }
        }
        
        // Update claimed rewards and transfer
        claimedRewards[tokenId] += softWithdrawAmount;
        claimCount[tokenId]++;
        
        emit RewardsProcessed(tokenId, softWithdrawAmount, 0);
        
        payable(msg.sender).transfer(softWithdrawAmount);
        return newWeight;
    }

    /// @dev Toggle hard withdraws
    function toggleHardWithdraw() external onlyOwner {
        hardWithdrawPaused = !hardWithdrawPaused;
    }

    /// @dev Hard withdraw 75% dust
    function hardWithdraw(uint256 tokenId) external nonReentrant {
        require(!hardWithdrawPaused, "Paused");
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        require(pendingRewards > 0, "No dust");

        uint256 hardWithdrawAmount = (pendingRewards * 75) / 100;
        uint256 redistributeAmount = pendingRewards - hardWithdrawAmount;

        require(address(this).balance >= hardWithdrawAmount, "No ETH");

        // Always update rewards tracking first
        lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        
        // Try to process redistribution
        if (redistributeAmount > 0 && totalSupply() > 1) {
            try this.updateGlobalRewardsExternal(redistributeAmount, false, tokenId) {
                // Distribution succeeded
            } catch {
                // Silently continue if rewards distribution fails
            }
        }

        // Zero out weight points
        totalWeightPoints -= positionWeightPoints[tokenId];
        positionWeightPoints[tokenId] = 0;
        positionWeights[tokenId] = 0;
        
        claimedRewards[tokenId] += hardWithdrawAmount;
        claimCount[tokenId]++;
        
        emit RewardsProcessed(tokenId, hardWithdrawAmount, 1);
        payable(msg.sender).transfer(hardWithdrawAmount);
    }

    /// @dev Set fee recipient
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Bad addr");
        feeRecipient = newRecipient;
    }

    /// @dev Set extra fee
    function setExtraMintFee(uint256 newFee) external onlyOwner {
        require(newFee >= 0, "Bad fee");
        extraMintFee = newFee;
    }

    /// @dev Toggle extra fee
    function toggleExtraMintFee() external onlyOwner {
        extraMintFeeEnabled = !extraMintFeeEnabled;
    }

    /// @dev Recover ERC20
    function recoverERC20(address token) external onlyOwner {
        require(token != address(0), "Bad token");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens");
        
        bool success = IERC20(token).transfer(owner(), balance);
        require(success, "Failed");
    }

    /// @dev Withdraw amount
    function withdrawAmount(uint256 amount) external onlyOwner {
        require(amount > 0, "Bad amt");
        require(address(this).balance >= amount, "No ETH");
        payable(owner()).transfer(amount);
    }

    /// @dev Withdraw balance
    function withdrawContractBalance() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH");
        payable(owner()).transfer(balance);
    }

    /// @dev Toggle minting
    function toggleMinting() external onlyOwner {
        mintingPaused = !mintingPaused;
    }

    /// @dev Handle burn tokens
    function _handleBurnAddressTokens(address burnAddress) internal {
        uint256 balance = balanceOf(burnAddress);
        if (balance == 0) return;

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(burnAddress, i);
            
            uint256 pendingRewards = getPendingRewards(tokenId);
            string memory name = unifrenNames[tokenId];
            string memory normalizedName = _toLower(name);
            
            uint256 oldWeightPoints = positionWeightPoints[tokenId];
            if (oldWeightPoints > 0) {
                uint256 currentTotalWeightPoints = totalWeightPoints;
                
                totalWeightPoints -= oldWeightPoints;
                positionWeightPoints[tokenId] = 0;
                positionWeights[tokenId] = 0;
                
                delete unifrenNames[tokenId];
                _normalizedNameTaken[normalizedName] = false;
                
                if (pendingRewards > 0 && currentTotalWeightPoints > 0) {
                    uint256 rewardsPerPoint = (pendingRewards * 1e18) / currentTotalWeightPoints;
                    rewardsPerWeightPoint += rewardsPerPoint;
                }
            }
            
            emit PositionStateChanged(tokenId, 2, 0, 0, "");
        }
    }

    /// @dev Add burn addr
    function addBurnAddress(address burnAddress) external onlyOwner {
        require(burnAddress != address(0), "Bad addr");
        require(!burnAddresses[burnAddress], "Exists");
        
        _handleBurnAddressTokens(burnAddress);
        burnAddresses[burnAddress] = true;
    }

    /// @dev Remove burn addr
    function removeBurnAddress(address burnAddress) external onlyOwner {
        require(burnAddresses[burnAddress], "Not reg");
        burnAddresses[burnAddress] = false;
    }

    /// @dev Check burn addr
    function isBurnAddress(address burnAddress) public view returns (bool) {
        return burnAddresses[burnAddress];
    }

    // View
    /// @dev Get mint price
    function getMintPrice(uint256 weight) public view returns (uint256) {
        require(weight >= 1 && weight <= MAX_MINT_WEIGHT, "Bad weight");
        return mintPrice * weight;
    }

    /// @dev Get health
    function getContractHealth() public view returns (
        uint256 totalRewardsDistributed,
        uint256 pendingRewards,
        uint256 contractBalance
    ) {
        totalRewardsDistributed = totalRewards;
        contractBalance = address(this).balance;
        
        pendingRewards = 0;
        uint256 supply = totalSupply();
        
        for (uint256 i = 1; i <= supply; i++) {
            if (positionWeightPoints[i] > 0) {
                uint256 positionRewards = getPendingRewards(i);
                if (pendingRewards + positionRewards > contractBalance) {
                    pendingRewards = contractBalance;
                    break;
                }
                pendingRewards += positionRewards;
            }
        }
        
        // Round to match individual token calculations
        pendingRewards = (pendingRewards / 1e2) * 1e2;
    }

    /// @dev Get token info
    function getTokenInfo(uint256 tokenId) public view returns (
        uint256 weight,
        uint256 positionMultiplier,
        uint256 pendingRewards,
        uint256 totalClaimed,
        bool isActive
    ) {
        if (!_exists(tokenId)) return (0, 0, 0, claimedRewards[tokenId], false);

        weight = positionWeights[tokenId];
        positionMultiplier = 1e18 / (tokenId**2);
        pendingRewards = getPendingRewards(tokenId);
        totalClaimed = claimedRewards[tokenId];
        isActive = weight > 0;  // Token is only active if it has weight
    }

    /// @dev Get by name
    function getName(string memory name) public view returns (address owner) {
        string memory normalizedName = _toLower(name);
        
        if (!_normalizedNameTaken[normalizedName]) {
            return address(0);
        }
        
        uint256 supply = totalSupply();
        for (uint256 i = 1; i <= supply; i++) {
            if (keccak256(bytes(_toLower(unifrenNames[i]))) == keccak256(bytes(normalizedName))) {
                return ownerOf(i);
            }
        }
        
        return address(0);
    }

    /// @dev Get rarity
    function _getRarityTier(uint256 weight) internal pure returns (string memory) {
        if (weight == 1000) return "Legendary";
        if (weight >= 500) return "Epic";
        if (weight >= 250) return "Rare";
        if (weight >= 100) return "Uncommon";
        return "Common";
    }

    /// @dev Gen attributes
    function _generateAttributes(
        uint256 tokenId,
        uint256 weight,
        uint256 positionMultiplier,
        bool isActive
    ) internal pure returns (string memory) {
        uint256 dustRate = (positionMultiplier * weight) / 1e16;
        
        return string(abi.encodePacked(
            '[{"display_type": "number", "trait_type": "Position", "value": ',
            tokenId.toString(),
            '}, {"display_type": "number", "trait_type": "Weight", "value": ',
            weight.toString(),
            ', "max_value": ',
            MAX_WEIGHT.toString(),
            '}, {"display_type": "number", "trait_type": "Dust Rate", "value": ',
            dustRate.toString(),
            '}, {"trait_type": "Rarity Tier", "value": "',
            _getRarityTier(weight),
            '"}, {"trait_type": "Status", "value": "',
            isActive ? "Active" : "Retired",
            '"}]'
        ));
    }

    /// @dev Get URI
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert("ERC721: URI query for nonexistent token");
        
        (uint256 weight, uint256 positionMultiplier, , , bool isActive) = getTokenInfo(tokenId);
        
        string memory name = bytes(unifrenNames[tokenId]).length > 0 
            ? unifrenNames[tokenId] 
            : string(abi.encodePacked("Unifren #", tokenId.toString()));

        string memory attributes = _generateAttributes(tokenId, weight, positionMultiplier, isActive);
        string memory imageUrl = string(abi.encodePacked("https://imgs.unifrens.com/", unifrenNames[tokenId]));

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        name,
                        '", "description": "Unifrens are unique identities that accumulate dust. Visit Unifrens.com", ',
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

    function _exists(uint256 tokenId) internal view returns (bool) {
        return ownerOf(tokenId) != address(0);
    }

    receive() external payable {}
    
    fallback() external payable {}

    /// @dev Pre-transfer
    function _beforeTokenTransfer(
        address /* from */,
        address /* to */,
        uint256 /* firstTokenId */,
        uint256 /* batchSize */
    ) internal virtual {}

    /// @dev Burn
    function burn(uint256 tokenId, address burnAddress) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender || msg.sender == owner(), "Not auth");
        require(isBurnAddress(burnAddress), "Invalid burn");
        
        uint256 pendingRewards = getPendingRewards(tokenId);
        string memory name = unifrenNames[tokenId];
        string memory normalizedName = _toLower(name);
        
        uint256 oldWeightPoints = positionWeightPoints[tokenId];
        if (oldWeightPoints > 0) {
            uint256 currentTotalWeightPoints = totalWeightPoints;
            
            // Core state changes first
            totalWeightPoints -= oldWeightPoints;
            positionWeightPoints[tokenId] = 0;
            positionWeights[tokenId] = 0;
            
            delete unifrenNames[tokenId];
            _normalizedNameTaken[normalizedName] = false;
            
            // Try to distribute pending rewards
            if (pendingRewards > 0 && currentTotalWeightPoints > 0) {
                try this.updateGlobalRewardsExternal(pendingRewards, false, tokenId) {
                    // Distribution succeeded
                } catch {
                    // Silently continue if rewards distribution fails
                }
            }
        }
        
        _transfer(msg.sender, burnAddress, tokenId);
        emit PositionStateChanged(tokenId, 2, 0, 0, "");
    }

    /// @dev Set rename fee
    function setRenameFee(uint256 newFee) external onlyOwner {
        require(newFee > 0, "Bad fee");
        renameFee = newFee;
    }

    /// @dev Rename
    function rename(uint256 tokenId, string memory newName) external payable nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(msg.value == renameFee, "Bad fee");
        
        string memory oldName = unifrenNames[tokenId];
        string memory normalizedOldName = _toLower(oldName);
        string memory normalizedNewName = _toLower(newName);
        
        require(_isValidName(newName, normalizedNewName), "Invalid name");
        
        // Core rename functionality
        delete unifrenNames[tokenId];
        _normalizedNameTaken[normalizedOldName] = false;
        unifrenNames[tokenId] = newName;
        _normalizedNameTaken[normalizedNewName] = true;
        
        // Always add to total rewards first
        totalRewards += msg.value;
        
        // Try to distribute the fee to other tokens
        if (totalSupply() > 1) {
            try this.updateGlobalRewardsExternal(msg.value, false, tokenId) {
                // Distribution succeeded
            } catch {
                // Silently continue if rewards distribution fails
            }
            
            // Always update lastRewardsPerWeightPoint to prevent claiming historical rewards
            lastRewardsPerWeightPoint[tokenId] = rewardsPerWeightPoint;
        }
        
        emit PositionStateChanged(tokenId, 0, 0, 0, newName);
    }

    /// @dev Admin rename
    function adminRename(uint256 tokenId, string memory newName) external onlyOwner nonReentrant {
        require(_exists(tokenId), "No token");
        
        string memory oldName = unifrenNames[tokenId];
        string memory normalizedOldName = _toLower(oldName);
        string memory normalizedNewName = _toLower(newName);
        
        require(_isValidName(newName, normalizedNewName), "Invalid name");
        
        delete unifrenNames[tokenId];
        _normalizedNameTaken[normalizedOldName] = false;
        unifrenNames[tokenId] = newName;
        _normalizedNameTaken[normalizedNewName] = true;
        
        // Admin rename doesn't affect rewards at all
        emit PositionStateChanged(tokenId, 0, 0, 0, newName);
    }
}