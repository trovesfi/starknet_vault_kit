

#[starknet::component]
pub mod LegacyToNewAvnuDecoderAndSanitizerComponent {
    use vault_allocator::decoders_and_sanitizers::legacy_to_new_avnu_decoder_and_sanitizer::interface::ILegacyToNewAvnuDecoderAndSanitizer;

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(LegacyToNewAvnuDecoderAndSanitizerImpl)]
    impl LegacyToNewAvnuDecoderAndSanitizer<
        TContractState, +HasComponent<TContractState>,
    > of ILegacyToNewAvnuDecoderAndSanitizer<ComponentState<TContractState>> {
        fn swap_to_legacy(
            self: @ComponentState<TContractState>,
            amount: u256
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            serialized_struct.span()
        }
        fn swap_to_new(
            self: @ComponentState<TContractState>,
            amount: u256
        ) -> Span<felt252> {
            let mut serialized_struct: Array<felt252> = ArrayTrait::new();
            serialized_struct.span()
        }
    }
}