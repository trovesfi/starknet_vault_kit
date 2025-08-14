// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use starknet::{ContractAddress, get_contract_address};

fn transfer_asset(
    asset: ContractAddress,
    sender: ContractAddress,
    to: ContractAddress,
    amount: u256,
    is_legacy: bool,
) {
    let erc20 = ERC20ABIDispatcher { contract_address: asset };
    if sender == get_contract_address() {
        assert!(erc20.transfer(to, amount), "transfer-failed");
    } else if is_legacy {
        assert!(erc20.transferFrom(sender, to, amount), "transferFrom-failed");
    } else {
        assert!(erc20.transfer_from(sender, to, amount), "transfer-from-failed");
    }
}

#[starknet::contract]
pub mod FlashLoanSingletonMock {
    use core::num::traits::Zero;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use vault_allocator::integration_interfaces::vesu::{
        IFlashloanReceiverDispatcher, IFlashloanReceiverDispatcherTrait,
    };
    use super::{get_contract_address, transfer_asset};


    #[storage]
    struct Storage {
        do_nothing: bool,
        i_did_something: bool,
        do_wrong_callback: bool,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl FlashLoanSingletonMockImpl of super::IFlashLoanSingletonMock<ContractState> {
        fn do_wrong_callback(self: @ContractState) -> bool {
            self.do_wrong_callback.read()
        }

        fn set_do_wrong_callback(ref self: ContractState, do_wrong_callback: bool) {
            self.do_wrong_callback.write(do_wrong_callback);
        }

        fn flash_loan(
            ref self: ContractState,
            receiver: ContractAddress,
            asset: ContractAddress,
            amount: u256,
            is_legacy: bool,
            data: Span<felt252>,
        ) {
            if (!self.do_nothing.read()) {
                if (!self.do_wrong_callback.read()) {
                    transfer_asset(asset, get_contract_address(), receiver, amount, is_legacy);
                    IFlashloanReceiverDispatcher { contract_address: receiver }
                        .on_flash_loan(get_caller_address(), asset, amount, data);
                    transfer_asset(asset, receiver, get_contract_address(), amount, is_legacy);
                } else {
                    let mut flash_loan_data_proofs: Array<Span<felt252>> = ArrayTrait::new();
                    flash_loan_data_proofs.append(array![Zero::zero()].span());
                    let mut flash_loan_data_decoder_and_sanitizer: Array<ContractAddress> =
                        ArrayTrait::new();
                    flash_loan_data_decoder_and_sanitizer.append(Zero::zero());
                    let mut flash_loan_data_target: Array<ContractAddress> = ArrayTrait::new();
                    flash_loan_data_target.append(Zero::zero());
                    let mut flash_loan_data_selector: Array<felt252> = ArrayTrait::new();
                    flash_loan_data_selector.append(Zero::zero());
                    let mut flash_loan_data_calldata: Array<Span<felt252>> = ArrayTrait::new();
                    flash_loan_data_calldata.append(array![Zero::zero()].span());
                    let mut serialized_flash_loan_data = ArrayTrait::new();
                    (
                        flash_loan_data_proofs.span(),
                        flash_loan_data_decoder_and_sanitizer.span(),
                        flash_loan_data_target.span(),
                        flash_loan_data_selector.span(),
                        flash_loan_data_calldata.span(),
                    )
                        .serialize(ref serialized_flash_loan_data);

                    transfer_asset(asset, get_contract_address(), receiver, amount, is_legacy);
                    IFlashloanReceiverDispatcher { contract_address: receiver }
                        .on_flash_loan(
                            get_caller_address(), asset, amount, serialized_flash_loan_data.span(),
                        );
                    transfer_asset(asset, receiver, get_contract_address(), amount, is_legacy);
                }
            }
        }

        fn approve(ref self: ContractState, token: ContractAddress, amount: u256) {
            transfer_asset(token, get_caller_address(), get_contract_address(), amount, true);
            transfer_asset(token, get_contract_address(), get_caller_address(), amount, true);
            self.i_did_something.write(true)
        }

        fn i_did_something(self: @ContractState) -> bool {
            self.i_did_something.read()
        }

        fn do_nothing(self: @ContractState) -> bool {
            self.do_nothing.read()
        }

        fn set_do_nothing(ref self: ContractState, do_nothing: bool) {
            self.do_nothing.write(do_nothing);
        }
    }
}

#[starknet::interface]
pub trait IFlashLoanSingletonMock<TContractState> {
    fn flash_loan(
        ref self: TContractState,
        receiver: ContractAddress,
        asset: ContractAddress,
        amount: u256,
        is_legacy: bool,
        data: Span<felt252>,
    );

    fn approve(ref self: TContractState, token: ContractAddress, amount: u256);

    fn i_did_something(self: @TContractState) -> bool;
    fn do_nothing(self: @TContractState) -> bool;
    fn do_wrong_callback(self: @TContractState) -> bool;
    fn set_do_nothing(ref self: TContractState, do_nothing: bool);
    fn set_do_wrong_callback(ref self: TContractState, do_wrong_callback: bool);
}
