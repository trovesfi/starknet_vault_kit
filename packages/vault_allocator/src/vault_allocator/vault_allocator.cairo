// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

#[starknet::contract]
pub mod VaultAllocator {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::interfaces::upgrades::IUpgradeable;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::account::Call;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::call_contract_syscall;
    use starknet::{ContractAddress, SyscallResultTrait, get_caller_address};
    use vault_allocator::vault_allocator::errors::Errors;
    use vault_allocator::vault_allocator::interface::IVaultAllocator;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        manager: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnableEvent: OwnableComponent::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
    }


    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
    }


    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: starknet::ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }


    #[abi(embed_v0)]
    impl VaultAllocatorImpl of IVaultAllocator<ContractState> {
        fn manager(self: @ContractState) -> ContractAddress {
            self.manager.read()
        }

        fn set_manager(ref self: ContractState, manager: ContractAddress) {
            self.ownable.assert_only_owner();
            self.manager.write(manager);
        }

        fn manage(ref self: ContractState, call: Call) -> Span<felt252> {
            self._only_manager();
            call_contract_syscall(call.to, call.selector, call.calldata).unwrap_syscall()
        }

        fn manage_multi(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            self._only_manager();
            let mut results = ArrayTrait::new();
            let calls_len = calls.len();
            for i in 0..calls_len {
                let call = *calls.at(i);
                results
                    .append(
                        call_contract_syscall(call.to, call.selector, call.calldata)
                            .unwrap_syscall(),
                    );
            }
            results
        }
    }


    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _only_manager(ref self: ContractState) {
            if get_caller_address() != self.manager.read() {
                Errors::only_manager();
            }
        }
    }
}
