// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

// Helps claim rewards from Defi spring rewards and any possible rewards 
// with similar claim contract structure
// This is called as SNFStyle because there can be other reward contracts (e.g. Ekubo)
// This is the default contract structure by SNF for rewards

#[starknet::component]
pub mod ExtendedExchangeDecoderAndSanitizerComponent {
    use vault_allocator::decoders_and_sanitizers::extended_exchange_decoder_and_sanitizer::interface::IExtendedExchangeDecoderAndSanitizer;
    use vault_allocator::integration_interfaces::extended::PositionId;
    
    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(ExtendedExchangeDecoderAndSanitizerImpl)]
    impl ExtendedExchangeDecoderAndSanitizer<
        TContractState, +HasComponent<TContractState>,
    > of IExtendedExchangeDecoderAndSanitizer<ComponentState<TContractState>> {
        fn deposit(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            quantized_amount: u64,
            salt: felt252
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            Serde::serialize(@position_id, ref serialized_struct);
            serialized_struct.span()
        }
    }
}
