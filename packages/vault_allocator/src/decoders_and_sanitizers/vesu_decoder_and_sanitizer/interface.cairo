// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use vault_allocator::decoders_and_sanitizers::decoder_custom_types::ModifyPositionParams;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IVesuDecoderAndSanitizer<T> {
    fn modify_position(self: @T, params: ModifyPositionParams) -> Span<felt252>;
    fn modify_delegation(self: @T, delegatee: ContractAddress, delegation: bool) -> Span<felt252>;
}

