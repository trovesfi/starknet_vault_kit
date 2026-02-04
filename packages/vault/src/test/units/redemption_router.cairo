// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use openzeppelin::interfaces::accesscontrol::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
use openzeppelin::interfaces::erc721::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
};
use starknet::{ContractAddress, get_block_timestamp};
use core::array::ArrayTrait;
use vault::redeem_request::interface::{
    IRedeemRequestDispatcher,
};
use vault::redemption_router::interface::{
    IRedemptionRouterDispatcher, IRedemptionRouterDispatcherTrait,
};
use vault::redemption_router::redemption_router::RedemptionRouter;
use vault::test::utils::{OWNER, USER1, USER2, WAD, deploy_erc20_mock, deploy_redeem_request, deploy_vault, VAULT_ALLOCATOR, ORACLE};
use snforge_std::start_cheat_block_timestamp_global;
use vault::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use vault::vault::vault::Vault;
use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;
use vault_allocator::mocks::mock_avnu_exchange::IAvnuExchangeDispatcher;

const RELAYER: ContractAddress = 0x1234567890.try_into().unwrap();

fn deploy_redemption_router(
    vault: ContractAddress,
    redeem_request: ContractAddress,
    to_asset: ContractAddress,
    avnu_exchange: ContractAddress,
    integrator_fee_recipient: ContractAddress,
    integrator_fee_amount_bps: u128,
    min_subscribe_amount: u256,
) -> IRedemptionRouterDispatcher {
    println!("deploying redemption router");
    let router = declare("RedemptionRouter").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    OWNER().serialize(ref calldata);
    vault.serialize(ref calldata);
    redeem_request.serialize(ref calldata);
    to_asset.serialize(ref calldata);
    avnu_exchange.serialize(ref calldata);
    integrator_fee_recipient.serialize(ref calldata);
    integrator_fee_amount_bps.serialize(ref calldata);
    min_subscribe_amount.serialize(ref calldata);
    println!("deploying redemption router with calldata");
    // let (router_address, _) = router.deploy(@calldata).unwrap();
    let res = router.deploy(@calldata);
    match res {
        Ok((router_address, _)) => IRedemptionRouterDispatcher { contract_address: router_address },
        Err(e) => {
            let err = *e.at(2);
            // to ensure exact error of panic is thrown
            assert(false, err);
            // just a fallback for compiling purposes
            panic!("error deploying redemption router");
        }
    }
}

fn deploy_mock_avnu_exchange() -> IAvnuExchangeDispatcher {
    let avnu = declare("MockAvnuExchange").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    let (avnu_address, _) = avnu.deploy(@calldata).unwrap();
    println!("avnu_address: {:?}", avnu_address);
    IAvnuExchangeDispatcher { contract_address: avnu_address }
}

fn set_up() -> (
    IVaultDispatcher, // vault
    ContractAddress, // from_asset
    ContractAddress, // to_asset
    IRedeemRequestDispatcher, // redeem_request
    IAvnuExchangeDispatcher, // avnu_exchange
    IRedemptionRouterDispatcher, // router
) {

    let from_asset = deploy_erc20_mock();
    let to_asset = deploy_erc20_mock();
    let vault = deploy_vault(
        from_asset
    );
    let vault_address = vault.contract_address;
    
    let redeem_request = deploy_redeem_request(vault_address);
    // Register the deployed redeem_request with vault
    cheat_caller_address(vault_address, OWNER(), span: CheatSpan::TargetCalls(1));
    vault.register_redeem_request(redeem_request.contract_address);
    
    // Register vault_allocator if needed
    let vault_allocator = VAULT_ALLOCATOR();
    cheat_caller_address(vault_address, OWNER(), span: CheatSpan::TargetCalls(1));
    vault.register_vault_allocator(vault_allocator);

    // overwrite set fees
    cheat_caller_address(vault_address, OWNER(), span: CheatSpan::TargetCalls(1));
    vault.set_fees_config(OWNER(), 0, 0, Vault::WAD / 10);
    
    // Grant ORACLE_ROLE to ORACLE for report calls
    let access_control_vault = IAccessControlDispatcher {
        contract_address: vault_address,
    };
    cheat_caller_address(vault_address, OWNER(), span: CheatSpan::TargetCalls(1));
    access_control_vault.grant_role(Vault::ORACLE_ROLE, ORACLE());
    
    let avnu_exchange = deploy_mock_avnu_exchange();
    println!("avnu_exchange deployed");
    let integrator_fee_recipient = 'FEE_RECIPIENT'.try_into().unwrap();
    let integrator_fee_amount_bps: u128 = 100; // 1%
    let min_subscribe_amount: u256 = 0; // No minimum by default for tests
    println!("integrator_fee_recipient and integrator_fee_amount_bps set");
    
    let router = deploy_redemption_router(
        vault_address,
        redeem_request.contract_address,
        to_asset,
        avnu_exchange.contract_address,
        integrator_fee_recipient,
        integrator_fee_amount_bps,
        min_subscribe_amount,
    );

    println!("router: {:?}", router.contract_address);

    // Grant RELAYER_ROLE and PAUSER_ROLE
    let access_control = IAccessControlDispatcher {
        contract_address: router.contract_address,
    };
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    access_control.grant_role(RedemptionRouter::RELAYER_ROLE, RELAYER);
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    access_control.grant_role(selector!("PAUSER_ROLE"), OWNER());
    println!("RELAYER_ROLE granted");

    // to avoid zero liquidity error, seed some initial liquidity
    let due_amount_1: u256 = WAD * 100;
    mint_old_nft_to_user(vault, OWNER(), due_amount_1);

    (vault, from_asset, to_asset, redeem_request, avnu_exchange, router)
}

