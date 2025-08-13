// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::ContractAddress;

#[starknet::interface]
pub trait ISingletonV2<
    TContractState,
> { // fn creator_nonce(self: @TContractState, creator: ContractAddress) -> felt252;
    fn extension(self: @TContractState, pool_id: felt252) -> ContractAddress;
    // fn asset_config_unsafe(
    //     self: @TContractState, pool_id: felt252, asset: ContractAddress,
    // ) -> (AssetConfig, u256);
    // fn asset_config(
    //     ref self: TContractState, pool_id: felt252, asset: ContractAddress,
    // ) -> (AssetConfig, u256);
    // fn ltv_config(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    // ) -> LTVConfig;
    // fn position_unsafe(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    // ) -> (Position, u256, u256);
    // fn position(
    //     ref self: TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    // ) -> (Position, u256, u256);
    // fn check_collateralization_unsafe(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    // ) -> (bool, u256, u256);
    // fn check_collateralization(
    //     ref self: TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    // ) -> (bool, u256, u256);
    // fn rate_accumulator_unsafe(
    //     self: @TContractState, pool_id: felt252, asset: ContractAddress,
    // ) -> u256;
    // fn rate_accumulator(ref self: TContractState, pool_id: felt252, asset: ContractAddress) ->
    // u256;
    // fn utilization_unsafe(self: @TContractState, pool_id: felt252, asset: ContractAddress) ->
    // u256;
    // fn utilization(ref self: TContractState, pool_id: felt252, asset: ContractAddress) -> u256;
    // fn delegation(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     delegator: ContractAddress,
    //     delegatee: ContractAddress,
    // ) -> bool;
    // fn calculate_pool_id(
    //     self: @TContractState, caller_address: ContractAddress, nonce: felt252,
    // ) -> felt252;
    // fn calculate_debt(
    //     self: @TContractState, nominal_debt: i257, rate_accumulator: u256, asset_scale: u256,
    // ) -> u256;
    // fn calculate_nominal_debt(
    //     self: @TContractState, debt: i257, rate_accumulator: u256, asset_scale: u256,
    // ) -> u256;
    // fn calculate_collateral_shares_unsafe(
    //     self: @TContractState, pool_id: felt252, asset: ContractAddress, collateral: i257,
    // ) -> u256;
    // fn calculate_collateral_shares(
    //     ref self: TContractState, pool_id: felt252, asset: ContractAddress, collateral: i257,
    // ) -> u256;
    // fn calculate_collateral_unsafe(
    //     self: @TContractState, pool_id: felt252, asset: ContractAddress, collateral_shares: i257,
    // ) -> u256;
    // fn calculate_collateral(
    //     ref self: TContractState, pool_id: felt252, asset: ContractAddress, collateral_shares:
    //     i257,
    // ) -> u256;
    // fn deconstruct_collateral_amount_unsafe(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    //     collateral: Amount,
    // ) -> (i257, i257);
    // fn deconstruct_collateral_amount(
    //     ref self: TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    //     collateral: Amount,
    // ) -> (i257, i257);
    // fn deconstruct_debt_amount_unsafe(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    //     debt: Amount,
    // ) -> (i257, i257);
    // fn deconstruct_debt_amount(
    //     ref self: TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    //     debt: Amount,
    // ) -> (i257, i257);
    // fn context_unsafe(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    // ) -> Context;
    // fn context(
    //     ref self: TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    //     user: ContractAddress,
    // ) -> Context;
    // fn create_pool(
    //     ref self: TContractState,
    //     asset_params: Span<AssetParams>,
    //     ltv_params: Span<LTVParams>,
    //     extension: ContractAddress,
    // ) -> felt252;
    // fn modify_position(
    //     ref self: TContractState, params: ModifyPositionParams,
    // ) -> UpdatePositionResponse;
    // fn transfer_position(ref self: TContractState, params: TransferPositionParams);
    // fn liquidate_position(
    //     ref self: TContractState, params: LiquidatePositionParams,
    // ) -> UpdatePositionResponse;
    fn flash_loan(
        ref self: TContractState,
        receiver: ContractAddress,
        asset: ContractAddress,
        amount: u256,
        is_legacy: bool,
        data: Span<felt252>,
    );
    // fn modify_delegation(
//     ref self: TContractState, pool_id: felt252, delegatee: ContractAddress, delegation: bool,
// );
// fn donate_to_reserve(
//     ref self: TContractState, pool_id: felt252, asset: ContractAddress, amount: u256,
// );
// fn retrieve_from_reserve(
//     ref self: TContractState,
//     pool_id: felt252,
//     asset: ContractAddress,
//     receiver: ContractAddress,
//     amount: u256,
// );
// fn set_asset_config(ref self: TContractState, pool_id: felt252, params: AssetParams);
// fn set_ltv_config(
//     ref self: TContractState,
//     pool_id: felt252,
//     collateral_asset: ContractAddress,
//     debt_asset: ContractAddress,
//     ltv_config: LTVConfig,
// );
// fn set_asset_parameter(
//     ref self: TContractState,
//     pool_id: felt252,
//     asset: ContractAddress,
//     parameter: felt252,
//     value: u256,
// );
// fn set_extension(ref self: TContractState, pool_id: felt252, extension: ContractAddress);
// fn set_extension_whitelist(
//     ref self: TContractState, extension: ContractAddress, approved: bool,
// );
// fn claim_fee_shares(ref self: TContractState, pool_id: felt252, asset: ContractAddress);

    // fn migrate_pool(
//     ref self: TContractState,
//     pool_id: felt252,
//     extension: ContractAddress,
//     creator: ContractAddress,
//     asset_configs: Span<(ContractAddress, AssetConfig)>,
//     ltv_configs: Span<(ContractAddress, ContractAddress, LTVConfig)>,
// );
// fn migrate_position(
//     ref self: TContractState,
//     pool_id: felt252,
//     collateral_asset: ContractAddress,
//     debt_asset: ContractAddress,
//     from: ContractAddress,
//     to: ContractAddress,
// );
// fn set_migrator(ref self: TContractState, migrator: ContractAddress);

    // fn upgrade_name(self: @TContractState) -> felt252;
// fn upgrade(ref self: TContractState, new_implementation: ClassHash);
}

