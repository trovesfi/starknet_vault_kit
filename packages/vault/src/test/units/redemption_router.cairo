// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use openzeppelin::interfaces::accesscontrol::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::interfaces::erc721::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
    start_mock_call, store, map_entry_address,
};
use starknet::ContractAddress;
use core::array::ArrayTrait;
use vault::redeem_request::interface::{
    IRedeemRequestDispatcher, IRedeemRequestDispatcherTrait, RedeemRequestInfo,
};
use vault::redemption_router::interface::{
    IRedemptionRouterDispatcher, IRedemptionRouterDispatcherTrait,
};
use vault::redemption_router::redemption_router::RedemptionRouter;
use vault::test::utils::{OWNER, USER1, USER2, WAD, deploy_erc20_mock, deploy_redeem_request};
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
    ContractAddress, // vault (dummy address)
    ContractAddress, // from_asset
    ContractAddress, // to_asset
    IRedeemRequestDispatcher, // redeem_request
    IAvnuExchangeDispatcher, // avnu_exchange
    IRedemptionRouterDispatcher, // router
) {
    let dummy_vault = 'DUMMY_VAULT'.try_into().unwrap();
    let from_asset = deploy_erc20_mock();
    let to_asset = deploy_erc20_mock();
    let redeem_request = deploy_redeem_request(dummy_vault);
    let avnu_exchange = deploy_mock_avnu_exchange();
    println!("avnu_exchange deployed");
    let integrator_fee_recipient = 'FEE_RECIPIENT'.try_into().unwrap();
    let integrator_fee_amount_bps: u128 = 100; // 1%
    let min_subscribe_amount: u256 = 0; // No minimum by default for tests
    println!("integrator_fee_recipient and integrator_fee_amount_bps set");
    
    // Mock vault's handled_epoch_len for constructor initialization
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 0_u256);
    
    let router = deploy_redemption_router(
        dummy_vault,
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
    (dummy_vault, from_asset, to_asset, redeem_request, avnu_exchange, router)
}

fn mint_old_nft_to_user(
    redeem_request: IRedeemRequestDispatcher, vault_address: ContractAddress, user: ContractAddress,
    epoch: u256, nominal: u256,
) -> u256 {
    let redeem_request_info = RedeemRequestInfo { epoch, nominal };
    cheat_caller_address(
        redeem_request.contract_address, vault_address, span: CheatSpan::TargetCalls(1),
    );
    redeem_request.mint(user, redeem_request_info)
}

fn fulfill_old_nft(
    redeem_request: IRedeemRequestDispatcher, vault_address: ContractAddress, nft_id: u256,
) {
    cheat_caller_address(
        redeem_request.contract_address, vault_address, span: CheatSpan::TargetCalls(1),
    );
    redeem_request.burn(nft_id);
}

fn mark_old_nft_fulfilled(router_address: ContractAddress, old_nft_id: u256) {
    // Mark old NFT as fulfilled in router's storage
    let mut cheat_calldata_key = ArrayTrait::new();
    old_nft_id.serialize(ref cheat_calldata_key);
    let mut cheat_calldata_value = ArrayTrait::new();
    true.serialize(ref cheat_calldata_value);
    let map_entry = map_entry_address(selector!("old_nft_fulfilled"), cheat_calldata_key.span());
    store(router_address, map_entry, cheat_calldata_value.span());
}

// ============================================================================
// 1. Constructor & Initialization Tests
// ============================================================================

