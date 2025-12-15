// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Starknet Vault Kit
// Licensed under the MIT License. See LICENSE file for details.

// Helps users redeem their NFTs in a different asset than the one configured in the vault
#[starknet::contract]
pub mod RedemptionRouter {
    // Role constants
    pub const OWNER_ROLE: felt252 = selector!("OWNER_ROLE");
    pub const PAUSER_ROLE: felt252 = selector!("PAUSER_ROLE");
    pub const RELAYER_ROLE: felt252 = selector!("RELAYER_ROLE");
    
    // Mathematical constants
    pub const WAD: u256 = 1_000_000_000_000_000_000; // 1e18
    
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use openzeppelin::interfaces::erc721::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
    use openzeppelin::interfaces::upgrades::IUpgradeable;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use openzeppelin::utils::math;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use vault::redemption_router::errors::Errors;
    use vault::redemption_router::interface::{IRedemptionRouter, RequestInfo};
    use vault::redeem_request::interface::{IRedeemRequestDispatcher, IRedeemRequestDispatcherTrait};
    use vault::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
    use vault_allocator::decoders_and_sanitizers::decoder_custom_types::Route;
    use vault_allocator::integration_interfaces::avnu::IAvnuExchangeDispatcher;
    use vault_allocator::integration_interfaces::avnu::IAvnuExchangeDispatcherTrait;

    // --- OpenZeppelin Component Integrations ---
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,

        // constants for the redemption router
        vault: ContractAddress,
        redeem_request: ContractAddress,
        to_asset: ContractAddress,
        avnu_exchange: ContractAddress,

        // modifiable parameters
        integrator_fee_recipient: ContractAddress,
        integrator_fee_amount_bps: u128,

        // state variables
        swap_id: u256,
        unsettled_swap_id: u256,
        nft_id_counter: u256, // Counter for new NFT IDs
        new_nft_request_map: Map<u256, RequestInfo>,
        swap_info: Map<u256, (u256, u256)>, // swap_id -> (from_remaining, to_remaining)
        
        // Epoch offset tracking
        epoch_offset_factor: Map<u256, u256>, // epoch -> offset_factor (defaults to WAD)
        epoch_redeem_assets: Map<u256, u256>, // epoch -> snapshot of redeem_assets at subscribe time
        epoch_redeem_nominal: Map<u256, u256>, // epoch -> snapshot of redeem_nominal at subscribe time
        epoch_wise_nominals: Map<u256, u256>, // epoch -> from_amount (nominal amount subscribed for this epoch)
        epoch_settled_amounts: Map<u256, u256>, // epoch -> actual settled from_amount received
        last_settled_epoch: u256, // Highest epoch number that has been fully settled (may not be sequential if some epochs have no subscriptions)
        old_nft_fulfilled: Map<u256, bool>, // old_nft_id -> whether the old NFT has been fulfilled (burned)

