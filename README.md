# sudoAMM v2

sudoAMM v2 is focused on delivering several specific feature upgrades missing from sudoAMM v1. 

Read the longform overview [here](https://blog.sudoswap.xyz/introducing-sudoswap-v2.html).

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

## Documentation
General documentation available [here](https://docs.sudoswap.xyz/).

To pull quote information, check out the sudo-defined-quoter package [here](https://github.com/sudoswap/sudo-defined-quoter).

To view audits for sudoAMM v2 by Narya, Spearbit, and Cyfrin check out [here](https://github.com/sudoswap/v2-audits)

## Deployments

The contracts have been deployed on Ethereum Mainnet to the following addresses:

**Factory & Router**

- LSSVMPairFactory: [0xA020d57aB0448Ef74115c112D18a9C231CC86000](https://etherscan.io/address/0xa020d57ab0448ef74115c112d18a9c231cc86000)
- VeryFastRouter: [0x090C236B62317db226e6ae6CD4c0Fd25b7028b65](https://etherscan.io/address/0x090C236B62317db226e6ae6CD4c0Fd25b7028b65)

**Price Curves**

- LinearCurve: [0xe5d78fec1a7f42d2F3620238C498F088A866FdC5](https://etherscan.io/address/0xe5d78fec1a7f42d2f3620238c498f088a866fdc5)
- ExponentialCurve: [0xfa056C602aD0C0C4EE4385b3233f2Cb06730334a](https://etherscan.io/address/0xfa056c602ad0c0c4ee4385b3233f2cb06730334a)
- XYKCurve: [0xc7fB91B6cd3C67E02EC08013CEBb29b1241f3De5](https://etherscan.io/address/0xc7fb91b6cd3c67e02ec08013cebb29b1241f3de5)
- GDACurve: [0x1fD5876d4A3860Eb0159055a3b7Cb79fdFFf6B67](https://etherscan.io/address/0x1fd5876d4a3860eb0159055a3b7cb79fdfff6b67)

**Other**

- SettingsFactory: [0xF4F439A6A152cFEcb1F34d726D490F82Bcb3c2C7](https://etherscan.io/address/0xf4f439a6a152cfecb1f34d726d490f82bcb3c2c7)
- PropertyCheckerFactory: [0x031b216FaBec82310FEa3426b33455609b99AfC1](https://etherscan.io/address/0x031b216fabec82310fea3426b33455609b99afc1)
- RoyaltyEngine: [0xBc40d21999b4BF120d330Ee3a2DE415287f626C9](https://etherscan.io/address/0xbc40d21999b4bf120d330ee3a2de415287f626c9)
- ZeroExRouter: [0xe4ac8eDd513074BA5f78DCdDc57680EF68Fa0CaE](https://etherscan.io/address/0xe4ac8edd513074ba5f78dcddc57680ef68fa0cae)