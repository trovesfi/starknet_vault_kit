# Indexer Service

Apibara-based event indexer for StarkNet Vault Kit smart contracts.

## Features

- Real-time event streaming from StarkNet
- Event decoding and processing
- Database persistence with batching
- Automatic reconnection and error handling

## Development

```bash
# Run in development mode
pnpm dev:indexer

# Build
pnpm build:indexer

# Start production
pnpm --filter indexer start
```

## Environment Variables

- `APIBARA_TOKEN` - Apibara API token
- `STARKNET_RPC_URL` - StarkNet RPC endpoint
- `DATABASE_URL` - PostgreSQL connection string