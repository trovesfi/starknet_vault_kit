// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC4626DecoderAndSanitizer<T> {
    fn deposit(self: @T, assets: u256, receiver: ContractAddress) -> Span<felt252>;
    fn mint(self: @T, shares: u256, receiver: ContractAddress) -> Span<felt252>;
    fn withdraw(
        self: @T, assets: u256, receiver: ContractAddress, owner: ContractAddress,
    ) -> Span<felt252>;
    fn redeem(
        self: @T, shares: u256, receiver: ContractAddress, owner: ContractAddress,
    ) -> Span<felt252>;
}
