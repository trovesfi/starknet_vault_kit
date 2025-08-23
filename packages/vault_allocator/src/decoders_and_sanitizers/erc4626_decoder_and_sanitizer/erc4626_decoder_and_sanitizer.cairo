// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::component]
pub mod Erc4626DecoderAndSanitizerComponent {
    use starknet::ContractAddress;
    use vault_allocator::decoders_and_sanitizers::erc4626_decoder_and_sanitizer::interface::IERC4626DecoderAndSanitizer;

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(Erc4626DecoderAndSanitizerImpl)]
    impl Erc4626DecoderAndSanitizer<
        TContractState, +HasComponent<TContractState>,
    > of IERC4626DecoderAndSanitizer<ComponentState<TContractState>> {
        fn deposit(
            self: @ComponentState<TContractState>, assets: u256, receiver: ContractAddress,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            Serde::serialize(@receiver, ref serialized_struct);
            serialized_struct.span()
        }
        fn mint(
            self: @ComponentState<TContractState>, shares: u256, receiver: ContractAddress,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            Serde::serialize(@receiver, ref serialized_struct);
            serialized_struct.span()
        }

        fn withdraw(
            self: @ComponentState<TContractState>,
            assets: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            Serde::serialize(@receiver, ref serialized_struct);
            Serde::serialize(@owner, ref serialized_struct);
            serialized_struct.span()
        }

        fn redeem(
            self: @ComponentState<TContractState>,
            shares: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            Serde::serialize(@receiver, ref serialized_struct);
            Serde::serialize(@owner, ref serialized_struct);
            serialized_struct.span()
        }
    }
}
