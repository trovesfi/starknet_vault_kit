// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

pub mod Errors {
    pub fn zero_address() {
        panic!("Zero address");
    }

    pub fn invalid_swap_id() {
        panic!("Invalid swap id");
    }

    pub fn swap_not_settled() {
        panic!("Swap not settled");
    }

    pub fn insufficient_from_amount() {
        panic!("Insufficient from amount");
    }

    pub fn invalid_nft_id() {
        panic!("Invalid NFT id");
    }

    pub fn invalid_old_nft_id() {
        panic!("Invalid old NFT id");
    }

    pub fn claim_not_allowed() {
        panic!("Claim not allowed");
    }

    pub fn swap_failed() {
        panic!("Swap failed");
    }

    pub fn nft_already_claimed() {
        panic!("NFT already claimed");
    }

    pub fn nft_already_withdrawn() {
        panic!("NFT already withdrawn");
    }

    pub fn insufficient_balance_for_withdrawal() {
        panic!("Insufficient balance for withdrawal");
    }

    pub fn cannot_unsubscribe_partial_swap() {
        panic!("Cannot unsubscribe: swaps have partially consumed assets");
    }

    pub fn invalid_swap_from_amount() {
        panic!("Invalid swap from amount");
    }

    pub fn too_small_subscribe_amount() {
        panic!("Too small subscribe amount");
    }
    
    pub fn not_owner() {
        panic!("Not owner");
    }

    pub fn invalid_fee_amount() {
        panic!("Invalid integrator fee amount");
    }
}


