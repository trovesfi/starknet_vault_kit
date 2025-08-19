// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::ContractAddress;
use vault_allocator::integration_interfaces::pragma::PragmaPricesResponse;


#[starknet::interface]
pub trait IPriceRouter<T> {
    fn get_value(
        self: @T, base_asset: ContractAddress, amount: u256, quote_asset: ContractAddress,
    ) -> u256;
    fn asset_to_id(self: @T, asset: ContractAddress) -> felt252;
    fn get_asset_price(self: @T, asset_id: felt252) -> PragmaPricesResponse;


    fn set_asset_to_id(ref self: T, asset: ContractAddress, id: felt252);
}

