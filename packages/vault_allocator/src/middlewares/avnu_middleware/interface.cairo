// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::ContractAddress;
use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;

#[starknet::interface]
pub trait IAvnuMiddleware<T> {
    fn avnu_router(self: @T) -> ContractAddress;
    fn price_router(self: @T) -> ContractAddress;
    fn slippage_tolerance_bps(self: @T) -> u256;


    fn multi_route_swap(
        self: @T,
        sell_token_address: ContractAddress,
        sell_token_amount: u256,
        buy_token_address: ContractAddress,
        buy_token_amount: u256,
        buy_token_min_amount: u256,
        beneficiary: ContractAddress,
        integrator_fee_amount_bps: u128,
        integrator_fee_recipient: ContractAddress,
        routes: Array<Route>,
    ) -> u256;
    fn set_slippage_tolerance_bps(ref self: T, new_slippage_bps: u256);
}
