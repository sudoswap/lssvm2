// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity ^0.8.0;

// import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// import {LSSVMPair} from "../LSSVMPair.sol";
// import {LSSVMPairERC721} from "../erc721/LSSVMPairERC721.sol";
// import {LSSVMPairFactory} from "../LSSVMPairFactory.sol";
// import {Test721} from "./Test721.sol";
// import {OrderBhook} from "../hooks/OrderBhook.sol";
// import {ICurve} from "../bonding-curves/ICurve.sol";

// contract MockMarketMaker {
//     address public immutable BOOK;
//     address payable public immutable PAIR_FACTORY;
//     address public immutable LINEAR_CURVE;

//     uint128 constant MAX_NFT = 20;
//     uint128 constant MIN_PRICE = 0.0001 ether;

//     uint256 supply;
//     Test721 public nft;

//     constructor(address payable _factory, address _book, address _linearCurve) {
//         PAIR_FACTORY = _factory;
//         BOOK = _book;
//         LINEAR_CURVE = _linearCurve;
//         nft = new Test721();
//         nft.setApprovalForAll(address(PAIR_FACTORY), true);
//     }

//     function make() public {
//         uint128 rng = uint128(
//             (uint256(blockhash(block.number - 1)) % MAX_NFT) + 1
//         );

//         address pair1 = address(0);
//         address pair2 = address(0);
//         uint256[] memory empty = new uint256[](0);

//         for (uint i; i < rng; ++i) {
//             nft.mint(address(this), supply + i);
//             if (i % 2 == 0) {
//                 if (pair1 == address(0)) {
//                     pair1 = address(
//                         LSSVMPairFactory(PAIR_FACTORY).createPairERC721ETH(
//                             IERC721(address(nft)),
//                             ICurve(LINEAR_CURVE),
//                             payable(address(this)),
//                             LSSVMPair.PoolType.TRADE,
//                             (MIN_PRICE * rng) / 10,
//                             0,
//                             MIN_PRICE,
//                             address(0),
//                             empty,
//                             BOOK,
//                             address(0)
//                         )
//                     );
//                 }
//                 uint256[] memory id = new uint256[](1);
//                 id[0] = supply + i;
//                 LSSVMPairFactory(PAIR_FACTORY).depositNFTs(
//                     IERC721(address(nft)),
//                     id,
//                     pair1
//                 );
//             } else {
//                 if (pair2 == address(0)) {
//                     pair2 = address(
//                         LSSVMPairFactory(PAIR_FACTORY).createPairERC721ETH(
//                             IERC721(address(nft)),
//                             ICurve(LINEAR_CURVE),
//                             payable(address(this)),
//                             LSSVMPair.PoolType.TRADE,
//                             (MIN_PRICE * rng) / 10,
//                             0,
//                             MIN_PRICE,
//                             address(0),
//                             empty,
//                             BOOK,
//                             address(0)
//                         )
//                     );
//                 }
//                 uint256[] memory id = new uint256[](1);
//                 id[0] = supply + i;
//                 LSSVMPairFactory(PAIR_FACTORY).depositNFTs(
//                     IERC721(address(nft)),
//                     id,
//                     pair2
//                 );
//             }
//         }
//         supply += rng;
//     }

//     function take() public payable {
//         (uint256 quote, address pair) = OrderBhook(BOOK)
//             .getBestBuyAccountForERC721(address(nft), address(0));
//         uint256[] memory idToTake = LSSVMPairERC721(pair).getIds(0, 1);
//         LSSVMPair(pair).swapTokenForSpecificNFTs{value: quote}(
//             idToTake,
//             quote,
//             address(this),
//             false,
//             address(0)
//         );
//     }

//     function getETHPriceBuy() public view returns (uint256) {
//         return
//             OrderBhook(BOOK).getBestBuyQuoteForERC721(address(nft), address(0));
//     }

//     function getETHPriceSell() public view returns (uint256) {
//         return
//             OrderBhook(BOOK).getBestSellQuoteForERC721(
//                 address(nft),
//                 address(0)
//             );
//     }

//     receive() external payable {}
// }
