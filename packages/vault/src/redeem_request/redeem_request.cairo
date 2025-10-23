// SPDX-License-Identifier: BUSL-1.1
// Licensed under the Business Source License 1.1
// See LICENSE file for details

#[starknet::contract]
mod RedeemRequest {
    use openzeppelin::interfaces::accesscontrol::{
        IAccessControlDispatcher, IAccessControlDispatcherTrait,
    };
    use openzeppelin::interfaces::upgrades::IUpgradeable;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::extensions::ERC721EnumerableComponent;
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use vault::redeem_request::errors::Errors;
    use vault::redeem_request::interface::{IRedeemRequest, RedeemRequestInfo};
    use vault::vault::vault::Vault::OWNER_ROLE;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(
        path: ERC721EnumerableComponent, storage: erc721_enumerable, event: ERC721EnumerableEvent,
    );
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        ERC721EnumerableComponent::ERC721EnumerableImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        erc721_enumerable: ERC721EnumerableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        id_len: u256,
        id_to_info: Map<u256, RedeemRequestInfo>,
        vault: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        ERC721EnumerableEvent: ERC721EnumerableComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }


    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, vault: ContractAddress) {
        self.erc721.initializer("redeem_request", "rr", "none");
        self.vault.write(vault);
    }

    #[abi(embed_v0)]
    impl RedeemRequestImpl of IRedeemRequest<ContractState> {
        // ─────────────────────────────────────────────────────────────────────
        // View functions
        // ─────────────────────────────────────────────────────────────────────

        fn vault(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }

        fn id_to_info(self: @ContractState, id: u256) -> RedeemRequestInfo {
            self.id_to_info.read(id)
        }

        fn id_len(self: @ContractState) -> u256 {
            self.id_len.read()
        }

        // ─────────────────────────────────────────────────────────────────────
        // External functions
        // ─────────────────────────────────────────────────────────────────────

        fn mint(
            ref self: ContractState, to: ContractAddress, redeem_request_info: RedeemRequestInfo,
        ) -> u256 {
            self._assert_vault();
            let id = self.id_len.read();
            self.erc721.mint(to, id);
            self.id_to_info.write(id, redeem_request_info);
            self.id_len.write(id + 1);
            id
        }

        fn burn(ref self: ContractState, id: u256) {
            self._assert_vault();
            self.erc721.burn(id);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: starknet::ClassHash) {
            let vault_access_control_dispatcher = IAccessControlDispatcher {
                contract_address: self.vault.read(),
            };
            if (!vault_access_control_dispatcher.has_role(OWNER_ROLE, get_caller_address())) {
                Errors::not_vault_owner();
            }
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// @notice Verifies that the caller is the token gateway
        /// @dev Panics with an error message if the caller is not the token gateway
        /// @custom:security Only the token gateway should be able to mint and burn redemption
        /// tokens
        fn _assert_vault(ref self: ContractState) {
            if (self.vault.read() != get_caller_address()) {
                Errors::not_vault();
            }
        }
    }
}
