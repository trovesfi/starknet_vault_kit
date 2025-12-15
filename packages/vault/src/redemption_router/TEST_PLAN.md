# Redemption Router Test Plan

## Overview
This document outlines comprehensive unit tests for the `RedemptionRouter` contract. Tests will use:
- **Mock Call Cheatcodes**: Use `mock_call` and `start_mock_call` from snforge to mock vault functions
- **RedeemRequest Contract**: Deploy actual `RedeemRequest` contract with dummy vault address
- **Avnu Exchange**: Deploy mock contract from `vault_allocator/src/mocks/mock_avnu_exchange.cairo`
- **ERC20 Tokens**: Use `Erc20Mock` from `vault_allocator/src/mocks/erc20.cairo` for from_asset and to_asset

## Test Setup & Mocking Strategy

### 1. Vault Contract Mocking (using `mock_call`)
- **No mock contract needed** - use `mock_call` cheatcode to mock vault functions
- Mock `due_assets_from_id(id: u256) -> u256`:
  ```cairo
  let due_amount: u256 = 100; // example
  mock_call(VAULT_ADDRESS, selector!("due_assets_from_id"), due_amount, 1);
  ```
- Mock `asset() -> ContractAddress`:
  ```cairo
  mock_call(VAULT_ADDRESS, selector!("asset"), from_asset_address, 1);
  ```
- **Important**: If old NFT is not burnt/claimed, `due_assets_from_id` returns non-zero. If burnt, returns 0.

### 2. RedeemRequest Contract
- **Deploy actual contract** with dummy vault address
- To mint NFT to user (simulate subscription):
  - Cheat caller as vault: `cheat_caller_address(redeem_request_address, VAULT_ADDRESS)`
  - Call `mint(user_address, redeem_request_info)` on redeem_request
  - User approves router: `approve(router_address, nft_id)`
  - User calls `subscribe(nft_id, receiver)` on router
- To burn NFT (simulate claim_redeem completion):
  - Cheat caller as vault: `cheat_caller_address(redeem_request_address, VAULT_ADDRESS)`
  - Call `burn(nft_id)` on redeem_request
  - After burn, `due_assets_from_id` should return 0 (mocked)

### 3. Avnu Exchange Mock
- **Deploy mock contract** from `vault_allocator/src/mocks/mock_avnu_exchange.cairo`
- The mock automatically transfers `sell_token_amount` from caller and `buy_token_min_amount` to beneficiary
- Returns `true` on success

### 4. ERC20 Tokens
- Deploy `Erc20Mock` from `vault_allocator/src/mocks/erc20.cairo` for:
  - `from_asset`: Asset token that vault uses
  - `to_asset`: Target token for swaps
- Mint tokens to router contract for swap operations

### 5. Test Flow Summary

**Setup:**
1. Deploy from_asset and to_asset ERC20 mocks
2. Deploy Avnu exchange mock
3. Deploy redeem_request with dummy vault address
4. Deploy redemption_router with all addresses
5. Set up roles (grant RELAYER_ROLE)

**Simulating User Subscription:**
1. Cheat caller as vault → mint NFT to user via redeem_request
2. User approves router for NFT
3. User calls `subscribe(nft_id, receiver)` on router
4. Router transfers old NFT and mints new NFT

