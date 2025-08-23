# StarkNet Vault Kit Backend - OSS Version

**This is a reference backend (read-only) for the StarkNet Vault Kit.**

It provides minimal functionality to index vault events and expose basic API endpoints. This OSS version does not include premium features like pricing, automated redeems, SLA monitoring, or advanced analytics.

**For production deployments with full features, see our premium services.**

## What's Included

### Applications

- **`api`** - Minimal HTTP API with 4 endpoints
- **`indexer`** - Event indexer for vault reports and redeems

### Libraries

- **`@forge/config`** - Configuration management
- **`@forge/db`** - Prisma database client
- **`@forge/logger`** - Logging utilities

## API Endpoints (4 total)

1. `GET /health` - Health check (`{ status: "ok" }`)
2. `GET /pending-redeems/:address` - Pending redeems for an address (with limit/offset)
3. `GET /reports/last` - Latest report from database
4. `GET /redeems/:id` - Redeem details by ID

## Events Indexed (3 total)

The indexer only tracks these events:

1. **Report** - Vault reports with epoch, supply, and assets
2. **RedeemRequested** - User redeem requests
3. **RedeemClaimed** - Completed redeem claims

## Database Schema (3 models + status)

- `Report`
- `RedeemRequested`
- `RedeemClaimed`
- `IndexerStatus`

## Quick Start with Docker

1. **Clone and setup:**

```bash
cp .env.example .env
# Edit .env with your configuration
```

2. **Run with Docker Compose:**

```bash
docker-compose up -d
```

This starts:

- PostgreSQL database
- Indexer service
- API service on port 3000

3. **Check health:**

```bash
curl http://localhost:3000/health
```

## Manual Setup

### Prerequisites

- Node.js 18+
- pnpm
- PostgreSQL
- Apibara token (for indexing)

### Installation

```bash
# Install dependencies
pnpm install

# Setup database
pnpm prisma:generate
pnpm prisma:migrate:deploy

# Build
pnpm build
```

### Run Services

```bash
# Start API
pnpm start:api

# Start Indexer (separate terminal)
pnpm start:indexer
```

## Configuration

Copy `.env.example` to `.env` and configure:

```bash
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/starknet_vault_kit"
RPC_URL="https://starknet-mainnet.public.blastapi.io"
VAULT_ADDRESS="0x..." # Your vault contract address
START_BLOCK=12993
APIBARA_TOKEN="your_token_here"
```

## License

This project is licensed for reference use only. For production deployments with full features and support, please contact us.

---

_Built for the StarkNet ecosystem 🚀_
