# UnichainFrens Contracts

This repository contains the smart contracts for the UnichainFrens project, a unique NFT staking and rewards system built on Ethereum.

## Overview

UnichainFrens is a dynamic NFT staking system where:
- Users can mint positions with customizable names and weights
- Positions accumulate rewards based on their weight and time staked
- Users can perform different types of withdrawals:
  - Soft withdraw (25% of rewards)
  - Hard withdraw (75% of rewards)
  - Redistribute (increase weight instead of claiming)

## Contract Versions

- `v1.sol` - Initial implementation
- `v2.sol` - Enhanced version with improved mechanics
- `v3.sol` - Latest version with optimizations

See [DEPLOYMENT_HISTORY.md](./DEPLOYMENT_HISTORY.md) for contract addresses and deployment details.

## Key Features

- Dynamic weight system (1-100 initial, up to 1000 max)
- Customizable position names
- Multiple withdrawal strategies
- Fair reward distribution based on weight and time
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