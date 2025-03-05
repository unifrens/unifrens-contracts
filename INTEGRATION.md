# Integrating .fren Names

This guide explains how to integrate .fren names into your platform, protocol, or application.

## Overview

.fren names are unique, resolvable identities on the blockchain that can be used across different platforms and protocols. They provide a human-readable way to identify and interact with blockchain addresses.

## Core Components

### Name Resolver Contract

The `UnifrensNameResolver` contract is the main entry point for resolving .fren names. It manages multiple versions of the Unifrens protocol and provides a unified interface for name resolution.

```solidity
interface IUnifrensNameResolver {
    function resolveName(string memory name) external view returns (
        address owner,
        uint256 tokenId,
        uint8 version
    );
}
```

## Integration Examples

### 1. Basic Name Resolution

```javascript
// Using ethers.js
const resolver = new ethers.Contract(
    "RESOLVER_ADDRESS",
    ["function resolveName(string) view returns (address,uint256,uint8)"],
    provider
);

async function resolveFrenName(name) {
    const [owner, tokenId, version] = await resolver.resolveName(name);
    return { owner, tokenId, version };
}
```

### 2. Wallet Integration

```javascript
// Example for wallet integration
class FrenNameWallet {
    constructor(resolverAddress) {
        this.resolver = new ethers.Contract(
            resolverAddress,
            ["function resolveName(string) view returns (address,uint256,uint8)"],
            provider
        );
    }

    async resolveAddress(name) {
        const [owner] = await this.resolver.resolveName(name);
        return owner;
    }

    async validateName(name) {
        const [owner] = await this.resolver.resolveName(name);
        return owner !== ethers.constants.AddressZero;
    }
}
```

### 3. Exchange Integration

```javascript
// Example for exchange integration
class FrenNameExchange {
    constructor(resolverAddress) {
        this.resolver = new ethers.Contract(
            resolverAddress,
            ["function resolveName(string) view returns (address,uint256,uint8)"],
            provider
        );
    }

    async validateWithdrawalAddress(name) {
        const [owner] = await this.resolver.resolveName(name);
        if (owner === ethers.constants.AddressZero) {
            throw new Error("Invalid .fren name");
        }
        return owner;
    }

    async processWithdrawal(name, amount) {
        const owner = await this.validateWithdrawalAddress(name);
        // Process withdrawal to resolved address
        await this.sendFunds(owner, amount);
    }
}
```

### 4. Social Platform Integration

```javascript
// Example for social platform integration
class FrenNameSocial {
    constructor(resolverAddress) {
        this.resolver = new ethers.Contract(
            resolverAddress,
            ["function resolveName(string) view returns (address,uint256,uint8)"],
            provider
        );
    }

    async resolveUserProfile(name) {
        const [owner, tokenId] = await this.resolver.resolveName(name);
        if (owner === ethers.constants.AddressZero) {
            return null;
        }
        return {
            address: owner,
            tokenId,
            displayName: name
        };
    }

    async linkSocialProfile(name, socialData) {
        const profile = await this.resolveUserProfile(name);
        if (!profile) {
            throw new Error("Invalid .fren name");
        }
        // Link social data to resolved address
        await this.saveSocialData(profile.address, socialData);
    }
}
```

## Best Practices

1. **Always Validate Names**
   - Check that the resolved address is not zero
   - Verify the name format before resolution
   - Handle resolution failures gracefully

2. **Never Cache Name Resolutions**
   - .fren names can change ownership at any time
   - Always resolve names on-demand to ensure accuracy
   - Caching could lead to incorrect address resolutions
   - Each resolution should be a fresh blockchain query

3. **Error Handling**
   - Implement proper error handling for failed resolutions
   - Provide clear error messages to users
   - Log resolution failures for monitoring

4. **Security Considerations**
   - Verify resolved addresses before processing transactions
   - Implement rate limiting for resolution requests
   - Consider implementing name blacklisting for security
   - Always use the latest resolution for critical operations

## Network Support

The Unifrens protocol is deployed on multiple networks. Make sure to use the correct resolver address for each network:

- Ethereum Mainnet: `0x...` (TBD)
- Test Networks: `0x...` (TBD)

## Additional Resources

- [Unifrens Documentation](https://unifrens.gitbook.io/unifrens-docs)
- [Contract Addresses](https://unifrens.gitbook.io/unifrens-docs)
- [API Reference](https://unifrens.gitbook.io/unifrens-docs) 