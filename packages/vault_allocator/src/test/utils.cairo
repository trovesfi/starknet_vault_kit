// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

use core::hash::HashStateTrait;
use core::num::traits::Zero;
use core::pedersen::PedersenTrait;
use openzeppelin::merkle_tree::hashes::PedersenCHasher;
use openzeppelin::token::erc20::extensions::erc4626::interface::{
    IERC4626Dispatcher, IERC4626DispatcherTrait,
};
use snforge_std::{CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare};
use starknet::{ClassHash, ContractAddress};
use vault_allocator::integration_interfaces::vesu::{
    IDefaultExtensionPOV2Dispatcher, IDefaultExtensionPOV2DispatcherTrait, ISingletonV2Dispatcher,
    ISingletonV2DispatcherTrait,
};
use vault_allocator::manager::interface::IManagerDispatcher;
use vault_allocator::mocks::counter::ICounterDispatcher;
use vault_allocator::test::register::VESU_SINGLETON;
use vault_allocator::vault_allocator::interface::IVaultAllocatorDispatcher;
pub const WAD: u256 = 1_000_000_000_000_000_000;

pub fn OWNER() -> ContractAddress {
    'OWNER'.try_into().unwrap()
}

pub fn MANAGER() -> ContractAddress {
    'MANAGER'.try_into().unwrap()
}

pub fn STRATEGIST() -> ContractAddress {
    'STRATEGIST'.try_into().unwrap()
}

pub fn DUMMY_ADDRESS() -> ContractAddress {
    'DUMMY_ADDRESS'.try_into().unwrap()
}


pub fn deploy_vault_allocator() -> IVaultAllocatorDispatcher {
    let vault_allocator = declare("VaultAllocator").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    OWNER().serialize(ref calldata);
    let (vault_allocator_address, _) = vault_allocator.deploy(@calldata).unwrap();
    IVaultAllocatorDispatcher { contract_address: vault_allocator_address }
}

pub fn deploy_manager(
    vault_allocator: IVaultAllocatorDispatcher, vesu_singleton: ContractAddress,
) -> IManagerDispatcher {
    let manager = declare("Manager").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    OWNER().serialize(ref calldata);
    vault_allocator.contract_address.serialize(ref calldata);
    vesu_singleton.serialize(ref calldata);
    let (manager_address, _) = manager.deploy(@calldata).unwrap();
    IManagerDispatcher { contract_address: manager_address }
}

pub fn deploy_counter() -> (ICounterDispatcher, ClassHash) {
    let counter = declare("Counter").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    let initial_value: u128 = 0;
    initial_value.serialize(ref calldata);
    let (counter_address, _) = counter.deploy(@calldata).unwrap();
    (ICounterDispatcher { contract_address: counter_address }, *counter.class_hash)
}

pub fn deploy_flashloan_mock() -> ContractAddress {
    let flashloan = declare("FlashLoanSingletonMock").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    let (flashloan_address, _) = flashloan.deploy(@calldata).unwrap();
    flashloan_address
}

pub fn deploy_erc4626_mock(underlying: ContractAddress) -> ContractAddress {
    let erc4626 = declare("Erc4626Mock").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    underlying.serialize(ref calldata);
    let (erc4626_address, _) = erc4626.deploy(@calldata).unwrap();
    erc4626_address
}

pub fn deploy_erc20_mock() -> ContractAddress {
    let erc20 = declare("Erc20Mock").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    (WAD * 100).serialize(ref calldata);
    OWNER().serialize(ref calldata);
    OWNER().serialize(ref calldata);
    let (erc20_address, _) = erc20.deploy(@calldata).unwrap();
    erc20_address
}

pub fn deploy_simple_decoder_and_sanitizer() -> ContractAddress {
    let simple_decoder_and_sanitizer = declare("SimpleDecoderAndSanitizer")
        .unwrap()
        .contract_class();
    let mut calldata = ArrayTrait::new();
    let (simple_decoder_and_sanitizer_address, _) = simple_decoder_and_sanitizer
        .deploy(@calldata)
        .unwrap();
    simple_decoder_and_sanitizer_address
}


