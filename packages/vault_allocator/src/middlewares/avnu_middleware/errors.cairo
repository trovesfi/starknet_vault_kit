// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

pub mod Errors {
    pub fn insufficient_output(out: u256, min: u256) {
        panic!("Insufficient output: {} < {}", out, min);
    }

    pub fn slippage_exceeds_max(slippage: u256) {
        panic!("Slippage exceeds max: {}", slippage);
    }
}
