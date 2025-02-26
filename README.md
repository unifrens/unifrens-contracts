# UnichainFrens Contracts

This repository contains the smart contracts for the UnichainFrens project, a unique NFT staking and rewards system built on Ethereum.

## Overview

UnichainFrens is a dynamic NFT ecosystem where Unifrens compete in an economic game:
- Users can mint positions with customizable names and weights
- Positions accumulate rewards based on their weight and time staked
- Earlier positions earn more through a square root decay formula
- Players compete to be the last active position

## Core Strategies

1. **Stay & Play**
   - Soft withdraw (25% of rewards)
   - Redistribute 75% back to the pool
   - Maintain position for future earnings

2. **Power-Up**
   - Convert rewards to weight increase
   - Maximum weight of 1000×
   - No ETH withdrawal

3. **Cash Out**
   - Hard withdraw (75% of rewards)
   - Redistribute 25% back to pool
   - Position becomes inactive (weight = 0)

## Victory Condition

When only one active Fren remains (all others have weight 0), that player can claim victory and receive the entire contract balance as the ultimate winner of the game.

## Contract Versions

- `v1.sol` - Initial implementation
- `v2.sol` - Enhanced version with improved mechanics
- `v3.sol` - Gas optimizations and bug fixes
- `v4.sol` - Changed to square root decay for more balanced distribution
- `v5.sol` - Added victory mechanics and standardized error handling

See [DEPLOYMENT_HISTORY.md](./DEPLOYMENT_HISTORY.md) for contract addresses and deployment details.

## Key Features

- Dynamic weight system (1-100 initial, up to 1000 max)
- Square root decay distribution (1/√position)
- Customizable position names
- Multiple withdrawal strategies
- Victory claim mechanic
- Emergency pause functionality
- Standardized error messages
- Gas-optimized implementations

## Events

### PositionMinted
Emitted when a new position is minted
```solidity
event PositionMinted(uint256 indexed tokenId, uint256 weight, string name, address owner)
```

### RewardsClaimed
Emitted when rewards are claimed
```solidity
event RewardsClaimed(uint256 indexed tokenId, uint256 amount, uint8 withdrawalType)
// withdrawalType: 0=soft, 1=hard, 2=redistribute, 3=victory
```

### WeightUpdated
Emitted when a position's weight changes
```solidity
event WeightUpdated(uint256 indexed tokenId, uint256 oldWeight, uint256 newWeight)
```

### GlobalRewardsUpdated
Emitted when global rewards are updated
```solidity
event GlobalRewardsUpdated(uint256 fee, uint256 newRewardsPerWeightPoint, bool isNewMoney)
```

### EmergencyPauseSet
Emitted when emergency pause state changes
```solidity
event EmergencyPauseSet(bool paused)
```

## Development

### Prerequisites
- Node.js
- Hardhat/Foundry
- Ethereum wallet with testnet ETH

### Setup
1. Clone the repository
```bash
git clone https://github.com/unifrens/unifrens-contracts.git
cd unifrens-contracts
```

2. Install dependencies
```bash
npm install
```

3. Create `.env` file with required environment variables
```
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_key
RPC_URL=your_rpc_url
```

## License

All rights reserved. Unauthorized copying or distribution of this project is strictly prohibited. 