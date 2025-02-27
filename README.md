# UnichainFrens Contracts

A dynamic NFT ecosystem where positions compete in an economic game of accumulation and strategy.

## Overview

UnichainFrens is a unique NFT staking system where each position (Unifren) has:
- A custom name (alphanumeric, 1-16 characters)
- A weight (1-1000)
- A position multiplier (1/position²)
- Active/Retired status

## Core Mechanics

### Position Power
Each position's earning power is determined by two factors:
1. **Weight** (1-1000)
   - Initial mint: 1-100 weight
   - Cost: 0.001 ETH per weight point
   - Can increase through rewards
   
2. **Position Multiplier** (1/position²)
   - Earlier positions get higher multipliers
   - Position #1: 1.0× (100%)
   - Position #2: 0.25× (25%)
   - Position #3: 0.11× (11%)
   - And so on...

### Effective Power
Total earning power = Weight × Position Multiplier

For example:
- Position #1 with weight 10: 10 × 1.0 = 10 power
- Position #2 with weight 50: 50 × 0.25 = 12.5 power
- Position #3 with weight 100: 100 × 0.11 = 11 power

### Reward Distribution
New rewards (from mints) are distributed proportionally to each position's effective power.

## Strategic Actions

### 1. Soft Withdraw
- Claim 25% of pending rewards as ETH
- Redistribute 75% to all active positions
- Increase weight by half of what redistribute would give
- Position remains active
- Minimum: 0.0001 ETH in rewards

### 2. Redistribute
- Keep 25% of rewards as future earning power
- Redistribute 75% to all active positions
- Maximum weight increase based on total rewards
- No ETH withdrawal
- Minimum: 0.00001 ETH in rewards

### 3. Hard Withdraw
- Claim 75% of pending rewards as ETH
- Redistribute 25% to all active positions
- Position becomes retired (weight = 0)
- Cannot earn future rewards

### 4. Burn
- Transfer position to burn address
- Set weight to 0 (retired)
- Preserve position history and name
- Cannot earn future rewards
- Counts towards victory condition

## Weight Increase Mechanics

Weight increases follow a logarithmic curve:
```solidity
weightIncrease = sqrt(pendingRewards / 0.001 ether) / 1e9
```

This makes it progressively harder to reach max weight (1000).

## Victory Condition

When only one position remains with non-zero weight:
1. That position can claim victory
2. Winner receives entire contract balance
3. Game concludes

## Events

### Core Events
```solidity
event PositionMinted(uint256 indexed tokenId, uint256 weight, string name, address owner)
event RewardsClaimed(uint256 indexed tokenId, uint256 amount, uint8 withdrawalType)
event WeightUpdated(uint256 indexed tokenId, uint256 oldWeight, uint256 newWeight, uint8 reason)
event PositionBurned(uint256 indexed tokenId)
event VictoryClaimed(uint256 indexed tokenId, uint256 amount)
```

### Withdrawal Types
- 0: Soft Withdraw
- 1: Hard Withdraw
- 2: Redistribute

### Weight Update Reasons
- 0: Soft Withdraw
- 1: Redistribute

## Development

### Prerequisites
- Node.js
- Hardhat
- Ethereum wallet

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

## License

All rights reserved. Unauthorized copying or distribution prohibited. 