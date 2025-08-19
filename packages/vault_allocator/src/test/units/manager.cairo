// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use openzeppelin::interfaces::accesscontrol::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::interfaces::security::pausable::{IPausableDispatcher, IPausableDispatcherTrait};
use openzeppelin::interfaces::upgrades::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use starknet::ContractAddress;
use vault_allocator::integration_interfaces::vesu::{
    IFlashloanReceiverDispatcher, IFlashloanReceiverDispatcherTrait,
};
use vault_allocator::manager::interface::{IManagerDispatcher, IManagerDispatcherTrait};
use vault_allocator::manager::manager::Manager::{OWNER_ROLE, PAUSER_ROLE};
use vault_allocator::mocks::counter::{ICounterDispatcher, ICounterDispatcherTrait};
use vault_allocator::mocks::flashloan::{
    IFlashLoanSingletonMockDispatcher, IFlashLoanSingletonMockDispatcherTrait,
};
use vault_allocator::test::register::VESU_SINGLETON;
use vault_allocator::test::utils::{
    DUMMY_ADDRESS, ManageLeaf, OWNER, STRATEGIST, WAD, _add_erc4626_leafs,
    _add_vesu_flash_loan_leafs, _get_proofs_using_tree, _pad_leafs_to_power_of_two,
    cheat_caller_address_once, deploy_counter, deploy_erc20_mock, deploy_erc4626_mock,
    deploy_flashloan_mock, deploy_manager, deploy_simple_decoder_and_sanitizer,
    deploy_vault_allocator, generate_merkle_tree,
};
use vault_allocator::vault_allocator::interface::IVaultAllocatorDispatcherTrait;

#[test]
fn test_constructor() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    let access_control_dispatcher = IAccessControlDispatcher {
        contract_address: manager.contract_address,
    };
    let role_admin = access_control_dispatcher.get_role_admin(OWNER_ROLE);
    assert(role_admin == OWNER_ROLE, 'Owner is not set correctly');
    let role_admin = access_control_dispatcher.get_role_admin(PAUSER_ROLE);
    assert(role_admin == OWNER_ROLE, 'Owner is not set correctly');
    let has_role = access_control_dispatcher.has_role(OWNER_ROLE, OWNER());
    assert(has_role, 'Owner is not set correctly');
    let has_role = access_control_dispatcher.has_role(PAUSER_ROLE, OWNER());
    assert(has_role, 'Pauser is not set correctly');

    assert(manager.vesu_singleton() == VESU_SINGLETON(), ' singleton is not set correctly');
    assert(
        manager.vault_allocator() == vault_allocator.contract_address,
        'allocator is not set correctly',
    );
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_upgrade_not_owner() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    let (_, counter_class_hash) = deploy_counter();
    IUpgradeableDispatcher { contract_address: manager.contract_address }
        .upgrade(counter_class_hash);
}

#[test]
fn test_upgrade() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    let (_, counter_class_hash) = deploy_counter();
    cheat_caller_address_once(manager.contract_address, OWNER());
    IUpgradeableDispatcher { contract_address: manager.contract_address }
        .upgrade(counter_class_hash);
    ICounterDispatcher { contract_address: manager.contract_address }.get_value();
}

#[test]
fn test_set_manage_root() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());

    let target = 0x123.try_into().unwrap();
    let root = 0x456;

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(target, root);

    let stored_root = manager.manage_root(target);
    assert(stored_root == root, 'Root not set correctly');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_set_manage_root_not_owner() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());

    let target = 0x123.try_into().unwrap();
    let root = 0x456;

    manager.set_manage_root(target, root);
}

#[test]
fn test_pause() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    let manager_dispatcher = IManagerDispatcher { contract_address: manager.contract_address };
    let pausable_dispatcher = IPausableDispatcher { contract_address: manager.contract_address };

    assert(!pausable_dispatcher.is_paused(), 'Should not be paused initially');

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager_dispatcher.pause();

    assert(pausable_dispatcher.is_paused(), 'Should be paused after pause()');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_pause_not_pauser() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    manager.pause();
}

#[test]
fn test_unpause() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    let manager_dispatcher = IManagerDispatcher { contract_address: manager.contract_address };
    let pausable_dispatcher = IPausableDispatcher { contract_address: manager.contract_address };

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager_dispatcher.pause();
    assert(pausable_dispatcher.is_paused(), 'Should be paused');

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager_dispatcher.unpause();

    assert(!pausable_dispatcher.is_paused(), ' not be paused after unpause()');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_unpause_not_owner() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.pause();
    manager.unpause();
}

