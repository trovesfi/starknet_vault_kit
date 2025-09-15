use core::to_byte_array::FormatAsByteArray;
use starknet::ContractAddress;
use vault_allocator::merkle_tree::base::{ManageLeaf, get_symbol};
use vault_allocator::merkle_tree::registery::VESU_SINGLETON;

#[derive(PartialEq, Drop, Serde, Debug, Clone)]
pub struct VesuV1Config {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_assets: Span<ContractAddress>,
}

pub fn _add_vesu_v1_leafs(
    ref leafs: Array<ManageLeaf>,
    ref leaf_index: u256,
    vault_allocator: ContractAddress,
    decoder_and_sanitizer: ContractAddress,
    vesu_v1_configs: Span<VesuV1Config>,
) {
    for i in 0..vesu_v1_configs.len() {
        let vesu_v1_config_elem = vesu_v1_configs.at(i);
        let pool_id = *vesu_v1_config_elem.pool_id;
        let collateral_asset = *vesu_v1_config_elem.collateral_asset;
        let debt_assets = *vesu_v1_config_elem.debt_assets;
        let mut pool_id_str: ByteArray = FormatAsByteArray::format_as_byte_array(@pool_id, 16);

        // APPROVAL of collateral asset to the singleton
        leafs
            .append(
                ManageLeaf {
                    decoder_and_sanitizer,
                    target: collateral_asset,
                    selector: selector!("approve"),
                    argument_addresses: array![VESU_SINGLETON().into()].span(),
                    description: "Approve"
                        + " "
                        + "singleton"
                        + "_"
                        + pool_id_str.clone()
                        + " "
                        + "to spend"
                        + " "
                        + get_symbol(collateral_asset),
                },
            );
        leaf_index += 1;

        for j in 0..debt_assets.len() {
            let debt_asset_elem = *debt_assets.at(j);

            // MODIFY POSITION
            let mut argument_addresses_modify_position = ArrayTrait::new();

            // pool_id
            pool_id.serialize(ref argument_addresses_modify_position);

            // collateral_asset
            collateral_asset.serialize(ref argument_addresses_modify_position);

            // debt_asset
            debt_asset_elem.serialize(ref argument_addresses_modify_position);

            // user
            vault_allocator.serialize(ref argument_addresses_modify_position);

            leafs
                .append(
                    ManageLeaf {
                        decoder_and_sanitizer,
                        target: VESU_SINGLETON(),
                        selector: selector!("modify_position"),
                        argument_addresses: argument_addresses_modify_position.span(),
                        description: "Modify position"
                            + " "
                            + "extension_pid"
                            + "_"
                            + pool_id_str.clone()
                            + " "
                            + "with collateral"
                            + " "
                            + get_symbol(collateral_asset)
                            + " "
                            + "and debt"
                            + " "
                            + get_symbol(debt_asset_elem),
                    },
                );
            leaf_index += 1;
        }
    }
}
