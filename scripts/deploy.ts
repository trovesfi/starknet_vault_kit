import dotenv from 'dotenv';
dotenv.config();
import { ContractAddr, Deployer, FlashloanCallParams, getMainnetConfig, Global, PricerFromApi, UNIVERSAL_MANAGE_IDS, UniversalStrategies, UniversalStrategy, VesuAdapter, VesuAmountDenomination, VesuAmountType, VesuModifyPositionCallParams, Web3Number } from '@strkfarm/sdk';
import { byteArray, CallData, Contract, hash, num, shortString, uint256 } from 'starknet';
import * as CommonSettings from './config.json';
import { StandardMerkleTree, LeafData } from './merkle';

interface VaultContracts {
    vault: ContractAddr;
    redeemRequest: ContractAddr;
    vaultAllocator: ContractAddr;
    manager: ContractAddr;
}

const config = getMainnetConfig();
const acc = Deployer.getAccount('strkfarmadmin', config);
const OWNER = ContractAddr.from(acc.address);
const FEE_RECIPIENT = ContractAddr.from(acc.address);
const VAULT_PACKAGE = 'vault';
const VAULT_ALLOCATOR_PACKAGE = 'vault_allocator';
const SIMPLE_SANITIZER = ContractAddr.from('0x11b59e89b35dfceb3e48ec18c01f8ec569592026c275bcb58e22af9f4dedaac');

const pricer = new PricerFromApi(config, Global.getDefaultTokens());
const universalUSDCVault = new UniversalStrategy(config, pricer, UniversalStrategies[0]);

async function deployStrategy() {
    // prepare vault contract
    const vaultContract = [{
        contract_name: 'Vault',
        package_name: VAULT_PACKAGE,
        constructorData: getVaultConstructorCall({
            name: 'Troves USDC Evergreen',
            symbol: 'tUSDC-E',
            underlying_asset: Global.getDefaultTokens().find(token => token.symbol === 'USDC')?.address!,
            owner: OWNER,
            fees_recipient: FEE_RECIPIENT,
            ...CommonSettings.vault.default_settings,
            max_delta: getMaxDelta(20, CommonSettings.vault.default_settings.report_delay)
        })
    }];

    const vaultDeploymentInfo = await Deployer.prepareMultiDeployContracts(vaultContract, config, acc);
    console.log(vaultDeploymentInfo);

    // config redeem request NFT contract
    const redeemRequestContract = [{
        contract_name: 'RedeemRequest',
        package_name: VAULT_PACKAGE,
        constructorData: {
            owner: OWNER.toString(),
            vault: vaultDeploymentInfo[0].address,
        }
    }];

    const redeemRequestDeploymentInfo = await Deployer.prepareMultiDeployContracts(redeemRequestContract, config, acc);
    console.log(redeemRequestDeploymentInfo);

    // prepare vault allocator contract
    const vaultAllocatorContract = [{
        contract_name: 'VaultAllocator',
        package_name: VAULT_ALLOCATOR_PACKAGE,
        constructorData: {
            owner: OWNER.toString(),
        }
    }];

    const vaultAllocatorDeploymentInfo = await Deployer.prepareMultiDeployContracts(vaultAllocatorContract, config, acc);
    console.log(vaultAllocatorDeploymentInfo);

    // prepare manager contract
    const managerContract = [{
        contract_name: 'Manager',
        package_name: VAULT_ALLOCATOR_PACKAGE,
        constructorData: {
            owner: OWNER.toString(),
            vault_allocator: vaultAllocatorDeploymentInfo[0].address,
            vesu_singleton: CommonSettings.vesu.singleton,
        }
    }];

    const managerDeploymentInfo = await Deployer.prepareMultiDeployContracts(managerContract, config, acc);
    console.log(managerDeploymentInfo);

    // deploy now
    await Deployer.executeDeployCalls([
        ...vaultDeploymentInfo,
        ...redeemRequestDeploymentInfo,
        ...vaultAllocatorDeploymentInfo,
        ...managerDeploymentInfo
    ], acc, config.provider)
}

/**
 * @description Configures the vault settings after deployment.
 * Specifically, register redeem request, vault allocator, and set manager
 * @param vaultContracts 
 */
