// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use vault_allocator::decoders_and_sanitizers::decoder_custom_types::ModifyLeverParams;

#[starknet::interface]
pub trait IMultiplyDecoderAndSanitizer<T> {
    fn modify_lever(self: @T, modify_lever_params: ModifyLeverParams) -> Span<felt252>;
}

