// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

pub mod Errors {
    pub fn insufficient_output(out: u256, min: u256) {
        panic!("Insufficient output: {} < {}", out, min);
    }

    pub fn slippage_exceeds_max(slippage: u16) {
        panic!("Slippage exceeds max: {}", slippage);
    }

    pub fn rate_limit_exceeded(next: u64, allowed: u64) {
        panic!("Rate limit exceeded: {} > {}", next, allowed);
    }

    pub fn period_zero() {
        panic!("Period is zero");
    }

    pub fn allowed_calls_per_period_zero() {
        panic!("Allowed calls per period is zero");
    }

    pub fn caller_not_vault_allocator() {
        panic!("Caller not vault allocator");
    }
}
