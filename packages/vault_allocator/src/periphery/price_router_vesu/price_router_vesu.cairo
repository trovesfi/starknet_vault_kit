// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::contract]
pub mod PriceRouter {
    use core::num::traits::Pow;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::utils::math;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use vault_allocator::integration_interfaces::vesu_v2::{
        IOracleDispatcher, IOracleDispatcherTrait,
    };
    use vault_allocator::periphery::price_router_vesu::errors::Errors;
    use vault_allocator::periphery::price_router_vesu::interface::IPriceRouter;


    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        vesu_oracle: IOracleDispatcher,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }


    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, vesu_oracle: ContractAddress) {
        self.ownable.initializer(owner);
        self.vesu_oracle.write(IOracleDispatcher { contract_address: vesu_oracle });
    }


    #[abi(embed_v0)]
    impl PriceRouterImpl of IPriceRouter<ContractState> {
        fn get_value(
            self: @ContractState,
            base_asset: ContractAddress,
            amount: u256,
            quote_asset: ContractAddress,
        ) -> u256 {
            if base_asset == quote_asset {
                return amount;
            }

            let base_resp = self
                .vesu_oracle
                .read()
                .price(base_asset); // USD price with its own decimals
            if !base_resp.is_valid {
                Errors::invalid_price(base_asset);
            }
            let quote_resp = self.vesu_oracle.read().price(quote_asset);
            if !quote_resp.is_valid {
                Errors::invalid_price(quote_asset);
            }

            let base_price: u256 = base_resp.value;
            let quote_price: u256 = quote_resp.value;

            let asset_decimals_base: u8 = ERC20ABIDispatcher { contract_address: base_asset }
                .decimals();
            let asset_decimals_quote: u8 = ERC20ABIDispatcher { contract_address: quote_asset }
                .decimals();

            let scale_base: u256 = 10_u256.pow(asset_decimals_base.into());
            let scale_quote: u256 = 10_u256.pow(asset_decimals_quote.into());

            let num: u256 = amount * base_price * scale_quote;
            let den: u256 = quote_price * scale_base;
            math::u256_mul_div(num, 1, den, math::Rounding::Ceil)
        }

        fn vesu_oracle_contract(self: @ContractState) -> ContractAddress {
            self.vesu_oracle.read().contract_address
        }
    }
}
