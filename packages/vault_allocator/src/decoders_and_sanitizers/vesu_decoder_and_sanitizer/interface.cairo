// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use vault_allocator::decoders_and_sanitizers::decoder_custom_types::{
    ModifyPositionParams, TransferPositionParams,
};

#[starknet::interface]
pub trait IVesuDecoderAndSanitizer<T> {
    fn transfer_position(self: @T, params: TransferPositionParams) -> Span<felt252>;
    fn modify_position(self: @T, params: ModifyPositionParams) -> Span<felt252>;
}

