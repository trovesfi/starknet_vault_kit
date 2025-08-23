// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::component]
pub mod VesuV2DecoderAndSanitizerComponent {
    use vault_allocator::decoders_and_sanitizers::decoder_custom_types::ModifyPositionParamsV2;
    use vault_allocator::decoders_and_sanitizers::erc4626_decoder_and_sanitizer::erc4626_decoder_and_sanitizer::Erc4626DecoderAndSanitizerComponent;
    use vault_allocator::decoders_and_sanitizers::erc4626_decoder_and_sanitizer::erc4626_decoder_and_sanitizer::Erc4626DecoderAndSanitizerComponent::Erc4626DecoderAndSanitizerImpl;
    use vault_allocator::decoders_and_sanitizers::vesu_v2_decoder_and_sanitizer::interface::IVesuV2DecoderAndSanitizer;

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(VesuDecoderAndSanitizerImpl)]
    impl VesuDecoderAndSanitizer<
        TContractState,
        +HasComponent<TContractState>,
        +Erc4626DecoderAndSanitizerComponent::HasComponent<TContractState>,
    > of IVesuV2DecoderAndSanitizer<ComponentState<TContractState>> {
        fn modify_position(
            self: @ComponentState<TContractState>, params: ModifyPositionParamsV2,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            params.collateral_asset.serialize(ref serialized_struct);
            params.debt_asset.serialize(ref serialized_struct);
            params.user.serialize(ref serialized_struct);
            serialized_struct.span()
        }
    }
}