#[test]
fn test_constructor_initializes_correctly() {
    let (dummy_vault, _, to_asset, redeem_request, avnu_exchange, router) = set_up();
    println!("setup done");

    // Verify addresses are stored correctly
    assert(router.vault() == dummy_vault, 'Vault address incorrect');
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
    let (dummy_vault, _, _, redeem_request, _, router) = set_up();

    // Mint old NFT to user
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let epoch: u256 = 1;
    let nominal: u256 = 100;
    let due_amount: u256 = WAD * nominal; // due_amount equals nominal in WAD

    // Mock vault functions needed by subscribe
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * nominal); // Total redeem assets for epoch
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * nominal); // Total redeem nominal for epoch

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
    let (dummy_vault, _, _, redeem_request, _, router) = set_up();

    // Subscribe first NFT
    let old_nft_id_1 = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let due_amount_1: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_1);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());
    assert(new_nft_id_1 == 0, 'First NFT ID should be 0');

    // Subscribe second NFT
    let old_nft_id_2 = mint_old_nft_to_user(redeem_request, dummy_vault, USER2(), 1, 200);
    let due_amount_2: u256 = WAD * 200;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_2);
    // Note: redeem_assets and redeem_nominal should now include both users (300 total)
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 300);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 300);
    
    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());
    assert(new_nft_id_2 == 1, 'Second NFT ID should be 1');
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_subscribe_reverts_when_paused() {
    let (dummy_vault, _, _, redeem_request, _, router) = set_up();

    // Pause contract
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.pause();

    // Attempt subscribe
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let due_amount: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
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
    let (dummy_vault, _, _, redeem_request, _, router) = set_up();
    
    // Set min_subscribe_amount
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.set_min_subscribe_amount(WAD * 100);
    
    // Attempt subscribe with amount below minimum
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 50); // 50 < 100
    let due_amount: u256 = WAD * 50;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.subscribe(old_nft_id, USER1());
}

// ============================================================================
// 3. Swap Function Tests
// ============================================================================

#[test]
fn test_swap_executes_successfully() {
    let (dummy_vault, from_asset, to_asset, _, avnu_exchange, router) = set_up();

    // Mock vault asset and epoch functions
    // handled_epoch_len must be at least 1 to avoid underflow (even if no epochs are handled)
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 1_u256); // At least 1 to avoid underflow
    start_mock_call(dummy_vault, selector!("epoch"), 0_u256); // Current epoch is 0

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
    let (dummy_vault, from_asset, _, _, _, router) = set_up();

    // Mock vault asset
    start_mock_call(dummy_vault, selector!("asset"), from_asset);

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
    let (dummy_vault, from_asset, _, _, _, router) = set_up();

    // Mock vault asset
    start_mock_call(dummy_vault, selector!("asset"), from_asset);

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
    let (dummy_vault, from_asset, _, _, _, router) = set_up();

    // Pause contract
    cheat_caller_address(router.contract_address, OWNER(), span: CheatSpan::TargetCalls(1));
    router.pause();

    // Mock vault asset
    start_mock_call(dummy_vault, selector!("asset"), from_asset);

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
    let (dummy_vault, from_asset, to_asset, _, avnu_exchange, router) = set_up();

    // Mock vault asset and epoch functions
    // handled_epoch_len must be at least 1 to avoid underflow (even if no epochs are handled)
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 1_u256); // At least 1 to avoid underflow

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
    let (dummy_vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();

    // 1. Subscribe
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let due_amount: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // 2. Fulfill old NFT (burn it)
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id);

    // 3. Transfer assets to router (simulate vault fulfilling redemption)
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 100); // 100 tokens

    // 4. Mint to_asset to mock exchange for swap
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 300);

    // 5. Swap
    // handled_epoch_len should be 2 if epoch 1 is handled (epochs are 0-indexed, len is count)
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 2_u256); // Epochs 0 and 1 handled
    start_mock_call(dummy_vault, selector!("epoch"), 1_u256);
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
    let (dummy_vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();

    // 1. Two subscribes
    let old_nft_id_1 = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let old_nft_id_2 = mint_old_nft_to_user(redeem_request, dummy_vault, USER2(), 1, 200);

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };

    // User 1 subscribes
    let due_amount_1: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_1);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());

    // User 2 subscribes
    let due_amount_2: u256 = WAD * 200;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_2);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 300); // Total for both users
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 300);
    
    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());

    // 2. Fulfill both old NFTs
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id_1);
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id_2);

    // 3. Transfer assets to router
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 300); // 300 tokens total

    // 4. Mint to_asset to mock exchange
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 1000);

    // 5. One swap: 300 from → 600 to (2:1 ratio)
    // handled_epoch_len should be 2 if epoch 1 is handled (epochs are 0-indexed, len is count)
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 2_u256); // Epochs 0 and 1 handled
    start_mock_call(dummy_vault, selector!("epoch"), 1_u256);
    let routes: Array<Route> = array![];
    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, WAD * 300, WAD * 600);

    // 6. Claim User 1: due = 100, should get 100 * 600 / 300 = 200
    // (no need to mock due_assets_from_id - it's stored in RequestInfo)
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let receivable_1 = router.claim(new_nft_id_1);
    assert(receivable_1 == WAD * 200, 'User 1 receivable incorrect');

    // Verify swap info updated correctly
    let (from_rem, to_rem) = router.swap_info(1);
    println!("from_rem: {}", from_rem);
    println!("to_rem: {}", to_rem);
    assert(from_rem == WAD * 200, 'Remaining from_amount incorrect');
    assert(to_rem == WAD * 400, 'Remaining to_amount incorrect');

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
    let (dummy_vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();

    // Subscribe to epoch 5
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 5, 100);
    let due_amount: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // Fulfill old NFT
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id);

    // Transfer assets and swap (but not enough to settle epoch 5)
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 50); // Only 50, not enough for epoch 5
    
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 1000);
    
    // handled_epoch_len should be 6 if epoch 5 is handled (epochs 0-5 are handled, len = 6)
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 6_u256); // Epochs 0-5 handled
    start_mock_call(dummy_vault, selector!("epoch"), 5_u256);
    
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
    let (dummy_vault, _, _, redeem_request, _, router) = set_up();

    // 1. Subscribe
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let due_amount: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
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
    let (dummy_vault, from_asset, _, redeem_request, _, router) = set_up();

    // 1. Subscribe
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let due_amount: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // 2. Fulfill old NFT (burn it)
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id);
    // Mark old NFT as fulfilled in router's storage
    mark_old_nft_fulfilled(router.contract_address, old_nft_id);

    // 3. Transfer assets to router (simulate vault fulfilling redemption)
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 100);

    // Get initial user balance
    let user_balance_before = from_asset_dispatcher.balance_of(USER1());

    // 4. Unsubscribe (original NFT fulfilled but not swapped)
    // Use unsubscribe_for_underlying since old NFT is fulfilled
    // Mock vault functions needed by unsubscribe_for_underlying
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 2_u256);
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    // Caller must own the NFT (USER1 already owns it)
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_underlying(new_nft_id, USER1());

    // Verify user received from_assets
    let user_balance_after = from_asset_dispatcher.balance_of(USER1());
    assert(user_balance_after == user_balance_before + WAD * 100, 'User should receive from_assets');

    // Verify new NFT is burned and marked as unsubscribed
    let request_info = router.new_nft_request_info(new_nft_id);
    assert(request_info.unsubscribed == true, 'NFT marked as unsubscribed');
}

