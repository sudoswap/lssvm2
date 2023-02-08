# sudoAMM v2

sudoAMM v2 is focused on delivering several specific feature upgrades missing from sudoAMM v1. 

The main focuses are:
- On-chain royalty support for all collections by default
- Property-checking for pools to allow for specifying desired trait / ID orders
- An opt-in on-chain structure for LPs and project owners that allows for revenue sharing
- ERC1155 support
- Separate fee accounting, unified router, improved events, and minor gas optimizations

### On-chain Royalty Support
If your collection is already ERC2981 compliant, then you're good to go. All buys and sells executed on sudoAMM v2 will send the appropriate royalty amount to your specified recipient address(es). If your collection isn't ERC2981 compliant, but your collection has an `owner()` or similar admin role, you can use the Manifold Royalty Registry to deploy a 2981 compliant royalty lookup.

If your collection uses a different royalty interface, the following interfaces are also supported via `RoyaltyEngine.sol`, a non-upgradeable version of the Manifold Royalty Engine:
* Rarible v1
* Rarible v2
* Foundation
* SuperRare
* Zora
* ArtBlocks 
* KnownOrigin v2

### Property Checking
Pools can set another contract to do on-chain verification of desired properties (e.g. ID set inclusion) to purchase only certain items in a collection. 

The protocol provides a generic `IPropertyChecker` interface, and it is agnostic about whether this is done through a bitmap, merkle tree, or any other on-chain property.

### Settings
For projects that want to work more closely with pool creators, sudoAMM v2 introduces a project-controlled Setting. 

A Setting is contract that enforces specific requirements for pools that opt into them. For example, a Setting might ask that assets stay locked in the pool for 90 days, collect an upfront fee, as well as a 50/50 split of trading fees. In return for adhering to a Setting, projects can configure a separate royalty amount for these pools to encourage more trading.

Settings are an *opt-in* feature that are always configured by a collection's owner. 

The sudoAMM v2 repo includes a configurable Setting template ready to use out of the box, with choices for direct payment, lock duration, and fee split. Project owners are free to create their own Setting for more bespoke conditions if they so choose.

### ERC1155 Support
Pools can now also be made for ERC1155<>ETH or ERC1155<>ERC20 pairs. Pools for ERC1155 assets will specify a specific ID in the ERC1155 collection that they buy or sell. Both ERC1155 and ERC721 pool types now inherit from the base `LSSVMPair` class.

### Misc
- TRADE pools can now set a separate `feeRecipient` to receive swap fees on each swap. Pools can also continue to keep fee balances internally if desired.
- Improved events for tracking NFTs swapped in or out
- A new `VeryFastRouter` which allows for handling all swap types (i.e. ERC721<>ETH, ERC721<>ERC20, ERC1155<>ETH, ERC1155<>ERC20), as well as an efficient method for handling **partial fills** when buying/selling multiple items from the same pool.

## Building/Testing

```
forge install
forge test
```

To generate coverage report locally: 
```
forge coverage --report lcov && genhtml lcov.info -o report --branch
open report/index.html
```
