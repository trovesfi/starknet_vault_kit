// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

pub mod vault {
    pub mod errors;
    pub mod interface;
    pub mod vault;
}

// waiting for openzeppelin to release vault with external assets
pub mod oz_4626;

pub mod redeem_request {
    pub mod errors;
    pub mod interface;
    pub mod redeem_request;
}

#[cfg(test)]
pub mod test {
    pub mod utils;
    pub mod units {
        pub mod redeem_request;
        pub mod vault;
    }
}
