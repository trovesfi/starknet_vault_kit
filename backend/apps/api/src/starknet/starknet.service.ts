import { Injectable, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@forge/config";
import { Provider, RpcProvider, Contract } from "starknet";
import { Logger } from "@forge/logger";
import * as VAULT_ABI from "./abis/vault.json";

@Injectable()
export class StarknetService implements OnModuleInit {
  private provider: Provider;
  private readonly logger = Logger.create('StarknetService');

  constructor(private configService: ConfigService) {}

  async onModuleInit() {
    try {
      const rpcUrl: string =
        (this.configService.get("RPC_URL") as string) ||
        "https://starknet-mainnet.public.blastapi.io";
        
      this.logger.info('Initializing StarkNet provider', { rpcUrl });
      this.provider = new RpcProvider({ nodeUrl: rpcUrl });
      this.logger.info('StarkNet provider initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize StarkNet provider', error);
      throw error;
    }
  }

  async view(
    address: string,
    abi: any,
    functionName: string,
    calldata?: any[]
  ) {
    try {
      this.logger.debug('Making contract view call', {
        address,
        functionName,
        calldataLength: calldata?.length || 0
      });
      
      const abiArray = Array.isArray(abi) ? abi : Object.values(abi);
      const contract = new Contract(abiArray, address, this.provider);

      const result = calldata 
        ? await contract.call(functionName, calldata)
        : await contract.call(functionName);
        
      this.logger.debug('Contract view call successful', {
        address,
        functionName,
        resultType: typeof result
      });
      
      return result;
    } catch (error) {
      this.logger.error('Contract view call failed', error, {
        address,
        functionName,
        calldata
      });
      throw error;
    }
  }

  async vault_due_assets_from_id(address: string, id: number): Promise<bigint> {
    try {
      this.logger.debug('Fetching due assets from vault', { address, id });
      
      const due_assets = (await this.view(
        address,
        VAULT_ABI,
        "due_assets_from_id",
        [id]
      )) as any;
      
      this.logger.debug('Successfully fetched due assets', {
        address,
        id,
        dueAssets: due_assets?.toString()
      });
      
      return due_assets;
    } catch (error) {
      this.logger.error('Failed to fetch due assets from vault', error, {
        address,
        id
      });
      throw error;
    }
  }

  async vault_decimals(address: string): Promise<bigint | undefined> {
    try {
      this.logger.debug('Fetching vault decimals', { address });
      
      const decimals = (await this.provider.callContract({
        contractAddress: address,
        entrypoint: "decimals",
      })) as any;
      
      this.logger.debug('Successfully fetched vault decimals', {
        address,
        decimals: decimals?.toString()
      });
      
      return decimals;
    } catch (error) {
      this.logger.error('Failed to fetch vault decimals', error, { address });
      throw error;
    }
  }
}
