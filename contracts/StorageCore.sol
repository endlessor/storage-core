
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

struct Account {
    uint256 balance;
    bool frozen;
    bool created;
}

/**
 * A pricing in one point of time.
 *
 * Owner can reset the pricing and all storage contracts refer to a historical pricing
 * they had when the storage contract was created.
 */
struct Pricing {

    IERC20 priceToken;

    // How many tokens it will cost to store one byte worth of content
    uint storageCostPerByte;

    // How many tokens a fisherman that makes a claim that a storage node cannot fulfill receives
    uint fishermanClaimReward;

    // How many tokens opening a claim costs
    uint fishermanClaimPrice;

}

contract StorageCore is Ownable {

    mapping(address=>Account) accounts;

    PriceMenu[] prices;

    event AccountCreated(address owner);
    event AccountToppedUp(address owner, amount);

    /**
     * Create a new account. Allocate initial balance to the account.
     */
    function openAccountForAddress(address owner, uint amount) public {
        if(!accounts[owner].created) {
            accounts[owner].created = true;
            emit AccountCreated(owner);
        }

        topUpAccount(owner, amount);
    }

    /**
     * Process incoming protocol tokens and add them on an account.
     */
    function topUpAccount(address owner, uint amount) public {
        PriceMenu memory pricing = prices[prices.length-1];
        token = pricing.token;
        requrire(token.transferFrom(msg.sender, address(this), amount) == true, "Could not top up");
    }

    function setPricing(Pricing pricing) public onlyOwner {
        prices[prices.length] = pricing;
    }

}