#[starknet::interface]
pub trait IDefaultExtensionPOV2<
    TContractState,
> { // fn pool_name(self: @TContractState, pool_id: felt252) -> felt252;
    // fn pool_owner(self: @TContractState, pool_id: felt252) -> ContractAddress;
    // fn shutdown_mode_agent(self: @TContractState, pool_id: felt252) -> ContractAddress;
    // fn pragma_oracle(self: @TContractState) -> ContractAddress;
    // fn pragma_summary(self: @TContractState) -> ContractAddress;
    // fn oracle_config(
    //     self: @TContractState, pool_id: felt252, asset: ContractAddress,
    // ) -> OracleConfig;
    // fn fee_config(self: @TContractState, pool_id: felt252) -> FeeConfig;
    // fn debt_caps(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    // ) -> u256;
    // fn interest_rate_config(
    //     self: @TContractState, pool_id: felt252, asset: ContractAddress,
    // ) -> InterestRateConfig;
    // fn liquidation_config(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    // ) -> LiquidationConfig;
    // fn shutdown_config(self: @TContractState, pool_id: felt252) -> ShutdownConfig;
    // fn shutdown_ltv_config(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    // ) -> LTVConfig;
    // fn shutdown_status(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    // ) -> ShutdownStatus;
    // fn pairs(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    // ) -> Pair;
    // fn violation_timestamp_for_pair(
    //     self: @TContractState,
    //     pool_id: felt252,
    //     collateral_asset: ContractAddress,
    //     debt_asset: ContractAddress,
    // ) -> u64;
    // fn violation_timestamp_count(
    //     self: @TContractState, pool_id: felt252, violation_timestamp: u64,
    // ) -> u128;
    // fn oldest_violation_timestamp(self: @TContractState, pool_id: felt252) -> u64;
    // fn next_violation_timestamp(
    //     self: @TContractState, pool_id: felt252, violation_timestamp: u64,
    // ) -> u64;
    fn v_token_for_collateral_asset(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress,
    ) -> ContractAddress;
    // fn collateral_asset_for_v_token(
//     self: @TContractState, pool_id: felt252, v_token: ContractAddress,
// ) -> ContractAddress;
// fn create_pool(
//     ref self: TContractState,
//     name: felt252,
//     asset_params: Span<AssetParams>,
//     v_token_params: Span<VTokenParams>,
//     ltv_params: Span<LTVParams>,
//     interest_rate_configs: Span<InterestRateConfig>,
//     pragma_oracle_params: Span<PragmaOracleParams>,
//     liquidation_params: Span<LiquidationParams>,
//     debt_caps: Span<DebtCapParams>,
//     shutdown_params: ShutdownParams,
//     fee_params: FeeParams,
//     owner: ContractAddress,
// ) -> felt252;
// fn add_asset(
//     ref self: TContractState,
//     pool_id: felt252,
//     asset_params: AssetParams,
//     v_token_params: VTokenParams,
//     interest_rate_config: InterestRateConfig,
//     pragma_oracle_params: PragmaOracleParams,
// );
// fn set_asset_parameter(
//     ref self: TContractState,
//     pool_id: felt252,
//     asset: ContractAddress,
//     parameter: felt252,
//     value: u256,
// );
// fn set_debt_cap(
//     ref self: TContractState,
//     pool_id: felt252,
//     collateral_asset: ContractAddress,
//     debt_asset: ContractAddress,
//     debt_cap: u256,
// );
// fn set_interest_rate_parameter(
//     ref self: TContractState,
//     pool_id: felt252,
//     asset: ContractAddress,
//     parameter: felt252,
//     value: u256,
// );
// fn set_oracle_parameter(
//     ref self: TContractState,
//     pool_id: felt252,
//     asset: ContractAddress,
//     parameter: felt252,
//     value: felt252,
// );
// fn set_liquidation_config(
//     ref self: TContractState,
//     pool_id: felt252,
//     collateral_asset: ContractAddress,
//     debt_asset: ContractAddress,
//     liquidation_config: LiquidationConfig,
// );
// fn set_ltv_config(
//     ref self: TContractState,
//     pool_id: felt252,
//     collateral_asset: ContractAddress,
//     debt_asset: ContractAddress,
//     ltv_config: LTVConfig,
// );
// fn set_shutdown_config(
//     ref self: TContractState, pool_id: felt252, shutdown_config: ShutdownConfig,
// );
// fn set_shutdown_ltv_config(
//     ref self: TContractState,
//     pool_id: felt252,
//     collateral_asset: ContractAddress,
//     debt_asset: ContractAddress,
//     shutdown_ltv_config: LTVConfig,
// );
// fn set_shutdown_mode(ref self: TContractState, pool_id: felt252, shutdown_mode:
// ShutdownMode);
// fn set_pool_owner(ref self: TContractState, pool_id: felt252, owner: ContractAddress);
// fn set_shutdown_mode_agent(
//     ref self: TContractState, pool_id: felt252, shutdown_mode_agent: ContractAddress,
// );
// fn update_shutdown_status(
//     ref self: TContractState,
//     pool_id: felt252,
//     collateral_asset: ContractAddress,
//     debt_asset: ContractAddress,
// ) -> ShutdownMode;
// fn set_fee_config(ref self: TContractState, pool_id: felt252, fee_config: FeeConfig);
// fn claim_fees(ref self: TContractState, pool_id: felt252, collateral_asset: ContractAddress);

    // fn migrate_pool(
//     ref self: TContractState,
//     pool_id: felt252,
//     name: felt252,
//     v_token_configs: Span<(felt252, felt252, ContractAddress, ContractAddress)>,
//     interest_rate_configs: Span<(ContractAddress, InterestRateConfig)>,
//     pragma_oracle_configs: Span<(ContractAddress, OracleConfig)>,
//     liquidation_configs: Span<(ContractAddress, ContractAddress, LiquidationConfig)>,
//     pairs: Span<(ContractAddress, ContractAddress, Pair)>,
//     debt_caps: Span<(ContractAddress, ContractAddress, u256)>,
//     shutdown_ltv_configs: Span<(ContractAddress, ContractAddress, LTVConfig)>,
//     shutdown_config: ShutdownConfig,
//     fee_config: FeeConfig,
//     owner: ContractAddress,
// );
// fn set_migrator(ref self: TContractState, migrator: ContractAddress);

    // fn set_extension_utils_class_hash(ref self: TContractState, extension: felt252);
// // Upgrade
// fn upgrade_name(self: @TContractState) -> felt252;
// fn upgrade(ref self: TContractState, new_implementation: ClassHash);
}

#[starknet::interface]
pub trait IFlashloanReceiver<TContractState> {
    fn on_flash_loan(
        ref self: TContractState,
        sender: ContractAddress,
        asset: ContractAddress,
        amount: u256,
        data: Span<felt252>,
    );
}
