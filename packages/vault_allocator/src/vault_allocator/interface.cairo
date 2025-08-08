// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

// Standard library imports
use starknet::ContractAddress;
use starknet::account::Call;

#[starknet::interface]
pub trait IVaultAllocator<TContractState> {
    fn manager(self: @TContractState) -> ContractAddress;
    fn set_manager(ref self: TContractState, manager: ContractAddress);
    fn manage(ref self: TContractState, call: Call) -> Span<felt252>;
    fn manage_multi(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
}

