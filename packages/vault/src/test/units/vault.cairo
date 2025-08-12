// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::security::interface::{IPausableDispatcher, IPausableDispatcherTrait};
use openzeppelin::token::erc20::extensions::erc4626::interface::{
    IERC4626Dispatcher, IERC4626DispatcherTrait,
};
use openzeppelin::token::erc20::interface::{
    ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20MetadataDispatcher,
    IERC20MetadataDispatcherTrait,
};
use openzeppelin::token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
use openzeppelin::upgrades::interface::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use openzeppelin::utils::math;
use openzeppelin::utils::math::Rounding;
use snforge_std::{map_entry_address, store};
use starknet::ContractAddress;
use starknet::account::Call;
use vault::redeem_request::interface::{IRedeemRequestDispatcher, IRedeemRequestDispatcherTrait};
use vault::test::utils::{
    DUMMY_ADDRESS, FEES_RECIPIENT, MANAGEMENT_FEES, OTHER_DUMMY_ADDRESS, OWNER, PERFORMANCE_FEES,
    REDEEM_FEES, REPORT_DELAY, VAULT_ALLOCATOR, VAULT_NAME, VAULT_SYMBOL, between,
    cheat_caller_address_once, deploy_counter, deploy_erc20_mock, deploy_redeem_request,
    deploy_vault,
};
use vault::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use vault::vault::vault::Vault;
use vault_allocator::mocks::counter::{ICounterDispatcher, ICounterDispatcherTrait};

fn set_up() -> (ContractAddress, IVaultDispatcher, IRedeemRequestDispatcher) {
    let underlying_assets = deploy_erc20_mock();
    let vault = deploy_vault(underlying_assets);
    let redeem_request = deploy_redeem_request(vault.contract_address);
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.register_redeem_request(redeem_request.contract_address);
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.register_vault_allocator(VAULT_ALLOCATOR());
    (underlying_assets, vault, redeem_request)
}