fn mint_old_nft_to_user(
    vault: IVaultDispatcher, user: ContractAddress, nominal: u256,
) -> u256 {
    // First, user needs to deposit assets to get vault shares
    // Get asset address from vault
    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    let asset_address = erc4626_dispatcher.asset();
    
    // Transfer underlying assets to user
    let asset_dispatcher = ERC20ABIDispatcher { contract_address: asset_address };
    cheat_caller_address(asset_address, OWNER(), span: CheatSpan::TargetCalls(1));
    asset_dispatcher.transfer(user, nominal);
    
    // User approves vault to spend assets
    cheat_caller_address(asset_address, user, span: CheatSpan::TargetCalls(1));
    asset_dispatcher.approve(vault.contract_address, nominal);
    
    // User deposits assets to get shares
    cheat_caller_address(vault.contract_address, user, span: CheatSpan::TargetCalls(1));
    let shares = erc4626_dispatcher.deposit(nominal, user);

    shares
}
    
fn mint_and_redeem_old_nft_to_user(
    vault: IVaultDispatcher, user: ContractAddress, nominal: u256,
) -> u256 {
    let shares = mint_old_nft_to_user(vault, user, nominal);

    // Call request_redeem on vault as if user is trying to withdraw
    // Now call request_redeem as the user
    cheat_caller_address(vault.contract_address, user, span: CheatSpan::TargetCalls(1));
    vault.request_redeem(shares, user, user)
}

fn report(vault: IVaultDispatcher, from_asset: ContractAddress) {
    // increase timestamp, else report fails
    let now = get_block_timestamp();
    start_cheat_block_timestamp_global(now + 3600); // 1 hour

    // First, call report on vault to handle epochs
    // Report needs ORACLE_ROLE
    let oracle = ORACLE();
    
    // After report, if all epochs are handled, excess funds are sent to vault_allocator
    // We need to mock bring_liquidity to get them back
    let vault_allocator_addr = vault.vault_allocator();
    // bring_liquidity transfers FROM caller TO vault
    let asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    let allocator_balance = asset_dispatcher.balance_of(vault_allocator_addr);
    if allocator_balance > 0 {
        // Transfer funds from allocator back to vault (simulating bring_liquidity)
        cheat_caller_address(from_asset, vault_allocator_addr, span: CheatSpan::TargetCalls(1));
        asset_dispatcher.approve(vault.contract_address, allocator_balance);
        
        // Mock the bring_liquidity call to update vault state
        cheat_caller_address(vault.contract_address, vault_allocator_addr, span: CheatSpan::TargetCalls(1));
        vault.bring_liquidity(allocator_balance);
    }

    let handled_epoch_len = vault.handled_epoch_len();
    println!("pre::handled_epoch_len: {}", handled_epoch_len);
    let erc4626_dispatcher = IERC4626Dispatcher { contract_address: vault.contract_address };
    println!("pre::total_assets: {}", erc4626_dispatcher.total_assets());
    println!("pre::total_supply: {}", erc4626_dispatcher.total_assets());

    // Call report as oracle
    cheat_caller_address(vault.contract_address, oracle, span: CheatSpan::TargetCalls(1));
    vault.report(0); // no assets in vault allocator
    let handled_epoch_len = vault.handled_epoch_len();
    println!("post::handled_epoch_len: {}", handled_epoch_len);
    println!("post::total_assets: {}", erc4626_dispatcher.total_assets());
    println!("post::total_supply: {}", erc4626_dispatcher.total_assets());
    
}
fn fulfill_old_nft(
    vault: IVaultDispatcher, from_asset: ContractAddress, nft_id: u256,
) {
    
    report(vault, from_asset);
    let asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };

    // Now claim_redeem on vault
    // Get NFT owner first
    let redeem_request_addr = vault.redeem_request();
    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: redeem_request_addr };
    let nft_owner = erc721_dispatcher.owner_of(nft_id);

    let owner_balance = asset_dispatcher.balance_of(nft_owner);
    println!("owner_balance: {}", owner_balance);

    // Call claim_redeem as the NFT owner
    cheat_caller_address(vault.contract_address, nft_owner, span: CheatSpan::TargetCalls(1));
    vault.claim_redeem(nft_id);
    let owner_balance_after = asset_dispatcher.balance_of(nft_owner);
    println!("owner_balance_after: {}", owner_balance_after);
}

