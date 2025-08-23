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
use vault_allocator::test::register::{ETH, GENESIS_POOL_ID, VESU_SINGLETON, wstETH};
use vault_allocator::test::utils::{
    ManageLeaf, OWNER, STRATEGIST, WAD, _add_avnu_leafs, _add_vesu_flash_loan_leafs,
    _add_vesu_leafs, _get_proofs_using_tree, _pad_leafs_to_power_of_two, cheat_caller_address_once,
    deploy_avnu_middleware, deploy_manager, deploy_price_router,
    deploy_simple_decoder_and_sanitizer, deploy_vault_allocator, generate_merkle_tree,
    initialize_price_router,
};
use vault_allocator::vault_allocator::interface::IVaultAllocatorDispatcherTrait;

#[fork("SLLSE")]
#[test]
fn test_leveraged_loop_staked_ether() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    let simple_decoder_and_sanitizer = deploy_simple_decoder_and_sanitizer();
    let price_router = deploy_price_router();
    initialize_price_router(price_router);
    let avnu_middleware = deploy_avnu_middleware(price_router);

    let mut leafs: Array<ManageLeaf> = ArrayTrait::new();
    let mut leaf_index: u256 = 0;

    let collateral_asset = wstETH();

    _add_vesu_flash_loan_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        manager.contract_address,
        collateral_asset,
        false,
    );

    _add_vesu_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        GENESIS_POOL_ID,
        array![wstETH()].span(),
        array![array![ETH()].span()].span(),
    );

    _add_avnu_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        avnu_middleware,
        array![(ETH(), wstETH())],
    );

    _pad_leafs_to_power_of_two(ref leafs, ref leaf_index);

    let tree = generate_merkle_tree(leafs.span());
    let root = *tree.at(tree.len() - 1).at(0);
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(manager.contract_address);

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(STRATEGIST(), root);

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(manager.contract_address, root);

    // config
    let collateral_asset = wstETH();
    let initial_collateral_balance: u256 = WAD;
    let collateral_to_flash_loan: u256 = WAD;
    let debt_asset = ETH();
    let allowed_slippage: u256 = 10; // 0.1%
    let required_debt_amount_to_refund_flash_loan = 1208100829164930048
        + 1208100829164930048 * allowed_slippage / 10000;

    let mut cheat_calldata = ArrayTrait::new();
    initial_collateral_balance.serialize(ref cheat_calldata);
    store(
        collateral_asset,
        map_entry_address(
            selector!("ERC20_balances"), array![vault_allocator.contract_address.into()].span(),
        ),
        cheat_calldata.span(),
    );

    let underlying_disp = ERC20ABIDispatcher { contract_address: collateral_asset };
    assert(
        underlying_disp.balance_of(vault_allocator.contract_address) == initial_collateral_balance,
        'wsteth balance is not correct',
    );

    let mut array_of_decoders_and_sanitizers = ArrayTrait::new();
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);

    let mut array_of_targets = ArrayTrait::new();
    array_of_targets.append(manager.contract_address);

    let mut array_of_selectors = ArrayTrait::new();
    array_of_selectors.append(selector!("flash_loan"));

    let mut array_of_calldatas = ArrayTrait::new();
    let mut array_of_calldatas_flash_loan = ArrayTrait::new();
    manager.contract_address.serialize(ref array_of_calldatas_flash_loan);
    collateral_asset.serialize(ref array_of_calldatas_flash_loan);
    collateral_to_flash_loan.serialize(ref array_of_calldatas_flash_loan);
    false.serialize(ref array_of_calldatas_flash_loan);

    let mut flash_loan_data_decoder_and_sanitizer: Array<ContractAddress> = ArrayTrait::new();
    flash_loan_data_decoder_and_sanitizer.append(simple_decoder_and_sanitizer);
    flash_loan_data_decoder_and_sanitizer.append(simple_decoder_and_sanitizer);
    flash_loan_data_decoder_and_sanitizer.append(simple_decoder_and_sanitizer);
    flash_loan_data_decoder_and_sanitizer.append(simple_decoder_and_sanitizer);

    let mut flash_loan_data_target: Array<ContractAddress> = ArrayTrait::new();
    flash_loan_data_target.append(collateral_asset);
    flash_loan_data_target.append(VESU_SINGLETON());
    flash_loan_data_target.append(debt_asset);
    flash_loan_data_target.append(avnu_middleware);

    let mut flash_loan_data_selector: Array<felt252> = ArrayTrait::new();
    flash_loan_data_selector.append(selector!("approve"));
    flash_loan_data_selector.append(selector!("modify_position"));
    flash_loan_data_selector.append(selector!("approve"));
    flash_loan_data_selector.append(selector!("multi_route_swap"));

    let mut flash_loan_data_calldata: Array<Span<felt252>> = ArrayTrait::new();

    // approve wsteth initial collateral + flash loan amount
    let mut flash_loan_data_calldata_approve = ArrayTrait::new();
    VESU_SINGLETON().serialize(ref flash_loan_data_calldata_approve);
    (initial_collateral_balance + collateral_to_flash_loan)
        .serialize(ref flash_loan_data_calldata_approve);
    flash_loan_data_calldata.append(flash_loan_data_calldata_approve.span());

    // modify position supplying wsteth initial collateral + flash loan amount and borrowing eth
    // equivalent to refund flashloan
    let mut flash_loan_data_calldata_modify_position = ArrayTrait::new();
    GENESIS_POOL_ID.serialize(ref flash_loan_data_calldata_modify_position);
    wstETH().serialize(ref flash_loan_data_calldata_modify_position);
    ETH().serialize(ref flash_loan_data_calldata_modify_position);
    vault_allocator.contract_address.serialize(ref flash_loan_data_calldata_modify_position);

    let value_for_collateral_modify_position = I257Trait::new(
        initial_collateral_balance + collateral_to_flash_loan, false,
    );
    let collateral_modify_position: Amount = Amount {
        amount_type: AmountType::Delta,
        denomination: AmountDenomination::Assets,
        value: value_for_collateral_modify_position,
    };
    collateral_modify_position.serialize(ref flash_loan_data_calldata_modify_position);

    let value_for_debt_modify_position = I257Trait::new(
        required_debt_amount_to_refund_flash_loan, false,
    );
    let debt_modify_position: Amount = Amount {
        amount_type: AmountType::Delta,
        denomination: AmountDenomination::Assets,
        value: value_for_debt_modify_position,
    };
    debt_modify_position.serialize(ref flash_loan_data_calldata_modify_position);

    let data: Span<felt252> = array![].span();
    data.serialize(ref flash_loan_data_calldata_modify_position);

    flash_loan_data_calldata.append(flash_loan_data_calldata_modify_position.span());

    // approve debt asset to avnu middleware
    let mut flash_loan_data_calldata_approve_debt_asset: Array<felt252> = ArrayTrait::new();
    avnu_middleware.serialize(ref flash_loan_data_calldata_approve_debt_asset);
    required_debt_amount_to_refund_flash_loan
        .serialize(ref flash_loan_data_calldata_approve_debt_asset);
    flash_loan_data_calldata.append(flash_loan_data_calldata_approve_debt_asset.span());

    // multi route swap: sell debt asset to avnu middleware for collateral to refund flashloan
    let mut array_of_calldata_multi_route_swap: Array<felt252> = ArrayTrait::new();
    debt_asset.serialize(ref array_of_calldata_multi_route_swap);
    required_debt_amount_to_refund_flash_loan.serialize(ref array_of_calldata_multi_route_swap);
    collateral_asset.serialize(ref array_of_calldata_multi_route_swap);
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
    // hardcode route to ekubo wsteth/eth
    let mut additional_swap_params: Array<felt252> = ArrayTrait::new();
    collateral_asset.serialize(ref additional_swap_params);
    debt_asset.serialize(ref additional_swap_params);

    let fee: u128 = 0x68db8bac710cb4000000000000000;
    fee.serialize(ref additional_swap_params);
    let tick_spacing: u128 = 0xc8;
    tick_spacing.serialize(ref additional_swap_params);
    let extension: ContractAddress = Zero::zero();
    extension.serialize(ref additional_swap_params);
    let sqrt_ratio_distance: felt252 = 0x290d5f61e20000000000000000000;
    sqrt_ratio_distance.serialize(ref additional_swap_params);

    routes
        .append(
            Route {
                sell_token: debt_asset,
                buy_token: collateral_asset,
                exchange_address: 0x5dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b
                    .try_into()
                    .unwrap(), // ekubo
                percent: 1000000000000,
                additional_swap_params,
            },
        );

    routes.serialize(ref array_of_calldata_multi_route_swap);

    flash_loan_data_calldata.append(array_of_calldata_multi_route_swap.span());

    let mut flash_loan_manager_leafs: Array<ManageLeaf> = ArrayTrait::new();
    flash_loan_manager_leafs.append(leafs.at(6).clone());
    flash_loan_manager_leafs.append(leafs.at(7).clone());
    flash_loan_manager_leafs.append(leafs.at(8).clone());
    flash_loan_manager_leafs.append(leafs.at(9).clone());

    let mut flash_loan_proofs = _get_proofs_using_tree(flash_loan_manager_leafs, tree.clone());

    let mut serialized_flash_loan_data = ArrayTrait::new();
    (
        flash_loan_proofs.span(),
        flash_loan_data_decoder_and_sanitizer.span(),
        flash_loan_data_target.span(),
        flash_loan_data_selector.span(),
        flash_loan_data_calldata.span(),
    )
        .serialize(ref serialized_flash_loan_data);

    serialized_flash_loan_data.span().serialize(ref array_of_calldatas_flash_loan);
    array_of_calldatas.append(array_of_calldatas_flash_loan.span());

    let mut manage_leafs: Array<ManageLeaf> = ArrayTrait::new();
    manage_leafs.append(leafs.at(0).clone());

    let proofs = _get_proofs_using_tree(manage_leafs, tree.clone());

    cheat_caller_address_once(manager.contract_address, STRATEGIST());
    manager
        .manage_vault_with_merkle_verification(
            proofs.span(),
            array_of_decoders_and_sanitizers.span(),
            array_of_targets.span(),
            array_of_selectors.span(),
            array_of_calldatas.span(),
        );
}
