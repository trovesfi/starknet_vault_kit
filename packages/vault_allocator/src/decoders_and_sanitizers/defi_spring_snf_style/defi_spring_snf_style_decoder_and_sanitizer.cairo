// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::component]
pub mod DefiSpringSNFStyleDecoderAndSanitizerComponent {
    use vault_allocator::decoders_and_sanitizers::defi_spring_snf_style::interface::IDefiSpringSNFStyleDecoderAndSanitizer;

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(DefiSpringSNFStyleDecoderAndSanitizerImpl)]
    impl DefiSpringSNFStyleDecoderAndSanitizer<
        TContractState, +HasComponent<TContractState>,
    > of IDefiSpringSNFStyleDecoderAndSanitizer<ComponentState<TContractState>> {
        fn claim(
            self: @ComponentState<TContractState>,
            amount: u128,
            proof: Span<felt252>,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            serialized_struct.span()
        }
    }
}
