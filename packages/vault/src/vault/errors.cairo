// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

pub mod Errors {
    pub fn not_implemented() {
        panic!("Not implemented");
    }

    pub fn invalid_redeem_fees() {
        panic!("Invalid redeem fees");
    }

    pub fn invalid_management_fees() {
        panic!("Invalid management fees");
    }

    pub fn invalid_performance_fees() {
        panic!("Invalid performance fees");
    }

    pub fn exceeded_max_redeem() {
        panic!("Exceeded max redeem");
    }

    pub fn zero_assets() {
        panic!("Zero assets");
    }

    pub fn redeem_assets_not_claimable() {
        panic!("Redeem assets not claimable");
    }

    pub fn aum_delta_too_high(delta_wad: u256, max_delta: u256) {
        panic!("AUM delta too high: {} > {}", delta_wad, max_delta);
    }

    pub fn vault_allocator_not_set() {
        panic!("Vault allocator not set");
    }

    pub fn fees_recipient_not_set() {
        panic!("Fees recipient not set");
    }

    pub fn liquidity_is_zero() {
        panic!("Liquidity is zero");
    }

    pub fn report_too_early() {
        panic!("Report too early - redeem delay not elapsed");
    }

    pub fn invalid_report_delay() {
        panic!("Invalid report delay");
    }

    pub fn redeem_request_already_registered() {
        panic!("Redeem request already registered");
    }

    pub fn vault_allocator_already_registered() {
        panic!("Vault allocator already registered");
    }
}