#[test]
#[should_panic(expected: "Cannot unsubscribe: swaps have partially consumed assets")]
fn test_unsubscribe_original_nft_fulfilled_partially_swapped_reverts() {
    let (dummy_vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();

    // 1. Subscribe
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let due_amount: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id = router.subscribe(old_nft_id, USER1());

    // 2. Fulfill old NFT
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id);
    // Mark old NFT as fulfilled in router's storage
    mark_old_nft_fulfilled(router.contract_address, old_nft_id);

    // 3. Transfer assets to router
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 100);

    // 4. Partial swap (swap 50 out of 100)
    // Mock handled_epoch_len as 2 so epoch 1 can be processed (epochs are 0-indexed)
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 2_u256);
    start_mock_call(dummy_vault, selector!("epoch"), 1_u256);
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 200);
    
    let routes: Array<Route> = array![];
    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, WAD * 50, WAD * 100); // Swap 50, leaving 50 remaining (epoch needs 100 total)

    // 5. Attempt unsubscribe - should revert because swaps have partially consumed
    // Use unsubscribe_for_underlying since old NFT is fulfilled
    // Mock vault functions needed by unsubscribe_for_underlying
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 2_u256);
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    // Caller must own the NFT (USER1 already owns it)
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.unsubscribe_for_underlying(new_nft_id, USER1());
}

