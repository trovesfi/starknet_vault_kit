// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use vault_allocator::decoders_and_sanitizers::decoder_custom_types::ModifyPositionParamsV2;

#[starknet::interface]
pub trait IVesuV2DecoderAndSanitizer<T> {
    fn modify_position(self: @T, params: ModifyPositionParamsV2) -> Span<felt252>;
}

