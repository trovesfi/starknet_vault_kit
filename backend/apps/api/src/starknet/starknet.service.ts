import { Injectable, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@forge/config";
import { Provider, RpcProvider, Contract } from "starknet";

@Injectable()
export class StarknetService implements OnModuleInit {
  private provider: Provider;

  constructor(private configService: ConfigService) {}

  async onModuleInit() {
    const rpcUrl = this.configService.get("STARKNET_RPC_URL") || "https://starknet-sepolia.public.blastapi.io/rpc/v0_7";
    this.provider = new RpcProvider({ nodeUrl: rpcUrl });
  }

  getProvider(): Provider {
    return this.provider;
  }

  async getBlockNumber(): Promise<number> {
    return await this.provider.getBlockNumber();
  }

  async getBlock(blockNumber: number) {
    return await this.provider.getBlockWithTxHashes(blockNumber);
  }

  async getTransaction(txHash: string) {
    return await this.provider.getTransaction(txHash);
  }

  async getTransactionReceipt(txHash: string) {
    return await this.provider.getTransactionReceipt(txHash);
  }

  async getContractClass(contractAddress: string) {
    return await this.provider.getClassAt(contractAddress);
  }

  createContract(address: string, abi: any): Contract {
    return new Contract(abi, address, this.provider);
  }

  async callContract(
    contractAddress: string,
    functionName: string,
    calldata: any[] = []
  ) {
    return await this.provider.callContract({
      contractAddress,
      entrypoint: functionName,
      calldata,
    });
  }
}