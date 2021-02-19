
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct Account {
    uint256 balance;
    bool frozen;
}

/**
 *
 */
struct PriceMenu {

    IERC20 priceToken;

    // How many tokens it will cost to store one byte worth of content
    uint storageCostPerByte;

    // How many tokens a fisherman that makes a claim that a storage node cannot fulfill receives
    uint fishermanClaimReward;

    // How many tokens opening a claim costs
    uint fishermanClaimPrice;

}

contract StorageCore {

    mapping(address=>Account) accounts;

    PriceMenu[] prices;

    function openAccountForAddress(address owner) public {
        PriceMenu memory pricing = prices[prices.length-1];
    }

    function topUpAccount(address owner) public {

    }

}