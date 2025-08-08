// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

pub mod vault_allocator {
    pub mod errors;
    pub mod interface;
    pub mod vault_allocator;
}

pub mod manager {
    pub mod errors;
    pub mod interface;
    pub mod manager;
}

pub mod integration_interfaces {
    pub mod vesu;
}

pub mod decoders_and_sanitizers {
    pub mod base_decoder_and_sanitizer;
    pub mod decoder_custom_types;
    pub mod interface;
    pub mod simple_decoder_and_sanitizer;
    pub mod avnu_exchange_decoder_and_sanitizer {
        pub mod avnu_exchange_decoder_and_sanitizer;
        pub mod interface;
    }
    pub mod erc4626_decoder_and_sanitizer {
        pub mod erc4626_decoder_and_sanitizer;
        pub mod interface;
    }
    pub mod vesu_decoder_and_sanitizer {
        pub mod interface;
        pub mod vesu_decoder_and_sanitizer;
    }
}

pub mod mocks {
    pub mod counter;
    pub mod erc20;
    pub mod erc4626;
}

#[cfg(test)]
pub mod test {
    pub mod register;
    pub mod utils;
    pub mod units {
        pub mod manager;
        pub mod vault_allocator;
    }

    pub mod integrations {
        pub mod vesu;
    }
}

