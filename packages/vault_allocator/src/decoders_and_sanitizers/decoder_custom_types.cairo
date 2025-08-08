// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use alexandria_math::i257::i257;
use starknet::ContractAddress;

// AVNU EXCHANGE
#[derive(Drop, Serde, Clone)]
pub struct Route {
    pub sell_token: ContractAddress,
    pub buy_token: ContractAddress,
    pub exchange_address: ContractAddress,
    pub percent: u128,
    pub additional_swap_params: Array<felt252>,
}


// VESU MONEY MARKET

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub enum AmountType {
    #[default]
    Delta,
    Target,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub enum AmountDenomination {
    #[default]
    Native,
    Assets,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub struct UnsignedAmount {
    pub amount_type: AmountType,
    pub denomination: AmountDenomination,
    pub value: u256,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct TransferPositionParams {
    pub pool_id: felt252,
    pub from_collateral_asset: ContractAddress,
    pub from_debt_asset: ContractAddress,
    pub to_collateral_asset: ContractAddress,
    pub to_debt_asset: ContractAddress,
    pub from_user: ContractAddress,
    pub to_user: ContractAddress,
    pub collateral: UnsignedAmount,
    pub debt: UnsignedAmount,
    pub from_data: Span<felt252>,
    pub to_data: Span<felt252>,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub struct Amount {
    pub amount_type: AmountType,
    pub denomination: AmountDenomination,
    pub value: i257,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct ModifyPositionParams {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub collateral: Amount,
    pub debt: Amount,
    pub data: Span<felt252>,
}
