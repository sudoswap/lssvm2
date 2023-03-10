// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {LSSVMPair} from "./LSSVMPair.sol";
import {LSSVMRouter} from "./LSSVMRouter.sol";
import {ICurve} from "./bonding-curves/ICurve.sol";
import {LSSVMPairCloner} from "./lib/LSSVMPairCloner.sol";
import {LSSVMPairERC1155} from "./erc1155/LSSVMPairERC1155.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {LSSVMPairERC20} from "./LSSVMPairERC20.sol";
import {LSSVMPairERC721ETH} from "./erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC1155ETH} from "./erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "./erc721/LSSVMPairERC721ERC20.sol";
import {LSSVMPairERC1155ERC20} from "./erc1155/LSSVMPairERC1155ERC20.sol";

import {ISettings} from "./settings/ISettings.sol";

/**
 * Imports for authAllowedForToken (forked from manifold.xyz Royalty Registry)
 */
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "./royalty-auth/INiftyGateway.sol";
import "./royalty-auth/IFoundation.sol";
import "./royalty-auth/IDigitalax.sol";
import "./royalty-auth/IArtBlocks.sol";

contract LSSVMPairFactory is Owned, ILSSVMPairFactoryLike {
    using LSSVMPairCloner for address;
    using AddressUpgradeable for address;
    using SafeTransferLib for address payable;
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal constant MAX_PROTOCOL_FEE = 0.1e18; // 10%, must <= 1 - MAX_FEE

    LSSVMPairERC721ETH public immutable erc721ETHTemplate;
    LSSVMPairERC721ERC20 public immutable erc721ERC20Template;
    LSSVMPairERC1155ETH public immutable erc1155ETHTemplate;
    LSSVMPairERC1155ERC20 public immutable erc1155ERC20Template;
    address payable public override protocolFeeRecipient;

    // Units are in base 1e18
    uint256 public override protocolFeeMultiplier;

    mapping(ICurve => bool) public bondingCurveAllowed;
    mapping(address => bool) public override callAllowed;

    // Data structures for settings logic
    mapping(address => mapping(address => bool)) public settingsForCollection;
    mapping(address => address) public settingsForPair;
    mapping(address => EnumerableSet.AddressSet) private pairsForSettings;

    struct RouterStatus {
        bool allowed;
        bool wasEverAllowed;
    }

    mapping(LSSVMRouter => RouterStatus) public override routerStatus;

    event NewERC721Pair(address indexed poolAddress);
    event NewERC1155Pair(address indexed poolAddress);
    event TokenDeposit(address indexed poolAddress);
    event NFTDeposit(address indexed poolAddress, uint256[] ids);
    event ERC1155Deposit(address indexed poolAddress, uint256 indexed id, uint256 amount);
    event ProtocolFeeRecipientUpdate(address indexed recipientAddress);
    event ProtocolFeeMultiplierUpdate(uint256 newMultiplier);
    event BondingCurveStatusUpdate(ICurve indexed bondingCurve, bool isAllowed);
    event CallTargetStatusUpdate(address indexed target, bool isAllowed);
    event RouterStatusUpdate(LSSVMRouter indexed router, bool isAllowed);

    constructor(
        LSSVMPairERC721ETH _erc721ETHTemplate,
        LSSVMPairERC721ERC20 _erc721ERC20Template,
        LSSVMPairERC1155ETH _erc1155ETHTemplate,
        LSSVMPairERC1155ERC20 _erc1155ERC20Template,
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeMultiplier,
        address _owner
    ) Owned(_owner) {
        erc721ETHTemplate = _erc721ETHTemplate;
        erc721ERC20Template = _erc721ERC20Template;
        erc1155ETHTemplate = _erc1155ETHTemplate;
        erc1155ERC20Template = _erc1155ERC20Template;
        protocolFeeRecipient = _protocolFeeRecipient;
        require(_protocolFeeMultiplier <= MAX_PROTOCOL_FEE, "Fee too large");
        protocolFeeMultiplier = _protocolFeeMultiplier;
    }

    /**
     * External functions
     */

    /**
     * @notice Creates a pair contract using EIP-1167.
     *     @param _nft The NFT contract of the collection the pair trades
     *     @param _bondingCurve The bonding curve for the pair to price NFTs, must be whitelisted
     *     @param _assetRecipient The address that will receive the assets traders give during trades.
     *                           If set to address(0), assets will be sent to the pool address.
     *                           Not available to TRADE pools.
     *     @param _poolType TOKEN, NFT, or TRADE
     *     @param _delta The delta value used by the bonding curve. The meaning of delta depends
     *     on the specific curve.
     *     @param _fee The fee taken by the LP in each trade. Can only be non-zero if _poolType is Trade.
     *     @param _spotPrice The initial selling spot price
     *     @param _propertyChecker The contract to use for verifying properties of IDs sent in
     *     @param _initialNFTIDs The list of IDs of NFTs to transfer from the sender to the pair
     *     @return pair The new pair
     */
    function createPairERC721ETH(
        IERC721 _nft,
        ICurve _bondingCurve,
        address payable _assetRecipient,
        LSSVMPair.PoolType _poolType,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        address _propertyChecker,
        uint256[] calldata _initialNFTIDs
    ) external payable returns (LSSVMPairERC721ETH pair) {
        require(bondingCurveAllowed[_bondingCurve], "Bonding curve not whitelisted");

        pair = LSSVMPairERC721ETH(
            payable(
                address(erc721ETHTemplate).cloneETHPair(this, _bondingCurve, _nft, uint8(_poolType), _propertyChecker)
            )
        );

        _initializePairERC721ETH(pair, _nft, _assetRecipient, _delta, _fee, _spotPrice, _initialNFTIDs);
        emit NewERC721Pair(address(pair));
    }

    /**
     * @notice Creates a pair contract using EIP-1167.
     *     @param nft The NFT contract of the collection the pair trades
     *     @param bondingCurve The bonding curve for the pair to price NFTs, must be whitelisted
     *     @param assetRecipient The address that will receive the assets traders give during trades.
     *                             If set to address(0), assets will be sent to the pool address.
     *                             Not available to TRADE pools.
     *     @param poolType TOKEN, NFT, or TRADE
     *     @param delta The delta value used by the bonding curve. The meaning of delta depends
     *     on the specific curve.
     *     @param fee The fee taken by the LP in each trade. Can only be non-zero if poolType is Trade.
     *     @param spotPrice Param 1 for the bonding curve, usually used for start price
     *     @param delta Param 2 for the bonding curve, usually used for dynamic adjustment
     *     @param propertyChecker The contract to use for verifying properties of IDs sent in
     *     @param initialNFTIDs The list of IDs of NFTs to transfer from the sender to the pair
     *     @param initialTokenBalance The initial token balance sent from the sender to the new pair
     *     @return pair The new pair
     */
    struct CreateERC721ERC20PairParams {
        ERC20 token;
        IERC721 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPair.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        address propertyChecker;
        uint256[] initialNFTIDs;
        uint256 initialTokenBalance;
    }

    function createPairERC721ERC20(CreateERC721ERC20PairParams calldata params)
        external
        returns (LSSVMPairERC721ERC20 pair)
    {
        require(bondingCurveAllowed[params.bondingCurve], "Bonding curve not whitelisted");

        pair = LSSVMPairERC721ERC20(
            payable(
                address(erc721ERC20Template).cloneERC20Pair(
                    this, params.bondingCurve, params.nft, uint8(params.poolType), params.propertyChecker, params.token
                )
            )
        );

        _initializePairERC721ERC20(
            pair,
            params.token,
            params.nft,
            params.assetRecipient,
            params.delta,
            params.fee,
            params.spotPrice,
            params.initialNFTIDs,
            params.initialTokenBalance
        );
        emit NewERC721Pair(address(pair));
    }
    /**
     * @notice Creates a pair contract using EIP-1167.
     *     @param _nft The NFT contract of the collection the pair trades
     *     @param _bondingCurve The bonding curve for the pair to price NFTs, must be whitelisted
     *     @param _assetRecipient The address that will receive the assets traders give during trades.
     *                           If set to address(0), assets will be sent to the pool address.
     *                           Not available to TRADE pools.
     *     @param _poolType TOKEN, NFT, or TRADE
     *     @param _delta The delta value used by the bonding curve. The meaning of delta depends
     *     on the specific curve.
     *     @param _fee The fee taken by the LP in each trade. Can only be non-zero if _poolType is Trade.
     *     @param _spotPrice The initial selling spot price
     *     @param _nftId The ID of the NFT to trade
     *     @param _initialNFTBalance The amount of NFTs to transfer from the sender to the pair
     *     @return pair The new pair
     */

    function createPairERC1155ETH(
        IERC1155 _nft,
        ICurve _bondingCurve,
        address payable _assetRecipient,
        LSSVMPairERC1155ETH.PoolType _poolType,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256 _nftId,
        uint256 _initialNFTBalance
    ) external payable returns (LSSVMPairERC1155ETH pair) {
        require(bondingCurveAllowed[_bondingCurve], "Bonding curve not whitelisted");

        pair = LSSVMPairERC1155ETH(
            payable(
                address(erc1155ETHTemplate).cloneERC1155ETHPair(this, _bondingCurve, _nft, uint8(_poolType), _nftId)
            )
        );

        _initializePairERC1155ETH(pair, _nft, _assetRecipient, _delta, _fee, _spotPrice, _nftId, _initialNFTBalance);
        emit NewERC1155Pair(address(pair));
    }

    /**
     * @notice Creates a pair contract using EIP-1167.
     *     @param _nft The NFT contract of the collection the pair trades
     *     @param _bondingCurve The bonding curve for the pair to price NFTs, must be whitelisted
     *     @param _assetRecipient The address that will receive the assets traders give during trades.
     *                             If set to address(0), assets will be sent to the pool address.
     *                             Not available to TRADE pools.
     *     @param _poolType TOKEN, NFT, or TRADE
     *     @param _delta The delta value used by the bonding curve. The meaning of delta depends
     *     on the specific curve.
     *     @param _fee The fee taken by the LP in each trade. Can only be non-zero if _poolType is Trade.
     *     @param _spotPrice The initial selling spot price, in ETH
     *     @param _nftId The ID of the NFT to trade
     *     @param _initialNFTBalance The amount of NFTs to transfer from the sender to the pair
     *     @param _initialTokenBalance The initial token balance sent from the sender to the new pair
     *     @return pair The new pair
     */
    struct CreateERC1155ERC20PairParams {
        ERC20 token;
        IERC1155 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPairERC1155ERC20.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        uint256 nftId;
        uint256 initialNFTBalance;
        uint256 initialTokenBalance;
    }

    function createPairERC1155ERC20(CreateERC1155ERC20PairParams calldata params)
        external
        returns (LSSVMPairERC1155ERC20 pair)
    {
        require(bondingCurveAllowed[params.bondingCurve], "Bonding curve not whitelisted");

        pair = LSSVMPairERC1155ERC20(
            payable(
                address(erc1155ERC20Template).cloneERC1155ERC20Pair(
                    this, params.bondingCurve, params.nft, uint8(params.poolType), params.nftId, params.token
                )
            )
        );

        _initializePairERC1155ERC20(
            pair,
            params.token,
            params.nft,
            params.assetRecipient,
            params.delta,
            params.fee,
            params.spotPrice,
            params.nftId,
            params.initialNFTBalance,
            params.initialTokenBalance
        );
        emit NewERC1155Pair(address(pair));
    }

    function isValidPair(address pairAddress) public view returns (bool) {
        PairVariant variant = LSSVMPair(pairAddress).pairVariant();
        if (variant == PairVariant.ERC721_ETH) {
            return LSSVMPairCloner.isERC721ETHPairClone(address(this), address(erc721ETHTemplate), pairAddress);
        } else if (variant == PairVariant.ERC721_ERC20) {
            return LSSVMPairCloner.isERC721ERC20PairClone(address(this), address(erc721ERC20Template), pairAddress);
        } else if (variant == PairVariant.ERC1155_ETH) {
            return LSSVMPairCloner.isERC1155ETHPairClone(address(this), address(erc1155ETHTemplate), pairAddress);
        } else if (variant == PairVariant.ERC1155_ERC20) {
            return LSSVMPairCloner.isERC1155ERC20PairClone(address(this), address(erc1155ERC20Template), pairAddress);
        } else {
            return false;
        }
    }

    function getPairNFTType(address pairAddress) public pure returns (PairNFTType) {
        PairVariant variant = LSSVMPair(pairAddress).pairVariant();
        return PairNFTType(uint8(variant) / 2);
    }

    function getPairTokenType(address pairAddress) public pure returns (PairTokenType) {
        PairVariant variant = LSSVMPair(pairAddress).pairVariant();
        return PairTokenType(uint8(variant) % 2);
    }

    /**
     * @notice Checks if an address is an allowed auth for a token
     *   @param tokenAddress The token address to check
     *   @param proposedAuthAddress The auth address to check
     *   @return True if the proposedAuthAddress is a valid auth for the tokenAddress, false otherwise.
     */
    function authAllowedForToken(address tokenAddress, address proposedAuthAddress) public view returns (bool) {
        // Check for admin interface
        if (
            ERC165Checker.supportsInterface(tokenAddress, type(IAdminControl).interfaceId)
                && IAdminControl(tokenAddress).isAdmin(proposedAuthAddress)
        ) {
            return true;
        }
        // Check for owner
        try OwnableUpgradeable(tokenAddress).owner() returns (address owner) {
            if (owner == proposedAuthAddress) return true;

            if (owner.isContract()) {
                try OwnableUpgradeable(owner).owner() returns (address passThroughOwner) {
                    if (passThroughOwner == proposedAuthAddress) return true;
                } catch {}
            }
        } catch {}
        // Check for default OZ auth role
        try IAccessControlUpgradeable(tokenAddress).hasRole(0x00, proposedAuthAddress) returns (bool hasRole) {
            if (hasRole) return true;
        } catch {}
        // Nifty Gateway overrides
        try INiftyBuilderInstance(tokenAddress).niftyRegistryContract() returns (address niftyRegistry) {
            try INiftyRegistry(niftyRegistry).isValidNiftySender(proposedAuthAddress) returns (bool valid) {
                if (valid) return true;
            } catch {}
        } catch {}
        // Foundation overrides
        try IFoundationTreasuryNode(tokenAddress).getFoundationTreasury() returns (address payable foundationTreasury) {
            try IFoundationTreasury(foundationTreasury).isAdmin(proposedAuthAddress) returns (bool isAdmin) {
                if (isAdmin) return true;
            } catch {}
        } catch {}
        // DIGITALAX overrides
        try IDigitalax(tokenAddress).accessControls() returns (address externalAccessControls) {
            try IDigitalaxAccessControls(externalAccessControls).hasAdminRole(proposedAuthAddress) returns (
                bool hasRole
            ) {
                if (hasRole) return true;
            } catch {}
        } catch {}
        // Art Blocks overrides
        try IArtBlocks(tokenAddress).admin() returns (address admin) {
            if (admin == proposedAuthAddress) return true;
        } catch {}
        return false;
    }

    /**
     * @notice Allows receiving ETH in order to receive protocol fees
     */
    receive() external payable {}

    /**
     * Admin functions
     */

    /**
     * @notice Withdraws the ETH balance to the protocol fee recipient.
     *     Only callable by the owner.
     */
    function withdrawETHProtocolFees() external onlyOwner {
        protocolFeeRecipient.safeTransferETH(address(this).balance);
    }

    /**
     * @notice Withdraws ERC20 tokens to the protocol fee recipient. Only callable by the owner.
     *     @param token The token to transfer
     *     @param amount The amount of tokens to transfer
     */
    function withdrawERC20ProtocolFees(ERC20 token, uint256 amount) external onlyOwner {
        token.safeTransfer(protocolFeeRecipient, amount);
    }

    /**
     * @notice Changes the protocol fee recipient address. Only callable by the owner.
     *     @param _protocolFeeRecipient The new fee recipient
     */
    function changeProtocolFeeRecipient(address payable _protocolFeeRecipient) external onlyOwner {
        require(_protocolFeeRecipient != address(0), "0 address");
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdate(_protocolFeeRecipient);
    }

    /**
     * @notice Changes the protocol fee multiplier. Only callable by the owner.
     *     @param _protocolFeeMultiplier The new fee multiplier, 18 decimals
     */
    function changeProtocolFeeMultiplier(uint256 _protocolFeeMultiplier) external onlyOwner {
        require(_protocolFeeMultiplier <= MAX_PROTOCOL_FEE, "Fee too large");
        protocolFeeMultiplier = _protocolFeeMultiplier;
        emit ProtocolFeeMultiplierUpdate(_protocolFeeMultiplier);
    }

    /**
     * @notice Sets the whitelist status of a bonding curve contract. Only callable by the owner.
     *     @param bondingCurve The bonding curve contract
     *     @param isAllowed True to whitelist, false to remove from whitelist
     */
    function setBondingCurveAllowed(ICurve bondingCurve, bool isAllowed) external onlyOwner {
        bondingCurveAllowed[bondingCurve] = isAllowed;
        emit BondingCurveStatusUpdate(bondingCurve, isAllowed);
    }

    /**
     * @notice Sets the whitelist status of a contract to be called arbitrarily by a pair.
     *     Only callable by the owner.
     *     @param target The target contract
     *     @param isAllowed True to whitelist, false to remove from whitelist
     */
    function setCallAllowed(address payable target, bool isAllowed) external onlyOwner {
        // ensure target is not / was not ever a router
        if (isAllowed) {
            require(!routerStatus[LSSVMRouter(target)].wasEverAllowed, "Can't call router");
        }

        callAllowed[target] = isAllowed;
        emit CallTargetStatusUpdate(target, isAllowed);
    }

    /**
     * @notice Updates the router whitelist. Only callable by the owner.
     *     @param _router The router
     *     @param isAllowed True to whitelist, false to remove from whitelist
     */
    function setRouterAllowed(LSSVMRouter _router, bool isAllowed) external onlyOwner {
        // ensure target is not arbitrarily callable by pairs
        if (isAllowed) {
            require(!callAllowed[address(_router)], "Can't call router");
        }
        routerStatus[_router] = RouterStatus({allowed: isAllowed, wasEverAllowed: true});

        emit RouterStatusUpdate(_router, isAllowed);
    }

    /**
     * @notice Returns the Settings for a pair if it currently has Settings
     * @param pairAddress The address of the pair to look up
     * Returns whether or not the pair has custom settings, and what its bps should be (if valid)
     */
    function getSettingsForPair(address pairAddress) public view returns (bool settingsEnabled, uint96 bps) {
        address settingsAddress = settingsForPair[pairAddress];
        if (settingsAddress == address(0)) {
            return (false, 0);
        }
        return ISettings(settingsAddress).getRoyaltyInfo(pairAddress);
    }

    /**
     * @notice Enables or disables an settings for a given NFT collection
     *      @param settings The address of the Settings contract
     *      @param collectionAddress The NFT project that the settings is toggled for
     *      @param enable Bool to determine whether to disable or enable the settings
     */
    function toggleSettingsForCollection(address settings, address collectionAddress, bool enable) public {
        require(authAllowedForToken(collectionAddress, msg.sender), "Unauthorized caller");
        if (enable) {
            settingsForCollection[collectionAddress][settings] = true;
        } else {
            delete settingsForCollection[collectionAddress][settings];
        }
    }

    /**
     * @notice Enables an Settings for a given Pair
     * @notice Only the owner of the Pair can call this function
     * @notice The Settings must be enabled for the Pair's collection
     *      @param settings The address of the Settings contract
     *      @param pairAddress The address of the Pair contract
     */
    function enableSettingsForPair(address settings, address pairAddress) public {
        require(isValidPair(pairAddress), "Invalid pair address");
        LSSVMPair pair = LSSVMPair(pairAddress);
        require(pair.owner() == msg.sender, "Msg sender is not pair owner");
        require(settingsForCollection[address(pair.nft())][settings], "Settings not enabled for collection");
        settingsForPair[pairAddress] = settings;
        pairsForSettings[settings].add(pairAddress);
    }

    /**
     * @notice Disables an Settings for a given Pair
     * @notice Only the owner of the Pair can call this function
     * @notice The Settings must already be enabled for the Pair
     *      @param settings The address of the Settings contract
     *      @param pairAddress The address of the Pair contract
     */
    function disableSettingsForPair(address settings, address pairAddress) public {
        require(isValidPair(pairAddress), "Invalid pair address");
        require(settingsForPair[pairAddress] == settings, "Settings not enabled for pair");
        LSSVMPair pair = LSSVMPair(pairAddress);
        require(pair.owner() == msg.sender, "Msg sender is not pair owner");
        delete settingsForPair[pairAddress];
        pairsForSettings[settings].remove(pairAddress);
    }

    /**
     * @notice Fetches all the Pair addresses that are registered with the given Settings
     *      @param settings The address of the Settings contract
     *      @return A list of addresses of the Pairs that belong to a Settings
     */
    function getAllPairsForSettings(address settings) external view returns (address[] memory) {
        uint256 numPairs = pairsForSettings[settings].length();
        address[] memory pairs = new address[](numPairs);
        for (uint256 i; i < numPairs;) {
            pairs[i] = pairsForSettings[settings].at(i);
            unchecked {
                ++i;
            }
        }
        return pairs;
    }

    /**
     * Internal functions
     */

    function _initializePairERC721ETH(
        LSSVMPairERC721ETH _pair,
        IERC721 _nft,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256[] calldata _initialNFTIDs
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _delta, _fee, _spotPrice);

        // transfer initial ETH to pair
        if (msg.value > 0) payable(address(_pair)).safeTransferETH(msg.value);

        // transfer initial NFTs from sender to pair
        uint256 numNFTs = _initialNFTIDs.length;
        for (uint256 i; i < numNFTs;) {
            _nft.transferFrom(msg.sender, address(_pair), _initialNFTIDs[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _initializePairERC721ERC20(
        LSSVMPairERC721ERC20 _pair,
        ERC20 _token,
        IERC721 _nft,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256[] calldata _initialNFTIDs,
        uint256 _initialTokenBalance
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _delta, _fee, _spotPrice);

        // transfer initial tokens to pair (if != 0)
        if (_initialTokenBalance != 0) {
            _token.safeTransferFrom(msg.sender, address(_pair), _initialTokenBalance);
        }

        // transfer initial NFTs from sender to pair
        uint256 numNFTs = _initialNFTIDs.length;
        for (uint256 i; i < numNFTs;) {
            _nft.transferFrom(msg.sender, address(_pair), _initialNFTIDs[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _initializePairERC1155ETH(
        LSSVMPairERC1155ETH _pair,
        IERC1155 _nft,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256 _nftId,
        uint256 _initialNFTBalance
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _delta, _fee, _spotPrice);

        // transfer initial ETH to pair
        if (msg.value > 0) payable(address(_pair)).safeTransferETH(msg.value);

        // transfer initial NFTs from sender to pair
        if (_initialNFTBalance != 0) {
            _nft.safeTransferFrom(msg.sender, address(_pair), _nftId, _initialNFTBalance, bytes(""));
        }
    }

    function _initializePairERC1155ERC20(
        LSSVMPairERC1155ERC20 _pair,
        ERC20 _token,
        IERC1155 _nft,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256 _nftId,
        uint256 _initialNFTBalance,
        uint256 _initialTokenBalance
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _delta, _fee, _spotPrice);

        // transfer initial tokens to pair
        if (_initialTokenBalance != 0) {
            _token.safeTransferFrom(msg.sender, address(_pair), _initialTokenBalance);
        }

        // transfer initial NFTs from sender to pair
        if (_initialNFTBalance != 0) {
            _nft.safeTransferFrom(msg.sender, address(_pair), _nftId, _initialNFTBalance, bytes(""));
        }
    }

    /**
     * @dev Used to deposit NFTs into a pair after creation and emit an event for indexing (if recipient is indeed a pair)
     */
    function depositNFTs(IERC721 _nft, uint256[] calldata ids, address recipient) external {
        uint256 numNFTs = ids.length;

        // early return for trivial transfers
        if (numNFTs == 0) return;

        // transfer NFTs from caller to recipient
        for (uint256 i; i < numNFTs;) {
            _nft.transferFrom(msg.sender, recipient, ids[i]);

            unchecked {
                ++i;
            }
        }
        if (isValidPair(recipient) && (address(_nft) == LSSVMPair(recipient).nft())) {
            emit NFTDeposit(recipient, ids);
        }
    }

    /**
     * @dev Used to deposit ERC20s into a pair after creation and emit an event for indexing (if recipient is indeed an ERC20 pair and the token matches)
     */
    function depositERC20(ERC20 token, address recipient, uint256 amount) external {
        // early return for trivial transfers
        if (amount == 0) return;

        token.safeTransferFrom(msg.sender, recipient, amount);
        if (
            isValidPair(recipient) && getPairTokenType(recipient) == PairTokenType.ERC20
                && token == LSSVMPairERC20(recipient).token()
        ) {
            emit TokenDeposit(recipient);
        }
    }

    /**
     * @dev Used to deposit ERC1155 NFTs into a pair after creation and emit an event for indexing (if recipient is indeed a pair)
     */
    function depositERC1155(IERC1155 nft, uint256 id, address recipient, uint256 amount) external {
        if (amount == 0) return;

        nft.safeTransferFrom(msg.sender, recipient, id, amount, bytes(""));

        if (
            isValidPair(recipient) && getPairNFTType(recipient) == PairNFTType.ERC1155
                && address(nft) == LSSVMPair(recipient).nft() && id == LSSVMPairERC1155(recipient).nftId()
        ) {
            emit ERC1155Deposit(recipient, id, amount);
        }
    }
}
