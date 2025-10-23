// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::contract]
pub mod VesuV2SpecificDecoderAndSanitizer {
    use vault_allocator::decoders_and_sanitizers::base_decoder_and_sanitizer::BaseDecoderAndSanitizerComponent;
    use vault_allocator::decoders_and_sanitizers::vesu_v2_decoder_and_sanitizer::vesu_v2_decoder_and_sanitizer::VesuV2DecoderAndSanitizerComponent;

    component!(
        path: BaseDecoderAndSanitizerComponent,
        storage: base_decoder_and_sanitizer,
        event: BaseDecoderAndSanitizerEvent,
    );

    component!(
        path: VesuV2DecoderAndSanitizerComponent,
        storage: vesu_v2_decoder_and_sanitizer,
        event: VesuV2DecoderAndSanitizerEvent,
    );

    #[abi(embed_v0)]
    impl BaseDecoderAndSanitizerImpl =
        BaseDecoderAndSanitizerComponent::BaseDecoderAndSanitizerImpl<ContractState>;

    #[abi(embed_v0)]
    impl VesuV2DecoderAndSanitizerImpl =
        VesuV2DecoderAndSanitizerComponent::VesuV2DecoderAndSanitizerImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub base_decoder_and_sanitizer: BaseDecoderAndSanitizerComponent::Storage,
        #[substorage(v0)]
        pub vesu_v2_decoder_and_sanitizer: VesuV2DecoderAndSanitizerComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        BaseDecoderAndSanitizerEvent: BaseDecoderAndSanitizerComponent::Event,
        #[flat]
        VesuV2DecoderAndSanitizerEvent: VesuV2DecoderAndSanitizerComponent::Event,
    }
}