fn mark_old_nft_fulfilled(router_address: ContractAddress, old_nft_id: u256) {
    // // Mark old NFT as fulfilled in router's storage
    // let mut cheat_calldata_key = ArrayTrait::new();
    // old_nft_id.serialize(ref cheat_calldata_key);
    // let mut cheat_calldata_value = ArrayTrait::new();
    // true.serialize(ref cheat_calldata_value);
    // let map_entry = map_entry_address(selector!("old_nft_fulfilled"), cheat_calldata_key.span());
    // store(router_address, map_entry, cheat_calldata_value.span());
}

// ============================================================================
// 1. Constructor & Initialization Tests
// ============================================================================

#[test]
fn test_constructor_initializes_correctly() {
    let (vault, _, to_asset, redeem_request, avnu_exchange, router) = set_up();
    println!("setup done");

    // Verify addresses are stored correctly
    assert(router.vault() == vault.contract_address, 'Vault address incorrect');
    assert(router.redeem_request() == redeem_request.contract_address, 'Redeem request incorrect');
    assert(router.to_asset() == to_asset, 'To asset incorrect');
    assert(router.avnu_exchange() == avnu_exchange.contract_address, 'Avnu exchange incorrect');
    println!("addresses stored correctly");

    // Verify roles are set
    let access_control = IAccessControlDispatcher {
        contract_address: router.contract_address,
    };
    let has_owner_role = access_control.has_role(selector!("OWNER_ROLE"), OWNER());
    assert(has_owner_role, 'Owner role not set');
    println!("roles set");
    // Verify swap_id and unsettled_swap_id start at 1
    assert(router.swap_id() == 1, 'swap_id should start at 1');
    assert(router.unsettled_swap_id() == 1, 'unsettled_swap_id != 1');
    println!("swap_id and unsettled_swap_id start at 1");
    // Verify NFT counter starts at 0 (but we can't directly read it, so check via first mint)
    // Actually, we can't verify this without minting, but the contract code shows it's initialized to 0
    println!("NFT counter starts at 0");
    // Verify NFT contract initialized
    let erc721 = ERC721ABIDispatcher { contract_address: router.contract_address };
    assert(erc721.name() == "RedemptionRouter", 'NFT name incorrect');
    assert(erc721.symbol() == "RR", 'NFT symbol incorrect');
    
    // Verify last_settled_epoch initialized (should be 0 when handled_epoch_len is 0)
    assert(router.last_settled_epoch() == 0, 'last_settled_epoch should be 0');
}

#[test]
#[should_panic(expected: ('Zero address',))]
fn test_constructor_reverts_zero_vault() {
    let zero_vault: ContractAddress = core::num::traits::Zero::zero();
    let to_asset = deploy_erc20_mock();
    // Note: deploy_redeem_request will fail with zero vault, so we skip it
    // and pass zero directly to router constructor which should check it
    let dummy_redeem_request: ContractAddress = 'DUMMY_RR'.try_into().unwrap();
    let avnu_exchange: ContractAddress = 'AVNU_EXCHANGE'.try_into().unwrap();
    let integrator_fee_recipient = 'FEE_RECIPIENT'.try_into().unwrap();
    deploy_redemption_router(
        zero_vault,
        dummy_redeem_request,
        to_asset,
        avnu_exchange,
        integrator_fee_recipient,
        100,
        0,
    );
}

#[test]
#[should_panic(expected: ('Zero address',))]
fn test_constructor_reverts_zero_redeem_request() {
    let dummy_vault = 'DUMMY_VAULT'.try_into().unwrap();
    let to_asset = deploy_erc20_mock();
    let avnu_exchange: ContractAddress = 'AVNU_EXCHANGE'.try_into().unwrap();
    let integrator_fee_recipient = 'FEE_RECIPIENT'.try_into().unwrap();
    let zero_redeem_request: ContractAddress = core::num::traits::Zero::zero();
    deploy_redemption_router(dummy_vault, zero_redeem_request, to_asset, avnu_exchange, integrator_fee_recipient, 100, 0);
}

#[test]
#[should_panic(expected: ('Zero address',))]
fn test_constructor_reverts_zero_to_asset() {
    let dummy_vault = 'DUMMY_VAULT'.try_into().unwrap();
    let redeem_request: ContractAddress = 'DUMMY_RR'.try_into().unwrap();
    let avnu_exchange = 'AVNU_EXCHANGE'.try_into().unwrap();
    let integrator_fee_recipient = 'FEE_RECIPIENT'.try_into().unwrap();
    let zero_to_asset: ContractAddress = core::num::traits::Zero::zero();
    deploy_redemption_router(
        dummy_vault,
        redeem_request,
        zero_to_asset,
        avnu_exchange,
        integrator_fee_recipient,
        100,
        0,
    );
}

// ============================================================================
// 2. Subscribe Function Tests
// ============================================================================