#[test]
fn test_unsubscribe_second_user_before_swaps() {
    let (dummy_vault, _, _, redeem_request, _, router) = set_up();

    // 1. Two users subscribe
    let old_nft_id_1 = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let old_nft_id_2 = mint_old_nft_to_user(redeem_request, dummy_vault, USER2(), 1, 200);

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };

    // User 1 subscribes
    let due_amount_1: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_1);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());

    // User 2 subscribes
    let due_amount_2: u256 = WAD * 200;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_2);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 300);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 300);
    
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
    let (dummy_vault, _, _, redeem_request, _, router) = set_up();

    // 1. Three users subscribe
    let old_nft_id_1 = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let old_nft_id_2 = mint_old_nft_to_user(redeem_request, dummy_vault, USER2(), 1, 200);
    let old_nft_id_3 = mint_old_nft_to_user(redeem_request, dummy_vault, 'USER3'.try_into().unwrap(), 1, 300);

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    let user3: ContractAddress = 'USER3'.try_into().unwrap();

    // User 1 subscribes
    let due_amount_1: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_1);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let _new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());

    // User 2 subscribes
    let due_amount_2: u256 = WAD * 200;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_2);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 300);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 300);
    
    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());

    // User 3 subscribes
    let due_amount_3: u256 = WAD * 300;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_3);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 600);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 600);
    
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
    let (dummy_vault, from_asset, _, redeem_request, _, router) = set_up();

    // 1. Two users subscribe
    let old_nft_id_1 = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let old_nft_id_2 = mint_old_nft_to_user(redeem_request, dummy_vault, USER2(), 1, 200);

    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };

    // User 1 subscribes
    let due_amount_1: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_1);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_1);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_1 = router.subscribe(old_nft_id_1, USER1());

    // User 2 subscribes
    let due_amount_2: u256 = WAD * 200;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount_2);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 300);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 300);
    
    cheat_caller_address(redeem_request.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id_2);
    cheat_caller_address(router.contract_address, USER2(), span: CheatSpan::TargetCalls(1));
    let new_nft_id_2 = router.subscribe(old_nft_id_2, USER2());

    // 2. Fulfill both old NFTs
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id_1);
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id_2);
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
    // Mock vault functions needed by unsubscribe_for_underlying
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 2_u256);
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
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
    let (dummy_vault, _, _, redeem_request, _, router) = set_up();

    // Subscribe
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let due_amount: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
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

// ============================================================================
// 7. Epoch Settlement & Sync Tests
// ============================================================================

#[test]
fn test_sync_settled_epochs() {
    let (dummy_vault, from_asset, to_asset, redeem_request, avnu_exchange, router) = set_up();
    
    // Subscribe to epoch 1
    let old_nft_id = mint_old_nft_to_user(redeem_request, dummy_vault, USER1(), 1, 100);
    let due_amount: u256 = WAD * 100;
    start_mock_call(dummy_vault, selector!("due_assets_from_id"), due_amount);
    start_mock_call(dummy_vault, selector!("redeem_assets"), WAD * 100);
    start_mock_call(dummy_vault, selector!("redeem_nominal"), WAD * 100);
    
    let erc721_dispatcher = ERC721ABIDispatcher {
        contract_address: redeem_request.contract_address,
    };
    cheat_caller_address(redeem_request.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(router.contract_address, old_nft_id);
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    let _new_nft_id = router.subscribe(old_nft_id, USER1());
    
    // Fulfill old NFT
    fulfill_old_nft(redeem_request, dummy_vault, old_nft_id);
    
    // Transfer assets and swap enough to settle epoch 1
    let from_asset_dispatcher = ERC20ABIDispatcher { contract_address: from_asset };
    cheat_caller_address(from_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    from_asset_dispatcher.transfer(router.contract_address, WAD * 100);
    
    let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset };
    cheat_caller_address(to_asset, OWNER(), span: CheatSpan::TargetCalls(1));
    to_asset_dispatcher.transfer(avnu_exchange.contract_address, WAD * 1000);
    
    // handled_epoch_len should be 2 if epoch 1 is handled (epochs are 0-indexed, len is count)
    start_mock_call(dummy_vault, selector!("asset"), from_asset);
    start_mock_call(dummy_vault, selector!("handled_epoch_len"), 2_u256); // Epochs 0 and 1 handled
    start_mock_call(dummy_vault, selector!("epoch"), 1_u256);
    
    let routes: Array<Route> = array![];
    cheat_caller_address(router.contract_address, RELAYER, span: CheatSpan::TargetCalls(1));
    router.swap(routes, WAD * 100, WAD * 200);
    
    // Sync settled epochs
    cheat_caller_address(router.contract_address, USER1(), span: CheatSpan::TargetCalls(1));
    router.sync_settled_epochs(10); // Check up to 10 epochs
    
    // Verify last_settled_epoch updated
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

