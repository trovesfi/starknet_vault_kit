#!/usr/bin/env node

import dotenv from 'dotenv';
dotenv.config();

import { ContractAddr, Deployer, getMainnetConfig, Global, HyperLSTStrategies, PricerFromApi, UniversalLstMultiplierStrategy, UniversalStrategies, UniversalStrategy, UniversalStrategySettings, Web3Number } from '@strkfarm/sdk';
import { Call, Contract, uint256 } from 'starknet';
import * as CommonSettings from './config.json';

// CLI argument parsing
const args = process.argv.slice(2);
const command = args[0];

const config = getMainnetConfig(process.env.RPC_URL!, 'latest');
const acc = Deployer.getAccount('strkfarmadmin', config, process.env.ACCOUNT_SECURE_PASSWORD!, process.env.ACCOUNT_FILE || 'accounts.json');
const pricer = new PricerFromApi(config, Global.getDefaultTokens());

// Helper function to get strategy by name
function getStrategyByName(name: string): UniversalStrategy<UniversalStrategySettings> | undefined {
    const strategy = HyperLSTStrategies.find(s => s.name.toLowerCase().includes(name.toLowerCase()));
    if (!strategy) {
        console.error(`Strategy with name containing "${name}" not found`);
        return undefined;
    }
    return new UniversalStrategy(config, pricer, strategy);
}

function getAllStrategies(): UniversalStrategy<UniversalStrategySettings>[] {
    const hyper = HyperLSTStrategies.map(s => new UniversalLstMultiplierStrategy(config, pricer, s));
    const universal = UniversalStrategies.map(s => new UniversalStrategy(config, pricer, s));
    return [...hyper, ...universal];
}

// Function to get vault contract instance
async function getVaultContract(vaultAddress: string) {
    const cls = await config.provider.getClassAt(vaultAddress);
    return new Contract({abi: cls.abi, address: vaultAddress, providerOrAccount: config.provider as any});
}

// Function to get max delta percentage from contract value
function getMaxDeltaPercentage(maxDeltaWei: string): number {
    const maxDelta = Number(uint256.uint256ToBN({low: maxDeltaWei, high: '0'}).toString());
    return (maxDelta / 1e18) * 100;
}

// Function to calculate max APY from max delta and report delay
function calculateMaxAPY(maxDeltaPercentage: number, reportDelaySeconds: number): number {
    return (maxDeltaPercentage) * (365 * 24 * 60 * 60) / reportDelaySeconds;
}

// Function to get performance fee percentage
function getPerformanceFeePercentage(performanceFeeWei: string): number {
    const performanceFee = Number(uint256.uint256ToBN({low: performanceFeeWei, high: '0'}).toString());
    return (performanceFee / 1e18) * 100;
}

// Log stats for all strategies
async function logStats() {
    console.log('📊 Collecting Strategy Statistics...\n');
    
    const statsData: any = [];
    const strategies = getAllStrategies();
    for (const strategy of strategies) {
        try {
            const vaultContract = await getVaultContract(strategy.address.toString());
            
            // Get data from contract
            const [reportDelay, maxDelta, performanceFees] = await Promise.all([
                vaultContract.call('report_delay'),
                vaultContract.call('max_delta'),
                vaultContract.call('performance_fees')
            ]);

            // Get strategy-specific data
            const prevAum = await strategy.getPrevAUM();
            const netAPY = await strategy.netAPY();

            // Format data
            const prevAumFormatted = prevAum.toNumber().toFixed(2);
            const netAPYFormatted = (netAPY.net * 100).toFixed(2);
            const reportDelayFormatted = `${Number(reportDelay)}s`;
            const maxDeltaPercentage = getMaxDeltaPercentage(maxDelta as any);
            const maxAPY = calculateMaxAPY(maxDeltaPercentage, Number(reportDelay));
            const performanceFeePercentage = getPerformanceFeePercentage(performanceFees as any);

            statsData.push({
                name: strategy.metadata.name,
                prevAum: prevAumFormatted,
                netAPY: netAPYFormatted,
                maxAPY: maxAPY.toFixed(2),
                reportDelay: reportDelayFormatted,
                maxDelta: maxDeltaPercentage.toFixed(6),
                performanceFee: performanceFeePercentage.toFixed(1)
            });
        } catch (error) {
            console.error(error);
            statsData.push({
                name: strategy.metadata.name,
                prevAum: 'Error',
                netAPY: 'Error',
                maxAPY: 'Error',
                reportDelay: 'Error',
                maxDelta: 'Error',
                performanceFee: 'Error',
                error: error.message
            });
        }
    }

    // Now log all the collected data
    console.log('📊 Strategy Statistics\n');
    console.log('Strategy Name'.padEnd(30) + 'Prev AUM'.padEnd(15) + 'Net APY%'.padEnd(12) + 'Max APY%'.padEnd(12) + 'Report Delay'.padEnd(15) + 'Max Delta%'.padEnd(12) + 'Perf Fee%');
    console.log('─'.repeat(120));

    for (const data of statsData) {
        if (data.error) {
            console.log(
                data.name.padEnd(30) +
                data.prevAum.padEnd(15) +
                data.netAPY.padEnd(12) +
                data.maxAPY.padEnd(12) +
                data.reportDelay.padEnd(15) +
                data.maxDelta.padEnd(12) +
                data.performanceFee
            );
            console.log(`  └─ Error: ${data.error}`);
        } else {
            console.log(
                data.name.padEnd(30) +
                data.prevAum.padEnd(15) +
                data.netAPY.padEnd(12) +
                data.maxAPY.padEnd(12) +
                data.reportDelay.padEnd(15) +
                data.maxDelta.padEnd(12) +
                data.performanceFee
            );
        }
    }
}

