// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.
use alexandria_math::i257::{I257Impl, I257Trait};
use core::num::traits::Zero;
use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{map_entry_address, store};
use starknet::ContractAddress;
use vault_allocator::decoders_and_sanitizers::decoder_custom_types::{
    Amount, AmountDenomination, AmountType, Route,
};
use vault_allocator::manager::interface::IManagerDispatcherTrait;
use vault_allocator::merkle_tree::base::{
    ManageLeaf, _get_proofs_using_tree, _pad_leafs_to_power_of_two, generate_merkle_tree,
};
use vault_allocator::merkle_tree::integrations::avnu::{AvnuConfig, _add_avnu_leafs};
use vault_allocator::merkle_tree::integrations::erc4626::_add_erc4626_leafs;
use vault_allocator::merkle_tree::integrations::vesu_v1::{VesuV1Config, _add_vesu_v1_leafs};
use vault_allocator::merkle_tree::registery::{
    ETH, GENESIS_POOL_ID, USDC, USDT, VESU_GENESIS_POOL_V_TOKEN_USDT, VESU_SINGLETON,
};
use vault_allocator::test::utils::{
    OWNER, STRATEGIST, WAD, cheat_caller_address_once, deploy_avnu_middleware, deploy_manager,
    deploy_price_router, deploy_simple_decoder_and_sanitizer, deploy_vault_allocator,
    initialize_price_router,
};
use vault_allocator::vault_allocator::interface::IVaultAllocatorDispatcherTrait;

