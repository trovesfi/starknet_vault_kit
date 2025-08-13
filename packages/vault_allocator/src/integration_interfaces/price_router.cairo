// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::ContractAddress;
use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;

#[starknet::interface]
pub trait IPriceRouter<T> {
    fn get_value(
        self: @T, base_asset: ContractAddress, amount: u256, quote_asset: ContractAddress,
    ) -> u256;
}

