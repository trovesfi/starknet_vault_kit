// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::contract]
pub mod AvnuMiddleware {
    const BPS_SCALE: u16 = 10_000;
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::utils::math;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;
    use vault_allocator::integration_interfaces::avnu::{
        IAvnuExchangeDispatcher, IAvnuExchangeDispatcherTrait,
    };
    use vault_allocator::merkle_tree::registery::AVNU_ROUTER;
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
        price_router: IPriceRouterDispatcher,
        vault_allocator: ContractAddress,
        slippage: u16,
        period: u64,
        allowed_calls_per_period: u64,
        call_count: Map<u64, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        ConfigUpdated: ConfigUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct ConfigUpdated {
        pub slippage: u16,
        period: u64,
        allowed_calls_per_period: u64,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        vault_allocator: ContractAddress,
        price_router: ContractAddress,
        slippage: u16,
        period: u64,
        allowed_calls_per_period: u64,
    ) {
        self.ownable.initializer(owner);
        self.price_router.write(IPriceRouterDispatcher { contract_address: price_router });
        self.vault_allocator.write(vault_allocator);
        self._set_config(slippage, period, allowed_calls_per_period)
    }


    #[abi(embed_v0)]
    impl AvnuMiddlewareViewImpl of IAvnuMiddleware<ContractState> {
        fn avnu_router(self: @ContractState) -> ContractAddress {
            AVNU_ROUTER()
        }

        fn price_router(self: @ContractState) -> ContractAddress {
            self.price_router.read().contract_address
        }

        fn vault_allocator(self: @ContractState) -> ContractAddress {
            self.vault_allocator.read()
        }

        fn config(self: @ContractState) -> (u16, u64, u64) {
            (self.slippage.read(), self.period.read(), self.allowed_calls_per_period.read())
        }
        fn set_config(
            ref self: ContractState, slippage: u16, period: u64, allowed_calls_per_period: u64,
        ) {
            self.ownable.assert_only_owner();
            self._set_config(slippage, period, allowed_calls_per_period);
            self.emit(ConfigUpdated { slippage, period, allowed_calls_per_period });
        }


        fn multi_route_swap(
            ref self: ContractState,
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
            self.enforce_rate_limit(caller);
            let this = get_contract_address();

            if (sell_token_amount == Zero::zero()) {
                return Zero::zero();
            }

            if sell_token_address == buy_token_address {
                ERC20ABIDispatcher { contract_address: sell_token_address }
                    .transfer_from(caller, beneficiary, sell_token_amount);
                return sell_token_amount;
            }
            let sell = ERC20ABIDispatcher { contract_address: sell_token_address };
            let buy = ERC20ABIDispatcher { contract_address: buy_token_address };
            let avnu = IAvnuExchangeDispatcher { contract_address: AVNU_ROUTER() };
            sell.transfer_from(caller, this, sell_token_amount);
            sell.approve(avnu.contract_address, sell_token_amount);
            let quote_out = self
                .price_router
                .read()
                .get_value(sell_token_address, sell_token_amount, buy_token_address);

            let computed_min = math::u256_mul_div(
                quote_out,
                (BPS_SCALE - self.slippage.read()).into(),
                BPS_SCALE.into(),
                math::Rounding::Ceil,
            );

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
                    Zero::zero(),
                    min_out,
                    this,
                    Zero::zero(),
                    Zero::zero(),
                    routes,
                );
            let buy_bal_1 = buy.balance_of(this);
            let out = buy_bal_1 - buy_bal_0;
            if (out < min_out) {
                Errors::insufficient_output(out, min_out);
            }
            buy.transfer(beneficiary, out);
            out
        }
    }


    #[generate_trait]
    pub impl InternalFunctions of InternalFunctionsTrait {
        fn enforce_rate_limit(ref self: ContractState, caller: ContractAddress) {
            if (caller != self.vault_allocator.read()) {
                Errors::caller_not_vault_allocator();
            }
            let ts: u64 = get_block_timestamp();
            let slot = ts % self.period.read();
            let current = self.call_count.read(slot);
            let next = current + 1;
            let allowed_calls_per_period = self.allowed_calls_per_period.read();
            if (next > allowed_calls_per_period) {
                Errors::rate_limit_exceeded(next, allowed_calls_per_period);
            }
            self.call_count.write(slot, next);
        }

        fn _set_config(
            ref self: ContractState, slippage: u16, period: u64, allowed_calls_per_period: u64,
        ) {
            if (slippage >= BPS_SCALE) {
                Errors::slippage_exceeds_max(slippage);
            }

            self.slippage.write(slippage);

            if (period.is_zero()) {
                Errors::period_zero();
            }
            self.period.write(period);
            if (allowed_calls_per_period.is_zero()) {
                Errors::allowed_calls_per_period_zero();
            }
            self.allowed_calls_per_period.write(allowed_calls_per_period);
        }
    }
}
