// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::contract]
pub mod AvnuMiddleware {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;
    use vault_allocator::integration_interfaces::avnu::{
        IAvnuExchangeDispatcher, IAvnuExchangeDispatcherTrait,
    };
    use vault_allocator::middlewares::avnu_middleware::errors::Errors;
    use vault_allocator::middlewares::avnu_middleware::interface::IAvnuMiddleware;
    use vault_allocator::periphery::price_router::interface::{
        IPriceRouterDispatcher, IPriceRouterDispatcherTrait,
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        avnu_router: IAvnuExchangeDispatcher,
        price_router: IPriceRouterDispatcher,
        slippage_tolerance_bps: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        SlippageUpdated: SlippageUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SlippageUpdated {
        pub old_slippage: u256,
        pub new_slippage: u256,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        avnu_router: ContractAddress,
        price_router: ContractAddress,
        initial_slippage_bps: u256,
    ) {
        self.ownable.initializer(owner);
        self.avnu_router.write(IAvnuExchangeDispatcher { contract_address: avnu_router });
        self.price_router.write(IPriceRouterDispatcher { contract_address: price_router });
        self.slippage_tolerance_bps.write(initial_slippage_bps);
    }


    #[abi(embed_v0)]
    impl AvnuMiddlewareViewImpl of IAvnuMiddleware<ContractState> {
        fn avnu_router(self: @ContractState) -> ContractAddress {
            self.avnu_router.read().contract_address
        }

        fn price_router(self: @ContractState) -> ContractAddress {
            self.price_router.read().contract_address
        }

        fn slippage_tolerance_bps(self: @ContractState) -> u256 {
            self.slippage_tolerance_bps.read()
        }

        fn set_slippage_tolerance_bps(ref self: ContractState, new_slippage_bps: u256) {
            self.ownable.assert_only_owner();
            if (new_slippage_bps > 10_000) {
                Errors::slippage_exceeds_max(new_slippage_bps);
            }
            let old_slippage = self.slippage_tolerance_bps.read();
            self.slippage_tolerance_bps.write(new_slippage_bps);
            self.emit(SlippageUpdated { old_slippage, new_slippage: new_slippage_bps });
        }

        fn multi_route_swap(
            self: @ContractState,
            sell_token_address: ContractAddress,
            sell_token_amount: u256,
            buy_token_address: ContractAddress,
            buy_token_amount: u256,
            buy_token_min_amount: u256,
            beneficiary: ContractAddress,
            integrator_fee_amount_bps: u128,
            integrator_fee_recipient: ContractAddress,
            routes: Array<Route>,
        ) -> u256 {
            let caller = get_caller_address();
            let this = get_contract_address();
            if sell_token_address == buy_token_address {
                ERC20ABIDispatcher { contract_address: sell_token_address }
                    .transfer_from(caller, beneficiary, sell_token_amount);
                return sell_token_amount;
            }
            let sell = ERC20ABIDispatcher { contract_address: sell_token_address };
            let buy = ERC20ABIDispatcher { contract_address: buy_token_address };
            let avnu = self.avnu_router.read();
            sell.transfer_from(caller, this, sell_token_amount);
            sell.approve(avnu.contract_address, sell_token_amount);
            let quote_out = self
                .price_router
                .read()
                .get_value(sell_token_address, sell_token_amount, buy_token_address);

            let computed_min = quote_out
                * (10_000_u256 - self.slippage_tolerance_bps.read())
                / 10_000_u256;
            let min_out = if buy_token_min_amount < computed_min {
                computed_min
            } else {
                buy_token_min_amount
            };
            let buy_bal_0 = buy.balance_of(this);

            avnu
                .multi_route_swap(
                    sell_token_address,
                    sell_token_amount,
                    buy_token_address,
                    buy_token_amount,
                    min_out,
                    this,
                    integrator_fee_amount_bps,
                    integrator_fee_recipient,
                    routes,
                );
            let buy_bal_1 = buy.balance_of(this);
            let out = buy_bal_1 - buy_bal_0;
            if (out < min_out) {
                Errors::insufficient_output(out, min_out);
            }
            buy.transfer(beneficiary, out);
            0
        }
    }
}