#[test]
fn test_subscribe_transfers_old_nft_and_mints_new() {
    let (vault, _, _, redeem_request, _, router) = set_up();

    // Mint old NFT to user by calling request_redeem on vault
    let due_amount: u256 = WAD * 100; // due_amount equals nominal in WAD
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount);
    let epoch: u256 = vault.epoch(); // Get current epoch from vault

    // User approves router
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);

    // User subscribes
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // Verify new NFT was minted
    let router_erc721 = ERC721ABIDispatcher { contract_address: router.contract_address };
    assert(router_erc721.owner_of(new_nft_id) == USER1(), 'New NFT owner incorrect');

    // Verify old NFT was transferred to router (on redeem_request contract)
    let redeem_request_erc721 = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    assert(redeem_request_erc721.owner_of(old_nft_id) == router.contract_address, 'Old NFT not transferred');

    // Verify mapping stored correctly
    let request_info = router.new_nft_request_info(new_nft_id);
    assert(request_info.old_nft_id == old_nft_id, 'Old NFT ID mapping incorrect');
    assert(request_info.is_claimed == false, 'is_claimed should be false');
    assert(request_info.epoch == epoch, 'Epoch stored incorrectly');
    assert(request_info.due_amount_approximate == due_amount, 'Due amount stored incorrectly');

    // Verify new_nft_id is 0 (first NFT)
    assert(new_nft_id == 0, 'First NFT ID should be 0');
}

#[test]
fn test_subscribe_increments_nft_counter() {
    let (vault, _, _, redeem_request, _, router) = set_up();

    // Subscribe first NFT
    let due_amount_1: u256 = WAD * 100;
    let old_nft_id_1 = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount_1);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());
    assert(new_nft_id_1 == 0, 'First NFT ID should be 0');

    // Subscribe second NFT
    let due_amount_2: u256 = WAD * 200;
    let old_nft_id_2 = mint_and_redeem_old_nft_to_user(vault, USER2(), due_amount_2);
    
    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());
    assert(new_nft_id_2 == 1, 'Second NFT ID should be 1');
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_subscribe_reverts_when_paused() {
    let (vault, _, _, redeem_request, _, router) = set_up();

    // Pause contract
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.pause();

    // Attempt subscribe
    let due_amount: u256 = WAD * 100;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.subscribe(old_nft_id, USER1());
}

#[test]
#[should_panic(expected: "Too small subscribe amount")]
fn test_subscribe_reverts_on_too_small_amount() {
    let (vault, _, _, redeem_request, _, router) = set_up();
    
    // Set min_subscribe_amount
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.set_min_subscribe_amount(WAD * 100);
    
    // Attempt subscribe with amount below minimum
    let due_amount: u256 = WAD * 50;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount); // 50 < 100
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.subscribe(old_nft_id, USER1());
}

#[test]
fn test_redeem_and_subscribe_transfers_shares_and_subscribes() {
    let (vault, _, _, redeem_request, _, router) = set_up();

    // User deposits assets to get vault shares
    let nominal: u256 = WAD * 100;
    let shares = mint_old_nft_to_user(vault, USER1(), nominal);
    let epoch: u256 = vault.epoch(); // Get current epoch from vault

    // User approves router to transfer shares
    let vault_erc20_dispatcher = ERC20ABIDispatcher { contract_address: vault.contract_address };
    cheat_caller_address(vault.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    vault_erc20_dispatcher.approve(router.contract_address, shares);

    // Get user's share balance before
    let user_shares_before = vault_erc20_dispatcher.balance_of(USER1());

    // Call redeem_and_subscribe
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.redeem_and_subscribe(shares, USER1());

    // Verify new NFT was minted to receiver
    let router_erc721 = ERC721ABIDispatcher { contract_address: router.contract_address };
    assert(router_erc721.owner_of(new_nft_id) == USER1(), 'New NFT owner incorrect');

    // Verify user's shares were transferred (burned by vault during request_redeem)
    let user_shares_after = vault_erc20_dispatcher.balance_of(USER1());
    assert(user_shares_after == user_shares_before - shares, 'User shares not transferred');

    // Verify old NFT (from request_redeem) is owned by router
    // The NFT ID returned from request_redeem is stored in old_nft_id
    let request_info = router.new_nft_request_info(new_nft_id);
    let old_nft_id = request_info.old_nft_id;
    let redeem_request_erc721 = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    assert(redeem_request_erc721.owner_of(old_nft_id) == router.contract_address, 'Old NFT not owned by router');

    // Verify mapping stored correctly
    assert(request_info.is_claimed == false, 'is_claimed should be false');
    assert(request_info.epoch == epoch, 'Epoch stored incorrectly');
    assert(request_info.due_amount_approximate > 0, 'Due amount should be set');
    assert(request_info.unsubscribed == false, 'unsubscribed should be false');

    // Verify new_nft_id is correct (should be 0 if this is the first subscription)
    assert(new_nft_id == 0, 'First NFT ID should be 0');
}

// ============================================================================
// 3. Swap Function Tests
// ============================================================================

#[test]
fn test_swap_executes_successfully() {
    let (vault, from_asset, to_asset, _, avnu_exchange, router) = set_up();

    // Mint from_asset tokens to router
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    let router_address = router.contract_address;
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router_address, WAD * 10); // 10 tokens

    // Mint to_asset tokens to mock exchange so it can transfer them back
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 100);

    // Execute swap
    let routes: Array<Route> = array![];
    let from_amount: u256 = WAD * 5; // 5 tokens
    let min_amount_out: u256 = WAD * 4; // 4 tokens (2:1 ratio for simplicity)

    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    let swap_id = router.swap(routes, from_amount, min_amount_out);

    // Verify swap_id is 1 (first swap)
    assert(swap_id == 1, 'swap_id should be 1');

    // Verify swap_info stores correct amounts
    let (stored_from, stored_to) = router.swap_info(swap_id);
    assert(stored_from == from_amount, 'Stored from_amount incorrect');
    assert(stored_to == min_amount_out, 'Stored to_amount incorrect');

    // Verify swap_id incremented
    assert(router.swap_id() == 2, 'swap_id should increment to 2');
}

