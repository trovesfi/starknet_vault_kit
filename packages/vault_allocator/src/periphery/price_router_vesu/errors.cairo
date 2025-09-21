// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

pub mod Errors {
    use starknet::ContractAddress;

    pub fn invalid_price(asset: ContractAddress) {
        panic!("Invalid price for asset: {:?}", asset);
    }
}
