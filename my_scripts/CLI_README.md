# Vault Strategy CLI

A command-line interface for managing vault strategies and viewing statistics.

## Installation

```bash
pnpm install
```

## Usage

### View Strategy Statistics

```bash
# View stats for all strategies
pnpm run log-stats
# or
node cli.ts log-stats
```

This will display a table with:
- Strategy Name
- Previous AUM (Assets Under Management)
- Net APY percentage
- Max APY percentage (calculated from max delta and report delay)
- Report Delay (in seconds)
- Max Delta percentage
- Performance Fee percentage

### Set Max Delta

```bash
# Set max delta for specific strategies
pnpm run set-max-delta "xSTRK,xtBTC" 200 6
# or
node cli.ts set-max-delta "xSTRK,xtBTC" 200 6

# Dry run mode (shows what would be executed without actually executing)
node cli.ts set-max-delta "xSTRK" 150 12 --dry-run
```

Parameters:
- `strategies`: Comma-separated list of strategy names (partial matching supported)
- `apy`: Annual APY percentage (e.g., 200 for 200%)
- `hours`: Delay in hours (e.g., 6 for 6 hours)
- `--dry-run`: Optional flag to preview the transaction without executing

### Available Strategies

- Hyper xSTRK
- Hyper xWBTC
- Hyper xtBTC
- Hyper xsBTC
- Hyper xLBTC

## Environment Variables

Make sure you have the following environment variables set in your `.env` file:

```
RPC_URL=your_starknet_rpc_url
ACCOUNT_SECURE_PASSWORD=your_account_password
ACCOUNT_FILE=accounts.json
```

## Examples

```bash
# View all strategy statistics
pnpm run log-stats

# Set max delta for xSTRK strategy with 200% APY and 6-hour delay
pnpm run set-max-delta "xSTRK" 200 6

# Set max delta for multiple strategies
pnpm run set-max-delta "xSTRK,xtBTC,xWBTC" 150 12

# Preview what would be executed (dry run)
pnpm run set-max-delta "xSTRK" 100 24 --dry-run
```

## Max Delta Calculation

The max delta is calculated using the formula:
```
max_delta_percentage = (annual_apy * delay_seconds) / (365 * 24 * 60 * 60)
```

This ensures that the vault can handle the expected return over the report delay period with some buffer.
