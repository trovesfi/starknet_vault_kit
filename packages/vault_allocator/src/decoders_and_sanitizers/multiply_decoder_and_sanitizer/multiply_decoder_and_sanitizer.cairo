// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::component]
pub mod MultiplyDecoderAndSanitizerComponent {
    use vault_allocator::decoders_and_sanitizers::decoder_custom_types::{
        ModifyLeverAction, ModifyLeverParams,
    };
    use vault_allocator::decoders_and_sanitizers::multiply_decoder_and_sanitizer::interface::IMultiplyDecoderAndSanitizer;

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(MultiplyDecoderAndSanitizerImpl)]
    impl MultiplyDecoderAndSanitizer<
        TContractState, +HasComponent<TContractState>,
    > of IMultiplyDecoderAndSanitizer<ComponentState<TContractState>> {
        fn modify_lever(
            self: @ComponentState<TContractState>, modify_lever_params: ModifyLeverParams,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            match modify_lever_params.action {
                ModifyLeverAction::IncreaseLever(params) => {
                    params.pool_id.serialize(ref serialized_struct);
                    params.collateral_asset.serialize(ref serialized_struct);
                    params.debt_asset.serialize(ref serialized_struct);
                    params.user.serialize(ref serialized_struct);
                },
                ModifyLeverAction::DecreaseLever(params) => {
                    params.pool_id.serialize(ref serialized_struct);
                    params.collateral_asset.serialize(ref serialized_struct);
                    params.debt_asset.serialize(ref serialized_struct);
                    params.user.serialize(ref serialized_struct);
                },
            }

            serialized_struct.span()
        }
    }
}
