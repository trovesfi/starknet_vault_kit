use core::hash::HashStateTrait;
use core::num::traits::Zero;
use core::pedersen::PedersenTrait;
use openzeppelin::interfaces::erc4626::{ERC4626ABIDispatcher, ERC4626ABIDispatcherTrait};
use openzeppelin::merkle_tree::hashes::PedersenCHasher;
use starknet::ContractAddress;
use starknet::syscalls::call_contract_syscall;


#[derive(PartialEq, Drop, Serde, Debug, Clone)]
pub struct ManageLeaf {
    pub decoder_and_sanitizer: ContractAddress,
    pub target: ContractAddress,
    pub selector: felt252,
    pub argument_addresses: Span<felt252>,
    pub description: ByteArray,
}


pub fn get_leaf_hash(leaf: ManageLeaf) -> felt252 {
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
    state.finalize()
}

pub fn generate_merkle_tree(manage_leafs: Span<ManageLeaf>) -> Array<Array<felt252>> {
    let mut first_layer = ArrayTrait::new();
    let leafs_length = manage_leafs.len();
    for i in 0..leafs_length {
        first_layer.append(get_leaf_hash(manage_leafs.at(i).clone()));
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


pub fn _pad_leafs_to_power_of_two(ref leafs: Array<ManageLeaf>, ref leaf_index: u256) {
    let target_len = if leaf_index < 4_u256 {
        4_u256
    } else {
        _next_power_of_two(leaf_index)
    };
    let padding_needed = target_len - leaf_index;

    let mut i: u256 = 0_u256;
    while i < padding_needed {
        leafs
            .append(
                ManageLeaf {
                    decoder_and_sanitizer: Zero::zero(),
                    target: Zero::zero(),
                    selector: Zero::zero(),
                    argument_addresses: ArrayTrait::new().span(),
                    description: "",
                },
            );
        leaf_index += 1_u256;
        i += 1_u256;
    }
}


pub fn _get_proofs_using_tree(
    leafs: Array<ManageLeaf>, tree: Array<Array<felt252>>,
) -> Array<Span<felt252>> {
    let mut proofs = ArrayTrait::new();
    for i in 0..leafs.len() {
        let leaf = leafs.at(i);
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


pub fn _add_vault_allocator_leafs(
    ref leafs: Array<ManageLeaf>,
    ref leaf_index: u256,
    vault_allocator: ContractAddress,
    decoder_and_sanitizer: ContractAddress,
    vault: ContractAddress,
) {
    let underlying_asset = ERC4626ABIDispatcher { contract_address: vault }.asset();

    // Approvals
    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: underlying_asset,
                selector: selector!("approve"),
                argument_addresses: array![vault.into()].span(),
                description: "Approve"
                    + " "
                    + get_symbol(vault)
                    + " "
                    + "to spend"
                    + " "
                    + get_symbol(underlying_asset),
            },
        );
    leaf_index += 1;

    // Bring liquidity

    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: vault,
                selector: selector!("bring_liquidity"),
                argument_addresses: array![].span(),
                description: "Bring liquidity" + " " + get_symbol(vault),
            },
        );
    leaf_index += 1;
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
                description: "Flash loan" + " " + get_symbol(asset),
            },
        );
    leaf_index += 1;
}


pub fn _generate_trading_pairs_from_unique_assets(
    ref unique_assets: Array<ContractAddress>,
) -> Array<(ContractAddress, ContractAddress)> {
    let mut trading_pairs: Array<(ContractAddress, ContractAddress)> = ArrayTrait::new();
    loop {
        match unique_assets.pop_front() {
            Option::Some(asset) => {
                for other_asset in @unique_assets {
                    trading_pairs.append((asset, *other_asset))
                }
            },
            Option::None(_) => { break; },
        };
    }
    trading_pairs
}


pub fn _append_unique_assets(
    ref array_of_unique_assets: Array<ContractAddress>,
    assets: Span<ContractAddress>,
    consider_underlying: bool,
) {
    for asset in assets {
        let mut asset_to_consider = *asset;
        if (consider_underlying) {
            asset_to_consider = ERC4626ABIDispatcher { contract_address: *asset }.asset();
        }
        if (!_contains_address(array_of_unique_assets.span(), asset_to_consider)) {
            array_of_unique_assets.append(asset_to_consider);
        }
    }
}


pub fn _contains_address(span: Span<ContractAddress>, addr: ContractAddress) -> bool {
    let mut i = 0;
    while i < span.len() {
        if *span.at(i) == addr {
            return true;
        }
        i += 1;
    }
    false
}


pub fn get_symbol(contract_address: ContractAddress) -> ByteArray {
    let ret_data = call_contract_syscall(contract_address, selector!("symbol"), array![].span());
    match ret_data {
        Ok(res) => {
            let res_len: u32 = res.len();
            if (res_len == 1) {
                let symbol_felt = *res.at(0);
                let mut symbol_byte_array: ByteArray = "";
                symbol_byte_array.append_word(symbol_felt, bytes_in_felt(symbol_felt));
                symbol_byte_array
            } else {
                let mut res_span = res;
                Serde::<ByteArray>::deserialize(ref res_span).unwrap()
            }
        },
        Err(revert_reason) => { panic!("revert_reason: {:?}", revert_reason); },
    }
}


fn bytes_in_felt(word: felt252) -> usize {
    if word == 0 {
        return 0;
    }
    let x: u256 = word.try_into().unwrap();

    let mut p: u256 = 1_u256;
    let mut bytes: usize = 0;

    while p <= x && bytes < 31 {
        p = p * 256_u256;
        bytes += 1;
    }

    bytes
}
