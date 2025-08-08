// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::component]
pub mod VesuDecoderAndSanitizerComponent {
    use starknet::ContractAddress;
    use vault_allocator::decoders_and_sanitizers::decoder_custom_types::{
        ModifyPositionParams, TransferPositionParams,
    };
    use vault_allocator::decoders_and_sanitizers::erc4626_decoder_and_sanitizer::erc4626_decoder_and_sanitizer::Erc4626DecoderAndSanitizerComponent;
    use vault_allocator::decoders_and_sanitizers::erc4626_decoder_and_sanitizer::erc4626_decoder_and_sanitizer::Erc4626DecoderAndSanitizerComponent::Erc4626DecoderAndSanitizerImpl;
    use vault_allocator::decoders_and_sanitizers::vesu_decoder_and_sanitizer::interface::IVesuDecoderAndSanitizer;

    #[storage]
    pub struct Storage {
        pub vault_allocator: ContractAddress,
    }

    #[event]
    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(VesuDecoderAndSanitizerImpl)]
    impl VesuDecoderAndSanitizer<
        TContractState,
        +HasComponent<TContractState>,
        +Erc4626DecoderAndSanitizerComponent::HasComponent<TContractState>,
    > of IVesuDecoderAndSanitizer<ComponentState<TContractState>> {
        fn transfer_position(
            self: @ComponentState<TContractState>, params: TransferPositionParams,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            params.pool_id.serialize(ref serialized_struct);
            params.from_collateral_asset.serialize(ref serialized_struct);

            // From debt asset, isn't it always 0 ? to confirm
            params.from_debt_asset.serialize(ref serialized_struct);
            params.to_collateral_asset.serialize(ref serialized_struct);
            params.to_debt_asset.serialize(ref serialized_struct);

            //From user is in fact the extensin : to confirm
            params.from_user.serialize(ref serialized_struct);
            params.to_user.serialize(ref serialized_struct);

            //not sure to include those 2 fields : to confirm
            params.from_data.serialize(ref serialized_struct);
            params.to_data.serialize(ref serialized_struct);
            serialized_struct.span()
        }


        fn modify_position(
            self: @ComponentState<TContractState>, params: ModifyPositionParams,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            params.pool_id.serialize(ref serialized_struct);
            params.collateral_asset.serialize(ref serialized_struct);
            params.debt_asset.serialize(ref serialized_struct);
            params.user.serialize(ref serialized_struct);

            // not sure to include this fields : to confirm
            params.data.serialize(ref serialized_struct);

            serialized_struct.span()
        }
    }
}
