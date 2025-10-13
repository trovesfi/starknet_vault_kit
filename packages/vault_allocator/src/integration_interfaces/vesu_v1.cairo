use starknet::ContractAddress;

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct Position {
    collateral_shares: u256,
    nominal_debt: u256,
}

#[starknet::interface]
pub trait IV1Token<TContractState> {
    fn pool_id(self: @TContractState) -> felt252;
}

#[starknet::interface]
pub trait ISingletonV2<TContractState> {
    fn position(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
    ) -> (Position, u256, u256);
}
