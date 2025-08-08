// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

// tokens
use starknet::ContractAddress;

pub fn STRK() -> ContractAddress {
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}

pub fn WBTC() -> ContractAddress {
    0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac.try_into().unwrap()
}

pub fn USDC() -> ContractAddress {
    0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8.try_into().unwrap()
}

pub fn USDT() -> ContractAddress {
    0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8.try_into().unwrap()
}

pub fn ETH() -> ContractAddress {
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap()
}

pub fn DAI() -> ContractAddress {
    0x05574eb6b8789a91466f902c380d978e472db68170ff82a5b650b95a58ddf4ad.try_into().unwrap()
}

pub fn wstETH() -> ContractAddress {
    0x042b8f0484674ca266ac5d08e4ac6a3fe65bd3129795def2dca5c34ecc5f96d2.try_into().unwrap()
}


// VESU

pub fn VESU_SINGLETON() -> ContractAddress {
    0x000d8d6dfec4d33bfb6895de9f3852143a17c6f92fd2a21da3d6924d34870160.try_into().unwrap()
}

pub const GENESIS_POOL_ID: felt252 =
    2198503327643286920898110335698706244522220458610657370981979460625005526824;