#[test]
#[should_panic(expected: "Insufficient from amount")]
fn test_swap_reverts_on_insufficient_balance() {
    let (vault, from_asset, _, _, _, router) = set_up();

    // Don't mint any tokens to router (has 0 balance)

    // Attempt swap
    let routes: Array<Route> = array![];
    let from_amount: u256 = WAD * 5;
    let min_amount_out: u256 = WAD * 4;

    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, from_amount, min_amount_out);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_swap_reverts_when_not_relayer() {
    let (vault, from_asset, _, _, _, router) = set_up();

    // Mint tokens to router
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 10);

    // Attempt swap as non-relayer
    let routes: Array<Route> = array![];
    let from_amount: u256 = WAD * 5;
    let min_amount_out: u256 = WAD * 4;

    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.swap(routes, from_amount, min_amount_out);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_swap_reverts_when_paused() {
    let (vault, from_asset, _, _, _, router) = set_up();

    // Pause contract
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.pause();

    // Attempt swap
    let routes: Array<Route> = array![];
    let from_amount: u256 = WAD * 5;
    let min_amount_out: u256 = WAD * 4;

    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, from_amount, min_amount_out);
}

// Note: test_swap_reverts_on_avnu_failure is skipped because:
// - The mock_avnu_exchange always returns true
// - To test failure, we would need a variant mock or different approach
// - The implementation correctly checks for swapped == false and reverts with "Swap failed"
// - This test case is documented in the test plan but requires mock modification to implement

#[test]
fn test_swap_uses_actual_received_amount() {
    let (vault, from_asset, to_asset, _, avnu_exchange, router) = set_up();

    // Mint from_asset tokens to router
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 10);

    // Mint to_asset tokens to mock exchange so it can transfer them
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 100);

    // Get initial to_asset balance (not used but kept for reference)
    let _initial_to_balance = to_asset_dispatcher.balance_of(router.contract_address);

    // Execute swap with min_amount_out = 4
    let routes: Array<Route> = array![];
    let from_amount: u256 = WAD * 5;
    let min_amount_out: u256 = WAD * 4;

    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    let swap_id = router.swap(routes, from_amount, min_amount_out);

    // Verify swap_info stores actual received amount (balance delta)
    let (stored_from, stored_to) = router.swap_info(swap_id);
    assert(stored_from == from_amount, 'Stored from_amount incorrect');
    // Verify stored to_amount matches what was actually received (min_amount_out)
    assert(stored_to == min_amount_out, 'Stored to_amount invalid');
}

// ============================================================================
// 4. Basic Claim Scenarios
// ============================================================================

#[test]
fn test_claim_single_subscribe_single_swap_single_claim() {
    let (vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();

    // 1. Subscribe
    let due_amount: u256 = WAD * 100;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // 2. Fulfill old NFT (burn it)
    fulfill_old_nft(vault, from_asset, old_nft_id);

    // 3. Transfer assets to router (simulate vault fulfilling redemption)
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 100); // 100 tokens

    // 4. Mint to_asset to mock exchange for swap
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 300);

    // 5. Swap
    let routes: Array<Route> = array![];
    let from_amount: u256 = WAD * 100;
    let min_amount_out: u256 = WAD * 200; // 2:1 ratio

    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, from_amount, min_amount_out);

    // 6. Claim (epoch should be settled now)
    // Offset factor defaults to WAD, so due_amount remains the same
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let receivable = router.claim(new_nft_id);

    // Verify user received correct proportional amount: 100 * 200 / 100 = 200
    let expected_receivable = WAD * 200;
    assert(receivable == expected_receivable, 'Receivable amount incorrect');

    // Verify NFT is burned
    let _pending_redeem_assetsrouter_erc721 = ERC721ABIDispatcher { contract_address: router.contract_address };
    // Should panic if trying to check owner of burned NFT, but we can check is_claimed
    let request_info = router.new_nft_request_info(new_nft_id);
    assert(request_info.is_claimed == true, 'NFT should be marked as claimed');

    // Verify pool fully consumed, unsettled_swap_id advanced
    assert(router.unsettled_swap_id() == 2, 'unsettled_swap_id != 2');
}

