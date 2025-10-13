// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::component]
pub mod VesuDecoderAndSanitizerComponent {
    use vault_allocator::decoders_and_sanitizers::decoder_custom_types::ModifyPositionParams;
    use vault_allocator::decoders_and_sanitizers::vesu_decoder_and_sanitizer::interface::IVesuDecoderAndSanitizer;
    use starknet::ContractAddress;
    
    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(VesuDecoderAndSanitizerImpl)]
    impl VesuDecoderAndSanitizer<
        TContractState, +HasComponent<TContractState>,
    > of IVesuDecoderAndSanitizer<ComponentState<TContractState>> {
        fn modify_position(
            self: @ComponentState<TContractState>, params: ModifyPositionParams,
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            params.pool_id.serialize(ref serialized_struct);
            params.collateral_asset.serialize(ref serialized_struct);
            params.debt_asset.serialize(ref serialized_struct);
            params.user.serialize(ref serialized_struct);
            serialized_struct.span()
        }

        fn modify_delegation(
            self: @ComponentState<TContractState>,
            delegatee: ContractAddress, delegation: bool
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            delegatee.serialize(ref serialized_struct);
            serialized_struct.span()
        }
    }
}
