# sudoAMM v2

sudoAMM v2 is focused on delivering several specific feature upgrades from sudoAMM v1. 

The main focuses are:
- ERC2981-compliant (i.e. royalty) support for all collections by default
- Property-checking for pools to allow for specifying desired trait / ID orders
- A novel opt-in structure for on-chain Agreements between LPs and project owners that allows for revenue sharing
- Improved events, minor gas optimizations

### ERC2981 Support
If your collection is already 2981 compliant, then you're good to go. Buys and sells executed on sudoAMM v2 will send the royalty amount. If your collection isn't 2981 compliant, but your collection has an `owner()` or similar admin role, you can use the Manifold Royalty Registry to deploy a 2981 compliant royalty lookup.

### Property Checking
Pools can set another contract to do on-chain verification of desired properties (e.g. ID set inclusion) to purchase only certain items in a collection.

### Agreements
For projects that want to work more closely with LPs, sudoAMM v2 introduces the notion of an Agreement. An Agreement is contract that enforces specific liquidity requirements for LPs. For example, an Agreement might ask that the LP is locked for 90 days, as well as a 50/50 split of trading fees. In return for adhering to an Agreement, projects can set a separate royalty amount for these pools. This can potentially lower spreads.

Agreements are an *opt-in* feature. The sudoAMM v2 repo includes several Agreement templates ready to use out of the box, and project owners are free to create their own Agreements.

## Building/Testing

```
forge install
forge test
```