#[fork("SSCL")]
#[test]
fn test_stable_carry_loop() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator);
    let simple_decoder_and_sanitizer = deploy_simple_decoder_and_sanitizer();
    let price_router = deploy_price_router();
    initialize_price_router(price_router);
    let avnu_middleware = deploy_avnu_middleware(
        vault_allocator.contract_address, price_router, 100, 100000, 1000000,
    );

    let mut leafs: Array<ManageLeaf> = ArrayTrait::new();
    let mut leaf_index: u256 = 0;

    // add vesu v1 leafs
    _add_vesu_v1_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        array![
            VesuV1Config {
                pool_id: GENESIS_POOL_ID,
                collateral_asset: ETH(),
                debt_assets: array![USDC()].span(),
            },
        ]
            .span(),
    );

    // add erc4626 leafs for usdt v-token
    _add_erc4626_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        VESU_GENESIS_POOL_V_TOKEN_USDT(),
    );

    _add_avnu_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        avnu_middleware,
        array![AvnuConfig { sell_token: USDC(), buy_token: USDT() }].span(),
    );

    _pad_leafs_to_power_of_two(ref leafs, ref leaf_index);

    let tree = generate_merkle_tree(leafs.span());
    let root = *tree.at(tree.len() - 1).at(0);
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(manager.contract_address);

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(STRATEGIST(), root);

    // add eth balance to vault allocator
    let initial_eth_balance: u256 = 10 * WAD;

    let mut cheat_calldata = ArrayTrait::new();
    initial_eth_balance.serialize(ref cheat_calldata);
    store(
        ETH(),
        map_entry_address(
            selector!("ERC20_balances"), array![vault_allocator.contract_address.into()].span(),
        ),
        cheat_calldata.span(),
    );

    let underlying_disp = ERC20ABIDispatcher { contract_address: ETH() };
    assert(
        underlying_disp.balance_of(vault_allocator.contract_address) == initial_eth_balance,
        'eth balance is not correct',
    );

    // Deposit eth to vesu genesis pool, borrow usdc, swap to usdt, deposit to usdt to genesis pool

    // // sell 1 wsteth for eth
    // let sell_amount: u256 = WAD;

    let collateral_amount_underlying = 5 * WAD;
    let debt_amount_underlying = 30_000_000; // 30 USDC
    let earn_amount_from_swap: u256 = 10_000_000; // 30 USDT

    let mut array_of_decoders_and_sanitizers = ArrayTrait::new();
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);

    let mut array_of_targets = ArrayTrait::new();
    array_of_targets.append(ETH());
    array_of_targets.append(VESU_SINGLETON());
    array_of_targets.append(USDC());
    array_of_targets.append(avnu_middleware);
    array_of_targets.append(USDT());
    array_of_targets.append(VESU_GENESIS_POOL_V_TOKEN_USDT());

    let mut array_of_selectors = ArrayTrait::new();
    array_of_selectors.append(selector!("approve"));
    array_of_selectors.append(selector!("modify_position"));
    array_of_selectors.append(selector!("approve"));
    array_of_selectors.append(selector!("multi_route_swap"));
    array_of_selectors.append(selector!("approve"));
    array_of_selectors.append(selector!("deposit"));

    let mut array_of_calldatas = ArrayTrait::new();

    let mut array_of_calldata_approve: Array<felt252> = ArrayTrait::new();
    VESU_SINGLETON().serialize(ref array_of_calldata_approve);
    initial_eth_balance.serialize(ref array_of_calldata_approve);
    array_of_calldatas.append(array_of_calldata_approve.span());

    let mut array_of_calldata_modify_position: Array<felt252> = ArrayTrait::new();
    GENESIS_POOL_ID.serialize(ref array_of_calldata_modify_position);
    ETH().serialize(ref array_of_calldata_modify_position);
    USDC().serialize(ref array_of_calldata_modify_position);
    vault_allocator.contract_address.serialize(ref array_of_calldata_modify_position);

    // collateral
    let value_for_collateral_modify_position = I257Trait::new(collateral_amount_underlying, false);
    let collateral_modify_position: Amount = Amount {
        amount_type: AmountType::Delta,
        denomination: AmountDenomination::Assets,
        value: value_for_collateral_modify_position,
    };
    collateral_modify_position.serialize(ref array_of_calldata_modify_position);

    // debt
    let value_for_debt_modify_position = I257Trait::new(debt_amount_underlying, false);
    let debt_modify_position: Amount = Amount {
        amount_type: AmountType::Delta,
        denomination: AmountDenomination::Assets,
        value: value_for_debt_modify_position,
    };
    debt_modify_position.serialize(ref array_of_calldata_modify_position);
    let data: Span<felt252> = array![].span();
    data.serialize(ref array_of_calldata_modify_position);
    array_of_calldatas.append(array_of_calldata_modify_position.span());

    // approve usdc to avnu middleware
    let mut array_of_calldata_approve_usdt: Array<felt252> = ArrayTrait::new();
    avnu_middleware.serialize(ref array_of_calldata_approve_usdt);
    debt_amount_underlying.serialize(ref array_of_calldata_approve_usdt);
    array_of_calldatas.append(array_of_calldata_approve_usdt.span());

    // multi route swap
    let mut array_of_calldata_multi_route_swap: Array<felt252> = ArrayTrait::new();
    USDC().serialize(ref array_of_calldata_multi_route_swap);
    debt_amount_underlying.serialize(ref array_of_calldata_multi_route_swap);
    USDT().serialize(ref array_of_calldata_multi_route_swap);
    // buy token amount is 0 because we are selling
    let buy_token_amount: u256 = Zero::zero();
    buy_token_amount.serialize(ref array_of_calldata_multi_route_swap);
    // buy_token_min_amount is set to 0 because we are protected by price router whatever
    let buy_token_min_amount: u256 = Zero::zero();
    buy_token_min_amount.serialize(ref array_of_calldata_multi_route_swap);
    vault_allocator.contract_address.serialize(ref array_of_calldata_multi_route_swap);
    let integrator_fee_amount_bps: u128 = Zero::zero();
    integrator_fee_amount_bps.serialize(ref array_of_calldata_multi_route_swap);
    let integrator_fee_recipient: ContractAddress = Zero::zero();
    integrator_fee_recipient.serialize(ref array_of_calldata_multi_route_swap);

    let mut routes: Array<Route> = ArrayTrait::new();
    // hardcode route to ekubo usdc/usdt
    let mut additional_swap_params: Array<felt252> = ArrayTrait::new();
    let token0: ContractAddress = USDC();
    token0.serialize(ref additional_swap_params);
    let token1: ContractAddress = USDT();
    token1.serialize(ref additional_swap_params);
    let fee: u128 = 0x14f8b588e368f1000000000000000;
    fee.serialize(ref additional_swap_params);
    let tick_spacing: u128 = 0x14;
    tick_spacing.serialize(ref additional_swap_params);
    let extension: ContractAddress = Zero::zero();
    extension.serialize(ref additional_swap_params);
    let sqrt_ratio_distance: felt252 = 0x4f8ca870000000000000000000;
    sqrt_ratio_distance.serialize(ref additional_swap_params);

    routes
        .append(
            Route {
                sell_token: USDC(),
                buy_token: USDT(),
                exchange_address: 0x5dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b
                    .try_into()
                    .unwrap(), // ekubo
                percent: 1000000000000,
                additional_swap_params,
            },
        );
    routes.serialize(ref array_of_calldata_multi_route_swap);
    array_of_calldatas.append(array_of_calldata_multi_route_swap.span());

    // approve usdt to the v-token
    let mut array_of_calldata_approve_vtoken: Array<felt252> = ArrayTrait::new();
    VESU_GENESIS_POOL_V_TOKEN_USDT().serialize(ref array_of_calldata_approve_vtoken);
    earn_amount_from_swap.serialize(ref array_of_calldata_approve_vtoken);
    array_of_calldatas.append(array_of_calldata_approve_vtoken.span());

    // deposit usdt to the v-token
    let mut array_of_calldata_deposit: Array<felt252> = ArrayTrait::new();
    earn_amount_from_swap.serialize(ref array_of_calldata_deposit);
    vault_allocator.contract_address.serialize(ref array_of_calldata_deposit);
    array_of_calldatas.append(array_of_calldata_deposit.span());

    let mut manage_leafs: Array<ManageLeaf> = ArrayTrait::new();
    manage_leafs.append(leafs.at(0).clone());
    manage_leafs.append(leafs.at(1).clone());
    manage_leafs.append(leafs.at(7).clone());
    manage_leafs.append(leafs.at(8).clone());
    manage_leafs.append(leafs.at(2).clone());
    manage_leafs.append(leafs.at(3).clone());

    let manage_proofs = _get_proofs_using_tree(manage_leafs, tree.clone());

    cheat_caller_address_once(manager.contract_address, STRATEGIST());
    manager
        .manage_vault_with_merkle_verification(
            manage_proofs.span(),
            array_of_decoders_and_sanitizers.span(),
            array_of_targets.span(),
            array_of_selectors.span(),
            array_of_calldatas.span(),
        );
}

