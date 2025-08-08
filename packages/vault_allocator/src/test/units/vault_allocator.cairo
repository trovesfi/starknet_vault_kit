// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::upgrades::interface::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use starknet::ContractAddress;
use starknet::account::Call;
use vault_allocator::mocks::counter::{ICounterDispatcher, ICounterDispatcherTrait};
use vault_allocator::test::utils::{
    MANAGER, OWNER, cheat_caller_address_once, deploy_counter, deploy_vault_allocator,
};
use vault_allocator::vault_allocator::interface::IVaultAllocatorDispatcherTrait;

#[test]
fn test_constructor() {
    let vault_allocator = deploy_vault_allocator();
    let owner = IOwnableDispatcher { contract_address: vault_allocator.contract_address }.owner();
    assert(owner == OWNER(), 'Owner is not set correctly');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_upgrade_not_owner() {
    let vault_allocator = deploy_vault_allocator();
    let (_, counter_class_hash) = deploy_counter();
    IUpgradeableDispatcher { contract_address: vault_allocator.contract_address }
        .upgrade(counter_class_hash);
}

#[test]
fn test_upgrade() {
    let vault_allocator = deploy_vault_allocator();
    let (_, counter_class_hash) = deploy_counter();
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    IUpgradeableDispatcher { contract_address: vault_allocator.contract_address }
        .upgrade(counter_class_hash);
    ICounterDispatcher { contract_address: vault_allocator.contract_address }.get_value();
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_manager_not_owner() {
    let vault_allocator = deploy_vault_allocator();
    let new_manager: ContractAddress = 'NEW_MANAGER'.try_into().unwrap();
    vault_allocator.set_manager(new_manager);
}

#[test]
fn test_set_manager() {
    let vault_allocator = deploy_vault_allocator();
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    let new_manager: ContractAddress = 'NEW_MANAGER'.try_into().unwrap();
    vault_allocator.set_manager(new_manager);
    let manager = vault_allocator.manager();
    assert(manager == new_manager, 'Manager is not set correctly');
}


#[test]
#[should_panic(expected: "Only manager can call this function")]
fn test_manage_not_manager() {
    let vault_allocator = deploy_vault_allocator();
    let call: Call = Call {
        to: vault_allocator.contract_address,
        selector: 'set_manager'.try_into().unwrap(),
        calldata: ArrayTrait::new().span(),
    };
    vault_allocator.manage(call);
}


#[test]
#[should_panic(expected: ('ENTRYPOINT_NOT_FOUND',))]
fn test_manage_invalid_entry_point() {
    let vault_allocator = deploy_vault_allocator();
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(MANAGER());
    let call: Call = Call {
        to: vault_allocator.contract_address,
        selector: 'set_manager'.try_into().unwrap(),
        calldata: ArrayTrait::new().span(),
    };
    cheat_caller_address_once(vault_allocator.contract_address, MANAGER());
    vault_allocator.manage(call);
}

#[test]
fn test_manage() {
    let vault_allocator = deploy_vault_allocator();
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(MANAGER());

    let (counter_dispatcher, _) = deploy_counter();
    let initial_value = counter_dispatcher.get_value();
    assert(initial_value == 0, 'init value');
    let counter_address = counter_dispatcher.contract_address;

    let mut calldata = ArrayTrait::new();
    let amount: u128 = 24;
    amount.serialize(ref calldata);

    let call: Call = Call {
        to: counter_address, selector: selector!("increase"), calldata: calldata.span(),
    };
    cheat_caller_address_once(vault_allocator.contract_address, MANAGER());
    vault_allocator.manage(call);

    let value = counter_dispatcher.get_value();
    assert(value == amount, 'Value is not set correctly');
}

#[test]
#[should_panic(expected: "Only manager can call this function")]
fn test_manage_multi_not_manager() {
    let vault_allocator = deploy_vault_allocator();
    let call: Call = Call {
        to: vault_allocator.contract_address, selector: 34, calldata: ArrayTrait::new().span(),
    };
    let mut calls = ArrayTrait::new();
    calls.append(call);
    vault_allocator.manage_multi(calls);
}

#[test]
#[should_panic(expected: ('ENTRYPOINT_NOT_FOUND',))]
fn test_manage_multi_invalid_entry_point() {
    let vault_allocator = deploy_vault_allocator();
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(MANAGER());
    let call: Call = Call {
        to: vault_allocator.contract_address, selector: 3434, calldata: ArrayTrait::new().span(),
    };
    let mut calls = ArrayTrait::new();
    calls.append(call);
    cheat_caller_address_once(vault_allocator.contract_address, MANAGER());
    vault_allocator.manage_multi(calls);
}

#[test]
fn test_manage_multi() {
    let vault_allocator = deploy_vault_allocator();
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(MANAGER());

    let (counter_dispatcher, _) = deploy_counter();
    let initial_value = counter_dispatcher.get_value();
    assert(initial_value == 0, 'init value');
    let counter_address = counter_dispatcher.contract_address;

    let mut calldata1 = ArrayTrait::new();
    let amount1: u128 = 10;
    amount1.serialize(ref calldata1);

    let mut calldata2 = ArrayTrait::new();
    let amount2: u128 = 15;
    amount2.serialize(ref calldata2);

    let call1: Call = Call {
        to: counter_address, selector: selector!("increase"), calldata: calldata1.span(),
    };
    let call2: Call = Call {
        to: counter_address, selector: selector!("increase"), calldata: calldata2.span(),
    };

    let mut calls = ArrayTrait::new();
    calls.append(call1);
    calls.append(call2);

    cheat_caller_address_once(vault_allocator.contract_address, MANAGER());
    let results = vault_allocator.manage_multi(calls);

    assert(results.len() == 2, 'Expected 2 results');
    let value = counter_dispatcher.get_value();
    assert(value == amount1 + amount2, 'Value is not set correctly');
}

#[test]
fn test_manage_multi_empty() {
    let vault_allocator = deploy_vault_allocator();
    cheat_caller_address_once(vault_allocator.contract_address, OWNER());
    vault_allocator.set_manager(MANAGER());

    let calls = ArrayTrait::new();
    cheat_caller_address_once(vault_allocator.contract_address, MANAGER());
    let results = vault_allocator.manage_multi(calls);

    assert(results.len() == 0, 'Expected 0 results');
}