pub fn cheat_caller_address_once(
    contract_address: ContractAddress, caller_address: ContractAddress,
) {
    cheat_caller_address(:contract_address, :caller_address, span: CheatSpan::TargetCalls(1));
}


#[derive(PartialEq, Copy, Drop, Serde, Debug)]
pub struct ManageLeaf {
    pub decoder_and_sanitizer: ContractAddress,
    pub target: ContractAddress,
    pub selector: felt252,
    pub argument_addresses: Span<felt252>,
}


pub fn generate_merkle_tree(manage_leafs: Span<ManageLeaf>) -> Array<Array<felt252>> {
    let mut first_layer = ArrayTrait::new();
    let leafs_length = manage_leafs.len();
    for i in 0..leafs_length {
        let mut serialized_struct: Array<felt252> = ArrayTrait::new();
        manage_leafs[i].decoder_and_sanitizer.serialize(ref serialized_struct);
        manage_leafs[i].target.serialize(ref serialized_struct);
        manage_leafs[i].selector.serialize(ref serialized_struct);
        manage_leafs[i].argument_addresses.serialize(ref serialized_struct);
        let first_element = serialized_struct.pop_front().unwrap();
        let mut state = PedersenTrait::new(first_element);

        while let Some(value) = serialized_struct.pop_front() {
            state = state.update(value);
        }
        let leaf_hash = state.finalize();
        first_layer.append(leaf_hash);
    }
    let mut leafs = ArrayTrait::new();
    leafs.append(first_layer);
    _build_tree(leafs)
}

pub fn _build_tree(merkle_tree_in: Array<Array<felt252>>) -> Array<Array<felt252>> {
    let merkle_tree_in_length = merkle_tree_in.len();

    let mut current_layer_index = merkle_tree_in_length - 1;
    let current_layer_length = merkle_tree_in[current_layer_index].len();
    let mut next_layer_length = 0;
    if (current_layer_length % 2 != 0) {
        next_layer_length = (current_layer_length + 1) / 2;
    } else {
        next_layer_length = current_layer_length / 2;
    }
    let mut current_layer = ArrayTrait::new();
    let mut count = 0;
    let mut i = 0;
    while i < current_layer_length {
        current_layer
            .append(
                PedersenCHasher::commutative_hash(
                    *merkle_tree_in[current_layer_index].at(i),
                    *merkle_tree_in[current_layer_index].at(i + 1),
                ),
            );
        count += 1;
        i += 2;
    }

    let mut merkle_tree_out = merkle_tree_in.clone();
    merkle_tree_out.append(current_layer);

    if (next_layer_length > 1) {
        _build_tree(merkle_tree_out)
    } else {
        merkle_tree_out
    }
}

fn _next_power_of_two(x: u256) -> u256 {
    let mut power = 1_u256;
    while power < x {
        power = power * 2_u256;
    }
    power
}
// pub fn _pad_leafs_to_power_of_two(ref leafs: Array<ManageLeaf>, ref leaf_index: u256) {
//     let next_power = _next_power_of_two(leaf_index);
//     let padding_needed = next_power - leaf_index;

//     let default_leaf = ManageLeaf {
//         decoder_and_sanitizer: Zero::zero(),
//         target: Zero::zero(),
//         selector: Zero::zero(),
//         argument_addresses: ArrayTrait::new().span(),
//     };

//     let mut i = 0;
//     while i < padding_needed {
//         leafs.append(default_leaf);
//         leaf_index += 1;
//         i += 1;
//     }
// }

pub fn _pad_leafs_to_power_of_two(ref leafs: Array<ManageLeaf>, ref leaf_index: u256) {
    let target_len = if leaf_index < 4_u256 {
        4_u256
    } else {
        _next_power_of_two(leaf_index)
    };
    let padding_needed = target_len - leaf_index;

    let default_leaf = ManageLeaf {
        decoder_and_sanitizer: Zero::zero(),
        target: Zero::zero(),
        selector: Zero::zero(),
        argument_addresses: ArrayTrait::new().span(),
    };

    let mut i: u256 = 0_u256;
    while i < padding_needed {
        leafs.append(default_leaf);
        leaf_index += 1_u256;
        i += 1_u256;
    }
}