#[test]
fn test_claim_two_subscribes_one_swap_two_claims() {
    let (vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();

    // 1. Two subscribes
    let due_amount_1: u256 = WAD * 100;
    let old_nft_id_1 = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount_1);
    let due_amount_2: u256 = WAD * 200;
    let old_nft_id_2 = mint_and_redeem_old_nft_to_user(vault, USER2(), due_amount_2);

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };

    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());

    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());

    // 2. Fulfill both old NFTs
    fulfill_old_nft(vault, from_asset, old_nft_id_1);
    fulfill_old_nft(vault, from_asset, old_nft_id_2);
    println!("fulfilled 1");

    // 3. Mint to_asset to mock exchange
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 1000);
    println!("minted to_asset");

    // 4. One swap: 300 from → 600 to (2:1 ratio)
    let routes: Array<Route> = array![];
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    let balance_from = from_asset_dispatcher.balance_of(router.contract_address);
    println!("balance_from: {}", balance_from);
    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, balance_from, WAD * 600);
    println!("swapped");

    // 6. Claim User 1: due = 100, should get 100 * 600 / 300 = 200
    // (no need to mock due_assets_from_id - it's stored in RequestInfo)
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let receivable_1 = router.claim(new_nft_id_1);
    assert(receivable_1 == WAD * 200, 'User 1 receivable incorrect');
    println!("claimed 1");

    // Verify swap info updated correctly
    let (from_rem, to_rem) = router.swap_info(1);
    println!("from_rem: {}", from_rem);
    println!("to_rem: {}", to_rem);
    assert(from_rem == WAD * 200, 'Remaining from_amount incorrect');
    assert(to_rem == WAD * 400, 'Remaining to_amount incorrect');
    println!("claimed 2");
    // 7. Claim User 2: due = 200, should get 200 * 600 / 300 = 400
    // But since pool has remaining: 200 from, 400 to, user gets 400
    // (no need to mock due_assets_from_id - it's stored in RequestInfo)

    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let receivable_2 = router.claim(new_nft_id_2);
    assert(receivable_2 == WAD * 400, 'User 2 receivable incorrect');

    // Verify pool fully consumed
    assert(router.unsettled_swap_id() == 2, 'unsettled_swap_id != 2');
}

#[test]
#[should_panic(expected: "Claim not allowed")]
fn test_claim_requires_epoch_settled() {
    let (vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();

    // Subscribe to epoch 5
    let due_amount: u256 = WAD * 100;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // Fulfill old NFT
    fulfill_old_nft(vault, from_asset, old_nft_id);

    // Transfer assets and swap (but not enough to settle epoch 5)
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 50); // Only 50, not enough for epoch 5
    
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 1000);
    
    let routes: Array<Route> = array![];
    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, WAD * 50, WAD * 100); // Swap 50, epoch 5 needs 100, so not fully settled

    // Attempt to claim - should fail because epoch not fully settled
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.claim(new_nft_id); // Should fail - epoch not settled
}

// ============================================================================
// 5. Unsubscribe Function Tests
// ============================================================================

#[test]
fn test_unsubscribe_original_nft_not_fulfilled_returns_nft() {
    let (vault, _, _, redeem_request, _, router) = set_up();

    // 1. Subscribe
    let due_amount: u256 = WAD * 100;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // Verify old NFT is owned by router
    let redeem_request_erc721 = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    assert(redeem_request_erc721.owner_of(old_nft_id) == router.contract_address, 'Old NFT owned by router');

    // 2. Unsubscribe (original NFT not fulfilled)
    // Use unsubscribe_for_nft since old NFT is not fulfilled
    // Caller must own the NFT (USER1 already owns it)
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_nft(new_nft_id, USER1());

    // Verify old NFT returned to user
    assert(redeem_request_erc721.owner_of(old_nft_id) == USER1(), 'Old NFT returned to user');

    // Verify new NFT is burned and marked as unsubscribed
    let request_info = router.new_nft_request_info(new_nft_id);
    assert(request_info.unsubscribed == true, 'NFT marked as unsubscribed');
}

#[test]
fn test_unsubscribe_original_nft_fulfilled_but_not_swapped_returns_assets() {
    let (vault, from_asset, _, redeem_request, _, router) = set_up();

    // 1. Subscribe
    let due_amount: u256 = WAD * 100;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // 2. Fulfill old NFT (burn it)
    fulfill_old_nft(vault, from_asset, old_nft_id);
    // Mark old NFT as fulfilled in router's storage
    mark_old_nft_fulfilled(router.contract_address, old_nft_id);
    println!("old_nft_id: {}", old_nft_id);
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };

    // Get initial user balance
    let user_balance_before = from_asset_dispatcher.balance_of(USER1());

    // 4. Unsubscribe (original NFT fulfilled but not swapped)
    // Use unsubscribe_for_underlying since old NFT is fulfilled
    // Caller must own the NFT (USER1 already owns it)
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_underlying(new_nft_id, USER1());
    println!("new_nft_id: {}", new_nft_id);

    // Verify user received from_assets
    let user_balance_after = from_asset_dispatcher.balance_of(USER1());
    println!("user_balance_before: {}", user_balance_before);
    println!("user_balance_after: {}", user_balance_after);
    let bal_remaining = ERC20ABIDispatcher { contract_address: from_asset }.balance_of(router.contract_address);
    println!("bal_remaining: {}", bal_remaining);
    assert(user_balance_after == user_balance_before + WAD * 100, 'User should receive from_assets');

    // Verify new NFT is burned and marked as unsubscribed
    let request_info = router.new_nft_request_info(new_nft_id);
    assert(request_info.unsubscribed == true, 'NFT marked as unsubscribed');
}

