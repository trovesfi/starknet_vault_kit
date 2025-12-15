# Redemption Router Integration Guidelines

## Subscribe Flow

When a user wants to redeem vault shares and receive assets in a different token via the Redemption Router:

1. **Request Redemption**: Call `vault.request_redeem(shares, receiver, owner)` to receive a RedeemRequest NFT
2. **Approve & Subscribe**: In the same multicall transaction:
   - Approve the RedeemRequest NFT to the RedemptionRouter contract
   - Call `redemptionRouter.subscribe(nft_id, receiver)` to transfer the redemption NFT to the router
3. **Receive New NFT**: The router transfers the user's RedeemRequest NFT to itself and mints a new RedemptionRouter NFT to the user
4. **Claim Assets**: Once the relayer has swapped assets and settled claims, the user calls `redemptionRouter.claim(new_nft_id)` which burns the NFT and transfers the swapped `to_asset` tokens to the user

**Note**: The subscribe operation should be done atomically with the approval in a multicall to ensure the NFT is immediately subscribed after redemption request, preventing any intermediate state where the NFT could be lost or mishandled.