pub fn _get_proofs_using_tree(
    leafs: Array<ManageLeaf>, tree: Array<Array<felt252>>,
) -> Array<Span<felt252>> {
    let mut proofs = ArrayTrait::new();
    for i in 0..leafs.len() {
        let leaf = *leafs.at(i);
        let mut serialized_struct: Array<felt252> = ArrayTrait::new();
        leaf.decoder_and_sanitizer.serialize(ref serialized_struct);
        leaf.target.serialize(ref serialized_struct);
        leaf.selector.serialize(ref serialized_struct);
        leaf.argument_addresses.serialize(ref serialized_struct);
        let first_element = serialized_struct.pop_front().unwrap();
        let mut state = PedersenTrait::new(first_element);

        while let Some(value) = serialized_struct.pop_front() {
            state = state.update(value);
        }
        let leaf_hash = state.finalize();
        let proof = _generate_proof(leaf_hash, tree.clone());
        proofs.append(proof);
    }
    proofs
}

pub fn _generate_proof(mut leaf: felt252, tree: Array<Array<felt252>>) -> Span<felt252> {
    let tree_length = tree.len();
    let mut proof = ArrayTrait::new();
    for i in 0..tree_length - 1 {
        let tree_current_layer = tree.at(i);
        let tree_current_layer_length = tree_current_layer.len();
        for j in 0..tree_current_layer_length {
            if leaf == *tree_current_layer.at(j) {
                let element_to_append = if j % 2 == 0 {
                    *tree_current_layer.at(j + 1)
                } else {
                    *tree_current_layer.at(j - 1)
                };
                leaf = PedersenCHasher::commutative_hash(leaf, element_to_append);
                proof.append(element_to_append);
                break;
            } else {
                assert(j != tree_current_layer_length - 1, 'leaf not found in tree');
            }
        }
    }
    proof.span()
}


// ========================================= ERC4626 =========================================

pub fn _add_erc4626_leafs(
    ref leafs: Array<ManageLeaf>,
    ref leaf_index: u256,
    vault: ContractAddress,
    decoder_and_sanitizer: ContractAddress,
    erc4626: ContractAddress,
) {
    let asset = IERC4626Dispatcher { contract_address: erc4626 }.asset();

    // Approvals
    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: asset,
                selector: selector!("approve"),
                argument_addresses: array![erc4626.into()].span(),
            },
        );
    leaf_index += 1;

    // Deposits

    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: erc4626,
                selector: selector!("deposit"),
                argument_addresses: array![vault.into()].span(),
            },
        );
    leaf_index += 1;

    // Withdrawals

    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: erc4626,
                selector: selector!("withdraw"),
                argument_addresses: array![vault.into(), vault.into()].span(),
            },
        );
    leaf_index += 1;

    // Minting

    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: erc4626,
                selector: selector!("mint"),
                argument_addresses: array![vault.into()].span(),
            },
        );
    leaf_index += 1;

    // Redeeming

    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: erc4626,
                selector: selector!("redeem"),
                argument_addresses: array![vault.into(), vault.into()].span(),
            },
        );
    leaf_index += 1;
}


// ========================================= VESU =========================================

