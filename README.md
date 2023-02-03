# sudoAMM v2

sudoAMM v2 is focused on delivering several specific feature upgrades missing from sudoAMM v1. 

The main focuses are:
- On-chain royalty support for all collections by default
- Property-checking for pools to allow for specifying desired trait / ID orders
- An opt-in on-chain structure for LPs and project owners that allows for revenue sharing
- Separate fee accounting, improved events, and minor gas optimizations

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

### Overrides
For projects that want to work more closely with pool creators, sudoAMM v2 introduces the notion of an Override. 

An Override is contract that enforces specific liquidity requirements for LPs. For example, an Override might ask that assets stay locked in the pool for 90 days, collect an upfront fee, as well as a 50/50 split of trading fees. In return for adhering to an Override, projects can set a separate royalty amount for these pools, to encourage more trading.

Agreements are an *opt-in* feature that are configured by a collection's owner. 

The sudoAMM v2 repo includes a configurable Override template ready to use out of the box, with choices for direct payment, lock duration, and fee split. Project owners are free to create their own Overrides for more bespoke conditions.

## Building/Testing

```
forge install
forge test
```