**Simulating Swap (after subscription):**
1. First, fulfill the old NFT (simulate claim_redeem):
   - Transfer vault assets to router (from_asset tokens)
   - Cheat caller as vault → burn old NFT on redeem_request
   - Mock `due_assets_from_id` to return 0 for this NFT (since it's burnt)
2. Router has from_asset balance
3. Relayer calls `swap()` with routes and amounts
4. Mock Avnu transfers tokens appropriately

**Simulating Claim:**
1. Ensure old NFT is fulfilled (burnt on redeem_request)
2. Mock `due_assets_from_id` for the old NFT with the amount user was owed (even though NFT is burnt, this represents historical due amount)
3. User calls `claim(new_nft_id)` on router
4. Router calls `vault.due_assets_from_id(old_nft_id)` - this should return the mocked amount
5. Router iterates pools and transfers proportional to_asset to user

**Important**: The router's `claim` function calls `vault.due_assets_from_id(old_nft_id)` to determine what the user was owed. Even if the old NFT is burnt, we need to mock this to return the historical due amount so the router can calculate proportional swap amounts correctly.

---

## Test Categories

### 1. Constructor & Initialization Tests

#### `test_constructor_initializes_correctly`
- Verify all addresses are stored correctly
- Verify roles are set (OWNER_ROLE, RELAYER_ROLE)
- Verify `swap_id` and `unsettled_swap_id` start at 1
- Verify `nft_id_counter` starts at 0
- Verify `min_subscribe_amount` is set correctly
- Verify `last_settled_epoch` is initialized from vault's `handled_epoch_len`
- Verify NFT contract initialized with name "RedemptionRouter", symbol "RR"

#### `test_constructor_reverts_on_zero_addresses`
- Test each address parameter (vault, redeem_request, to_asset, avnu_exchange, integrator_fee_recipient)
- Verify appropriate error is raised

---

### 2. Subscribe Function Tests

#### `test_subscribe_transfers_old_nft_and_mints_new`
- User subscribes with old NFT ID
- Verify old NFT transferred from user to router
- Verify new NFT minted to receiver
- Verify `new_nft_request_map` stores correct `old_nft_id` and `is_claimed = false`
- Verify `Subscribed` event emitted

#### `test_subscribe_increments_nft_counter`
- Multiple subscriptions
- Verify NFT IDs are sequential (0, 1, 2, ...)

#### `test_subscribe_reverts_when_paused`
- Pause contract
- Attempt subscribe
- Verify revert

#### `test_subscribe_reverts_on_too_small_amount`
- Set `min_subscribe_amount` to 100
- Attempt subscribe with NFT that has `due_amount` < 100
- Verify `too_small_subscribe_amount` error

#### `test_subscribe_snapshots_epoch_data`
- Subscribe with NFT from epoch 5
- Verify `epoch_redeem_assets` and `epoch_redeem_nominal` are stored for epoch 5
- Verify `epoch_offset_factor` defaults to WAD if not set
- Verify `epoch_wise_nominals` accumulates nominal amount

---

### 3. Swap Function Tests

#### `test_swap_executes_successfully`
- Router has balance of from_asset
- Execute swap
- Verify Avnu `multi_route_swap` called with correct parameters
- Verify `swap_info` stores `(from_amount, to_amount)` correctly
- Verify `swap_id` increments
- Verify `Swapped` event emitted with `swap_id`, `from_amount`, `to_amount`, and `last_settled_epoch`
- Verify epochs are settled correctly based on `from_amount`

#### `test_swap_reverts_on_insufficient_balance`
- Router has insufficient from_asset balance
- Attempt swap
- Verify `insufficient_from_amount` error

#### `test_swap_reverts_when_not_relayer`
- Non-relayer attempts swap
- Verify access control revert

#### `test_swap_reverts_when_paused`
- Pause contract
- Attempt swap
- Verify revert

#### `test_swap_reverts_on_avnu_failure`
- Mock Avnu returns `false`
- Verify `swap_failed` error

#### `test_swap_uses_actual_received_amount`
- Mock Avnu returns different amount than `min_amount_out`
- Verify `swap_info` stores actual received amount (balance_delta)

---

### 4. Basic Claim Scenarios

#### `test_claim_single_subscribe_single_swap_single_claim`
- 1 subscribe → 1 swap → 1 claim
- Verify user receives correct proportional amount: `due_assets * to_amount / from_amount`
- Verify NFT burned
- Verify `is_claimed = true`
- Verify `Claimed` event emitted with `new_nft_id`, `old_nft_id`, `receivable`, and `swap_id`
- Verify pool fully consumed, `unsettled_swap_id` advances

#### `test_claim_two_subscribes_one_swap_two_claims`
- 2 subscribes → 1 swap → 2 claims
- User 1 due: 100, User 2 due: 200, Swap: 300 from → 600 to
- Verify User 1 gets: 100 * 600 / 300 = 200
- Assert remaining swap info is updated correctly, correct all swap IDs
- Verify User 2 gets: 200 * 600 / 300 = 400
- Verify both claims succeed (both epochs must be settled)
- Verify pool fully consumed after both claims

#### `test_claim_requires_epoch_settled`
- User subscribes to epoch 5
- Execute swap but epoch 5 not fully settled yet
- Attempt to claim
- Verify `claim_not_allowed` error
- Complete epoch settlement
- Now claim should succeed

---

### 5. Multi-Pool Claim Scenarios

#### `test_claim_spans_multiple_pools_single_user`
- User subscribes with due: 500
- Swap 1: 200 from → 400 to
- Swap 2: 300 from → 600 to
- Claim should drain:
  - From pool 1: 200 from → 400 to
  - From pool 2: 300 from → 600 to
- Verify total received: 1000
- Verify both pools consumed
- Verify `unsettled_swap_id` advances to 3

#### `test_claim_partial_pool_consumption`
- User 1 subscribes with due: 100
- User 2 subscribes with due: 200
- Swap 1: 300 from → 600 to
- Claim User 1: Takes 100 from → 200 to, pool remains (200 from, 400 to)
- Claim User 2: Takes remaining 200 from → 400 to, pool emptied
- Verify User 1 gets 200, User 2 gets 400
- Verify pool state updated correctly after each claim

#### `test_claim_multiple_swaps_before_claims`
- 4 subscribes (User 0-3)
- Swap 1: 100 from → 200 to
- Swap 2: 200 from → 400 to
- Swap 3: 300 from → 600 to
- All users have due: 150 each
- Claims in order:
  - User 0: 100 from pool 1 (100 from → 200 to), 50 from pool 2 (50 from → 100 to) = 300 total
  - User 1: 50 from pool 2 (50 from → 100 to), 100 from pool 3 (100 from → 200 to) = 300 total
  - User 2: 200 from pool 3 (200 from → 400 to) = 400 total
  - User 3: Claims from remaining pools
- Verify each user gets correct proportional amounts
- Verify pools consumed in order

---

### 6. Fairness Scenarios (Different Due Amounts)

#### `test_fairness_different_vault_due_amounts`
- User A subscribes: vault due = 100
- User B subscribes: vault due = 99 (reporting loss)
- Swap: 199 from → 398 to (2:1 ratio)
- Claim User A: 100 * 398 / 199 = 200
- Claim User B: 99 * 398 / 199 = 198 (rounded down)
- Verify User B gets exactly 99/100 of User A's amount
- Verify fairness: User B gets less because they received less from vault

#### `test_fairness_across_multiple_pools`
- User A: due = 100
- User B: due = 50
- Swap 1: 50 from → 100 to (for User B)
- Swap 2: 100 from → 200 to (for User A)
- Claim User A: 100 from pool 2 → 200
- Claim User B: 50 from pool 1 → 100
- Verify User B gets exactly half of User A (proportional)

#### `test_fairness_with_rounding_dust`
- User A: due = 100
- User B: due = 100
- Swap: 199 from → 399 to (rounding will leave dust)
- Claim User A: 100 * 399 / 199 = 200 (rounded)
- Claim User B: 99 * 399 / 199 = 198 (rounded)
- Verify remaining dust stays in pool or goes to last claimer
- Verify no value leakage

---

### 7. Complex Ordering Scenarios

#### `test_complex_ordering_4_subscribes_2_swaps_4_claims`
- Subscribe 4 NFTs (IDs 0-3)
- Swap 1: 200 from → 400 to (intended for NFTs 2-3, but available globally)
- Swap 2: 200 from → 400 to (intended for NFTs 0-1, but available globally)
- Claims in original sequence (0, 1, 2, 3):
  - NFT 0: Claims from pool 1 (global head), drains 200 → 400
  - NFT 1: Claims from pool 2 (next), drains 200 → 400
  - NFT 2: Claims from pool 1 (if still available) or pool 2
  - NFT 3: Claims from remaining pools
- Verify all claims succeed sequentially
- Verify users get proportional amounts based on their vault due

#### `test_swaps_between_subscribes`
- Subscribe NFT 0
- Swap 1: 100 from → 200 to
- Subscribe NFT 1
- Swap 2: 100 from → 200 to
- Subscribe NFT 2
- Claim NFT 0: Gets from pool 1
- Claim NFT 1: Gets from pool 2 (if pool 1 drained) or pool 1 (if available)
- Claim NFT 2: Gets from remaining pools
- Verify sequential claiming still works

#### `test_claims_after_multiple_swaps`
- Subscribe 3 NFTs
- Swap 1: 100 from → 200 to
- Swap 2: 100 from → 200 to
- Swap 3: 100 from → 200 to
- Claim NFT 0: Drains pool 1 entirely or partially
- Claim NFT 1: Continues from where NFT 0 left off
- Claim NFT 2: Continues from remaining pools
- Verify global head advances correctly

---

### 8. Edge Cases

#### `test_claim_with_zero_due_assets`
- User subscribes but vault returns 0 due (mock `due_assets_from_id` to return 0)
- Attempt claim
- Verify `invalid_nft_id` error

**Note**: This can happen if old NFT is already burnt but router hasn't processed it yet

#### `test_claim_when_no_swaps_exist`
- Subscribe NFT
- Fulfill old NFT (burn it, mock due_assets = 0)
- Mock `due_assets_from_id` to return desired amount
- Attempt claim before any swaps
- Verify claim succeeds but returns 0 (no pools available, but old NFT is valid)

#### `test_claim_insufficient_pools`
- User subscribes with due: 1000
- Fulfill old NFT (burn it)
- Mock `due_assets_from_id` to return 1000
- Swap: 100 from → 200 to
- Attempt claim
- Verify claim succeeds but only gets 200 (from available pool)
- Verify user can claim remaining 900 in future when more swaps occur

#### `test_claim_empty_pools_skipped`
- Swap 1: 100 from → 200 to (fully consumed)
- Swap 2: 100 from → 200 to (fully consumed)
- Swap 3: 100 from → 200 to (available)
- User subscribes and claims
- Verify skips empty pools 1 and 2, uses pool 3
- Verify `unsettled_swap_id` advances correctly

#### `test_claim_invalid_nft_id`
- Attempt claim with non-existent NFT
- Verify `invalid_old_nft_id` error

#### `test_claim_already_claimed_nft`
- Subscribe and claim NFT
- Attempt claim again
- Verify `nft_already_claimed` error (from `_validate_request_info`)

#### `test_claim_reverts_on_insufficient_to_asset_balance`
- Subscribe and swap successfully
- Router has insufficient to_asset balance
- Attempt claim
- Verify `insufficient_balance_for_withdrawal` error

---

### 9. Unsubscribe Function Tests

#### `test_unsubscribe_original_nft_not_fulfilled`
- User subscribes
- Original NFT not fulfilled (router still owns it)
- Epoch not settled
- Call `unsubscribe(nft_id, receiver)`
- Verify original NFT transferred to receiver
- Verify new NFT burned
- Verify `Unsubscribed` event with `is_old_nft_returned = true`
- Verify `is_original_assets_returned = false`

#### `test_unsubscribe_original_nft_fulfilled`
- User subscribes
- Original NFT fulfilled (burnt on redeem_request)
- Epoch not settled
- Router has from_asset balance
- Call `unsubscribe(nft_id, receiver)`
- Verify from_asset transferred to receiver (proportional to user's share)
- Verify new NFT burned
- Verify `Unsubscribed` event with `is_old_nft_returned = false`
- Verify `is_original_assets_returned = true` and `original_assets_returned` amount

#### `test_unsubscribe_reverts_when_epoch_settled`
- User subscribes
- Epoch fully settled
- Attempt unsubscribe
- Verify `cannot_unsubscribe_partial_swap` error

#### `test_unsubscribe_reverts_when_partial_settlement`
- User subscribes
- Original NFT fulfilled
- Epoch partially settled (some swaps occurred)
- Attempt unsubscribe
- Verify `cannot_unsubscribe_partial_swap` error

#### `test_unsubscribe_reverts_when_not_owner`
- User subscribes
- Another user attempts to unsubscribe
- Verify `not_owner` error (router must own the NFT)

#### `test_unsubscribe_reverts_on_insufficient_balance`
- User subscribes
- Original NFT fulfilled
- Router has insufficient from_asset balance
- Attempt unsubscribe
- Verify `insufficient_balance_for_withdrawal` error

#### `test_unsubscribe_reverts_when_paused`
- Pause contract
- Attempt unsubscribe
- Verify revert

---

### 10. Access Control & Authorization Tests

#### `test_set_integrator_fee_recipient_only_owner`
- Non-owner attempts to set fee recipient
- Verify revert

#### `test_set_integrator_fee_amount_bps_only_owner`
- Non-owner attempts to set fee BPS
- Verify revert

#### `test_set_integrator_fee_recipient_zero_address`
- Owner attempts to set zero address
- Verify `zero_address` error

#### `test_set_min_subscribe_amount_only_owner`
- Non-owner attempts to set min subscribe amount
- Verify revert

#### `test_set_epoch_offset_only_relayer`
- Non-relayer attempts to set epoch offset
- Verify revert

#### `test_swap_only_relayer`
- Non-relayer attempts swap
- Verify access control revert

#### `test_report_only_relayer`
- Non-relayer attempts report
- Verify access control revert

---

#### `test_subscribe_reverts_when_paused`
- Pause contract
- Attempt subscribe
- Verify revert

#### `test_swap_reverts_when_paused`
- Pause contract
- Attempt swap
- Verify revert

#### `test_claim_reverts_when_paused`
- Pause contract
- Attempt claim
- Verify revert

---

### 11. Pausable Tests

#### `test_subscribe_reverts_when_paused`
- Pause contract
- Attempt subscribe
- Verify revert

#### `test_swap_reverts_when_paused`
- Pause contract
- Attempt swap
- Verify revert

#### `test_claim_reverts_when_paused`
- Pause contract
- Attempt claim
- Verify revert

#### `test_unsubscribe_reverts_when_paused`
- Pause contract
- Attempt unsubscribe
- Verify revert

---

### 14. Integration Flow Tests

#### `test_full_redemption_flow`
- User requests redemption from vault (mock)
- User subscribes to router with redemption NFT
- Relayer swaps assets
- User claims swapped assets
- Verify entire flow works end-to-end

#### `test_batch_redemption_flow`
- Multiple users subscribe
- Multiple swaps executed
- All users claim in sequence
- Verify all receive correct proportional amounts

#### `test_unsubscribe_flow`
- User subscribes
- User changes mind and unsubscribes before epoch settled
- Verify original NFT or assets returned correctly

### 12. View Function Tests

#### `test_view_functions_return_correct_values`
- Test all view functions:
  - `vault()`, `redeem_request()`, `to_asset()`, `avnu_exchange()`
  - `integrator_fee_recipient()`, `integrator_fee_amount_bps()`
  - `swap_id()`, `unsettled_swap_id()`
  - `new_nft_request_info()`, `swap_info()`
  - `last_settled_epoch()`, `epoch_settled_amounts(epoch)`
  - `expected_receivable(nft_id)`, `last_nft_id()`
- Verify all return expected values

---

### 13. Epoch Settlement & Sync Tests

#### `test_settle_epochs_from_amount`
- Multiple users subscribe to different epochs
- Execute swap with from_amount
- Verify epochs are settled in order (skipping epochs without subscriptions)
- Verify `epoch_settled_amounts` updated correctly
- Verify `last_settled_epoch` updated

#### `test_settle_epochs_skips_empty_epochs`
- Users subscribe to epochs 1, 3, 5 (epochs 2, 4 have no subscriptions)
- Execute swap
- Verify epochs 1, 3, 5 are settled
- Verify epochs 2, 4 are skipped

#### `test_sync_settled_epochs`
- Multiple epochs with subscriptions
- Some epochs fully settled, some partially settled
- Call `sync_settled_epochs(max_epochs_to_check)`
- Verify `last_settled_epoch` updated to highest fully settled epoch
- Verify respects `max_epochs_to_check` limit

#### `test_sync_settled_epochs_with_limit`
- Many epochs to check
- Call `sync_settled_epochs(10)` to limit to 10 epochs
- Verify only checks up to 10 epochs
- Verify doesn't run out of gas

#### `test_sync_settled_epochs_reverts_when_paused`
- Pause contract
- Attempt sync_settled_epochs
- Verify revert

---

### 14. Integration Flow Tests

#### `test_full_redemption_flow`
- User requests redemption from vault (mock)
- User subscribes to router with redemption NFT
- Relayer swaps assets
- User claims swapped assets
- Verify entire flow works end-to-end

#### `test_batch_redemption_flow`
- Multiple users subscribe
- Multiple swaps executed
- All users claim in sequence
- Verify all receive correct proportional amounts

#### `test_unsubscribe_flow`
- User subscribes
- User changes mind and unsubscribes before epoch settled
- Verify original NFT or assets returned correctly

---

## Test Utilities Needed

### Helper Functions
- `deploy_redemption_router()`: Deploy router with all dependencies (vault, redeem_request, to_asset, avnu_exchange addresses, integrator_fee_recipient, integrator_fee_amount_bps, min_subscribe_amount)
- `deploy_redeem_request(dummy_vault_address)`: Deploy actual RedeemRequest contract
- `deploy_mock_avnu_exchange()`: Deploy mock Avnu exchange from vault_allocator mocks
- `deploy_erc20_mock(name, symbol, initial_supply)`: Deploy ERC20 mock for from_asset/to_asset
- `setup_test_environment()`: Complete test setup with all contracts
- `execute_unsubscribe(router, nft_id, receiver)`: Helper to execute unsubscribe (requires router to own NFT)
- `mint_old_nft_to_user(user, redeem_request_info)`: 
  - Cheat caller as vault
  - Mint NFT to user via redeem_request.mint()
  - Return minted NFT ID
- `fulfill_old_nft(old_nft_id, asset_amount)`:
  - Transfer asset_amount from vault to router (from_asset tokens)
  - Cheat caller as vault → burn old NFT on redeem_request
  - Mock `due_assets_from_id` to return 0 (since NFT is burnt)
- `mock_vault_due_assets(old_nft_id, amount)`: 
  - Use `mock_call` to set `due_assets_from_id` return value
  - Use `mock_call(VAULT_ADDRESS, selector!("due_assets_from_id"), amount, 1)`
- `mock_vault_asset(asset_address)`: 
  - Use `mock_call` to set `asset()` return value
- `execute_swap(router, from_amount, to_amount, routes)`: Helper to execute swap (requires relayer role)

---

## Test File Structure

```
packages/vault/src/redemption_router/
└── test/
    └── redemption_router_test.cairo

packages/vault_allocator/src/mocks/
├── mock_avnu_exchange.cairo  (for Avnu exchange mocking)
├── erc20.cairo  (for ERC20 token mocking)
└── (other existing mocks)
```

## Mock Call Cheatcode Reference

From [Starknet Foundry Documentation](https://foundry-rs.github.io/starknet-foundry/appendix/cheatcodes/mock_call.html):

- `mock_call<T>(contract_address, function_selector, ret_data, n_times)`: Mock a function call for `n_times` calls
- `start_mock_call<T>(contract_address, function_selector, ret_data)`: Mock a function call indefinitely
- `stop_mock_call(contract_address, function_selector)`: Stop mocking a function

Example usage:
```cairo
use snforge_std::{mock_call, start_mock_call, stop_mock_call};

// Mock due_assets_from_id to return 100 for 1 call
let due_amount: u256 = 100;
mock_call(VAULT_ADDRESS, selector!("due_assets_from_id"), due_amount, 1);

// Mock asset() indefinitely
start_mock_call(VAULT_ADDRESS, selector!("asset"), from_asset_address);
```

---

## Notes

1. **Epoch-Based Claiming**: Claims require the epoch to be fully settled. Users can only claim after their epoch is settled.
2. **Global Head**: All claims start from `unsettled_swap_id` (global head)
3. **Fairness**: Users with less vault due should get proportionally less swapped assets
4. **Rounding**: Use floor rounding for calculations, verify no value leakage
5. **Events**: Verify all events are emitted with correct parameters:
   - `Subscribed`: `new_nft_id`, `old_nft_id`, `receiver`
   - `Swapped`: `swap_id`, `from_amount`, `to_amount`, `last_settled_epoch`
   - `Claimed`: `new_nft_id`, `old_nft_id`, `receivable`, `swap_id`
   - `Unsubscribed`: `new_nft_id`, `old_nft_id`, `owner`, `is_old_nft_returned`, `is_original_assets_returned`, `original_assets_returned`
6. **State Updates**: Verify storage is updated correctly after each operation
7. **Mock Call Limitations**: 
   - `mock_call` only works for entry point calls, not internal calls
   - Use `n_times = 1` for single-call scenarios, or `start_mock_call` for indefinite mocking
   - Remember to mock `due_assets_from_id` AFTER burning old NFT (should return 0) or BEFORE (should return desired amount)
8. **Old NFT State & Due Assets Mocking**: 
   - **During subscription**: Old NFT exists, not burnt yet. `due_assets_from_id` returns non-zero (used for validation)
   - **After fulfillment**: Old NFT is burnt on redeem_request (vault called `burn`). 
   - **During claim**: Router calls `vault.due_assets_from_id(old_nft_id)` to get what user was owed. 
     - **Mock this** to return the historical due amount (e.g., 100 tokens) even though NFT is burnt
     - This represents "what was the user owed before redemption was fulfilled"
     - Router uses this to calculate proportional swap amounts
   - If old NFT is NOT burnt and we try to claim: Mock `due_assets_from_id` to return non-zero
   - If old NFT IS burnt and we try to claim: Mock `due_assets_from_id` to return the historical amount (not 0, unless user was owed 0)
9. **Test Flow Order**:
   - Setup contracts → Mint old NFT to user → User subscribes → Fulfill old NFT (burn) → Execute swaps → Mock `due_assets_from_id` with historical amount → Claim
10. **Epoch Settlement**: 
    - Epochs are settled in order (1, 2, 3...), but only epochs with subscriptions matter
    - Epochs without subscriptions are skipped
    - `last_settled_epoch` tracks the highest fully settled epoch (may not be sequential)
11. **Unsubscribe**: 
    - Requires router to own the NFT (not the original subscriber)
    - Returns original NFT if not fulfilled, or from_assets if fulfilled
    - Cannot unsubscribe if epoch is settled or partially settled
12. **Min Subscribe Amount**: 
    - Subscriptions below `min_subscribe_amount` are rejected to save gas
    - Set by owner via `set_min_subscribe_amount`