#[test]
fn test_constructor() {
    let (underlying_assets, vault, redeem_request) = set_up();

    let access_control_dispatcher = IAccessControlDispatcher {
        contract_address: vault.contract_address,
    };
    let role_admin = access_control_dispatcher.get_role_admin(Vault::OWNER_ROLE);
    assert(role_admin == Vault::OWNER_ROLE, 'invalid role admin');
    let role_admin = access_control_dispatcher.get_role_admin(Vault::PAUSER_ROLE);
    assert(role_admin == Vault::OWNER_ROLE, 'invalid role admin');
    let role_admin = access_control_dispatcher.get_role_admin(Vault::ORACLE_ROLE);
    assert(role_admin == Vault::OWNER_ROLE, 'invalid role admin');

    let has_role = access_control_dispatcher.has_role(Vault::OWNER_ROLE, OWNER());
    assert(has_role, 'Owner is not set correctly');
    let has_role = access_control_dispatcher.has_role(Vault::PAUSER_ROLE, OWNER());
    assert(has_role, 'Pauser is not set correctly');
    let has_role = access_control_dispatcher.has_role(Vault::ORACLE_ROLE, OWNER());
    assert(has_role, 'Oracle is not set correctly');

    let erc20_metadata_dispatcher = IERC20MetadataDispatcher {
        contract_address: vault.contract_address,
    };
    assert(erc20_metadata_dispatcher.name() == VAULT_NAME(), 'Name is not set correctly');
    assert(erc20_metadata_dispatcher.symbol() == VAULT_SYMBOL(), 'Symbol is not set correctly');
    assert(erc20_metadata_dispatcher.decimals() == 18, 'Decimals are not set correctly');

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    assert(erc4626_dispatcher.asset() == underlying_assets, 'Underlying asset ');
    assert(vault.fees_recipient() == FEES_RECIPIENT(), 'Fees recipient');
    assert(vault.redeem_fees() == REDEEM_FEES(), 'Redeem fees');
    assert(vault.management_fees() == MANAGEMENT_FEES(), 'Management fees');
    assert(vault.performance_fees() == PERFORMANCE_FEES(), 'Performance fees');
    assert(vault.report_delay() == REPORT_DELAY(), 'Report delay');
    assert(vault.redeem_request() == redeem_request.contract_address, 'Redeem request');
    assert(vault.vault_allocator() == VAULT_ALLOCATOR(), 'Vault allocator');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_upgrade_not_owner() {
    let (_, vault, _) = set_up();
    let (_, counter_class_hash) = deploy_counter();
    IUpgradeableDispatcher { contract_address: vault.contract_address }.upgrade(counter_class_hash);
}

#[test]
fn test_upgrade() {
    let (_, vault, _) = set_up();
    let (_, counter_class_hash) = deploy_counter();
    cheat_caller_address_once(vault.contract_address, OWNER());
    IUpgradeableDispatcher { contract_address: vault.contract_address }.upgrade(counter_class_hash);
    ICounterDispatcher { contract_address: vault.contract_address }.get_value();
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_register_redeem_not_owner() {
    let (_, vault, _) = set_up();
    vault.register_redeem_request(DUMMY_ADDRESS());
}

#[test]
#[should_panic(expected: "Redeem request already registered")]
fn test_register_redeem_already_registered() {
    let (_, vault, _) = set_up();
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.register_redeem_request(DUMMY_ADDRESS());
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_register_vault_allocator_not_owner() {
    let (_, vault, _) = set_up();
    vault.register_vault_allocator(DUMMY_ADDRESS());
}

#[test]
#[should_panic(expected: "Vault allocator already registered")]
fn test_register_vault_allocator_already_registered() {
    let (_, vault, _) = set_up();
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.register_vault_allocator(DUMMY_ADDRESS());
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_set_fees_config_not_owner() {
    let (_, vault, _) = set_up();
    vault.set_fees_config(FEES_RECIPIENT(), REDEEM_FEES(), MANAGEMENT_FEES(), PERFORMANCE_FEES());
}

#[test]
#[should_panic(expected: "Invalid redeem fees")]
fn test_set_fees_config_invalid_redeem_fees() {
    let (_, vault, _) = set_up();
    let invalid_redeem_fees = Vault::MAX_REDEEM_FEE + 1;
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault
        .set_fees_config(
            FEES_RECIPIENT(), invalid_redeem_fees, MANAGEMENT_FEES(), PERFORMANCE_FEES(),
        );
}

#[test]
#[should_panic(expected: "Invalid management fees")]
fn test_set_fees_config_invalid_management_fees() {
    let (_, vault, _) = set_up();
    let invalid_management_fees = Vault::MAX_MANAGEMENT_FEE + 1;
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault
        .set_fees_config(
            FEES_RECIPIENT(), REDEEM_FEES(), invalid_management_fees, PERFORMANCE_FEES(),
        );
}

#[test]
#[should_panic(expected: "Invalid performance fees")]
fn test_set_fees_config_invalid_performance_fees() {
    let (_, vault, _) = set_up();
    let invalid_performance_fees = Vault::MAX_PERFORMANCE_FEE + 1;
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault
        .set_fees_config(
            FEES_RECIPIENT(), REDEEM_FEES(), MANAGEMENT_FEES(), invalid_performance_fees,
        );
}

#[test]
fn test_set_fees_config_success() {
    let (_, vault, _) = set_up();
    let new_fees_recipient = DUMMY_ADDRESS();
    let new_redeem_fees = Vault::MAX_REDEEM_FEE;
    let new_management_fees = Vault::MAX_MANAGEMENT_FEE;
    let new_performance_fees = Vault::MAX_PERFORMANCE_FEE;

    cheat_caller_address_once(vault.contract_address, OWNER());
    vault
        .set_fees_config(
            new_fees_recipient, new_redeem_fees, new_management_fees, new_performance_fees,
        );

    assert(vault.fees_recipient() == new_fees_recipient, 'Fees recipient not updated');
    assert(vault.redeem_fees() == new_redeem_fees, 'Redeem fees not updated');
    assert(vault.management_fees() == new_management_fees, 'Management fees not updated');
    assert(vault.performance_fees() == new_performance_fees, 'Performance fees not updated');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_set_report_delay_not_owner() {
    let (_, vault, _) = set_up();
    vault.set_report_delay(Vault::MIN_REPORT_DELAY);
}

#[test]
#[should_panic(expected: "Invalid report delay")]
fn test_set_report_delay_invalid_delay() {
    let (_, vault, _) = set_up();
    let invalid_delay = Vault::MIN_REPORT_DELAY - 1;
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.set_report_delay(invalid_delay);
}

#[test]
fn test_set_report_delay_success() {
    let (_, vault, _) = set_up();
    let new_delay = Vault::MIN_REPORT_DELAY + 100;
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.set_report_delay(new_delay);
    assert(vault.report_delay() == new_delay, 'Report delay not updated');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_pause_not_pauser() {
    let (_, vault, _) = set_up();
    vault.pause();
}

#[test]
fn test_pause_success() {
    let (_, vault, _) = set_up();
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.pause();
    let pausable_dispatcher = IPausableDispatcher { contract_address: vault.contract_address };
    assert(pausable_dispatcher.is_paused(), 'Vault is not unpaused');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_unpause_not_owner() {
    let (_, vault, _) = set_up();
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.pause();
    vault.unpause();
}

#[test]
fn test_unpause_success() {
    let (_, vault, _) = set_up();
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.pause();
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.unpause();
    let pausable_dispatcher = IPausableDispatcher { contract_address: vault.contract_address };
    assert(!pausable_dispatcher.is_paused(), 'Vault is not unpaused');
}

#[test]
#[should_panic(expected: "Not implemented")]
fn test_redeem_not_implemented() {
    let (underlying, vault, _) = set_up();

    let deposit_amount = Vault::WAD;
    cheat_caller_address_once(underlying, OWNER());
    ERC20ABIDispatcher { contract_address: underlying }
        .approve(vault.contract_address, deposit_amount);

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };

    cheat_caller_address_once(vault.contract_address, OWNER());
    let shares = erc4626_dispatcher.deposit(deposit_amount, OWNER());

    cheat_caller_address_once(vault.contract_address, OWNER());
    erc4626_dispatcher.redeem(shares, OWNER(), OWNER());
}

#[test]
#[should_panic(expected: "Not implemented")]
fn test_withdraw_not_implemented() {
    let (underlying, vault, _) = set_up();

    let deposit_amount = Vault::WAD;
    cheat_caller_address_once(underlying, OWNER());
    ERC20ABIDispatcher { contract_address: underlying }
        .approve(vault.contract_address, deposit_amount);

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };

    cheat_caller_address_once(vault.contract_address, OWNER());
    erc4626_dispatcher.deposit(deposit_amount, OWNER());

    cheat_caller_address_once(vault.contract_address, OWNER());
    erc4626_dispatcher.withdraw(deposit_amount, OWNER(), OWNER());
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_deposit_when_paused() {
    let (underlying, vault, _) = set_up();

    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.pause();

    let deposit_amount = Vault::WAD;
    cheat_caller_address_once(underlying, OWNER());
    ERC20ABIDispatcher { contract_address: underlying }
        .approve(vault.contract_address, deposit_amount);

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    cheat_caller_address_once(vault.contract_address, OWNER());
    erc4626_dispatcher.deposit(deposit_amount, OWNER());
}

#[test]
#[fuzzer]
fn test_deposit_success_buffer_increase(x: u256) {
    let (underlying, vault, _) = set_up();

    let deposit_amount = between(1, Vault::WAD * 100, x);
    let buffer_before = vault.buffer();

    cheat_caller_address_once(underlying, OWNER());
    ERC20ABIDispatcher { contract_address: underlying }
        .approve(vault.contract_address, deposit_amount);

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    cheat_caller_address_once(vault.contract_address, OWNER());
    let shares = erc4626_dispatcher.deposit(deposit_amount, OWNER());

    let buffer_after = vault.buffer();
    assert(buffer_after == buffer_before + deposit_amount, 'Buffer did not increase');
    assert(shares > 0, 'No shares minted');

    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: vault.contract_address };
    assert(erc20_dispatcher.balance_of(OWNER()) == shares, 'Shares not minted to owner');
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_request_redeem_paused() {
    let (_, vault, _) = set_up();
    cheat_caller_address_once(vault.contract_address, OWNER());
    vault.pause();
    vault.request_redeem(Vault::WAD, DUMMY_ADDRESS(), DUMMY_ADDRESS());
}

#[test]
#[fuzzer]
#[should_panic(expected: "Exceeded max redeem")]
fn test_request_redeem_exceeds_max_redeem(x: u256) {
    let (underlying, vault, _) = set_up();

    let deposit_amount = Vault::WAD;

    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: underlying };

    cheat_caller_address_once(underlying, OWNER());
    erc20_dispatcher.transfer(DUMMY_ADDRESS(), deposit_amount);

    cheat_caller_address_once(underlying, DUMMY_ADDRESS());
    erc20_dispatcher.approve(vault.contract_address, deposit_amount);

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    cheat_caller_address_once(vault.contract_address, DUMMY_ADDRESS());
    let shares = erc4626_dispatcher.deposit(deposit_amount, DUMMY_ADDRESS());

    let shares_to_redeem = between(shares + 1, shares * 100, x);

    cheat_caller_address_once(vault.contract_address, OTHER_DUMMY_ADDRESS());
    vault.request_redeem(shares_to_redeem, OTHER_DUMMY_ADDRESS(), DUMMY_ADDRESS());
}

#[test]
#[fuzzer]
#[should_panic(expected: ('ERC20: insufficient allowance',))]
fn test_request_redeem_exceeds_max_allowance(x: u256) {
    let (underlying, vault, _) = set_up();

    let deposit_amount = Vault::WAD;

    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: underlying };

    cheat_caller_address_once(underlying, OWNER());
    erc20_dispatcher.transfer(DUMMY_ADDRESS(), deposit_amount);

    cheat_caller_address_once(underlying, DUMMY_ADDRESS());
    erc20_dispatcher.approve(vault.contract_address, deposit_amount);

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    cheat_caller_address_once(vault.contract_address, DUMMY_ADDRESS());
    let shares = erc4626_dispatcher.deposit(deposit_amount, DUMMY_ADDRESS());

    let shares_to_redeem = between(1, shares, x);

    cheat_caller_address_once(vault.contract_address, OTHER_DUMMY_ADDRESS());
    vault.request_redeem(shares_to_redeem, OTHER_DUMMY_ADDRESS(), DUMMY_ADDRESS());
}

#[test]
#[should_panic(expected: "Zero assets")]
fn test_request_redeem_exceeds_zero_assets() {
    let (underlying, vault, _) = set_up();

    let deposit_amount = Vault::WAD;

    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: underlying };

    cheat_caller_address_once(underlying, OWNER());
    erc20_dispatcher.transfer(DUMMY_ADDRESS(), deposit_amount);

    cheat_caller_address_once(underlying, DUMMY_ADDRESS());
    erc20_dispatcher.approve(vault.contract_address, deposit_amount);

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    cheat_caller_address_once(vault.contract_address, DUMMY_ADDRESS());
    erc4626_dispatcher.deposit(deposit_amount, DUMMY_ADDRESS());

    let shares_to_redeem = 1;

    let erc20_dispatcher_vault = ERC20ABIDispatcher { contract_address: vault.contract_address };
    cheat_caller_address_once(vault.contract_address, DUMMY_ADDRESS());
    erc20_dispatcher_vault.approve(OTHER_DUMMY_ADDRESS(), shares_to_redeem);

    let mut cheat_calldata = ArrayTrait::new();
    (deposit_amount - 1).serialize(ref cheat_calldata);

    store(vault.contract_address, selector!("buffer"), cheat_calldata.span());

    cheat_caller_address_once(vault.contract_address, OTHER_DUMMY_ADDRESS());
    vault.request_redeem(shares_to_redeem, OTHER_DUMMY_ADDRESS(), DUMMY_ADDRESS());
}

#[test]
#[fuzzer]
fn test_request_redeem_success(x: u256) {
    let (underlying, vault, redeem_request) = set_up();

    let deposit_amount = Vault::WAD;

    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: underlying };

    cheat_caller_address_once(underlying, OWNER());
    erc20_dispatcher.transfer(DUMMY_ADDRESS(), deposit_amount);

    cheat_caller_address_once(underlying, DUMMY_ADDRESS());
    erc20_dispatcher.approve(vault.contract_address, deposit_amount);

    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    cheat_caller_address_once(vault.contract_address, DUMMY_ADDRESS());
    let shares = erc4626_dispatcher.deposit(deposit_amount, DUMMY_ADDRESS());

    let shares_to_redeem = between(1, shares, x);

    let erc20_dispatcher_vault = ERC20ABIDispatcher { contract_address: vault.contract_address };
    cheat_caller_address_once(vault.contract_address, DUMMY_ADDRESS());
    erc20_dispatcher_vault.approve(OTHER_DUMMY_ADDRESS(), shares_to_redeem);

    let mut cheat_calldata_buffer = ArrayTrait::new();
    (deposit_amount * 10).serialize(ref cheat_calldata_buffer); // make share price 10x higher
    store(vault.contract_address, selector!("buffer"), cheat_calldata_buffer.span());

    let mut cheat_calldata_epoch = ArrayTrait::new();
    let epoch: u256 = 7;
    epoch.serialize(ref cheat_calldata_epoch);
    store(vault.contract_address, selector!("epoch"), cheat_calldata_epoch.span());

    let mut cheat_calldata_redeem_nominal = ArrayTrait::new();
    (2 * Vault::WAD).serialize(ref cheat_calldata_redeem_nominal);

    let mut map_entry = map_entry_address(selector!("redeem_nominal"), cheat_calldata_epoch.span());
    store(vault.contract_address, map_entry, cheat_calldata_redeem_nominal.span());

    assert(vault.buffer() == deposit_amount * 10, 'Buffer not updated');
    assert(vault.epoch() == epoch, 'Epoch not updated');
    assert(vault.redeem_nominal(epoch) == 2 * Vault::WAD, 'Redeem nominal not updated');

    cheat_caller_address_once(vault.contract_address, OTHER_DUMMY_ADDRESS());
    let id = vault.request_redeem(shares_to_redeem, OTHER_DUMMY_ADDRESS(), DUMMY_ADDRESS());
    assert(id == 0, 'Id not minted');

    assert(
        erc20_dispatcher_vault.balance_of(DUMMY_ADDRESS()) == shares - shares_to_redeem,
        'Shares not burned',
    );

    let expected_shares_fee_recipient = shares_to_redeem * REDEEM_FEES() / Vault::WAD;
    let remaining_shares = shares_to_redeem - expected_shares_fee_recipient;
    let expected_assets = math::u256_mul_div(
        remaining_shares, deposit_amount * 10 + 1, deposit_amount + 1, Rounding::Floor,
    );

    let expected_redeem_nominal = 2 * Vault::WAD + expected_assets;

    assert(vault.redeem_nominal(epoch) == expected_redeem_nominal, 'Redeem nominal not updated');

    let id_info = redeem_request.id_to_info(id);
    assert(id_info.epoch == epoch, 'Epoch not set correctly');
    assert(id_info.nominal == expected_assets, 'Nominal not set correctly');

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    assert(erc721_dispatcher.owner_of(id) == OTHER_DUMMY_ADDRESS(), 'Owner not set correctly');
}