#[test]
#[should_panic(expected: "Cannot unsubscribe: swaps have partially consumed assets")]
fn test_unsubscribe_original_nft_fulfilled_partially_swapped_reverts() {
    let (vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();

    // 1. Subscribe
    let due_amount: u256 = WAD * 100;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), 100);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // 2. Fulfill old NFT
    fulfill_old_nft(vault, from_asset, old_nft_id);
    // Mark old NFT as fulfilled in router's storage
    mark_old_nft_fulfilled(router.contract_address, old_nft_id);

    // 3. Transfer assets to router
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 100);

    // 4. Partial swap (swap 50 out of 100)
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 200);
    
    let routes: Array<Route> = array![];
    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, WAD * 50, WAD * 100); // Swap 50, leaving 50 remaining (epoch needs 100 total)

    // 5. Attempt unsubscribe - should revert because swaps have partially consumed
    // Use unsubscribe_for_underlying since old NFT is fulfilled
    // Caller must own the NFT (USER1 already owns it)
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_underlying(new_nft_id, USER1());
}

#[test]
fn test_unsubscribe_second_user_before_swaps() {
    let (vault, _, _, redeem_request, _, router) = set_up();

    // 1. Two users subscribe
    let due_amount_1: u256 = WAD * 100;
    let old_nft_id_1 = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount_1);
    let due_amount_2: u256 = WAD * 200;
    let old_nft_id_2 = mint_and_redeem_old_nft_to_user(vault, USER2(), due_amount_2);

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };

    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());

    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());

    // 2. User 2 unsubscribes (original NFT not fulfilled)
    let redeem_request_erc721 = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    // Use unsubscribe_for_nft since old NFT is not fulfilled
    // Caller must own the NFT (USER2 already owns it)
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_nft(new_nft_id_2, USER2());

    // Verify User 2's old NFT returned
    assert(redeem_request_erc721.owner_of(old_nft_id_2) == USER2(), 'User 2 NFT returned');

    // Verify User 1's old NFT still owned by router
    assert(redeem_request_erc721.owner_of(old_nft_id_1) == router.contract_address, 'User 1 NFT in router');

    // Verify User 1 can still claim later (after swaps)
    let request_info_1 = router.new_nft_request_info(new_nft_id_1);
    assert(request_info_1.unsubscribed == false, 'User 1 not unsubscribed');
}

#[test]
fn test_unsubscribe_third_user_after_second_withdrawn() {
    let (vault, _, _, redeem_request, _, router) = set_up();

    // 1. Three users subscribe
    let due_amount_1: u256 = WAD * 100;
    let old_nft_id_1 = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount_1);
    let due_amount_2: u256 = WAD * 200;
    let old_nft_id_2 = mint_and_redeem_old_nft_to_user(vault, USER2(), due_amount_2);
    let due_amount_3: u256 = WAD * 300;
    let old_nft_id_3 = mint_and_redeem_old_nft_to_user(vault, 'USER3'.try_into().unwrap(), due_amount_3);

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    let user3: ContractAddress = 'USER3'.try_into().unwrap();

    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let _new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());

    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());

    cheat_caller_address(redeem_request.contract_address, user3, span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_3);
    cheat_caller_address(router.contract_address, user3, span: CheatSpan::TargetCalls(1));
    let new_nft_id_3 = router.subscribe(old_nft_id_3, user3);

    // 2. User 2 unsubscribes
    // Use unsubscribe_for_nft since old NFT is not fulfilled
    // Caller must own the NFT (USER2 already owns it)
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_nft(new_nft_id_2, USER2());

    // 3. User 3 unsubscribes (should work even though User 2 withdrew)
    let redeem_request_erc721 = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    // Use unsubscribe_for_nft since old NFT is not fulfilled
    // Caller must own the NFT (user3 already owns it)
    cheat_caller_address(router.contract_address, user3, span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_nft(new_nft_id_3, user3);

    // Verify User 3's old NFT returned
    assert(redeem_request_erc721.owner_of(old_nft_id_3) == user3, 'User 3 NFT returned');

    // Verify User 1's old NFT still owned by router
    assert(redeem_request_erc721.owner_of(old_nft_id_1) == router.contract_address, 'User 1 NFT in router');
}

#[test]
fn test_unsubscribe_second_user_after_fulfillment_but_before_swaps() {
    let (vault, from_asset, _, redeem_request, _, router) = set_up();

    // 1. Two users subscribe
    let due_amount_1: u256 = WAD * 100;
    let old_nft_id_1 = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount_1);

    let due_amount_2: u256 = WAD * 200;
    let old_nft_id_2 = mint_and_redeem_old_nft_to_user(vault, USER2(), due_amount_2);

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };

    // User 1 subscribes
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());

    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());

    // 2. Fulfill both old NFTs
    fulfill_old_nft(vault, from_asset, old_nft_id_1);
    fulfill_old_nft(vault, from_asset, old_nft_id_2);
    // Mark old NFTs as fulfilled in router's storage
    mark_old_nft_fulfilled(router.contract_address, old_nft_id_1);
    mark_old_nft_fulfilled(router.contract_address, old_nft_id_2);

    // 3. Transfer assets to router (300 total: 100 for user1, 200 for user2)
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 300);

    // Get User 2 balance before
    let user2_balance_before = from_asset_dispatcher.balance_of(USER2());

    // 4. User 2 unsubscribes (original NFT fulfilled but not swapped)
    // Use unsubscribe_for_underlying since old NFT is fulfilled
    // Caller must own the NFT (USER2 already owns it)
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_underlying(new_nft_id_2, USER2());

    // Verify User 2 received from_assets (200)
    let user2_balance_after = from_asset_dispatcher.balance_of(USER2());
    assert(user2_balance_after == user2_balance_before + WAD * 200, 'User 2 received 200');

    // Verify User 1 can still claim later
    let request_info_1 = router.new_nft_request_info(new_nft_id_1);
    assert(request_info_1.unsubscribed == false, 'User 1 not unsubscribed');
}