#[test]
#[should_panic(expected: "Inconsistent lengths")]
fn test_manage_vault_with_merkle_verification_inconsistent_lengths_1() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    manager
        .manage_vault_with_merkle_verification(
            array![array![].span()].span(),
            array![].span(),
            array![].span(),
            array![].span(),
            array![].span(),
        );
}

#[test]
#[should_panic(expected: "Inconsistent lengths")]
fn test_manage_vault_with_merkle_verification_inconsistent_lengths_2() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    manager
        .manage_vault_with_merkle_verification(
            array![array![].span()].span(),
            array![DUMMY_ADDRESS()].span(),
            array![].span(),
            array![].span(),
            array![].span(),
        );
}

#[test]
#[should_panic(expected: "Inconsistent lengths")]
fn test_manage_vault_with_merkle_verification_inconsistent_lengths_3() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());

    manager
        .manage_vault_with_merkle_verification(
            array![array![].span()].span(),
            array![DUMMY_ADDRESS()].span(),
            array![DUMMY_ADDRESS()].span(),
            array![].span(),
            array![].span(),
        );
}

#[test]
#[should_panic(expected: "Inconsistent lengths")]
fn test_manage_vault_with_merkle_verification_inconsistent_lengths_4() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());

    manager
        .manage_vault_with_merkle_verification(
            array![array![].span()].span(),
            array![DUMMY_ADDRESS()].span(),
            array![DUMMY_ADDRESS()].span(),
            array![3].span(),
            array![].span(),
        );
}

#[test]
#[should_panic(expected: "Invalid manage proof")]
fn test_manage_vault_with_merkle_verification_invalid_proof() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    let simple_decoder_and_sanitizer = deploy_simple_decoder_and_sanitizer();
    let underlying = deploy_erc20_mock();
    let erc4626 = deploy_erc4626_mock(underlying);
    let mut leafs: Array<ManageLeaf> = ArrayTrait::new();
    let mut leaf_index: u256 = 0;
    _add_erc4626_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        erc4626,
    );
    _pad_leafs_to_power_of_two(ref leafs, ref leaf_index);
    let tree = generate_merkle_tree(leafs.span());

    let mut array_of_decoders_and_sanitizers = ArrayTrait::new();
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);

    let mut array_of_targets = ArrayTrait::new();
    array_of_targets.append(underlying);
    array_of_targets.append(erc4626);

    let mut array_of_selectors = ArrayTrait::new();
    array_of_selectors.append(selector!("approve"));
    array_of_selectors.append(selector!("deposit"));
    let mut array_of_calldatas = ArrayTrait::new();
    let mut array_of_calldata_approve: Array<felt252> = ArrayTrait::new();
    vault_allocator.contract_address.serialize(ref array_of_calldata_approve);
    let amount: u256 = WAD;
    amount.serialize(ref array_of_calldata_approve);
    array_of_calldatas.append(array_of_calldata_approve.span());

    let mut array_of_calldata_deposit: Array<felt252> = ArrayTrait::new();
    amount.serialize(ref array_of_calldata_deposit);
    vault_allocator.contract_address.serialize(ref array_of_calldata_deposit);
    array_of_calldatas.append(array_of_calldata_deposit.span());

    let mut manage_leafs: Array<ManageLeaf> = ArrayTrait::new();
    manage_leafs.append(leafs.at(0).clone());
    manage_leafs.append(leafs.at(1).clone());

    let proofs = _get_proofs_using_tree(manage_leafs, tree);
    manager
        .manage_vault_with_merkle_verification(
            proofs.span(),
            array_of_decoders_and_sanitizers.span(),
            array_of_targets.span(),
            array_of_selectors.span(),
            array_of_calldatas.span(),
        );
}

