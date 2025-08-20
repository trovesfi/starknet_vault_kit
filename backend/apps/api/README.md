# API Service

NestJS-based HTTP API for the StarkNet Vault Kit backend.

## Features

- RESTful API endpoints
- Swagger documentation
- Health checks
- StarkNet integration

## Development

```bash
# Run in development mode
pnpm dev:api

# Build
pnpm build:api

# Start production
pnpm --filter api start
```

## Endpoints

- `GET /` - Basic health check
- `GET /health` - Detailed health status
- `GET /api` - Swagger UI documentation