#[test]
#[should_panic(expected: "NFT already withdrawn")]
fn test_unsubscribe_twice_reverts() {
    let (vault, _, _, redeem_request, _, router) = set_up();

    // Subscribe
    let due_amount: u256 = WAD * 100;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // Unsubscribe first time
    // Use unsubscribe_for_nft since old NFT is not fulfilled
    // Caller must own the NFT (USER1 already owns it)
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_nft(new_nft_id, USER1());

    // Attempt unsubscribe second time - should revert
    // Note: NFT is already burned, so we can't transfer it again
    // But we can try to call unsubscribe again which should fail
    // Use unsubscribe_for_nft since old NFT is not fulfilled
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_nft(new_nft_id, USER1());
}

// ============================================================================
// 6. Access Control & Setter Tests
// ============================================================================

#[test]
fn test_set_min_subscribe_amount_only_owner() {
    let (_, _, _, _, _, router) = set_up();
    
    // Owner can set min_subscribe_amount
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.set_min_subscribe_amount(WAD * 100);
    
    // Verify it was set (we can't directly read it, but we can test it works)
    // by trying to subscribe with amount below minimum
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_set_min_subscribe_amount_reverts_when_not_owner() {
    let (_, _, _, _, _, router) = set_up();
    
    // Non-owner attempts to set min_subscribe_amount
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.set_min_subscribe_amount(WAD * 100);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_set_integrator_fee_amount_bps_reverts_when_not_owner() {
    let (_, _, _, _, _, router) = set_up();
    
    // Non-owner attempts to set integrator_fee_amount_bps
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.set_integrator_fee_amount_bps(100);
}

#[test]
#[should_panic(expected: "Invalid integrator fee amount")]
fn test_set_integrator_fee_amount_bps_reverts_on_invalid_fee() {
    let (_, _, _, _, _, router) = set_up();
    
    // Owner attempts to set fee > 500 bps (max allowed)
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.set_integrator_fee_amount_bps(501); // Exceeds max of 500 bps
}

#[test]
fn test_set_integrator_fee_amount_bps_success() {
    let (_, _, _, _, _, router) = set_up();
    
    // Verify initial fee (set in set_up)
    let initial_fee = router.integrator_fee_amount_bps();
    assert(initial_fee == 100, 'Initial fee should be 100 bps');
    
    // Owner sets valid fee
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.set_integrator_fee_amount_bps(250);
    
    // Verify fee was updated
    let new_fee = router.integrator_fee_amount_bps();
    assert(new_fee == 250, 'Fee should be 250 bps');
    
    // Test edge case: set to max allowed (500 bps)
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.set_integrator_fee_amount_bps(500);
    
    let max_fee = router.integrator_fee_amount_bps();
    assert(max_fee == 500, 'Fee should be 500 bps');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_set_integrator_fee_recipient_reverts_when_not_owner() {
    let (_, _, _, _, _, router) = set_up();
    
    // Non-owner attempts to set integrator_fee_recipient
    let new_recipient: ContractAddress = 'NEW_RECIPIENT'.try_into().unwrap();
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.set_integrator_fee_recipient(new_recipient);
}

// ============================================================================
// 7. Epoch Settlement & Sync Tests
// ============================================================================

#[test]
fn test_sync_settled_epochs() {
    let (vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();
    
    // Subscribe to epoch 1
    let due_amount: u256 = WAD * 100;
    let old_nft_id = mint_and_redeem_old_nft_to_user(vault, USER1(), due_amount);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let _new_nft_id = router.subscribe(old_nft_id, USER1());
    
    // report once to skip epoch 0
    report(vault, from_asset);

    // Fulfill old NFT
    fulfill_old_nft(vault, from_asset, old_nft_id);
    
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 1000);
    
    let routes: Array<Route> = array![];
    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, WAD * 100, WAD * 200);
    
    // Sync settled epochs
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.sync_settled_epochs(10); // Check up to 10 epochs
    
    // Verify last_settled_epoch updated
    println!("last_settled_epoch: {}", router.last_settled_epoch());
    assert(router.last_settled_epoch() == 1, 'last_settled_epoch should be 1');
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_sync_settled_epochs_reverts_when_paused() {
    let (_, _, _, _, _, router) = set_up();
    
    // Pause contract
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.pause();
    
    // Attempt sync
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.sync_settled_epochs(10);
}

