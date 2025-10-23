// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IStarknetVaultKitDecoderAndSanitizer<T> {
    fn request_redeem(
        self: @T, shares: u256, receiver: ContractAddress, owner: ContractAddress,
    ) -> Span<felt252>;

    fn claim_redeem(self: @T, id: u256) -> Span<felt252>;
}

