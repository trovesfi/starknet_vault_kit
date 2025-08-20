# Relayer Service

Cron job scheduler and worker service for automated vault operations.

## Features

- Scheduled job execution
- Database operations
- Cross-chain bridging (planned)
- Vault management automation

## Development

```bash
# Run in development mode
pnpm dev:relayer

# Build
pnpm build:relayer

# Start production
pnpm --filter relayer start
```

## Jobs

- Example Job: Runs every 5 minutes for demonstration
- Add your custom jobs in `src/jobs/`