#[test]
fn test_manage_vault_with_merkle_verification_valid_proof() {
    let vault_allocator = deploy_vault_allocator();
    let manager = deploy_manager(vault_allocator, VESU_SINGLETON());
    let simple_decoder_and_sanitizer = deploy_simple_decoder_and_sanitizer();
    let underlying = deploy_erc20_mock();
    let erc4626 = deploy_erc4626_mock(underlying);
    let mut leafs: Array<ManageLeaf> = ArrayTrait::new();
    let mut leaf_index: u256 = 0;
    _add_erc4626_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        erc4626,
    );
    _pad_leafs_to_power_of_two(ref leafs, ref leaf_index);
    let tree = generate_merkle_tree(leafs.span());

    let mut array_of_decoders_and_sanitizers = ArrayTrait::new();
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);

    let mut array_of_targets = ArrayTrait::new();
    array_of_targets.append(underlying);
    array_of_targets.append(erc4626);

    let mut array_of_selectors = ArrayTrait::new();
    array_of_selectors.append(selector!("approve"));
    array_of_selectors.append(selector!("deposit"));
    let mut array_of_calldatas = ArrayTrait::new();
    let mut array_of_calldata_approve: Array<felt252> = ArrayTrait::new();
    erc4626.serialize(ref array_of_calldata_approve);
    let amount: u256 = WAD;
    amount.serialize(ref array_of_calldata_approve);
    array_of_calldatas.append(array_of_calldata_approve.span());

    let mut array_of_calldata_deposit: Array<felt252> = ArrayTrait::new();
    amount.serialize(ref array_of_calldata_deposit);
    vault_allocator.contract_address.serialize(ref array_of_calldata_deposit);
    array_of_calldatas.append(array_of_calldata_deposit.span());

    let mut manage_leafs: Array<ManageLeaf> = ArrayTrait::new();
    manage_leafs.append(leafs.at(0).clone());
    manage_leafs.append(leafs.at(1).clone());

    let proofs = _get_proofs_using_tree(manage_leafs, tree.clone());

    let manager_root = *tree.at(tree.len() - 1).at(0);

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(STRATEGIST(), manager_root);
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(manager.contract_address);
    cheat_caller_address_once(manager.contract_address, OWNER());

    let underlying_disp = ERC20ABIDispatcher { contract_address: underlying };

    cheat_caller_address_once(underlying, OWNER());
    underlying_disp.transfer(vault_allocator.contract_address, WAD * 10);

    let balance = underlying_disp.balance_of(vault_allocator.contract_address);
    assert(balance == WAD * 10, 'Balance wrong');

    cheat_caller_address_once(manager.contract_address, STRATEGIST());
    manager
        .manage_vault_with_merkle_verification(
            proofs.span(),
            array_of_decoders_and_sanitizers.span(),
            array_of_targets.span(),
            array_of_selectors.span(),
            array_of_calldatas.span(),
        );

    let strategy_balance = ERC20ABIDispatcher { contract_address: erc4626 }
        .balance_of(vault_allocator.contract_address);
    assert(strategy_balance == WAD, 'Balance wrong');

    let underlying_balance = underlying_disp.balance_of(vault_allocator.contract_address);
    assert(underlying_balance == WAD * 9, 'Balance wrong');
}

#[test]
#[should_panic(expected: "Not vault allocator")]
fn test_flash_loan_not_vault_allocator() {
    let vault_allocator = deploy_vault_allocator();
    let flashloan_mock = deploy_flashloan_mock();
    let manager = deploy_manager(vault_allocator, flashloan_mock);
    manager
        .flash_loan(
            manager.contract_address, manager.contract_address, WAD, false, array!['0xdead'].span(),
        );
}

#[test]
#[should_panic(expected: "Not vesu singleton")]
fn test_on_flash_loan_not_vesu_singleton() {
    let vault_allocator = deploy_vault_allocator();
    let flashloan_mock = deploy_flashloan_mock();
    let manager = deploy_manager(vault_allocator, flashloan_mock);
    let flash_loan_recipient_dispatcher = IFlashloanReceiverDispatcher {
        contract_address: manager.contract_address,
    };
    flash_loan_recipient_dispatcher
        .on_flash_loan(DUMMY_ADDRESS(), DUMMY_ADDRESS(), WAD, array!['0xdead'].span());
}

