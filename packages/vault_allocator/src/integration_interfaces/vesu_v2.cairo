use starknet::ContractAddress;
use vault_allocator::integration_interfaces::vesu_v1::Position;

#[starknet::interface]
pub trait IV2Token<TContractState> {
    fn pool_contract(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
pub trait IPool<TContractState> {
    fn position(
        self: @TContractState,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
    ) -> (Position, u256, u256);
}


#[starknet::interface]
pub trait IOracle<TContractState> {
    fn price(self: @TContractState, asset: ContractAddress) -> AssetPrice;
}
#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub struct AssetPrice {
    pub value: u256,
    pub is_valid: bool,
}
