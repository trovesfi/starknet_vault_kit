// SPDX-License-Identifier: BUSL-1.1
// Licensed under the Business Source License 1.1
// See LICENSE file for details

use starknet::ContractAddress;

/// @title IRedeemRequest Interface
/// @notice Interface for the Redeem Request contract that handles minting and burning of redemption
/// tokens
#[starknet::interface]
pub trait IRedeemRequest<TStorage> {
    // ─────────────────────────────────────────────────────────────────────
    // View functions
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Returns the vault address
    /// @return Address of the vault contract
    fn vault(self: @TStorage) -> ContractAddress;

    /// @notice Get the redemption information associated with an ID
    /// @param id The token ID to query
    /// @return Redemption request information (epoch and shares)
    fn id_to_info(self: @TStorage, id: u256) -> RedeemRequestInfo;

    /// @notice Get the total number of redemption requests created
    /// @return Current count of redemption request IDs
    fn id_len(self: @TStorage) -> u256;

    // ─────────────────────────────────────────────────────────────────────
    // External functions
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Mints a new redemption request token
    /// @param to The address to mint the token to
    /// @param redeem_request_info Information about the redemption request
    /// @return The ID of the newly minted token
    fn mint(
        ref self: TStorage, to: ContractAddress, redeem_request_info: RedeemRequestInfo,
    ) -> u256;

    /// @notice Burns a redemption request token
    /// @param id The ID of the token to burn
    fn burn(ref self: TStorage, id: u256);
}

/// @notice Struct containing information about a redemption request
/// @param epoch The epoch when the redemption was requested
/// @param shares The number of shares to redeem
#[derive(Debug, PartialEq, Drop, Serde, Copy, starknet::Store)]
pub struct RedeemRequestInfo {
    pub epoch: u256,
    pub nominal: u256,
}

