use starknet::ContractAddress;
use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;

#[starknet::interface]
pub trait ILegacyToNewAvnuDecoderAndSanitizer<T> {
    fn swap_to_legacy(
        self: @T,
        amount: u256
    ) -> Span<felt252>;
    fn swap_to_new(
        self: @T,
        amount: u256
    ) -> Span<felt252>;
}