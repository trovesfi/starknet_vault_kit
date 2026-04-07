// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use starknet::{ContractAddress, get_caller_address, get_contract_address};
use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;

#[starknet::interface]
pub trait IAvnuExchange<T> {
    fn multi_route_swap(
        ref self: T,
        sell_token_address: ContractAddress,
        sell_token_amount: u256,
        buy_token_address: ContractAddress,
        buy_token_amount: u256,
        buy_token_min_amount: u256,
        beneficiary: ContractAddress,
        integrator_fee_amount_bps: u128,
        integrator_fee_recipient: ContractAddress,
        routes: Array<Route>,
    ) -> bool;
    fn swap_exact_token_to(
        ref self: T,
        sell_token_address: ContractAddress,
        sell_token_amount: u256,
        sell_token_max_amount: u256,
        buy_token_address: ContractAddress,
        buy_token_amount: u256,
        beneficiary: ContractAddress,
        routes: Array<Route>,
    ) -> bool;
}

#[starknet::contract]
pub mod MockAvnuExchange {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;
    use super::IAvnuExchange;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Swapped: Swapped,
    }

    #[derive(Drop, starknet::Event)]
    struct Swapped {
        pub sell_token: ContractAddress,
        pub sell_amount: u256,
        pub buy_token: ContractAddress,
        pub buy_amount: u256,
        pub beneficiary: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        // Empty constructor
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn execute_swap(
            ref self: ContractState,
            sell_token_address: ContractAddress,
            sell_token_amount: u256,
            buy_token_address: ContractAddress,
            buy_token_min_amount: u256,
            beneficiary: ContractAddress,
        ) {
            let caller = get_caller_address();
            let this = get_contract_address();

            // Transfer sell_token_amount from caller (router) to this contract
            let sell_token_dispatcher = ERC20ABIDispatcher {
                contract_address: sell_token_address,
            };
            sell_token_dispatcher.transfer_from(caller, this, sell_token_amount);

            // Transfer buy_token_min_amount to beneficiary (router)
            let buy_token_dispatcher = ERC20ABIDispatcher {
                contract_address: buy_token_address,
            };
            buy_token_dispatcher.transfer(beneficiary, buy_token_min_amount);

            // Emit event
            self.emit(Swapped {
                sell_token: sell_token_address,
                sell_amount: sell_token_amount,
                buy_token: buy_token_address,
                buy_amount: buy_token_min_amount,
                beneficiary,
            });
        }
    }

    #[abi(embed_v0)]
    impl MockAvnuExchangeImpl of IAvnuExchange<ContractState> {
        /// Mock implementation of multi_route_swap
        /// Transfers sell_token_amount from caller and transfers buy_token_min_amount to beneficiary
        fn multi_route_swap(
            ref self: ContractState,
            sell_token_address: ContractAddress,
            sell_token_amount: u256,
            buy_token_address: ContractAddress,
            buy_token_amount: u256,
            buy_token_min_amount: u256,
            beneficiary: ContractAddress,
            integrator_fee_amount_bps: u128,
            integrator_fee_recipient: ContractAddress,
            routes: Array<Route>,
        ) -> bool {
            InternalImpl::execute_swap(
                ref self,
                sell_token_address,
                sell_token_amount,
                buy_token_address,
                buy_token_min_amount,
                beneficiary,
            );
            true
        }

        fn swap_exact_token_to(
            ref self: ContractState,
            sell_token_address: ContractAddress,
            sell_token_amount: u256,
            sell_token_max_amount: u256,
            buy_token_address: ContractAddress,
            buy_token_amount: u256,
            beneficiary: ContractAddress,
            routes: Array<Route>,
        ) -> bool {
            // Not used in redemption router, but required by interface
            false
        }
    }
}

