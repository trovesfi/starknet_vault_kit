use openzeppelin::interfaces::erc4626::{ERC4626ABIDispatcher, ERC4626ABIDispatcherTrait};
use starknet::ContractAddress;
use vault_allocator::merkle_tree::base::{ManageLeaf, get_symbol};


pub fn _add_starknet_vault_kit_strategies(
    ref leafs: Array<ManageLeaf>,
    ref leaf_index: u256,
    vault_allocator: ContractAddress,
    decoder_and_sanitizer: ContractAddress,
    starknet_vault_kit_strategy: ContractAddress,
) {
    let starknet_vault_kit_strategy_erc4646_disp = ERC4626ABIDispatcher {
        contract_address: starknet_vault_kit_strategy,
    };
    let asset = starknet_vault_kit_strategy_erc4646_disp.asset();

    // Approvals
    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: asset,
                selector: selector!("approve"),
                argument_addresses: array![starknet_vault_kit_strategy.into()].span(),
                description: "Approve"
                    + " "
                    + get_symbol(starknet_vault_kit_strategy)
                    + " "
                    + "to spend"
                    + " "
                    + get_symbol(asset),
            },
        );
    leaf_index += 1;

    // Deposits

    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: starknet_vault_kit_strategy,
                selector: selector!("deposit"),
                argument_addresses: array![vault_allocator.into()].span(),
                description: "Deposit"
                    + " "
                    + get_symbol(asset)
                    + " "
                    + "for"
                    + " "
                    + get_symbol(starknet_vault_kit_strategy),
            },
        );
    leaf_index += 1;

    // Minting

    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: starknet_vault_kit_strategy,
                selector: selector!("mint"),
                argument_addresses: array![vault_allocator.into()].span(),
                description: "Mint"
                    + " "
                    + get_symbol(starknet_vault_kit_strategy)
                    + " "
                    + "from"
                    + " "
                    + get_symbol(starknet_vault_kit_strategy),
            },
        );
    leaf_index += 1;

    // Request Redeen
    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: starknet_vault_kit_strategy,
                selector: selector!("request_redeem"),
                argument_addresses: array![vault_allocator.into(), vault_allocator.into()].span(),
                description: "Request Redeem" + " " + get_symbol(starknet_vault_kit_strategy),
            },
        );
    leaf_index += 1;

    // Claim Redeem
    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: starknet_vault_kit_strategy,
                selector: selector!("claim_redeem"),
                argument_addresses: array![].span(),
                description: "Claim Redeem" + " " + get_symbol(starknet_vault_kit_strategy),
            },
        );
    leaf_index += 1;
}
