// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::ContractAddress;


#[starknet::interface]
pub trait IPriceRouter<T> {
    fn get_value(
        self: @T, base_asset: ContractAddress, amount: u256, quote_asset: ContractAddress,
    ) -> u256;
    fn vesu_oracle_contract(self: @T) -> ContractAddress;
}

