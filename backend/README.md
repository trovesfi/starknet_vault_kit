# StarkNet Vault Kit Backend

A monorepo containing the backend services for the StarkNet Vault Kit project.

## Architecture

This project is organized as a monorepo with shared libraries and independent applications:

### Applications (`apps/`)

- **`api`** - NestJS HTTP API service
- **`indexer`** - Apibara event indexer
- **`relayer`** - Cron job worker for automated operations

### Libraries (`libs/`)

- **`@forge/core`** - Core types, DTOs, and constants
- **`@forge/config`** - Configuration management with validation
- **`@forge/db`** - Prisma client and database access layer
- **`@forge/logger`** - Logging utilities

## Getting Started

### Prerequisites

- Node.js 18+
- pnpm (recommended) or yarn/npm with workspaces
- PostgreSQL database
- StarkNet RPC access
- Apibara API token (for indexer)

### Installation

```bash
# Install all dependencies
pnpm install

# Generate Prisma client
pnpm generate

# Run database migrations
pnpm migrate:dev
```

### Development

```bash
# Run all services in development mode
pnpm dev:all

# Run individual services
pnpm dev:api
pnpm dev:indexer
pnpm dev:relayer
```

### Building

```bash
# Build all packages
pnpm build

# Build individual packages
pnpm build:api
pnpm build:indexer
pnpm build:relayer
```

### Database

```bash
# Generate Prisma client
pnpm generate

# Run migrations
pnpm migrate:dev

# Open Prisma Studio
pnpm studio
```

## Environment Variables

Create a `.env` file in the root with:

```bash
DATABASE_URL="postgresql://user:password@localhost:5432/starknet_vault_kit"
STARKNET_RPC_URL="https://starknet-sepolia.public.blastapi.io/rpc/v0_7"
APIBARA_TOKEN="your_apibara_token"
PORT=3000
```

## Project Structure

```
.
├── apps/
│   ├── api/              # NestJS HTTP API
│   ├── indexer/          # Apibara event indexer
│   └── relayer/          # Cron job worker
├── libs/
│   ├── core/             # Shared types and constants
│   ├── config/           # Configuration management
│   ├── db/               # Database client and DAL
│   └── logger/           # Logging utilities
├── prisma/
│   └── schema.prisma     # Database schema
├── package.json          # Root package with workspace scripts
├── pnpm-workspace.yaml   # pnpm workspace configuration
└── tsconfig.base.json    # Base TypeScript configuration
```

## Scripts

- `pnpm dev:all` - Run all services in development
- `pnpm build` - Build all packages
- `pnpm lint` - Lint all packages
- `pnpm test` - Run tests for all packages
- `pnpm migrate:dev` - Run database migrations
- `pnpm generate` - Generate Prisma client
- `pnpm studio` - Open Prisma Studio

## Services

### API Service (`apps/api`)

- RESTful API endpoints
- Swagger documentation at `/api`
- Health checks at `/` and `/health`

### Indexer Service (`apps/indexer`)

- Real-time StarkNet event streaming via Apibara
- Automatic event decoding and database persistence
- Vault-specific event tracking (RedeemRequested, RedeemClaimed, Report)

### Relayer Service (`apps/relayer`)

- Scheduled job execution with cron
- Automated vault operations and maintenance
- Cross-chain bridging (planned)