async function configureSettings(vaultContracts: VaultContracts) {
    const provider = config.provider;

    const vaultCls = await provider.getClassAt(vaultContracts.vault.toString());
    const vaultContract = new Contract(vaultCls.abi, vaultContracts.vault.toString(), provider as any);

    const setRedeemContractCall = vaultContract.populate('register_redeem_request', [vaultContracts.redeemRequest.toString()])
    const setVaultAllocatorCall = vaultContract.populate('register_vault_allocator', [vaultContracts.vaultAllocator.toString()])

    const vaultAllocatorCls = await provider.getClassAt(vaultContracts.vaultAllocator.toString());
    const vaultAllocatorContract = new Contract(vaultAllocatorCls.abi, vaultContracts.vaultAllocator.toString(), provider as any);

    const setManagerCall = vaultAllocatorContract.populate('set_manager', [vaultContracts.manager.toString()]);

    await Deployer.executeTransactions([
        setRedeemContractCall,
        setVaultAllocatorCall,
        setManagerCall
    ], acc, provider, 'Setup vault configs')
}

async function deploySanitizer() {
    await Deployer.deployContract('SimpleDecoderAndSanitizer', '0x6aecb2461dbda5f54ebd7de06bf741359504ece3d0d5282dc8afdcf30ff0d1f', [], config, acc);
}

function constructRoot(vaultContracts: VaultContracts) {
    const root = universalUSDCVault.getMerkleRoot();
    return {
        root
    }
}

async function setManagerRoot(vaultContracts: VaultContracts, caller: ContractAddr) {
    const provider = config.provider;
    const managerCls = await provider.getClassAt(vaultContracts.manager.toString());
    const managerContract = new Contract(managerCls.abi, vaultContracts.manager.toString(), provider as any);

    const setRootCall = universalUSDCVault.getSetManagerCall(caller);
    await Deployer.executeTransactions([setRootCall], acc, provider, 'Trigger manage');
}

async function upgrade(
    contractName: string,
    packageName: string,
    contractAddr: string
) {
    const cls = await Deployer.myDeclare(contractName, packageName, config, acc);

    const contractCls = await config.provider.getClassAt(contractAddr);
    const contract = new Contract(contractCls.abi, contractAddr, config.provider as any);

    const call = contract.populate('upgrade', [cls.class_hash]);
    await Deployer.executeTransactions([call], acc, config.provider, 'Upgrade contract');
}

function toBigInt(value: string): bigint {
    return BigInt(num.getDecimalString(value));
}

function getVaultConstructorCall(args: {
    name: string,
    symbol: string,
    underlying_asset: ContractAddr,
    owner: ContractAddr,
    fees_recipient: ContractAddr,
    redeem_fees: number,
    management_fees: number,
    performance_fees: number,
    report_delay: number, // seconds
    max_delta: number,
}) {
    return {
        name: byteArray.byteArrayFromString(args.name),
        symbol: byteArray.byteArrayFromString(args.symbol),
        underlying_asset: args.underlying_asset.toString(),
        owner: args.owner.toString(),
        fees_recipient: args.fees_recipient.toString(),
        redeem_fees: uint256.bnToUint256(Math.round(args.redeem_fees * 1e18)),
        management_fees: uint256.bnToUint256(Math.round(args.management_fees * 1e18)),
        performance_fees: uint256.bnToUint256(Math.round(args.performance_fees * 1e18)),
        report_delay: args.report_delay,
        max_delta: uint256.bnToUint256(Math.round(args.max_delta * 1e18))
    }
}

function getMaxDelta(expectedAPYPercent: number, report_delay_seconds: number, addedBufferPercent: number = 0.5) {
    const expectedReturnForTheReportDelayPercent = expectedAPYPercent * report_delay_seconds / (365 * 24 * 60 * 60);
    const output = (expectedReturnForTheReportDelayPercent + (expectedReturnForTheReportDelayPercent * addedBufferPercent));
    console.log(`Max delta for expected APY ${expectedAPYPercent}% and report delay ${report_delay_seconds} seconds is: ${output}%`);
    return output / 100;
}


if (require.main === module) {
    // deployStrategy();
    const vaultContracts = {
        vault: ContractAddr.from('0x7e6498cf6a1bfc7e6fc89f1831865e2dacb9756def4ec4b031a9138788a3b5e'),
        redeemRequest: ContractAddr.from('0x906d03590010868cbf7590ad47043959d7af8e782089a605d9b22567b64fda'),
        vaultAllocator: ContractAddr.from('0x228cca1005d3f2b55cbaba27cb291dacf1b9a92d1d6b1638195fbd3d0c1e3ba'),
        manager: ContractAddr.from('0xf41a2b1f498a7f9629db0b8519259e66e964260a23d20003f3e42bb1997a07')
    }
    // configureSettings();
    // deploySanitizer();
    // setManagerRoot(vaultContracts, vaultContracts.manager);
    upgrade('Manager', VAULT_ALLOCATOR_PACKAGE, vaultContracts.manager.toString());
}