        min_subscribe_amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        Subscribed: Subscribed,
        Swapped: Swapped,
        Claimed: Claimed,
        RequestInfo: RequestInfo,
        Unsubscribed: Unsubscribed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Subscribed {
        pub new_nft_id: u256,
        pub old_nft_id: u256,
        pub receiver: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Unsubscribed {
        pub new_nft_id: u256,
        pub old_nft_id: u256,
        pub owner: ContractAddress,
        pub is_old_nft_returned: bool, // true if old NFT returned as is
        pub is_original_assets_returned: bool, // true if original assets returned proportional to user's share
        pub original_assets_returned: u256, // original assets returned proportional to user's share
    }

    #[derive(Drop, starknet::Event)]
    pub struct Swapped {
        pub swap_id: u256,
        pub from_amount: u256,
        pub to_amount: u256,
        pub last_settled_epoch: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Claimed {
        pub new_nft_id: u256,
        pub old_nft_id: u256,
        pub receivable: u256,
        pub swap_id: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        vault: ContractAddress,
        redeem_request: ContractAddress,
        to_asset: ContractAddress,
        avnu_exchange: ContractAddress,
        integrator_fee_recipient: ContractAddress,
        integrator_fee_amount_bps: u128,
        min_subscribe_amount: u256,
    ) {
        // Non-zero checks
        if (vault.is_zero()) {
            Errors::zero_address();
        }
        if (redeem_request.is_zero()) {
            Errors::zero_address();
        }
        if (to_asset.is_zero()) {
            Errors::zero_address();
        }
        if (avnu_exchange.is_zero()) {
            Errors::zero_address();
        }
        if (integrator_fee_recipient.is_zero()) {
            Errors::zero_address();
        }

        // Initialize components
        self.erc721.initializer("RedemptionRouter", "RR", "none");
        self.access_control.initializer();
        
        // Set up role hierarchy - OWNER_ROLE is admin for all roles
        self.access_control.set_role_admin(OWNER_ROLE, OWNER_ROLE);
        self.access_control.set_role_admin(PAUSER_ROLE, OWNER_ROLE);
        self.access_control.set_role_admin(RELAYER_ROLE, OWNER_ROLE);
        // Initialize NFT counter
        self.nft_id_counter.write(0);
        // Grant owner role to owner
        self.access_control._grant_role(OWNER_ROLE, owner);
        // Store addresses
        self.vault.write(vault);
        self.redeem_request.write(redeem_request);
        self.to_asset.write(to_asset);
        self.avnu_exchange.write(avnu_exchange);
        self.integrator_fee_recipient.write(integrator_fee_recipient);
        self.integrator_fee_amount_bps.write(integrator_fee_amount_bps);
        // Initialize swap counters (starting from 1)
        self.swap_id.write(1);
        self.unsettled_swap_id.write(1);
        // Read the latest handled epoch from the vault
        let vault_dispatcher = IVaultDispatcher { contract_address: self.vault.read() };
        let latest_handled_epoch = vault_dispatcher.handled_epoch_len();
        if (latest_handled_epoch > 0) {
            self.last_settled_epoch.write(latest_handled_epoch - 1);
        }
        self.min_subscribe_amount.write(min_subscribe_amount);
    }

    // Internal implementation for helper functions
    #[generate_trait]
    impl RedemptionRouterInternalImpl of RedemptionRouterInternalTrait {
        fn _transfer_original_nft(self: @ContractState, nft_id: u256, from_address: ContractAddress, to_address: ContractAddress) {
            let redeem_request_dispatcher = ERC721ABIDispatcher {
                contract_address: self.redeem_request.read(),
            };
            redeem_request_dispatcher.transfer_from(from_address, to_address, nft_id);
        }

        // Get effective offset factor for an epoch (defaults to WAD if 0)
        fn _get_effective_offset_factor(self: @ContractState, epoch: u256) -> u256 {
            let offset_factor = self.epoch_offset_factor.read(epoch);
            if (offset_factor == 0) { WAD } else { offset_factor }
        }

        // Calculate expected settled amount for an epoch
        fn _calculate_expected_settled(self: @ContractState, epoch: u256) -> u256 {
            let epoch_nominal = self.epoch_redeem_nominal.read(epoch);
            if (epoch_nominal == 0) {
                return 0;
            }
            let effective_offset = self._get_effective_offset_factor(epoch);
            math::u256_mul_div(
                epoch_nominal,
                effective_offset,
                WAD,
                math::Rounding::Floor
            )
        }

        // Check if an epoch is fully settled
        fn _is_epoch_settled(self: @ContractState, epoch: u256) -> bool {
            let expected_settled = self._calculate_expected_settled(epoch);
            if (expected_settled == 0) {
                return false;
            }
            let settled_amount = self.epoch_settled_amounts.read(epoch);
            settled_amount >= expected_settled
        }

        // Calculate adjusted due amount with epoch offset factor
        fn _calculate_adjusted_due_amount(self: @ContractState, stored_due_amount: u256, epoch: u256) -> u256 {
            let effective_offset = self._get_effective_offset_factor(epoch);
            math::u256_mul_div(
                stored_due_amount,
                effective_offset,
                WAD,
                math::Rounding::Floor
            )
        }

        // Validate request info (not claimed, not unsubscribed, valid)
        fn _validate_request_info(self: @ContractState, request_info: RequestInfo) {
            if (request_info.is_claimed) {
                Errors::nft_already_claimed();
            }
            if (request_info.unsubscribed) {
                Errors::nft_already_withdrawn();
            }
            if (request_info.due_amount_approximate == 0) {
                Errors::invalid_nft_id();
            }
        }

        // Validate epoch exists
        fn _validate_epoch(self: @ContractState, epoch: u256) {
            let epoch_nominal = self.epoch_redeem_nominal.read(epoch);
            if (epoch_nominal == 0) {
                Errors::invalid_nft_id();
            }
        }

        fn _update_request_info(ref self: ContractState, nft_id: u256, request_info: RequestInfo) {
            self.new_nft_request_map.write(nft_id, request_info);
            self.emit(request_info);
        }

        // Snapshot epoch data if not already stored
        fn _snapshot_epoch_data(ref self: ContractState, epoch: u256, vault_dispatcher: IVaultDispatcher) {
            let redeem_assets = vault_dispatcher.redeem_assets(epoch);
            let redeem_nominal = vault_dispatcher.redeem_nominal(epoch);
            
            self.epoch_redeem_assets.write(epoch, redeem_assets);
            self.epoch_redeem_nominal.write(epoch, redeem_nominal);
            
            // Initialize epoch_offset_factor to WAD if not set
            if (self.epoch_offset_factor.read(epoch) == 0) {
                self.epoch_offset_factor.write(epoch, WAD);
            }
        }

        // Process swap pool iteration to calculate receivable (read-only)
        fn _calculate_receivable_from_pools(
            self: @ContractState,
            mut remaining_due: u256
        ) -> u256 {
            let mut pool_id = self.unsettled_swap_id.read();
            let end_pool = self.swap_id.read();
            let mut total_to: u256 = 0;

            while (remaining_due > 0 && pool_id < end_pool) {
                let (from_remaining, to_remaining) = self.swap_info.read(pool_id);

                if (from_remaining == 0) {
                    pool_id = pool_id + 1;
                    continue;
                }

                let take_from = if (remaining_due > from_remaining) { from_remaining } else { remaining_due };
                let take_to = math::u256_mul_div(take_from, to_remaining, from_remaining, math::Rounding::Floor);

                remaining_due = remaining_due - take_from;
                total_to = total_to + take_to;
                pool_id = pool_id + 1;
            }

            total_to
        }

        // Process swap pool iteration and update state (write)
        fn _process_swap_pools_for_claim(
            ref self: ContractState,
            mut remaining_due: u256
        ) -> u256 {
            let mut pool_id = self.unsettled_swap_id.read();
            let end_pool = self.swap_id.read();
            let mut total_to: u256 = 0;

            while (remaining_due > 0 && pool_id < end_pool) {
                let (from_remaining, to_remaining) = self.swap_info.read(pool_id);

                if (from_remaining == 0) {
                    if (self.unsettled_swap_id.read() == pool_id) {
                        self.unsettled_swap_id.write(pool_id + 1);
                    }
                    pool_id = pool_id + 1;
                    continue;
                }

                let take_from = if (remaining_due > from_remaining) { from_remaining } else { remaining_due };
                let take_to = math::u256_mul_div(take_from, to_remaining, from_remaining, math::Rounding::Floor);

                let new_from = from_remaining - take_from;
                let new_to = to_remaining - take_to;
                self.swap_info.write(pool_id, (new_from, new_to));

                if (new_from == 0 && self.unsettled_swap_id.read() == pool_id) {
                    self.unsettled_swap_id.write(pool_id + 1);
                }

                remaining_due = remaining_due - take_from;
                total_to = total_to + take_to;
                pool_id = pool_id + 1;
            }

            total_to
        }

        // todo what if a subscription comes in after an epoch was handled but redeem not claimed?

        // Settle epochs and/or sync settled epochs state
        // - If remaining_from > 0: settles epochs by allocating remaining_from to them
        // - After settling (or if remaining_from == 0): syncs by checking which epochs are fully settled
        // - max_epochs_to_check limits how many epochs to check during sync (0 means check all)
        // Epochs are processed in order (1, 2, 3...), but only epochs with subscriptions matter
        // Subscriptions can come in any order, so we skip epochs without subscriptions
        fn _settle_and_sync_epochs(
            ref self: ContractState,
            mut remaining_from: u256,
            max_epochs_to_check: u256
        ) -> u256 {
            // Get the vault's current epoch to know the upper bound
            let vault_dispatcher = IVaultDispatcher { contract_address: self.vault.read() };
            let max_epoch = vault_dispatcher.handled_epoch_len() - 1; // -1 because we are using 0-indexed epochs
            
            // Start from last_settled_epoch + 1 to avoid re-checking already settled epochs
            let last_settled_epoch = self.last_settled_epoch.read();
            let mut current_epoch = last_settled_epoch + 1;
            let mut highest_settled_epoch: u256 = last_settled_epoch;
            let mut epochs_checked: u256 = 0;
            
            // If max_epochs_to_check is 0, check all epochs (no limit)
            let check_all = max_epochs_to_check == 0;
            
            // Phase 1: Settle epochs with remaining_from (if any)
            while (remaining_from > 0 && current_epoch <= max_epoch) {
                let epoch_nominal = self.epoch_redeem_nominal.read(current_epoch);

                epochs_checked = epochs_checked + 1;
                // designed to prevent excessive gas usage
                if (!check_all && epochs_checked > max_epochs_to_check) {
                    break;
                }

                // Skip epochs without subscriptions
                if (epoch_nominal == 0) {
                    // since this function is intended to be called by the swap function,
                    // the assumption is there is atleast one epoch with subscriptions
                    // that is waiting to be settled
                    // - so we can continue to the next epoch, at some point we should 
                    // update the last_settled_epoch
                    current_epoch = current_epoch + 1;
                    continue;
                }
                
                let effective_offset = self._get_effective_offset_factor(current_epoch);
                let expected_settled = math::u256_mul_div(
                    epoch_nominal,
                    effective_offset,
                    WAD,
                    math::Rounding::Floor
                );
                
                let already_settled = self.epoch_settled_amounts.read(current_epoch);
                let remaining_to_settle = expected_settled - already_settled;
                
                // Skip if epoch is already fully settled
                if (remaining_to_settle == 0) {
                    if (current_epoch > highest_settled_epoch) {
                        highest_settled_epoch = current_epoch;
                    }
                    current_epoch = current_epoch + 1;
                    continue;
                }
                
                let settle_amount = if (remaining_from >= remaining_to_settle) {
                    remaining_to_settle
                } else {
                    remaining_from
                };
                
                let new_settled = already_settled + settle_amount;
                self.epoch_settled_amounts.write(current_epoch, new_settled);
                remaining_from = remaining_from - settle_amount;
                
                // If epoch is now fully settled, update highest_settled_epoch
                if (new_settled >= expected_settled) {
                    if (current_epoch > highest_settled_epoch) {
                        highest_settled_epoch = current_epoch;
                    }
                    current_epoch = current_epoch + 1;
                } else {
                    // Epoch partially settled, stop here (don't move to next epoch)
                    break;
                }
            }
            
            // ideally, only sync until the last settled epoch
            let mut last_settled_epoch = highest_settled_epoch;

            // but if called wanted to do check limited blocks, update till then
            if (!check_all && current_epoch > highest_settled_epoch) {
                last_settled_epoch = current_epoch - 1;
            }
            self.last_settled_epoch.write(last_settled_epoch);

            last_settled_epoch // return the last settled epoch
        }

        // Execute swap via Avnu exchange
        fn _execute_avnu_swap(
            ref self: ContractState,
            routes: Array<Route>,
            from_amount: u256,
            min_amount_out: u256,
        ) -> u256 {
            let from_asset_address = self._get_from_asset_address();
            let to_asset_address = self.to_asset.read();
            let avnu_exchange_address = self.avnu_exchange.read();
            let this = get_contract_address();

            // Check balance
            let erc20_dispatcher = ERC20ABIDispatcher { contract_address: from_asset_address };
            let balance = erc20_dispatcher.balance_of(this);
            if (from_amount > balance) {
                Errors::insufficient_from_amount();
            }

            // Get balance before swap
            let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: to_asset_address };
            let balance_before = to_asset_dispatcher.balance_of(this);

            // Approve Avnu exchange
            erc20_dispatcher.approve(avnu_exchange_address, from_amount);

            // Execute swap
            let avnu_dispatcher = IAvnuExchangeDispatcher { contract_address: avnu_exchange_address };
            let swapped = avnu_dispatcher.multi_route_swap(
                from_asset_address,
                from_amount,
                to_asset_address,
                0,
                min_amount_out,
                this,
                self.integrator_fee_amount_bps.read(),
                self.integrator_fee_recipient.read(),
                routes,
            );

            if (!swapped) {
                Errors::swap_failed();
            }

            // Get actual amount received
            let balance_after = to_asset_dispatcher.balance_of(this);
            balance_after - balance_before
        }

        // Get from asset address from vault
        fn _get_from_asset_address(self: @ContractState) -> ContractAddress {
            let vault_dispatcher = IERC4626Dispatcher { contract_address: self.vault.read() };
            vault_dispatcher.asset()
        }

        // Handle unsubscribe when original NFT not fulfilled
        fn _handle_unsubscribe_original_nft(
            ref self: ContractState,
            nft_id: u256,
            request_info: RequestInfo,
            receiver: ContractAddress,
        ) {
            let epoch = request_info.epoch;
            if (self._is_epoch_settled(epoch)) {
                Errors::cannot_unsubscribe_partial_swap();
            }
            
            self._transfer_original_nft(nft_id: request_info.old_nft_id, from_address: get_contract_address(), to_address: receiver);
            
            let mut updated = request_info;
            updated.unsubscribed = true;
            self._update_request_info(nft_id, updated);
            self.erc721.burn(nft_id);

            self.emit(Unsubscribed { new_nft_id: nft_id, old_nft_id: request_info.old_nft_id, owner: receiver, is_old_nft_returned: true, is_original_assets_returned: false, original_assets_returned: 0 });
        }

        // Handle unsubscribe when original NFT fulfilled
        fn _handle_unsubscribe_fulfilled_nft(
            ref self: ContractState,
            nft_id: u256,
            request_info: RequestInfo,
            receiver: ContractAddress,
        ) {
            let epoch = request_info.epoch;
            if (self._is_epoch_settled(epoch)) {
                Errors::cannot_unsubscribe_partial_swap();
            }
            
            let settled_amount = self.epoch_settled_amounts.read(epoch);
            let expected_settled = self._calculate_expected_settled(epoch);
            
            if (settled_amount > 0 && settled_amount < expected_settled) {
                Errors::cannot_unsubscribe_partial_swap();
            }
            
            // Compute assets based on current offset factor
            // due_amount_approximate is the asset amount, adjust it by offset factor
            let user_expected_amount = self._calculate_adjusted_due_amount(request_info.due_amount_approximate, epoch);
            
            let from_asset_address = self._get_from_asset_address();
            let erc20_dispatcher = ERC20ABIDispatcher { contract_address: from_asset_address };
            let this = get_contract_address();
            let contract_balance = erc20_dispatcher.balance_of(this);
            
            if (user_expected_amount > contract_balance) {
                Errors::insufficient_balance_for_withdrawal();
            }
            
            erc20_dispatcher.transfer(receiver, user_expected_amount);
            
            let mut updated = request_info;
            updated.unsubscribed = true;
            self._update_request_info(nft_id, updated);
            self.erc721.burn(nft_id);

            self.emit(Unsubscribed { new_nft_id: nft_id, old_nft_id: request_info.old_nft_id, owner: receiver, is_old_nft_returned: false, is_original_assets_returned: true, original_assets_returned: user_expected_amount });
        }

        // Validate common prerequisites for unsubscribe operations
        fn _validate_unsubscribe_prerequisites(
            self: @ContractState,
            nft_id: u256,
        ) -> RequestInfo {
            let request_info = self.new_nft_request_map.read(nft_id);
            
            // Validate request info
            self._validate_request_info(request_info);
            
            // Validate epoch exists
            let epoch = request_info.epoch;
            self._validate_epoch(epoch);

            // Validate owner is the owner of the NFT 
            let owner = self.erc721.owner_of(nft_id);
            if (owner != get_caller_address()) {
                Errors::not_owner();
            }
            
            request_info
        }

        // Assert that epoch is not settled (fully or partially) in swap
        fn _assert_epoch_not_settled(self: @ContractState, epoch: u256) {
            if (self._is_epoch_settled(epoch)) {
                Errors::cannot_unsubscribe_partial_swap();
            }
            
            let settled_amount = self.epoch_settled_amounts.read(epoch);
            let expected_settled = self._calculate_expected_settled(epoch);
            
            if (settled_amount > 0 && settled_amount < expected_settled) {
                Errors::cannot_unsubscribe_partial_swap();
            }
        }

        // Finalize unsubscribe: mark as unsubscribed, burn NFT, and emit event
        fn _finalize_unsubscribe(
            ref self: ContractState,
            nft_id: u256,
            request_info: RequestInfo,
            receiver: ContractAddress,
            is_old_nft_returned: bool,
            original_assets_returned: u256,
        ) {
            let mut updated = request_info;
            updated.unsubscribed = true;
            self._update_request_info(nft_id, updated);
            self.erc721.burn(nft_id);

            self.emit(Unsubscribed { 
                new_nft_id: nft_id, 
                old_nft_id: request_info.old_nft_id, 
                owner: receiver, 
                is_old_nft_returned, 
                is_original_assets_returned: !is_old_nft_returned, 
                original_assets_returned 
            });
        }
    }

    #[abi(embed_v0)]
    impl RedemptionRouterImpl of IRedemptionRouter<ContractState> {
        fn subscribe(ref self: ContractState, nft_id: u256, receiver: ContractAddress) -> u256 {
            self.pausable.assert_not_paused();
            
            let caller = get_caller_address();
            
            // Read epoch and due_amount from old NFT before transferring
            let redeem_request_interface = IRedeemRequestDispatcher {
                contract_address: self.redeem_request.read(),
            };
            let redeem_request_info = redeem_request_interface.id_to_info(nft_id);
            let epoch = redeem_request_info.epoch;
            
            // Get due_amount from vault (before NFT is transferred/burned)
            let vault_dispatcher = IVaultDispatcher { contract_address: self.vault.read() };
            let due_amount = vault_dispatcher.due_assets_from_id(nft_id);
            if (due_amount == 0) {
                // nothing to settle for any NFT with due_amount == 0
                Errors::invalid_nft_id();
            }

            // avoid processing very small subscriptions to save gas
            if (due_amount < self.min_subscribe_amount.read()) {
                Errors::too_small_subscribe_amount();
            }

            // Snapshot epoch data (required for fairly distributing redeemed assets to subscribers)
            self._snapshot_epoch_data(epoch, vault_dispatcher);
            
            // Transfer original NFT from caller to this contract
            self._transfer_original_nft(nft_id: nft_id, from_address: caller, to_address: get_contract_address());
            // Mark old NFT as not fulfilled yet (router owns it now)
            self.old_nft_fulfilled.write(nft_id, false);

            // Mint new NFT to receiver
            let new_nft_id = self.nft_id_counter.read();
            self.erc721.mint(receiver, new_nft_id);
            self.nft_id_counter.write(new_nft_id + 1);

            // Store mapping with epoch and due_amount_approximate
            let request_info = RequestInfo {
                old_nft_id: nft_id,
                is_claimed: false,
                epoch,
                due_amount_approximate: due_amount,
                unsubscribed: false,
            };
            self._update_request_info(new_nft_id, request_info);
            
            // Update epoch_wise_nominals (accumulate nominal for this epoch)
            // Use to compute how much of the epoch is settled
            let current_epoch_amount = self.epoch_wise_nominals.read(epoch);
            self.epoch_wise_nominals.write(epoch, current_epoch_amount + redeem_request_info.nominal);

            // Emit event
            self.emit(Subscribed { new_nft_id, old_nft_id: nft_id, receiver });

            new_nft_id
        }

        fn swap(
            ref self: ContractState,
            routes: Array<Route>,
            from_amount: u256,
            min_amount_out: u256,
        ) -> u256 {
            self.pausable.assert_not_paused();
            self.access_control.assert_only_role(RELAYER_ROLE);

            if (from_amount == 0) {
                Errors::invalid_swap_from_amount();
            }

            // Execute swap via Avnu exchange
            let to_amount = self._execute_avnu_swap(routes, from_amount, min_amount_out);

            // Settle epochs based on from_amount received
            let last_settled_epoch = self._settle_and_sync_epochs(from_amount, 0);

            // Store swap info
            let current_swap_id = self.swap_id.read();
            self.swap_info.write(current_swap_id, (from_amount, to_amount));
            self.swap_id.write(current_swap_id + 1);

            // Emit event
            self.emit(Swapped { swap_id: current_swap_id, from_amount, to_amount, last_settled_epoch });

            current_swap_id
        }

        fn claim(ref self: ContractState, nft_id: u256) -> u256 {
            self.pausable.assert_not_paused();

            let owner = self.erc721.owner_of(nft_id);
            let request_info = self.new_nft_request_map.read(nft_id);
            
            // Validate request info
            self._validate_request_info(request_info);
            
            // Validate epoch exists
            let epoch = request_info.epoch;
            self._validate_epoch(epoch);
            
            // Check if epoch has been settled
            if (!self._is_epoch_settled(epoch)) {
                Errors::claim_not_allowed();
            }
            
            // Calculate adjusted due amount with epoch offset factor
            let remaining_due = self._calculate_adjusted_due_amount(request_info.due_amount_approximate, epoch);

            // Process swap pools and calculate receivable
            let total_to = self._process_swap_pools_for_claim(remaining_due);

            // Burn NFT and mark claimed
            self.erc721.burn(nft_id);
            let mut updated = request_info;
            updated.is_claimed = true;
            self._update_request_info(nft_id, updated);

            // Transfer payout
            let to_asset_dispatcher = ERC20ABIDispatcher { contract_address: self.to_asset.read() };
            let this = get_contract_address();
            let router_balance = to_asset_dispatcher.balance_of(this);
            if (total_to > router_balance) {
                Errors::insufficient_balance_for_withdrawal();
            }
            to_asset_dispatcher.transfer(owner, total_to);

            self.emit(Claimed { new_nft_id: nft_id, old_nft_id: request_info.old_nft_id, receivable: total_to, swap_id: self.unsettled_swap_id.read() });

            total_to
        }

      
        fn unsubscribe_for_nft(ref self: ContractState, nft_id: u256, receiver: ContractAddress) {
            self.pausable.assert_not_paused();

            let request_info = self._validate_unsubscribe_prerequisites(nft_id);
            let epoch = request_info.epoch;
            
            // Revert if epoch is fully or partially settled in swap
            self._assert_epoch_not_settled(epoch);
            
            // Transfer original NFT to receiver
            self._transfer_original_nft(nft_id: request_info.old_nft_id, from_address: get_contract_address(), to_address: receiver);
            
            // Finalize unsubscribe
            self._finalize_unsubscribe(nft_id, request_info, receiver, true, 0);
        }

        fn unsubscribe_for_underlying(ref self: ContractState, nft_id: u256, receiver: ContractAddress) {
            self.pausable.assert_not_paused();

            let request_info = self._validate_unsubscribe_prerequisites(nft_id);
            let epoch = request_info.epoch;
            
            // Check if epoch < handled_epoch_len (meaning epoch has been handled by vault)
            let vault_dispatcher = IVaultDispatcher { contract_address: self.vault.read() };
            let handled_epoch_len = vault_dispatcher.handled_epoch_len();
            
            if (epoch >= handled_epoch_len) {
                Errors::invalid_nft_id(); // Epoch not yet handled by vault
            }
            
            // Revert if epoch is fully or partially settled in swap
            self._assert_epoch_not_settled(epoch);
            
            // Compute assets based on current offset factor
            // due_amount_approximate is the asset amount, adjust it by offset factor
            let user_expected_amount = self._calculate_adjusted_due_amount(request_info.due_amount_approximate, epoch);
            
            // Return assets if contract has balance
            let from_asset_address = self._get_from_asset_address();
            let erc20_dispatcher = ERC20ABIDispatcher { contract_address: from_asset_address };
            let this = get_contract_address();
            let contract_balance = erc20_dispatcher.balance_of(this);
            
            if (user_expected_amount > contract_balance) {
                Errors::insufficient_balance_for_withdrawal();
            }
            
            erc20_dispatcher.transfer(receiver, user_expected_amount);
            
            // Finalize unsubscribe
            self._finalize_unsubscribe(nft_id, request_info, receiver, false, user_expected_amount);
        }

        fn set_integrator_fee_recipient(ref self: ContractState, recipient: ContractAddress) {
            self.access_control.assert_only_role(OWNER_ROLE);
            if (recipient.is_zero()) {
                Errors::zero_address();
            }
            self.integrator_fee_recipient.write(recipient);
        }

        fn set_integrator_fee_amount_bps(ref self: ContractState, fee_bps: u128) {
            self.access_control.assert_only_role(OWNER_ROLE);
            self.integrator_fee_amount_bps.write(fee_bps);
        }

        fn set_epoch_offset(ref self: ContractState, epoch: u256, offset_factor: u256) {
            self.access_control.assert_only_role(RELAYER_ROLE);
            self.epoch_offset_factor.write(epoch, offset_factor);
        }

        fn report(ref self: ContractState, new_aum: u256) {
            self.access_control.assert_only_role(RELAYER_ROLE);
            
            let vault_dispatcher = IVaultDispatcher { contract_address: self.vault.read() };
            
            // Read handled_epoch_len before calling report
            let handled_epochs_before = vault_dispatcher.handled_epoch_len();
            
            // Call vault's report function
            vault_dispatcher.report(new_aum);
            
            // Read handled_epoch_len after calling report
            let handled_epochs_after = vault_dispatcher.handled_epoch_len();
            
            // For each newly handled epoch, compute and update offset factor
            let mut epoch = handled_epochs_before + 1;
            while (epoch <= handled_epochs_after) {
                // Read new redeem_assets and redeem_nominal after report
                let new_redeem_assets = vault_dispatcher.redeem_assets(epoch);
                let new_redeem_nominal = vault_dispatcher.redeem_nominal(epoch);
                
                // Read old snapshots
                let old_redeem_assets = self.epoch_redeem_assets.read(epoch);
                let old_redeem_nominal = self.epoch_redeem_nominal.read(epoch);
                
                // Compute new offset factor: WAD * (new_redeem_assets / new_redeem_nominal) / (old_redeem_assets / old_redeem_nominal)
                // This simplifies to: WAD * new_redeem_assets * old_redeem_nominal / (new_redeem_nominal * old_redeem_assets)
                if (old_redeem_assets > 0 && old_redeem_nominal > 0 && new_redeem_nominal > 0) {
                    // Compute numerator: WAD * new_redeem_assets * old_redeem_nominal
                    let numerator = WAD * new_redeem_assets * old_redeem_nominal;
                    // Compute denominator: new_redeem_nominal * old_redeem_assets
                    let denominator = new_redeem_nominal * old_redeem_assets;
                    // Compute: numerator / denominator
                    let new_offset_factor = math::u256_mul_div(
                        numerator,
                        1,
                        denominator,
                        math::Rounding::Floor
                    );
                    self.epoch_offset_factor.write(epoch, new_offset_factor);
                }
                
                epoch = epoch + 1;
            }
        }

        fn set_min_subscribe_amount(ref self: ContractState, min_subscribe_amount: u256) {
            self.access_control.assert_only_role(OWNER_ROLE);
            self.min_subscribe_amount.write(min_subscribe_amount);
        }

        fn pause(ref self: ContractState) {
            self.access_control.assert_only_role(PAUSER_ROLE);
            self.pausable.pause();
        }

        fn unpause(ref self: ContractState) {
            self.access_control.assert_only_role(OWNER_ROLE);
            self.pausable.unpause();
        }

        fn vault(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }

        fn redeem_request(self: @ContractState) -> ContractAddress {
            self.redeem_request.read()
        }

        fn to_asset(self: @ContractState) -> ContractAddress {
            self.to_asset.read()
        }

        fn avnu_exchange(self: @ContractState) -> ContractAddress {
            self.avnu_exchange.read()
        }

        fn integrator_fee_recipient(self: @ContractState) -> ContractAddress {
            self.integrator_fee_recipient.read()
        }

        fn integrator_fee_amount_bps(self: @ContractState) -> u128 {
            self.integrator_fee_amount_bps.read()
        }

        fn swap_id(self: @ContractState) -> u256 {
            self.swap_id.read()
        }

        fn unsettled_swap_id(self: @ContractState) -> u256 {
            self.unsettled_swap_id.read()
        }

        fn new_nft_request_info(self: @ContractState, new_nft_id: u256) -> RequestInfo {
            self.new_nft_request_map.read(new_nft_id)
        }

        fn swap_info(self: @ContractState, swap_id: u256) -> (u256, u256) {
            self.swap_info.read(swap_id)
        }

        fn last_nft_id(self: @ContractState) -> u256 {
            let counter = self.nft_id_counter.read();
            if (counter == 0) {
                0
            } else {
                counter - 1
            }
        }

        fn expected_receivable(self: @ContractState, nft_id: u256) -> u256 {
            let request_info = self.new_nft_request_map.read(nft_id);
            
            // If already claimed or unsubscribed, return 0
            if (request_info.is_claimed || request_info.unsubscribed || request_info.due_amount_approximate == 0) {
                return 0;
            }
            
            // Calculate adjusted due amount with epoch offset factor
            let remaining_due = self._calculate_adjusted_due_amount(request_info.due_amount_approximate, request_info.epoch);

            // Calculate receivable from swap pools (read-only)
            self._calculate_receivable_from_pools(remaining_due)
        }

        fn last_settled_epoch(self: @ContractState) -> u256 {
            self.last_settled_epoch.read()
        }

        fn epoch_settled_amounts(self: @ContractState, epoch: u256) -> u256 {
            self.epoch_settled_amounts.read(epoch)
        }

        // Useful when there are many empty epochs.
        // Allows batching their settlement without running out of gas.
        fn sync_settled_epochs(ref self: ContractState, max_epochs_to_check: u256) {
            self.pausable.assert_not_paused();
            self._settle_and_sync_epochs(remaining_from: 0, max_epochs_to_check: max_epochs_to_check);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: starknet::ClassHash) {
            self.access_control.assert_only_role(OWNER_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}

