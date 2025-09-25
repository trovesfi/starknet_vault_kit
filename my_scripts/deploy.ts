import dotenv from 'dotenv';
dotenv.config();
import { ContractAddr, Deployer, getMainnetConfig, Global, HyperLSTStrategies, PricerFromApi, UNIVERSAL_MANAGE_IDS, UniversalLstMultiplierStrategy, UniversalStrategies, UniversalStrategy, UniversalStrategySettings, VesuAdapter, VesuAmountDenomination, VesuAmountType, VesuModifyPositionCallParams, Web3Number } from '@strkfarm/sdk';
import { byteArray, CallData, Contract, hash, num, provider, shortString, uint256 } from 'starknet';
import * as CommonSettings from './config.json';
import { StandardMerkleTree, LeafData } from './merkle';

interface VaultContracts {
    vault: ContractAddr;
    redeemRequest: ContractAddr;
    vaultAllocator: ContractAddr;
    manager: ContractAddr;
}

console.log('url', process.env.RPC_URL);
const config = getMainnetConfig(process.env.RPC_URL!, 'latest');
const acc = Deployer.getAccount('strkfarmadmin', config, process.env.ACCOUNT_SECURE_PASSWORD!, process.env.ACCOUNT_FILE || 'accounts.json');
const OWNER = ContractAddr.from(acc.address);
const FEE_RECIPIENT = ContractAddr.from('0x06419f7DeA356b74bC1443bd1600AB3831b7808D1EF897789FacFAd11a172Da7');
const VAULT_PACKAGE = 'vault';
const VAULT_ALLOCATOR_PACKAGE = 'vault_allocator';
const SIMPLE_SANITIZER = ContractAddr.from('0x3798dc4f83fdfad199e5236e3656cf2fb79bc50c00504d0dd41522e0f042072');
const RELAYER = '0x02D6cf6182259ee62A001EfC67e62C1fbc0dF109D2AA4163EB70D6d1074F0173';
const pricer = new PricerFromApi(config, Global.getDefaultTokens());
const universalUSDCVault = new UniversalStrategy(config, pricer, UniversalStrategies[0]);

