// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use alexandria_math::i257::i257;
use starknet::ContractAddress;

// AVNU EXCHANGE
#[derive(Drop, Serde, Clone, Debug)]
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

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct ModifyPositionParamsV2 {
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub collateral: Amount,
    pub debt: Amount,
    pub data: Span<felt252>,
}


#[derive(Serde, Drop, Clone)]
pub enum ModifyLeverAction {
    IncreaseLever: IncreaseLeverParams,
    DecreaseLever: DecreaseLeverParams,
}

#[derive(Serde, Drop, Clone)]
pub struct ModifyLeverParams {
    pub action: ModifyLeverAction,
}


#[derive(Serde, Drop, Clone)]
pub struct IncreaseLeverParams {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub add_margin: u128,
    pub margin_swap: Array<Swap>,
    pub margin_swap_limit_amount: u128,
    pub lever_swap: Array<Swap>,
    pub lever_swap_limit_amount: u128,
}

#[derive(Serde, Drop, Clone)]
pub struct DecreaseLeverParams {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub sub_margin: u128,
    pub recipient: ContractAddress,
    pub lever_swap: Array<Swap>,
    pub lever_swap_limit_amount: u128,
    pub lever_swap_weights: Array<u128>,
    pub withdraw_swap: Array<Swap>,
    pub withdraw_swap_limit_amount: u128,
    pub withdraw_swap_weights: Array<u128>,
    pub close_position: bool,
}

#[derive(Serde, Drop, Clone)]
pub struct Swap {
    pub route: Array<RouteNode>,
    pub token_amount: TokenAmount,
}


#[derive(Serde, Copy, Drop)]
pub struct RouteNode {
    pub pool_key: PoolKey,
    pub sqrt_ratio_limit: u256,
    pub skip_ahead: u128,
}


#[derive(Serde, Copy, Drop)]
pub struct TokenAmount {
    pub token: ContractAddress,
    pub amount: i129,
}

#[derive(Copy, Drop, Serde, PartialEq, Hash)]
pub struct PoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
    pub extension: ContractAddress,
}

#[derive(Copy, Drop, Serde, Debug)]
pub struct i129 {
    pub mag: u128,
    pub sign: bool,
}