#[test]
#[should_panic(expected: "Flash loan not executed")]
fn test_flash_loan_not_executed() {
    let vault_allocator = deploy_vault_allocator();
    let flashloan_mock = deploy_flashloan_mock();
    let underlying = deploy_erc20_mock();
    let underlying_disp = ERC20ABIDispatcher { contract_address: underlying };
    cheat_caller_address_once(underlying, OWNER());
    underlying_disp.transfer(flashloan_mock, WAD * 10);
    let manager = deploy_manager(vault_allocator, flashloan_mock);
    let simple_decoder_and_sanitizer = deploy_simple_decoder_and_sanitizer();

    let mut leafs: Array<ManageLeaf> = ArrayTrait::new();
    let mut leaf_index: u256 = 0;

    _add_vesu_flash_loan_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        manager.contract_address,
        underlying,
        false,
    );

    _pad_leafs_to_power_of_two(ref leafs, ref leaf_index);

    let tree = generate_merkle_tree(leafs.span());

    let root = *tree.at(tree.len() - 1).at(0);
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(manager.contract_address);

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(STRATEGIST(), root);

    // Since the manager calls to itself to fulfill the flashloan, we need to set its root.
    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(manager.contract_address, root);

    let mut array_of_decoders_and_sanitizers = ArrayTrait::new();
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);

    let mut array_of_targets = ArrayTrait::new();
    array_of_targets.append(manager.contract_address);

    let mut array_of_selectors = ArrayTrait::new();
    array_of_selectors.append(selector!("flash_loan"));

    let mut array_of_calldatas = ArrayTrait::new();
    let mut array_of_calldatas_flash_loan = ArrayTrait::new();
    manager.contract_address.serialize(ref array_of_calldatas_flash_loan);
    underlying.serialize(ref array_of_calldatas_flash_loan);
    WAD.serialize(ref array_of_calldatas_flash_loan);
    false.serialize(ref array_of_calldatas_flash_loan);

    let mut flash_loan_data_proofs: Array<Span<felt252>> = ArrayTrait::new();
    let mut flash_loan_data_decoder_and_sanitizer: Array<ContractAddress> = ArrayTrait::new();
    let mut flash_loan_data_target: Array<ContractAddress> = ArrayTrait::new();
    let mut flash_loan_data_selector: Array<felt252> = ArrayTrait::new();
    let mut flash_loan_data_calldata: Array<Span<felt252>> = ArrayTrait::new();
    let mut serialized_flash_loan_data = ArrayTrait::new();
    (
        flash_loan_data_proofs.span(),
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

    IFlashLoanSingletonMockDispatcher { contract_address: flashloan_mock }.set_do_nothing(true);

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

#[test]
#[should_panic(expected: "Bad flash loan intent hash")]
fn test_flash_loan_bad_flash_loan_intent_hash() {
    let vault_allocator = deploy_vault_allocator();
    let flashloan_mock = deploy_flashloan_mock();
    let underlying = deploy_erc20_mock();
    let underlying_disp = ERC20ABIDispatcher { contract_address: underlying };
    cheat_caller_address_once(underlying, OWNER());
    underlying_disp.transfer(flashloan_mock, WAD * 10);
    let manager = deploy_manager(vault_allocator, flashloan_mock);
    let simple_decoder_and_sanitizer = deploy_simple_decoder_and_sanitizer();

    let mut leafs: Array<ManageLeaf> = ArrayTrait::new();
    let mut leaf_index: u256 = 0;

    _add_vesu_flash_loan_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        manager.contract_address,
        underlying,
        false,
    );

    _pad_leafs_to_power_of_two(ref leafs, ref leaf_index);

    let tree = generate_merkle_tree(leafs.span());

    let root = *tree.at(tree.len() - 1).at(0);
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(manager.contract_address);

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(STRATEGIST(), root);

    // Since the manager calls to itself to fulfill the flashloan, we need to set its root.
    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(manager.contract_address, root);

    let mut array_of_decoders_and_sanitizers = ArrayTrait::new();
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);

    let mut array_of_targets = ArrayTrait::new();
    array_of_targets.append(manager.contract_address);

    let mut array_of_selectors = ArrayTrait::new();
    array_of_selectors.append(selector!("flash_loan"));

    let mut array_of_calldatas = ArrayTrait::new();
    let mut array_of_calldatas_flash_loan = ArrayTrait::new();
    manager.contract_address.serialize(ref array_of_calldatas_flash_loan);
    underlying.serialize(ref array_of_calldatas_flash_loan);
    WAD.serialize(ref array_of_calldatas_flash_loan);
    false.serialize(ref array_of_calldatas_flash_loan);

    let mut flash_loan_data_proofs: Array<Span<felt252>> = ArrayTrait::new();
    let mut flash_loan_data_decoder_and_sanitizer: Array<ContractAddress> = ArrayTrait::new();
    let mut flash_loan_data_target: Array<ContractAddress> = ArrayTrait::new();
    let mut flash_loan_data_selector: Array<felt252> = ArrayTrait::new();
    let mut flash_loan_data_calldata: Array<Span<felt252>> = ArrayTrait::new();
    let mut serialized_flash_loan_data = ArrayTrait::new();
    (
        flash_loan_data_proofs.span(),
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

    IFlashLoanSingletonMockDispatcher { contract_address: flashloan_mock }
        .set_do_wrong_callback(true);

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

#[test]
fn test_flash_loan_bad_flash_loan() {
    let vault_allocator = deploy_vault_allocator();
    let flashloan_mock = deploy_flashloan_mock();
    let underlying = deploy_erc20_mock();
    let underlying_disp = ERC20ABIDispatcher { contract_address: underlying };
    cheat_caller_address_once(underlying, OWNER());
    underlying_disp.transfer(flashloan_mock, WAD * 10);
    let manager = deploy_manager(vault_allocator, flashloan_mock);
    let simple_decoder_and_sanitizer = deploy_simple_decoder_and_sanitizer();

    let mut leafs: Array<ManageLeaf> = ArrayTrait::new();
    let mut leaf_index: u256 = 0;

    _add_vesu_flash_loan_leafs(
        ref leafs,
        ref leaf_index,
        vault_allocator.contract_address,
        simple_decoder_and_sanitizer,
        manager.contract_address,
        underlying,
        false,
    );

    let amount_flash_loan = WAD;

    // approve the mock flashloan token to spend underlying

    let mut argument_addresses_approve = ArrayTrait::new();
    flashloan_mock.serialize(ref argument_addresses_approve);
    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer: simple_decoder_and_sanitizer,
                target: underlying,
                selector: selector!("approve"),
                argument_addresses: argument_addresses_approve.span(),
                description: "",
            },
        );

    leaf_index += 1;

    // do something function called approve from the mock flashloan
    let mut argument_addresses_fake_approve_func = ArrayTrait::new();
    underlying.serialize(ref argument_addresses_fake_approve_func);
    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer: simple_decoder_and_sanitizer,
                target: flashloan_mock,
                selector: selector!("approve"),
                argument_addresses: argument_addresses_fake_approve_func.span(),
                description: "Approve",
            },
        );
    leaf_index += 1;

    _pad_leafs_to_power_of_two(ref leafs, ref leaf_index);

    let tree = generate_merkle_tree(leafs.span());

    let root = *tree.at(tree.len() - 1).at(0);
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(manager.contract_address);

    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(STRATEGIST(), root);

    // Since the manager calls to itself to fulfill the flashloan, we need to set its root.
    cheat_caller_address_once(manager.contract_address, OWNER());
    manager.set_manage_root(manager.contract_address, root);

    let mut array_of_decoders_and_sanitizers = ArrayTrait::new();
    array_of_decoders_and_sanitizers.append(simple_decoder_and_sanitizer);

    let mut array_of_targets = ArrayTrait::new();
    array_of_targets.append(manager.contract_address);

    let mut array_of_selectors = ArrayTrait::new();
    array_of_selectors.append(selector!("flash_loan"));

    let mut array_of_calldatas = ArrayTrait::new();
    let mut array_of_calldatas_flash_loan = ArrayTrait::new();
    manager.contract_address.serialize(ref array_of_calldatas_flash_loan);
    underlying.serialize(ref array_of_calldatas_flash_loan);
    WAD.serialize(ref array_of_calldatas_flash_loan);
    false.serialize(ref array_of_calldatas_flash_loan);

    /// construct the flash loan data to trigger do_something from the flashloan mock
    let mut flash_loan_data_decoder_and_sanitizer: Array<ContractAddress> = ArrayTrait::new();
    flash_loan_data_decoder_and_sanitizer.append(simple_decoder_and_sanitizer);
    flash_loan_data_decoder_and_sanitizer.append(simple_decoder_and_sanitizer);

    let mut flash_loan_data_target: Array<ContractAddress> = ArrayTrait::new();
    flash_loan_data_target.append(underlying);
    flash_loan_data_target.append(flashloan_mock);

    let mut flash_loan_data_selector: Array<felt252> = ArrayTrait::new();
    flash_loan_data_selector.append(selector!("approve"));
    flash_loan_data_selector.append(selector!("approve"));

    let mut flash_loan_data_calldata: Array<Span<felt252>> = ArrayTrait::new();
    let mut flash_loan_data_calldata_approve = ArrayTrait::new();
    flashloan_mock.serialize(ref flash_loan_data_calldata_approve);
    amount_flash_loan.serialize(ref flash_loan_data_calldata_approve);

    let mut flash_loan_data_calldata_approve_fake = ArrayTrait::new();
    underlying.serialize(ref flash_loan_data_calldata_approve_fake);
    amount_flash_loan.serialize(ref flash_loan_data_calldata_approve_fake);
    flash_loan_data_calldata.append(flash_loan_data_calldata_approve.span());
    flash_loan_data_calldata.append(flash_loan_data_calldata_approve_fake.span());

    let mut flash_loan_manager_leafs: Array<ManageLeaf> = ArrayTrait::new();
    flash_loan_manager_leafs.append(leafs.at(1).clone());
    flash_loan_manager_leafs.append(leafs.at(2).clone());

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
    assert(
        IFlashLoanSingletonMockDispatcher { contract_address: flashloan_mock }.i_did_something(),
        'i_did_something is not true',
    );
}
