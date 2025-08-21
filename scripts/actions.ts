import dotenv from 'dotenv';
dotenv.config();
import { ApproveCallParams, ContractAddr, Deployer, FlashloanCallParams, getMainnetConfig, Global, PricerFromApi, UNIVERSAL_ADAPTERS, UNIVERSAL_MANAGE_IDS, UniversalStrategies, UniversalStrategy, VesuAdapter, VesuModifyPositionCallParams, Web3Number } from "@strkfarm/sdk";
import { CallData, uint256 } from "starknet";

const config = getMainnetConfig();
const acc = Deployer.getAccount('strkfarmadmin', config);
const OWNER = ContractAddr.from(acc.address);

const pricer = new PricerFromApi(config, Global.getDefaultTokens());
const universalUSDCVault = new UniversalStrategy(config, pricer, UniversalStrategies[0]);

async function main() {
    const AMOUNT = new Web3Number(200, 6);

    // const depositCall = await universalUSDCVault.depositCall({
    //     tokenInfo: Global.getDefaultTokens().find(token => token.symbol === 'USDC')!,
    //     amount: new Web3Number(200, 6)
    // }, OWNER);

    // const reportCall = universalUSDCVault.contract.populate('report', [uint256.bnToUint256('0')]);
    // const manageCall = await universalUSDCVault.getVesuMultiplyCall({
    //     isDeposit: true,
    //     leg1DepositAmount: AMOUNT
    // })
    // await Deployer.executeTransactions([
    //     ...depositCall, reportCall, manageCall
    // ], acc, config.provider, 'Trigger manage');

    // const gas = await acc.estimateInvokeFee([...depositCall, reportCall, manageCall])
    // console.log(gas)

    const vesuLeg1Adapter = universalUSDCVault.getAdapter(UNIVERSAL_ADAPTERS.VESU_LEG1) as VesuAdapter;
    console.log(`LTV1: ${await vesuLeg1Adapter.getLTVConfig(config)}`);
    console.log(`AUM: ${JSON.stringify(await universalUSDCVault.getAUM())}`);
    console.log(`Positions: ${JSON.stringify(await universalUSDCVault.getVaultPositions())}`);
    console.log(`Net APY: ${JSON.stringify(await universalUSDCVault.netAPY())}`);
}

if (require.main === module) {
    main().catch(console.error);
}