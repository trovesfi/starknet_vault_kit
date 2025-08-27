import dotenv from 'dotenv';
dotenv.config();
import { ContractAddr, Deployer, FlashloanCallParams, getMainnetConfig, Global, PricerFromApi, UNIVERSAL_MANAGE_IDS, UniversalStrategies, UniversalStrategy, UniversalStrategySettings, VesuAdapter, VesuAmountDenomination, VesuAmountType, VesuModifyPositionCallParams, Web3Number } from '@strkfarm/sdk';
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
    // ! ensure correct names and token
    const vaultContract = [{
        contract_name: 'Vault',
        package_name: VAULT_PACKAGE,
        constructorData: getVaultConstructorCall({
            name: 'Troves WBTC Evergreen',
            symbol: 'tWBTC-E',
            underlying_asset: Global.getDefaultTokens().find(token => token.symbol === 'WBTC')?.address!,
            owner: OWNER,
            fees_recipient: FEE_RECIPIENT,
            ...CommonSettings.vault.default_settings,
            max_delta: getMaxDelta(15, CommonSettings.vault.default_settings.report_delay * 6)
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

async function setManagerRoot(vaultStrategy: UniversalStrategy<UniversalStrategySettings>, caller: ContractAddr) {
    const provider = config.provider;
    const setRootCall = vaultStrategy.getSetManagerCall(caller);
    const setRootCall2 = vaultStrategy.getSetManagerCall(vaultStrategy.metadata.additionalInfo.manager);
    await Deployer.executeTransactions([setRootCall, setRootCall2], acc, provider, 'Trigger manage');
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

async function grantRole(vault: UniversalStrategy<UniversalStrategySettings>, role: string, account: string) {
    const provider = config.provider;
    const cls = await provider.getClassAt(vault.address.toString());
    const contract = new Contract(cls.abi, vault.address.toString(), provider as any);
    const grantRoleCall = contract.populate('grant_role', [role, account]);
    await Deployer.executeTransactions([grantRoleCall], acc, provider, 'Grant role');
}

async function setMaxDelta(vault: UniversalStrategy<UniversalStrategySettings>, maxDelta: number) {
    const provider = config.provider;
    const cls = await provider.getClassAt(vault.address.toString());
    const contract = new Contract(cls.abi, vault.address.toString(), provider as any);
    const setMaxDeltaCall = contract.populate('set_max_delta', [uint256.bnToUint256(Math.round(maxDelta * 1e18))]);
    await Deployer.executeTransactions([setMaxDeltaCall], acc, provider, 'Set max delta');
}

async function test() {
    const addr = '0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc';
    const provider = config.provider;
    const cls = await provider.getClassAt(addr);
    const contract = new Contract(cls.abi, addr, provider as any);

    const result = await contract.call('')
}
if (require.main === module) {
    // deployStrategy();
    const strategy = UniversalStrategies[1];
    const vaultStrategy = new UniversalStrategy(config, pricer, strategy);
    const vaultContracts = {
        vault: strategy.address,
        redeemRequest: strategy.additionalInfo.manager,
        vaultAllocator: strategy.additionalInfo.vaultAllocator,
        manager: strategy.additionalInfo.manager
    }
    // configureSettings(vaultContracts);
    // deploySanitizer();
    // setManagerRoot(vaultStrategy, ContractAddr.from('0x02D6cf6182259ee62A001EfC67e62C1fbc0dF109D2AA4163EB70D6d1074F0173'));
    // upgrade('Manager', VAULT_ALLOCATOR_PACKAGE, vaultContracts.manager.toString());
    grantRole(vaultStrategy, hash.getSelectorFromName('ORACLE_ROLE'), '0x2edf4edbed3f839e7f07dcd913e92299898ff4cf0ba532f8c572c66c5b331b2')
    // setMaxDelta(vaultStrategy, getMaxDelta(15, CommonSettings.vault.default_settings.report_delay * 24));
}