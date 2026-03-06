// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::ContractAddress;
use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;

#[derive(Drop, Copy, starknet::Store, Serde, starknet::Event)]
pub struct RequestInfo {
    pub old_nft_id: u256,
    pub is_claimed: bool,
    pub epoch: u256,
    pub nominal: u256,
    pub due_amount_approximate: u256,
    pub unsubscribed: bool, // if true, the original NFT has been unsubscribed
}

#[starknet::interface]
pub trait IRedemptionRouter<TContractState> {
    fn subscribe(ref self: TContractState, nft_id: u256, receiver: ContractAddress) -> u256;
    fn redeem_and_subscribe(ref self: TContractState, shares: u256, receiver: ContractAddress) -> u256;
    fn swap(
        ref self: TContractState,
        routes: Array<Route>,
        from_amount: u256,
        min_amount_out: u256,
    ) -> u256;
    fn claim(ref self: TContractState, nft_id: u256) -> u256;

    // Transfer the original NFT to receiver (contract is the owner itself)
    // Reverts if epoch is fully or partially settled in swap
    fn unsubscribe_for_nft(ref self: TContractState, nft_id: u256, receiver: ContractAddress);

    // Return underlying assets proportional to user's share
    // Checks if epoch < handled_epoch_len, computes assets based on current offset factor
    // Reverts if epoch is fully or partially settled in swap
    fn unsubscribe_for_underlying(ref self: TContractState, nft_id: u256, receiver: ContractAddress);

    // Setters
    fn set_integrator_fee_recipient(ref self: TContractState, recipient: ContractAddress);
    fn set_integrator_fee_amount_bps(ref self: TContractState, fee_bps: u128);
    fn set_epoch_offset(ref self: TContractState, epoch: u256, offset_factor: u256);
    fn get_epoch_offset(self: @TContractState, epoch: u256) -> u256;
    fn report(ref self: TContractState, new_aum: u256);
    fn set_min_subscribe_amount(ref self: TContractState, min_subscribe_amount: u256);

    // View functions
    fn vault(self: @TContractState) -> ContractAddress;
    fn redeem_request(self: @TContractState) -> ContractAddress;
    fn to_asset(self: @TContractState) -> ContractAddress;
    fn avnu_exchange(self: @TContractState) -> ContractAddress;
    fn integrator_fee_recipient(self: @TContractState) -> ContractAddress;
    fn integrator_fee_amount_bps(self: @TContractState) -> u128;
    fn new_nft_request_info(self: @TContractState, new_nft_id: u256) -> RequestInfo;
    fn last_nft_id(self: @TContractState) -> u256;
    fn expected_receivable(self: @TContractState, nft_id: u256) -> u256;
    fn last_settled_epoch(self: @TContractState) -> u256;
    fn epoch_settled_amounts(self: @TContractState, epoch: u256) -> u256;

    // Sync settled epochs state by checking which epochs are fully settled
    // max_epochs_to_check limits how many epochs to check to prevent excessive gas usage
    // - swap function also call this, but incase it goes of out gas, caller can call this to sync settled epochs
    fn sync_settled_epochs(ref self: TContractState, max_epochs_to_check: u256);

    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
}


