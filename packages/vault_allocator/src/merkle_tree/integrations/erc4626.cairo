use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
use starknet::ContractAddress;
use vesu_vaults::merkle_tree::base::{ManageLeaf, get_symbol};


pub fn _add_erc4626_leafs(
    ref leafs: Array<ManageLeaf>,
    ref leaf_index: u256,
    vault_allocator: ContractAddress,
    decoder_and_sanitizer: ContractAddress,
    erc4626: ContractAddress,
) {
    let erc4626_erc4646_disp = IERC4626Dispatcher { contract_address: erc4626 };
    let asset = erc4626_erc4646_disp.asset();

    // Approvals
    leafs
        .append(
            ManageLeaf {
                decoder_and_sanitizer,
                target: asset,
                selector: selector!("approve"),
                argument_addresses: array![erc4626.into()].span(),
                description: "Approve"
                    + " "
                    + get_symbol(erc4626)
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
                target: erc4626,
                selector: selector!("deposit"),
                argument_addresses: array![vault_allocator.into()].span(),
                description: "Deposit"
                    + " "
                    + get_symbol(asset)
                    + " "
                    + "for"
                    + " "
                    + get_symbol(erc4626),
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
                argument_addresses: array![vault_allocator.into(), vault_allocator.into()].span(),
                description: "Withdraw"
                    + " "
                    + get_symbol(asset)
                    + " "
                    + "from"
                    + " "
                    + get_symbol(erc4626),
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
                argument_addresses: array![vault_allocator.into()].span(),
                description: "Mint"
                    + " "
                    + get_symbol(erc4626)
                    + " "
                    + "from"
                    + " "
                    + get_symbol(asset),
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
                argument_addresses: array![vault_allocator.into(), vault_allocator.into()].span(),
                description: "Redeem"
                    + " "
                    + get_symbol(erc4626)
                    + " "
                    + "for"
                    + " "
                    + get_symbol(asset),
            },
        );
    leaf_index += 1;
}