async function deployStrategy() {
    // prepare vault contract
    // ! ensure correct names and token
    const symbol = 'xLBTC'
    const vaultContract = [{
        contract_name: 'Vault',
        package_name: VAULT_PACKAGE,
        constructorData: getVaultConstructorCall({
            // ! update all 3
            name: `Troves Hyper ${symbol}`,
            symbol: `t${symbol}-H`,
            underlying_asset: Global.getDefaultTokens().find(token => token.symbol === symbol)?.address!,
            owner: OWNER,
            fees_recipient: FEE_RECIPIENT,
            ...CommonSettings.vault.default_settings,
            max_delta: getMaxDelta(40, CommonSettings.vault.default_settings.report_delay * 6)
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
        }
    }];

    const managerDeploymentInfo = await Deployer.prepareMultiDeployContracts(managerContract, config, acc);
    console.log(managerDeploymentInfo);

    const aumOracleCh = '0x00713f2c45a43e7427b161bcccd3797b88c4216bc055f5f1deab1debbb772b4d';

    // deploy now
    await Deployer.executeDeployCalls([
        ...vaultDeploymentInfo,
        ...redeemRequestDeploymentInfo,
        ...vaultAllocatorDeploymentInfo,
        ...managerDeploymentInfo
    ], acc, config.provider)

    console.log("Deploying aum oracle")
    await Deployer.deployContract('aum_oracle', aumOracleCh, {
        admin_address: OWNER,
        default_relayer_address: RELAYER,
        vault_contract_address: vaultDeploymentInfo[0].address,
    }, config, acc);
}

/**
 * @description Configures the vault settings after deployment.
 * Specifically, register redeem request, vault allocator, and set manager
 * @param vaultContracts 
 */
async function configureSettings(vaultContracts: VaultContracts) {
    const provider = config.provider;

    const vaultCls = await provider.getClassAt(vaultContracts.vault.toString());
    const vaultContract = new Contract({abi: vaultCls.abi, address: vaultContracts.vault.toString(), providerOrAccount: provider as any});

    const setRedeemContractCall = vaultContract.populate('register_redeem_request', [vaultContracts.redeemRequest.address.toString()])
    const setVaultAllocatorCall = vaultContract.populate('register_vault_allocator', [vaultContracts.vaultAllocator.address.toString()])

    const vaultAllocatorCls = await provider.getClassAt(vaultContracts.vaultAllocator.toString());
    const vaultAllocatorContract = new Contract({abi: vaultAllocatorCls.abi, address: vaultContracts.vaultAllocator.toString(), providerOrAccount: provider as any});

    const setManagerCall = vaultAllocatorContract.populate('set_manager', [vaultContracts.manager.address.toString()]);

    await Deployer.executeTransactions([
        setRedeemContractCall,
        setVaultAllocatorCall,
        setManagerCall
    ], acc, provider, 'Setup vault configs')
}

async function deploySanitizer() {
    const calls = await Deployer.prepareMultiDeployContracts([{
        contract_name: 'SimpleDecoderAndSanitizer',
        package_name: VAULT_ALLOCATOR_PACKAGE,
        constructorData: []
    }], config, acc);

    // const ch = await Deployer.myDeclare('SimpleDecoderAndSanitizer', VAULT_ALLOCATOR_PACKAGE, config, acc);
    await Deployer.executeDeployCalls(calls, acc, config.provider);
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
    const contract = new Contract({abi: contractCls.abi, address: contractAddr, providerOrAccount: config.provider as any});

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
    const contract = new Contract({abi: cls.abi, address: vault.address.toString(), providerOrAccount: provider as any});
    const grantRoleCall = contract.populate('grant_role', [role, account]);
    await Deployer.executeTransactions([grantRoleCall], acc, provider, 'Grant role');
}

async function setMaxDelta(vault: UniversalStrategy<UniversalStrategySettings>, maxDelta: number) {
    const provider = config.provider;
    console.log('getting cls');
    const cls = await provider.getClassAt(vault.address.toString());
    console.log('getting cls2', cls.abi.length);
    const contract = new Contract({abi: cls.abi, address: vault.address.toString(), providerOrAccount: provider as any});
    const setMaxDeltaCall = contract.populate('set_max_delta', [uint256.bnToUint256(Math.round(maxDelta * 1e18))]);
    await Deployer.executeTransactions([setMaxDeltaCall], acc, provider, 'Set max delta');
}

async function test() {
    const addr = '0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc';
    const provider = config.provider;
    const cls = await provider.getClassAt(addr);
    const contract = new Contract({abi: cls.abi, address: addr, providerOrAccount: provider as any});

    const result = await contract.call('')
}

async function deployPriceRouter() {
    const provider = config.provider;
    const PRAMGA = '0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b';
    const calls = await Deployer.prepareMultiDeployContracts([{
        contract_name: 'PriceRouter',
        package_name: VAULT_ALLOCATOR_PACKAGE,
        constructorData: [OWNER, PRAMGA]
    }], config, acc);
    await Deployer.executeTransactions(calls.map(c => c.call), acc, provider, 'Deploy Price Router');
}

async function deployAvnuMiddleware() {
    const provider = config.provider;
    const AVNU = '0x4270219d365d6b017231b52e92b3fb5d7c8378b05e9abc97724537a80e93b0f';
    const PRICE_ROUTER = '0x05e83Fa38D791d2dba8E6f487758A9687FfEe191A6Cf8a6c5761ab0a110DB837'
    const calls = await Deployer.prepareMultiDeployContracts([{
        contract_name: 'AvnuMiddleware',
        package_name: VAULT_ALLOCATOR_PACKAGE,
        constructorData: [
            OWNER, 
            AVNU,
            PRICE_ROUTER,
            100, 0 // 1% max slippage
        ]
    }], config, acc);
    await Deployer.executeDeployCalls(calls, acc, provider);
}

async function configurePriceRouter() {
    const PRICE_ROUTER = '0x05e83Fa38D791d2dba8E6f487758A9687FfEe191A6Cf8a6c5761ab0a110DB837'
    const cls = await config.provider.getClassAt(PRICE_ROUTER);
    const contract = new Contract({abi: cls.abi, address: PRICE_ROUTER, providerOrAccount: config.provider as any});

    // ETH/WBTC/USDC/USDT/STRK
    const assetIdMap = [{
        asset: Global.getDefaultTokens().find(t => t.symbol === 'USDC')?.address!,
        id: '6148332971638477636'
    }, {
        asset: Global.getDefaultTokens().find(t => t.symbol === 'USDT')?.address!,
        id: '6148333044652921668'
    }, {
        asset: Global.getDefaultTokens().find(t => t.symbol === 'STRK')?.address!,
        id: '6004514686061859652'
    }, {
        asset: Global.getDefaultTokens().find(t => t.symbol === 'WBTC')?.address!,
        id: '6287680677296296772'
    }, {
        asset: Global.getDefaultTokens().find(t => t.symbol === 'ETH')?.address!,
        id: '19514442401534788'
    }]
    const calls = assetIdMap.map(m => contract.populate('set_asset_to_id', [m.asset.toString(), m.id]));
    await Deployer.executeTransactions(calls, acc, config.provider, 'Configure Price Router');
}

// fn set_fees_config(
//         ref self: TContractState,
//         fees_recipient: ContractAddress,
//         redeem_fees: u256,
//         management_fees: u256,
//         performance_fees: u256,
//     );
async function setFeesConfig(strategy: UniversalStrategy<UniversalStrategySettings>) {
  const provider = config.provider;
  const cls = await provider.getClassAt(strategy.address.address.toString());
  const contract = new Contract({abi: cls.abi, address: strategy.address.toString(), providerOrAccount: provider as any});
  console.log(`got cls`)
  const feeReceiver = '0x06419f7DeA356b74bC1443bd1600AB3831b7808D1EF897789FacFAd11a172Da7';
  const setFeesCall = contract.populate('set_fees_config', [
    feeReceiver,
    uint256.bnToUint256(0),
    uint256.bnToUint256(0),
    uint256.bnToUint256(1e17), // 10%
  ]);
  await Deployer.executeTransactions([setFeesCall], acc, provider, 'Set fees config');
}

async function pause(strategy: UniversalStrategy<UniversalStrategySettings>) {
  const provider = config.provider;
  const cls = await provider.getClassAt(strategy.address.address.toString());
  const contract = new Contract({abi: cls.abi, address: strategy.address.toString(), providerOrAccount: provider as any});
  const pauseCall = contract.populate('pause');
  await Deployer.executeTransactions([pauseCall], acc, provider, 'Pause');
}

async function unpause(strategy: UniversalStrategy<UniversalStrategySettings>) {
    const provider = config.provider;
    const cls = await provider.getClassAt(strategy.address.address.toString());
    const contract = new Contract({abi: cls.abi, address: strategy.address.toString(), providerOrAccount: provider as any});
    const pauseCall = contract.populate('unpause');
    await Deployer.executeTransactions([pauseCall], acc, provider, 'Pause');
  }

if (require.main === module) {
    // Contract deployed: Vault, addr: 0x46c7a54c82b1fe374353859f554a40b8bd31d3e30f742901579e7b57b1b5960
    // Contract deployed: RedeemRequest, addr: 0x51e40b839dc0c2feca923f863072673b94abfa2483345be3b30b457a90d095
    // Contract deployed: VaultAllocator, addr: 0x511d07953a09bc7c505970891507c5a2486d2ea22752601a14db092186d7caa
    // Contract deployed: Manager, addr: 0x5d499cd333757f461a0bedaca3dfc4d77320c773037e0aa299f22a6dbfdc03a

    // xSTRK
    const vaultContracts = {
        vault: ContractAddr.from('0x46c7a54c82b1fe374353859f554a40b8bd31d3e30f742901579e7b57b1b5960'),
        redeemRequest: ContractAddr.from('0x51e40b839dc0c2feca923f863072673b94abfa2483345be3b30b457a90d095'),
        vaultAllocator: ContractAddr.from('0x511d07953a09bc7c505970891507c5a2486d2ea22752601a14db092186d7caa'),
        manager: ContractAddr.from('0x5d499cd333757f461a0bedaca3dfc4d77320c773037e0aa299f22a6dbfdc03a')
    }

    // xsBTC
    // const vaultContracts = {
    //     vault: ContractAddr.from('0x437ef1e7d0f100b2e070b7a65cafec0b2be31b0290776da8b4112f5473d8d9'),
    //     redeemRequest: ContractAddr.from('0x429e8ee8bc7ecd1ade72630d350a2e0f10f9a2507c45f188ba17fe8f2ab4cf3'),
    //     vaultAllocator: ContractAddr.from('0x60c2d856936b975459a5b4eb28b8672d91f757bd76cebb6241f8d670185dc01'),
    //     manager: ContractAddr.from('0xc9ac023090625b0be3f6532ca353f086746f9c09f939dbc1b2613f09e5f821')
    // }
    
    // xtBTC
    // const vaultContracts = {
    //     vault: ContractAddr.from('0x47d5f68477e5637ce0e56436c6b5eee5a354e6828995dae106b11a48679328'),
    //     redeemRequest: ContractAddr.from('0xeac9032f02057779816e38a6cb9185d12d86b3aacc9949b96b36de359c1e3'),
    //     vaultAllocator: ContractAddr.from('0x50bbd4fe69f841ecb13b2619fe50ebfa4e8944671b5d0ebf7868fd80c61b31e'),
    //     manager: ContractAddr.from('0xc4cc3e08029a0ae076f5fdfca70575abb78d23c5cd1c49a957f7e697885401')
    // }

    // xWBTC
    // const vaultContracts = {
    //     vault: ContractAddr.from('0x2da9d0f96a46b453f55604313785dc866424240b1c6811d13bef594343db818'),
    //     redeemRequest: ContractAddr.from('0x7a5dc288325456f05e70e9616e16bc02ffbe448f4b89f80b47c0970b989c7c'),
    //     vaultAllocator: ContractAddr.from('0x57b5c1bb457b5e840a2714ae53ada87d77be2f3fd33a59b4fe709ef20c020c1'),
    //     manager: ContractAddr.from('0x75866db44c81e6986f06035206ee9c7d15833ddb22d6a22c016cfb5c866a491')
    // }

    // xLBTC
    // Contract deployed: Vault, addr: 0x38e96a301428d204ab4553799aa386a0f14a5ef9b30a5830be1814e4fb8da1c
    // Contract deployed: RedeemRequest, addr: 0x268017b4c8b2117ca0136d9a77e3666db44b143447566f0746ca0b1c9ab1e72
    // Contract deployed: VaultAllocator, addr: 0x3e98774ca0508505ba6d7f17d95ec391648f44f947b0d211241464a4f5b9b20
    // Contract deployed: Manager, addr: 0x18d376446d9df1f783e17aff1f21bac3d97aa3ba378e367742cdd744468ad35
    // Aum oracle 0x521a3f339c65e918e0d8a065b14baef1ea25676bb7fca1e0238ac47e20d7755

    deployStrategy();
    // const strategy = HyperLSTStrategies.find(u => u.name.includes('xSTRK'))!;
    // const vaultStrategy = new UniversalStrategy(config, pricer, strategy);
    // const vaultStrategy = new UniversalLstMultiplierStrategy(config, pricer, strategy);
    // const vaultContracts = {
    //     vault: strategy.address,
    //     redeemRequest: strategy.additionalInfo.redeemRequestNFT,
    //     vaultAllocator: strategy.additionalInfo.vaultAllocator,
    //     manager: strategy.additionalInfo.manager
    // }
    
    async function setConfig() {
        // await upgrade('Vault', VAULT_PACKAGE, vaultContracts.vault.toString());
        // await configureSettings(vaultContracts);
        // await setManagerRoot(vaultStrategy, ContractAddr.from(RELAYER));
        // await grantRole(vaultStrategy, hash.getSelectorFromName('ORACLE_ROLE'), strategy.additionalInfo.aumOracle.address);
        // await setMaxDelta(vaultStrategy, getMaxDelta(15, CommonSettings.vault.default_settings.report_delay * 24));

        // for (let i=0; i < UniversalStrategies.length; i++) {
        //     const u = UniversalStrategies[i];
        //     const strategy = new UniversalStrategy(config, pricer, u);
            // await setManagerRoot(strategy, ContractAddr.from(RELAYER));
            // await setMaxDelta(strategy, getMaxDelta(200, CommonSettings.vault.default_settings.report_delay * 24));
            // await grantRole(u, hash.getSelectorFromName('ORACLE_ROLE'), strategy.additionalInfo.aumOracle.address);
            // await setFeesConfig(strategy);
            // await pause(strategy);
        //     await unpause(strategy);
        // }
    }
    setConfig();
    // configurePriceRouter();
    // deployPriceRouter();
    // deployAvnuMiddleware();
    // console.log(UniversalStrategies.map(u => ({
    //     address: u.address.address,
    //     name: u.name,
    //     asset: u.depositTokens[0].address.address
    // })))
    // deploySanitizer();
    // upgrade('Vault', VAULT_PACKAGE, vaultContracts.vault.toString());
    // grantRole(vaultStrategy, hash.getSelectorFromName('ORACLE_ROLE'), '0x2edf4edbed3f839e7f07dcd913e92299898ff4cf0ba532f8c572c66c5b331b2')
    // setMaxDelta(vaultStrategy, getMaxDelta(15, CommonSettings.vault.default_settings.report_delay * 24));
}