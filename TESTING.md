# Unifrens Contract Testing Document

## Stage 1: Core Functionality Tests

### 1. Initial Dev Token Mint
- [x] Deploy contract successfully
- [x] Token #1 exists with name "Dev"
- [x] Token #1 has weight = 1
- [x] Token #1 has no pending rewards
- [x] Token #1 is owned by deployer
- [x] Token #1 has correct position multiplier (1e18)

### 2. Basic Mint Functionality
- [x] Mint new token with weight = 1
  - [x] Correct payment (0.001 ETH)
  - [x] Name set correctly
  - [x] Weight set correctly
  - [x] Position multiplier correct (1e18/4 for token #2)
- [x] Verify token URI generation
- [x] Verify token attributes

### 3. Weight Limits
- [x] Attempt mint with weight = 0 (should fail)
- [x] Attempt mint with weight = 101 (should fail)
- [x] Mint with weight = 100 (should succeed)
- [x] Verify weight is exactly 100
- [x] Verify position multiplier calculation

### 4. Name Validation
- [x] Attempt mint with empty name (should fail)
- [x] Attempt mint with name > 21 chars (should fail)
- [x] Attempt mint with invalid characters (should fail)
- [x] Attempt mint with same name as existing token (should fail)
- [x] Verify name normalization works correctly

### 5. Reward Distribution
- [x] Mint two tokens
- [x] Send ETH to contract
- [x] Verify both tokens accrue rewards
- [x] Verify rewards proportional to weights
- [x] Verify totalRewards updates correctly
- [x] Verify rewardsPerWeightPoint updates correctly

### 6. Soft Withdraw
- [x] Mint token and accrue rewards
- [x] Perform soft withdraw
- [x] Verify 25% withdrawn
- [x] Verify weight increased
- [x] Verify 75% redistributed
- [x] Verify lastRewardsPerWeightPoint updated
- [x] Verify events emitted correctly

### 7. Hard Withdraw
- [x] Mint token and accrue rewards
- [x] Perform hard withdraw
- [x] Verify 75% withdrawn
- [x] Verify weight zeroed
- [x] Verify 25% redistributed
- [x] Verify lastRewardsPerWeightPoint updated
- [x] Verify events emitted correctly

### 8. Redistribute
- [x] Mint token and accrue rewards
- [x] Perform redistribute
- [x] Verify 75% redistributed
- [x] Verify weight increased
- [x] Verify 25% kept
- [x] Verify lastRewardsPerWeightPoint updated
- [x] Verify events emitted correctly

### 9. Contract Health
- [x] Call getContractHealth
- [x] Verify totalRewardsDistributed matches ETH received
- [x] Verify pendingRewards matches sum of individual rewards
- [x] Verify contractBalance matches actual ETH balance
- [x] Verify rounding matches individual token calculations

### 10. Token Info
- [x] Call getTokenInfo for various tokens
- [x] Verify weight matches positionWeights
- [x] Verify positionMultiplier is correct
- [x] Verify pendingRewards matches getPendingRewards
- [x] Verify totalClaimed matches claimedRewards
- [x] Verify isActive matches weight > 0

## Test Results Log

### Test Run 1
Date: March 7, 2024 10:00 AM
Environment: Remix VM
Results: Initial Dev Token Mint - PASSED
- All initial token parameters verified
- Token URI generated correctly with proper attributes
- Position multiplier (1e18) confirmed
- Weight (1) confirmed
- No pending rewards confirmed
- Active status confirmed
- Rarity tier (Common) confirmed
- Dust rate (100) confirmed

### Test Run 2
Date: March 7, 2024 10:15 AM
Environment: Remix VM
Results: Basic Mint Functionality - PASSED
- Token #2 minted successfully with weight = 1
- Correct payment (0.001 ETH) verified
- Name "test1" set correctly
- Weight (1) confirmed
- Position multiplier (1e18/4) confirmed
- Token URI generated with correct attributes
- Events emitted correctly (Transfer and PositionStateChanged)
- Contract health shows correct totalRewardsDistributed (0.002 ETH)
- Pending rewards and contract balance verified

### Test Run 3
Date: March 7, 2024 10:35 AM
Environment: Remix VM
Results: Weight Limits - PASSED
- Attempted mint with weight = 0 (failed as expected)
- Attempted mint with weight = 101 (failed as expected)
- Successfully minted token #3 with weight = 100
- Verified weight is exactly 100
- Position multiplier (1e18/9) confirmed for token #3
- Token URI generated with correct attributes
- Rarity tier (Uncommon) confirmed
- Dust rate (1111) confirmed
- Active status confirmed
- No pending rewards for new token
- Contract health shows correct totalRewardsDistributed (0.202 ETH)
- Pending rewards and contract balance verified

### Test Run 4
Date: March 7, 2024 10:50 AM
Environment: Remix VM
Results: Name Validation - PASSED
- Empty name rejected
- Name > 21 chars rejected
- Invalid characters rejected
- Duplicate names rejected
- Name normalization working correctly

### Test Run 5
Date: March 7, 2024 11:10 AM
Environment: Remix VM
Results: Reward Distribution - PASSED
- Initial state:
  - Total rewards: 0.2 ETH
  - Pending rewards: 0.1 ETH
  - Contract balance: 0.1 ETH
- After sending 0.013984 ETH:
  - Total rewards: 0.4 ETH
  - Pending rewards: ~0.2 ETH
  - Contract balance: 0.213984 ETH
- Token rewards distribution verified:
  - Token #1 (weight 1, pos mult 1e18): ~0.1038 ETH
  - Token #2 (weight 100, pos mult 0.25e18): ~0.0961 ETH
  - Token #3 (weight 100, pos mult 0.111e18): 0 ETH (newest)
- Rewards proportional to weights and position multipliers
- All state updates correct

### Test Run 6
Date: March 7, 2024 11:30 AM
Environment: Remix VM
Results: Soft Withdraw - PASSED
- Initial state:
  - Token #1: 0.1038 ETH pending, weight 1
  - Token #2: 0.0961 ETH pending, weight 100
  - Token #3: 0 ETH pending, weight 100
  - Contract balance: 1.443984 ETH
- After soft withdraw on Token #1:
  - 25% withdrawn (~0.0259 ETH) verified in totalClaimed
  - Weight increased from 1 to 6
  - 75% redistributed successfully:
    - Token #1: 0.0110 ETH new pending
    - Token #2: 0.1423 ETH pending
    - Token #3: 0.0205 ETH pending
  - Contract balance reduced correctly
  - Total rewards unchanged (0.4 ETH)
  - All state updates verified

### Test Run 7
Date: March 7, 2024 11:45 AM
Environment: Remix VM
Results: Hard Withdraw - PASSED
- Initial state:
  - Token #1: 0.0110 ETH pending, weight 6
  - Token #2: 0.1423 ETH pending, weight 100
  - Token #3: 0.0205 ETH pending, weight 100
  - Contract balance: 1.4189 ETH
- After hard withdraw on Token #2:
  - 75% withdrawn (~0.1067 ETH) verified in totalClaimed
  - Weight zeroed (from 100 to 0)
  - isActive status changed to false
  - 25% redistributed successfully:
    - Token #1: 0.0161 ETH pending
    - Token #2: 0 ETH pending
    - Token #3: 0.0299 ETH pending
  - Contract balance reduced correctly
  - Total rewards unchanged (0.4 ETH)
  - Proper events emitted (RewardsProcessed)
  - All state updates verified

### Test Run 8
Date: March 7, 2024 12:05 PM
Environment: Remix VM
Results: Redistribute - PASSED
- Initial setup:
  - Minted new token #4 (weight 1)
  - Position multiplier 0.0625e18 verified
- Initial state before redistribute:
  - Token #1: ~0.0161 ETH pending, weight 6
  - Token #2: 0 ETH pending, weight 0 (inactive)
  - Token #3: ~0.0299 ETH pending, weight 100
  - Token #4: New token, weight 1
- After redistribute on Token #1:
  - Weight increased from 6 to 10
  - 25% kept (~0.0041 ETH pending)
  - 75% redistributed successfully:
    - Token #2: 0 ETH (inactive)
    - Token #3: ~0.0429 ETH pending
    - Token #4: ~0.000069 ETH pending
  - Contract state verified:
    - Total rewards: 0.402 ETH
    - Total pending: ~0.0471 ETH
    - Contract balance maintained
  - All state updates verified

### Test Run 9
Date: March 7, 2024 12:25 PM
Environment: Remix VM
Results: Contract Health - PASSED
- ETH Flow Verification:
  - Total inflow: 1.645984 ETH
    - Mints/fees: 0.402 ETH
    - External transfer 1: 0.013984 ETH
    - External transfer 2: 1.23 ETH
  - Total outflow: ~0.132755 ETH
    - Soft withdraw: 0.025961538461538450 ETH
    - Hard withdraw: 0.106793560990460700 ETH
- Current State Verified:
  - Contract balance: 1.312228900548000850 ETH
  - Total pending rewards: 0.047111610114532100 ETH
  - Individual token rewards sum matches total pending:
    - Token #1: 0.004129913873676500 ETH
    - Token #2: 0 ETH (inactive)
    - Token #3: 0.042912393770632400 ETH
    - Token #4: 0.000069302470223200 ETH
  - All calculations properly rounded
  - All state variables consistent

### Test Run 10
Date: March 7, 2024 12:48 PM
Environment: Remix VM
Results: Token Info - PASSED
- Token #1 verified:
  - Weight: 10
  - Position multiplier: 1e18 (correct for pos 1)
  - Pending rewards: ~0.00413 ETH
  - Total claimed: ~0.02596 ETH
  - Active: true
- Token #2 verified:
  - Weight: 0
  - Position multiplier: 0.25e18 (correct for pos 2)
  - Pending rewards: 0
  - Total claimed: ~0.10679 ETH
  - Active: false
- Token #3 verified:
  - Weight: 100
  - Position multiplier: ~0.111e18 (correct for pos 3)
  - Pending rewards: ~0.04291 ETH
  - Total claimed: 0
  - Active: true
- Token #4 verified:
  - Weight: 1
  - Position multiplier: 0.0625e18 (correct for pos 4)
  - Pending rewards: ~0.000069 ETH
  - Total claimed: 0
  - Active: true
- Global state verified:
  - rewardsPerWeightPoint: 107708269285510767
  - totalWeightPoints: 21173611111111111100
- All calculations consistent
- Position multipliers follow correct formula (1/position^2)
- Active status correctly reflects weight > 0
- All claimed rewards properly tracked

## Stage 2: Advanced Testing

### 11. Security Features
- [ ] Owner Functions
  - [ ] Test setFeeRecipient with invalid address
  - [ ] Test setExtraMintFee with various values
  - [ ] Test toggleExtraMintFee functionality
  - [ ] Test toggleMinting functionality
  - [ ] Test toggleHardWithdraw functionality
  - [ ] Verify only owner can call these functions
- [ ] Burn Address Management
  - [ ] Test addBurnAddress with valid address
  - [ ] Test addBurnAddress with zero address (should fail)
  - [ ] Test removeBurnAddress functionality
  - [ ] Verify burn address token handling
  - [ ] Test isBurnAddress function

### 12. Edge Cases
- [ ] Token Operations
  - [ ] Test mint with maximum allowed weight
  - [ ] Test redistribute at MAX_WEIGHT
  - [ ] Test soft withdraw with minimum rewards
  - [ ] Test hard withdraw with minimum rewards
  - [ ] Test operations on non-existent tokens
- [ ] Reward Calculations
  - [ ] Test with very large ETH amounts
  - [ ] Test with very small ETH amounts
  - [ ] Test reward distribution with many tokens
  - [ ] Verify no overflow in calculations
  - [ ] Test rounding edge cases

### 13. Advanced Token Management
- [ ] Name Management
  - [ ] Test rename with maximum length name
  - [ ] Test adminRename functionality
  - [ ] Verify case sensitivity handling
  - [ ] Test name normalization edge cases
  - [ ] Verify name uniqueness constraints
- [ ] Token Transfers
  - [ ] Test transfer of active token
  - [ ] Test transfer of inactive token
  - [ ] Verify reward accrual after transfer
  - [ ] Test transfer to/from burn addresses
  - [ ] Verify events after transfers

### 14. Contract Recovery
- [ ] Emergency Functions
  - [ ] Test ERC20 token recovery
  - [ ] Test ETH withdrawal functions
  - [ ] Verify contract balance handling
  - [ ] Test pausing functionality
  - [ ] Verify state consistency after recovery
- [ ] Error Handling
  - [ ] Test revert messages
  - [ ] Verify gas refunds on failures
  - [ ] Test contract behavior under stress
  - [ ] Verify reentrancy protection
  - [ ] Test fallback function

### 15. Integration Testing
- [ ] Multi-Operation Sequences
  - [ ] Test mint->redistribute->withdraw sequence
  - [ ] Test rename->transfer->withdraw sequence
  - [ ] Test complex reward scenarios
  - [ ] Verify state consistency
  - [ ] Test concurrent operations
- [ ] Contract Interactions
  - [ ] Test ETH receiving functionality
  - [ ] Verify external contract calls
  - [ ] Test batch operations
  - [ ] Verify event emission ordering
  - [ ] Test contract upgrades

## Test Results Log

### Test Run 11
Date: March 7, 2024 1:15 PM
Environment: Remix VM
Results: Security Features - PENDING
- Owner function tests in progress
- Burn address management verification planned
- Access control checks scheduled

### Test Run 12
Date: March 7, 2024 1:45 PM
Environment: Remix VM
Results: Edge Cases - PENDING
- Token operation limits to be tested
- Reward calculation edge cases planned
- Overflow protection verification scheduled

### Test Run 13
Date: March 7, 2024 2:15 PM
Environment: Remix VM
Results: Advanced Token Management - PENDING
- Name management tests planned
- Transfer scenarios to be verified
- Event emission checks scheduled

### Test Run 14
Date: March 7, 2024 2:45 PM
Environment: Remix VM
Results: Contract Recovery - PENDING
- Emergency function testing planned
- Error handling verification scheduled
- State consistency checks to be performed

### Test Run 15
Date: March 7, 2024 3:15 PM
Environment: Remix VM
Results: Integration Testing - PENDING
- Multi-operation sequences to be tested
- Contract interaction verification planned
- Complex scenarios scheduled

## Notes
- All tests should be performed on Remix VM
- Each test should verify both successful and failure cases
- Events should be verified for all state changes
- Calculations should be cross-checked for accuracy
- Stage 2 testing focuses on edge cases and security
- Each test should include both positive and negative scenarios
- Complex operations should be tested in various sequences
- Gas optimization should be monitored during testing 