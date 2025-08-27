import dotenv from 'dotenv';
dotenv.config();
import { ApproveCallParams, ContractAddr, Deployer, FlashloanCallParams, getMainnetConfig, Global, Pricer, PricerFromApi, UNIVERSAL_ADAPTERS, UNIVERSAL_MANAGE_IDS, UniversalStrategies, UniversalStrategy, VesuAdapter, VesuModifyPositionCallParams, Web3Number } from "@strkfarm/sdk";
import { CallData, uint256 } from "starknet";

const config = getMainnetConfig();
const acc = Deployer.getAccount('strkfarmadmin', config);
const OWNER = ContractAddr.from(acc.address);

// const pricer = new PricerFromApi(config, Global.getDefaultTokens());?
const pricer = new Pricer(config, Global.getDefaultTokens());

async function main() {
    pricer.start();
    await pricer.waitTillReady();
    const strategy = UniversalStrategies[0];
    const vaultStrategy = new UniversalStrategy(config, pricer, strategy);
    const AMOUNT = new Web3Number(0.001793, 8);

    // const depositCall = await vaultStrategy.depositCall({
    //     tokenInfo: Global.getDefaultTokens().find(token => token.symbol === 'USDC')!,
    //     amount: new Web3Number(200, 6)
    // }, OWNER);

    // const reportCall = vaultStrategy.contract.populate('report', [uint256.bnToUint256('0')]);
    // const manageCall = await vaultStrategy.getVesuMultiplyCall({
    //     isDeposit: true,
    //     leg1DepositAmount: AMOUNT
    // });
    // await Deployer.executeTransactions([
    //      reportCall, manageCall
    // ], acc, config.provider, 'Trigger manage');

    // const gas = await acc.estimateInvokeFee([reportCall, manageCall])
    // console.log(gas)

  
    console.log(`AUM: ${JSON.stringify(await vaultStrategy.getAUM())}`);
    // console.log(`Positions: ${JSON.stringify(await vaultStrategy.getVaultPositions())}`);
    // console.log(`Net APY: ${JSON.stringify(await vaultStrategy.netAPY())}`);
    // console.log(`Health factors: ${JSON.stringify(await vaultStrategy.getVesuHealthFactors())}`)
}

if (require.main === module) {
    main().catch(console.error);
}