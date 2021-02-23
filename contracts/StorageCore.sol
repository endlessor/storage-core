
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/**
 * An account holds balance in the protocol.
 *
 * We have top level address => Accout mappings in the controller.
 */
struct Account {

    // How many tokens of balance this account has
    uint256 balance;

    // In which state is this account
    AccountState state;
}

/**
 * One host that has volunteered as a storage node.
 *
 * We cheat here - we do not have a true P2P network in
 * POC, but each host registers itself on a blockchain directly.
 */
struct StorageHost {

    // Address the node uses to sign the traffic
    address hostAddress;

    // Separate wallet where any earnings going
    address payoutAddress;

    // 128 bit for IPv6 address and 16 bit for the port
    uint144[] ipAddresses;

    // How many claims this node has failed during its lifetime
    uint16 failedClaims;

    // Host terminates itself.
    // There won't be further claims against this host.
    // The host needs to restart itself.
    uint64 voluntarilyTerminatedAt;
}

/**
 * Abstract away rent payer.
 *
 * Instead of having hard addresses who is paying the rent for the data,
 * have an abstraction over it so that a rent payer can be more easily
 * changed, updated and topped up.
 *
 * This enables high level account owner transferships for multiple
 * data items at once.
 */
struct RentPayer {

    uint128 rentPayerId;

    // From which account we transfer balance for storage nodes that are
    // taking care of data
    address activePayerAccount;

    // A rent payer may voluntarily terminate paying of any data prematurely.
    // In this case there is a quarantive periof 6 months for anyone
    // else to take over the hosting agreements.
    uint64 voluntarilyTerminatedAt;

    // How many tokens this payer has currently on active rent contracts
    uint256 allocatedTokens;

    // How many tokens this payer has currently available to pay new rent
    uint256 unallocatedTokens;

    // How many tokens this account has topped up over its lifetime
    uint256 totalTokens;
}

/**
 * A pricing in one point of time.
 *
 * Owner can reset the pricing and all storage contracts refer to a historical pricing
 * they had when the storage contract was created.
 */
struct Pricing {

    // Which token
    IERC20 priceToken;

    // How many tokens it will cost to store one byte worth of content
    uint storageCostPerBytePerDay;

    // How many tokens a fisherman that makes a claim that a storage node cannot fulfill receives
    uint fishermanClaimReward;

    // How many tokens opening a claim costs
    uint fishermanClaimPrice;

}

/**
 * A contract to to pay hosting for one file.
 *
 */
struct DataItem {

    // Smart contract or EOA that can request deletion of this data
    address contentOwner;

    // An account that pays the rent
    // This is an indirect reference - it does not map to an address
    // because we want to make it possible to have mutable rent payer
    // for multiple contracts
    uint128 rentPayer;

    // The id of Pricing used to negotiated rent for this data
    uint32 pricingId;

    // sha256 of the content
    bytes32 contentHash;

    // For better indexing of the content
    // The mask is formed as
    // 1. byte = application id
    // 2-30 bytes = reserved for application use
    // 31 byte = content type
    uint256 mask;

    // How many bytes is the data
    uint64 size;

    // When this item was created.
    // This will tell the rounds for claiming rewards for this data.
    uint64 createdAt;

    // When the rent for this data runs out
    uint64 endsAt;

    // Rent payer or content owner voluntarily deletes this item
    uint64 endedAt;

    // Storage hosts that are volunteered to host this content
    uint128 storageHosts;
}

contract StorageCore is Ownable {


    enum AccountState {

        Unknown,

        // Account in a normal state
        Active,

        // If account is frozen through a governance then only way to move out its balance is through governance.
        // Data renting fees still run out from this account, but it cannot rent.
        Frozen,

        // All data related to this account must be destroyed. Account is asking this voluntary or delete is through governance action.
        Destroyed
    }


    /**
    * Common content types used in the mask of the data.
    *
    * This is used as the last byte of DataItem mask to allow easy analysis of content of the protocol.
    * This is rough categorisation - it should only give enough hints so that a content sniffer
    * can have an educated guess what kind of data it is.
    *
    * See https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types/Common_types
    */
    enum ContentType {

        // Default - the protocol user does not tell
        Unknown,

        // Any that maps as image/* mime type
        Image,

        // Any that maps as audio/* mime type
        Audio,

        // Any that maps as video/* mime type
        Video,

        // Any that maps as text/* mime type.
        // Popular choices include text/plain and text/html
        Text,

        // JSON based data
        JSON

    }

    mapping(address=>Account) accounts;

    mapping(bytes32=>DataItem) data;

    mapping(address=>uint128) rentPayers;

    // Active and historical prices.
    // The active price is always the last item on the lsit.
    Pricing[] prices;

    event AccountCreated(address owner);
    event AccountToppedUp(address owner, amount);

    event DataStored(bytes32 contentHash, uint256 mask);

    /**
     * Create a new account. Allocate initial balance to the account.
     *
     * Each account opening must come with a balance of tokens attached to get started.
     */
    function openAccount(address owner) public {
        require(!accounts[owner].created, "Account already exists");

        accounts[owner].created = true;
        emit AccountCreated(owner);
    }

    /**
     * Process incoming protocol tokens and add them on an account.
     */
    function topUpRentPayer(uint128 rentPayerId) public {
        Pricing memory pricing = prices[prices.length-1];
        token = pricing.token;
        require(token.transferFrom(msg.sender, address(this), amount) == true, "Could not top up");
    }

    /**
     * Protocol governance can set the pricing deal for all new data.
     */
    function setPricing(Pricing pricing) public onlyOwner {
        prices[prices.length] = pricing;
    }

    /**
     * How many tokens cost renting data for certain time.
     *
     * Allow calculate historical pricing as well.
     */
    function getStorageCost(uint65 size, uint32 durationAsDays, uint32 pricingId) public view returns (uint256 tokenAmount) {
        Pricing memory pricing = prices[pricingId];
        return pricing.storageCostPerBytePerDay * size * durationAsDays;
    }

    /**
     * Get the storage cost of bytes with the current pricing.
     */
    function getCurrentPricingInfo(uint65 size, uint32 durationAsDays) public view returns (IERC20 token, uint256 tokenAmount) {
        uint32 pricingId = prices.length-1;
        return (prices[pricingId].token, getStorageCost(size, durationAsDays, pricingId));
    }

    /**
     * For an account get a rent payer currently active.
     */
    function getActiveRentPayer(address owner) public view returns(uint128 rentPayerId) {

    }

    /**
     * Allocate rent for data.
     *
     * If the rent payer has enough tokens to create a rent contract, then
     * someone can proceed to upload the data to the first storage node.
     */
    function storeData(bytes32 contentHash, uint256 mask, uint64 size, uint32 durationAsDays, address owner) public {

        uint128 rentPayer = getActiveRentPayer(msg.sender);

        // Use active pricing
        uint32 activePricingId = prices.length - 1;

        uint256 cost = getStorageCost(size, size, activePricingId);

        data[contentHash].size = size;
        data[contentHash].createdAt = now;
        data[contentHash].pricingId = activePricingId;
        data[contentHash].contentOwner = owner;

        _allocateTokensForData(rentPayerId, cost, contentHash);

        emit DataStored(contentHash, mask);
    }

    function _allocateTokensForData(uint128 rentPayerId, uint256 cost, uint256 contentHash) private {
        require(rentPayer[rentPayerId].unallocatedTokens >= cost, "Not enough tokens");
        rentPayer[rentPayerId].unallocatedTokens -= cost;
        rentPayer[rentPayerId].allocatedTokens += cost;

    }
}