pub fn _add_vesu_leafs(
    ref leafs: Array<ManageLeaf>,
    ref leaf_index: u256,
    vault: ContractAddress,
    decoder_and_sanitizer: ContractAddress,
    pool_id: felt252,
    collateral_assets: Span<ContractAddress>,
    debt_assets_per_collateral_asset: Span<Span<ContractAddress>>,
) {
    assert(collateral_assets.len() == debt_assets_per_collateral_asset.len(), 'inconsistent len');
    let singleton = ISingletonV2Dispatcher { contract_address: VESU_SINGLETON() };
    let pool_extension = singleton.extension(pool_id);
    assert(pool_extension != Zero::zero(), 'pool extension not found');
    let pool_extension = IDefaultExtensionPOV2Dispatcher { contract_address: pool_extension };

    for i in 0..collateral_assets.len() {
        let collateral_asset = *collateral_assets.at(i);
        let debt_assets = *debt_assets_per_collateral_asset.at(i);

        let v_token = pool_extension.v_token_for_collateral_asset(pool_id, collateral_asset);
        assert(v_token != Zero::zero(), 'v token not found');

        // earn mode
        _add_erc4626_leafs(ref leafs, ref leaf_index, vault, decoder_and_sanitizer, v_token);

        // debt mode
        let debt_assets_len = debt_assets.len();
        if debt_assets_len > 0 {
            for j in 0..debt_assets_len {
                // APPROVAL of v-token to the extension
                leafs
                    .append(
                        ManageLeaf {
                            decoder_and_sanitizer,
                            target: v_token,
                            selector: selector!("approve"),
                            argument_addresses: array![pool_extension.contract_address.into()]
                                .span(),
                        },
                    );
                leaf_index += 1;

                let debt_asset = *debt_assets.at(j);

                // TRANSFER POSITION to create the pair collateral/debt
                let mut argument_addresses_transfer_position = ArrayTrait::new();

                // pool_id
                pool_id.serialize(ref argument_addresses_transfer_position);

                // from_collateral_asset
                collateral_asset.serialize(ref argument_addresses_transfer_position);

                // from_debt_asset
                let from_debt_asset: ContractAddress = Zero::zero();
                from_debt_asset.serialize(ref argument_addresses_transfer_position);

                // to_collateral_asset
                collateral_asset.serialize(ref argument_addresses_transfer_position);

                // to_debt_asset
                debt_asset.serialize(ref argument_addresses_transfer_position);

                // from_user
                pool_extension.contract_address.serialize(ref argument_addresses_transfer_position);

                // to_user
                vault.serialize(ref argument_addresses_transfer_position);

                // from_data
                let from_data: Span<felt252> = array![].span();
                from_data.serialize(ref argument_addresses_transfer_position);

                // to_data
                let to_data: Span<felt252> = array![].span();
                to_data.serialize(ref argument_addresses_transfer_position);

                leafs
                    .append(
                        ManageLeaf {
                            decoder_and_sanitizer,
                            target: singleton.contract_address,
                            selector: selector!("transfer_position"),
                            argument_addresses: argument_addresses_transfer_position.span(),
                        },
                    );
                leaf_index += 1;

                // MODIFY POSITION
                let mut argument_addresses_modify_position = ArrayTrait::new();

                // pool_id
                pool_id.serialize(ref argument_addresses_modify_position);

                // collateral_asset
                collateral_asset.serialize(ref argument_addresses_modify_position);

                // debt_asset
                debt_asset.serialize(ref argument_addresses_modify_position);

                // user
                vault.serialize(ref argument_addresses_modify_position);

                // data
                let data: Span<felt252> = array![].span();
                data.serialize(ref argument_addresses_modify_position);

                leafs
                    .append(
                        ManageLeaf {
                            decoder_and_sanitizer,
                            target: singleton.contract_address,
                            selector: selector!("modify_position"),
                            argument_addresses: argument_addresses_modify_position.span(),
                        },
                    );
                leaf_index += 1;
            }
        }
    }
}


pub fn _add_vesu_flash_loan_leafs(
    ref leafs: Array<ManageLeaf>,
    ref leaf_index: u256,
    vault: ContractAddress,
    decoder_and_sanitizer: ContractAddress,
    manager: ContractAddress,
    asset: ContractAddress,
    is_legacy: bool,
) {
    let mut argument_addresses = ArrayTrait::new();
    manager.serialize(ref argument_addresses);
    asset.serialize(ref argument_addresses);
    is_legacy.serialize(ref argument_addresses);

    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: manager,
                selector: selector!("flash_loan"),
                argument_addresses: argument_addresses.span(),
            },
        );
    leaf_index += 1;
}
