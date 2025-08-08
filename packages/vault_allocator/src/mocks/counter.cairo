// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::contract]
pub mod Counter {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        value: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_value: u128) {
        self.value.write(initial_value);
    }

    #[abi(embed_v0)]
    impl CounterImpl of super::ICounter<ContractState> {
        fn get_value(self: @ContractState) -> u128 {
            self.value.read()
        }

        fn increase(ref self: ContractState, amount: u128) {
            let current_value = self.value.read();
            self.value.write(current_value + amount);
        }

        fn decrease(ref self: ContractState, amount: u128) {
            let current_value = self.value.read();
            assert(current_value >= amount, 'Underflow: value too small');
            self.value.write(current_value - amount);
        }

        fn reset(ref self: ContractState) {
            self.value.write(0);
        }
    }
}

#[starknet::interface]
pub trait ICounter<TContractState> {
    fn get_value(self: @TContractState) -> u128;
    fn increase(ref self: TContractState, amount: u128);
    fn decrease(ref self: TContractState, amount: u128);
    fn reset(ref self: TContractState);
}
