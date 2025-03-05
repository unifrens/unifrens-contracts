# Unifrens Contract Suite

A modular and upgradeable suite of smart contracts for managing web3 usernames with dust accumulation mechanics.

## Contract Architecture

```mermaid
graph TD
    A[UnifrensCore] --> B[UnifrensDuster]
    A --> C[UnifrensMetadataResolver]
    A --> D[UnifrensFeeManager]
    A --> E[UnifrensBurnRegistry]
    B --> A
    C --> A
    D --> A
    E --> A
```

## Core Components

### UnifrensCore
- Base contract for NFT functionality and name management
- Handles weight storage and basic dust calculations
- Manages minting, transfers, and basic operations
- Interfaces with other components

### UnifrensDuster
- Dust management contract
- Handles dust calculations and distributions
- Manages weight modification logic
- Implements UUPS upgrade pattern

### UnifrensMetadataResolver
- Metadata management contract
- Handles custom metadata and image generation
- Implements UUPS upgrade pattern

### UnifrensFeeManager
- Fee management contract
- Handles additional fees on top of base minting fee
- Implements UUPS upgrade pattern

### UnifrensBurnRegistry
- Burn address management contract
- Manages list of burn addresses
- Handles dust redistribution for burned tokens
- Provides name override functionality for burned tokens
- Implements UUPS upgrade pattern

## Contract Interactions

### Minting Flow
```mermaid
sequenceDiagram
    participant User
    participant Core
    participant FeeManager
    participant Duster
    
    User->>Core: mint(weight, name)
    Core->>FeeManager: calculate additional fee
    Core->>Core: validate name
    Core->>Core: mint NFT
    Core->>Duster: update global dust
```

### Dust Operations
```mermaid
sequenceDiagram
    participant User
    participant Core
    participant Duster
    
    User->>Core: softWithdraw/hardWithdraw/redistribute
    Core->>Duster: handle dust operation
    Duster->>Core: update position weight
    Duster->>Core: update global dust
```

### Burn Operations
```mermaid
sequenceDiagram
    participant User
    participant Core
    participant BurnRegistry
    
    User->>Core: burn(tokenId)
    Core->>BurnRegistry: check burn address
    BurnRegistry->>Core: handle dust
    Core->>Core: update weights
```

### Name Override Flow
```mermaid
sequenceDiagram
    participant Admin
    participant BurnRegistry
    participant Core
    
    Admin->>BurnRegistry: overrideName(tokenId, newName)
    BurnRegistry->>Core: verify burn address ownership
    Core->>Core: update name
    Core->>BurnRegistry: confirm update
```

## Deployment Order

1. Deploy `UnifrensCore`
2. Deploy other components:
   - `UnifrensDuster`
   - `UnifrensMetadataResolver`
   - `UnifrensFeeManager`
   - `UnifrensBurnRegistry`
3. Set component addresses in Core contract

## Upgrade Process

### Core Contract
- Non-upgradeable
- Requires new deployment for updates
- State migration required

### Other Components
- Each can be upgraded independently
- Uses OpenZeppelin UUPS pattern
- State preserved through proxy
- Upgrade process:
  1. Deploy new implementation
  2. Call upgradeTo() on proxy
  3. Verify new implementation

## State Management

### Core Contract
- Stores NFT state
- Manages name uniqueness
- Tracks weights and dust
- Maintains component references

### Optional Components
- Duster: Manages dust calculations
- MetadataResolver: Handles metadata generation
- FeeManager: Manages additional fees
- BurnRegistry: Manages burn addresses and name overrides

## Security Considerations

1. Access Control
   - Core: Owner-only admin functions
   - Components: Owner-only upgrades
   - Component-specific access modifiers

2. State Protection
   - Core state only modifiable through defined interfaces
   - Component upgrades preserve state
   - Burn registry protects against unauthorized name changes

3. Dust Safety
   - Duster handles all dust calculations
   - Burn registry ensures proper dust redistribution
   - Core maintains weight integrity

## Events

### Core Events
- PositionMinted
- DustClaimed
- PositionBurned
- WeightUpdated
- VictoryClaimed
- Component updates

### Component Events
- Duster: Dust updates
- MetadataResolver: Metadata updates
- FeeManager: Fee updates
- BurnRegistry: Burn address updates, name overrides

## License

MIT License 