// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use vault_allocator::integration_interfaces::extended::PositionId;

#[starknet::interface]
pub trait IExtendedExchangeDecoderAndSanitizer<T> {
    fn deposit(
        ref self: T,
        position_id: PositionId,
        quantized_amount: u64,
        salt: felt252,
    ) -> Span<felt252>;
}