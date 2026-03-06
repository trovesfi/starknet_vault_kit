# Redemption Router Integration Guide

This guide explains how to integrate the Redemption Router contract for both backend services (relayers/indexers) and frontend applications.

## Table of Contents

- [Overview](#overview)
- [Backend Integration](#backend-integration)
  - [Indexing Pending Subscriptions](#indexing-pending-subscriptions)
  - [Checking Epoch Settlement Status](#checking-epoch-settlement-status)
  - [Executing Swaps](#executing-swaps)
  - [Processing Claims](#processing-claims)
- [Frontend Integration](#frontend-integration)
  - [Request Redeem and Subscribe (Multicall)](#request-redeem-and-subscribe-multicall)
  - [Checking Subscription Status](#checking-subscription-status)
  - [Unsubscribing](#unsubscribing)
  - [Claiming Redeemed Assets](#claiming-redeemed-assets)

## Overview

The Redemption Router allows users to:
1. **Subscribe** their redemption NFTs to receive assets in a different token (`to_asset`) instead of the vault's native asset
2. **Claim** their swapped assets once epochs are settled and swaps are executed
3. **Unsubscribe** if they want to opt out before settlement

Backend services (relayers) are responsible for:
- Monitoring pending subscriptions
- Executing swaps when epochs are settled
- Managing the swap pool

## Reporting
For simplicity, its recommended to call report function on vault contract via this contract. Else, its important to set the epoch offset factor for each epoch before calling swap. 

Note: Until audit of RR, our (Troves team) backend shall follow manually setting epoch offset factor for each epoch before calling swap. This is to avoid transfering oracle permission to RR for vaults already in production.

## Backend Integration

### Indexing Pending Subscriptions

To track pending subscriptions, you need to index the `Subscribed` event emitted by the Redemption Router contract.

#### You could use apibara to index events. 
```

#### Decoding Subscribed Event

The `Subscribed` event has the following structure:
```cairo
Subscribed {
    new_nft_id: u256,
    old_nft_id: u256,
    receiver: ContractAddress,
}
```

Store this information in your database to track pending subscriptions.

Additionally, more events to track:
1. Claimed
```cairo
Claimed {
    new_nft_id: u256,
    old_nft_id: u256,
    receivable: u256,
    swap_id: u256,
}
```
2. Unsubscribed
```cairo
Unsubscribed {
    new_nft_id: u256,
    old_nft_id: u256,
    owner: ContractAddress,
    is_old_nft_returned: bool,
    is_original_assets_returned: bool,
    original_assets_returned: u256,
}
```

### Checking Epoch Settlement Status

Before executing swaps, you need to check where required epochs are already handled by the vault. An epoch is considered "handled" when the vault has handled it (i.e., `epoch < vault.handled_epoch_len()`).

Get above info by calling vault contract.

#### Key Functions to Monitor

- `vault.handled_epoch_len()` - Returns the number of handled epochs
- `router.last_settled_epoch()` - Returns the highest fully settled epoch in router (i.e. assets swapped and ready for claims)
- `router.epoch_settled_amounts(epoch)` - Returns how much of an epoch has been settled (i.e. swapped from asset)
- `router.epoch_offset_factor(epoch)` - Returns the offset factor for an epoch (defaults to WAD) (i.e. nft shares to asset conversion factor. precisely, final assets / shares settled for which can vary in a epoch due to epoch level vault losses)


### Swapping
Read the balance of the redemption router contract of the from asset (i.e. vault asset). You can have some min check, but if enough balance is available, you can proceed to swap. Ensure you add sufficient min amoutn out checks. 

Call `router.swap(routes: Array<Route>, from_amount: u256, min_amount_out: u256)` to swap the assets.  
Can get routes from Avnu. 

#### Monitoring Swap Pool

The router maintains a swap pool that users claim from. Monitor:
- Swap accounting is epoch-scoped via `epoch_swap_pool` internally. Per-swap pool views are removed.

### Processing Claims

Users can claim their assets once their epoch is settled. To settle NFTs, you use the Claimed event to check events which are still pending. Query them, order them by epoch (asc). If epoch is settled, you can claim the assets.

Call `router.claim(nft_id)` to claim the assets.

## Frontend Integration

### Request Redeem and Subscribe (Multicall)

To provide a seamless UX, combine `vault.request_redeem()` and `router.subscribe()` in a single multicall transaction.

1. Read next NFT ID to mint (i.e. `redeem_request.id_len()`)
2. Create a redeem request on vault (i.e. `vault.request_redeem(shares, receiver, user_address)`)
3. Approve the NFT to RR (i.e. `redeem_request.approve(router_address, nft_id)`)
4. Subscribe to the router (i.e. `router.subscribe(nft_id, receiver)`)

Put all above 3 steps into a single starknet multicall transaction.

In rare cases, the step 1 might cause race condition, in that case, simply retrying the transaction should work. 

## Unsubscribing
In case the router couldnt settle the funds in to_asset or its taking time, users might want to unsubscribe.

Users can unsubscribe in two ways:
1. **`unsubscribe_for_nft`** - Get back the original redemption NFT (if epoch not settled)
2. **`unsubscribe_for_underlying`** - Get back the underlying assets proportional to their share (only possible if router assets are not fully settled for the epoch. Even partial swap shall prevent this, in such a case, users must wait for their funds to be fully swapped). 

### How to decide which function to call?
- Call `vault.due_assets_from_id(old_nft_id)` to get the due assets for the NFT. If returns non-zero, call `unsubscribe_for_nft`. If the call fails or returns 0, call `unsubscribe_for_underlying`.
- The `unsubscribe_for_underlying` shall only work if epoch is not settled. Call `router.epoch_settled_amounts(epoch)`, if returns 0, you can proceed. Else better to inform users to wait as swapping has already started and is in progress. 