// Set max delta for strategies
async function setMaxDelta(strategyNames: string[], annualAPY: number, dryRun: boolean = false) {
    const delaySeconds = 3600;
    const maxDeltaPercentage = (annualAPY * delaySeconds) / (365 * 24 * 60 * 60) / 100;
    const maxDeltaWei = Math.round(maxDeltaPercentage * 1e18);

    console.log(`Setting max delta for strategies: ${strategyNames.join(', ')}`);
    console.log(`Annual APY: ${annualAPY}%`);
    console.log(`Reporting delay assumed as: 1 hour (${delaySeconds} seconds)`);
    console.log(`Calculated max delta: ${maxDeltaPercentage.toFixed(6)}% (${maxDeltaWei} wei)`);

    const calls: Call[] = [];

    for (const strategyName of strategyNames) {
        const strategy = getAllStrategies().find(s => s.metadata.name.toLowerCase().includes(strategyName.toLowerCase()));
        if (!strategy) {
            console.error(`Strategy "${strategyName}" not found, skipping...`);
            continue;
        }

        try {
            const vaultContract = await getVaultContract(strategy.address.toString());
            const setMaxDeltaCall = vaultContract.populate('set_max_delta', [uint256.bnToUint256(maxDeltaWei)]);
            
            calls.push(setMaxDeltaCall);
        } catch (error) {
            console.error(`Error preparing call for ${strategyName}:`, error.message);
        }
    }

    if (dryRun) {
        console.log('\n🔍 Dry run - Transaction calls:');
        console.log(JSON.stringify(calls, null, 2));
        return;
    }

    if (calls.length === 0) {
        console.log('No valid calls to execute');
        return;
    }

    try {
        await Deployer.executeTransactions(
            calls, 
            acc, 
            config.provider, 
            `Set max delta for ${strategyNames.join(', ')}`
        );
        console.log('✅ Max delta set successfully for all strategies');
    } catch (error) {
        console.error('❌ Error executing transactions:', error.message);
    }
}

// Main CLI logic
async function main() {
    if (!command) {
        console.log(`
📊 Vault Strategy CLI

Usage:
  node cli.ts log-stats                                    # Log statistics for all strategies
  node cli.ts set-max-delta <strategies> <apy> <hours>     # Set max delta for strategies
  node cli.ts set-max-delta <strategies> <apy> <hours> --dry-run  # Dry run mode

Examples:
  node cli.ts log-stats
  node cli.ts set-max-delta "xSTRK,xtBTC" 200 6
  node cli.ts set-max-delta "xSTRK" 150 12 --dry-run

Available strategies: ${HyperLSTStrategies.map(s => s.name).join(', ')}
        `);
        return;
    }

    switch (command) {
        case 'log-stats':
            await logStats();
            break;

        case 'set-max-delta':
            const strategies = args[1];
            const apy = parseFloat(args[2]);
            // const hours = parseFloat(args[3]);
            const dryRun = args.includes('--dry-run');

            if (!strategies || isNaN(apy)) {
                console.error('❌ Invalid arguments. Usage: set-max-delta <strategies> <apy> [--dry-run]');
                process.exit(1);
            }

            const strategyNames = strategies.split(',').map(s => s.trim());
            await setMaxDelta(strategyNames, apy, dryRun);
            break;

        default:
            console.error(`❌ Unknown command: ${command}`);
            console.log('Available commands: log-stats, set-max-delta');
            process.exit(1);
    }
}

// Run the CLI
if (import.meta.url === `file://${process.argv[1]}`) {
    main().catch(error => {
        console.error('❌ CLI Error:', error.message);
        process.exit(1);
    });
}

export { logStats, setMaxDelta };


/**
 * Examples
 * -- Hyper strategies
 * npx tsx cli.ts set-max-delta "hyper xstrk,hyper xwbtc,hyper xtbtc,hyper xsbtc,hyper xlbtc" 50  
 * -- Evergreen strategies
 * npx tsx cli.ts set-max-delta "usdc evergreen,strk evergreen,wbtc evergreen,eth evergreen,usdt evergreen" 50         
 */