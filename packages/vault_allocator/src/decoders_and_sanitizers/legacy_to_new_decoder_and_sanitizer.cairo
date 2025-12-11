// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::contract]
pub mod LegacyToNewDecoderAndSanitizer {
    use vault_allocator::decoders_and_sanitizers::base_decoder_and_sanitizer::BaseDecoderAndSanitizerComponent;
    use vault_allocator::decoders_and_sanitizers::legacy_to_new_avnu_decoder_and_sanitizer::legacy_to_new_avnu_decoder_and_sanitizer::LegacyToNewAvnuDecoderAndSanitizerComponent;

    component!(
        path: BaseDecoderAndSanitizerComponent,
        storage: base_decoder_and_sanitizer,
        event: BaseDecoderAndSanitizerEvent,
    );

    component!(
        path: LegacyToNewAvnuDecoderAndSanitizerComponent,
        storage: legacy_to_new_avnu_decoder_and_sanitizer,
        event: LegacyToNewAvnuDecoderAndSanitizerEvent,
    );

    #[abi(embed_v0)]
    impl BaseDecoderAndSanitizerImpl =
        BaseDecoderAndSanitizerComponent::BaseDecoderAndSanitizerImpl<ContractState>;

    #[abi(embed_v0)]
    impl LegacyToNewAvnuDecoderAndSanitizerImpl =
        LegacyToNewAvnuDecoderAndSanitizerComponent::LegacyToNewAvnuDecoderAndSanitizerImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub base_decoder_and_sanitizer: BaseDecoderAndSanitizerComponent::Storage,
        #[substorage(v0)]
        pub legacy_to_new_avnu_decoder_and_sanitizer: LegacyToNewAvnuDecoderAndSanitizerComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        BaseDecoderAndSanitizerEvent: BaseDecoderAndSanitizerComponent::Event,
        #[flat]
        LegacyToNewAvnuDecoderAndSanitizerEvent: LegacyToNewAvnuDecoderAndSanitizerComponent::Event,
    }
}

