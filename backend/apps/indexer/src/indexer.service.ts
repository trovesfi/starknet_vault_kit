import {
  Filter,
  FieldElement,
  StarkNetCursor,
  v1alpha2,
} from "@apibara/starknet";
import { StreamClient } from "@apibara/protocol";
import { DataFinality } from "@apibara/protocol/dist/proto/apibara/node/v1alpha2/DataFinality";
import { hash as starknetHash, validateAndParseAddress } from "starknet";
import { ConfigService } from "@forge/config";
import { PrismaService } from "@forge/db";
import { Logger } from "@forge/logger";
import {
  decodeReportEvent,
  decodeRedeemRequestedEvent,
  decodeRedeemClaimedEvent,
} from "./decoder";
import {
  BATCH_SIZE,
  MAX_RETRY_AFTER_RECONNECT_NO_INTERNAL_ERROR,
  MIN_SLEEP_TIME_AFTER_RECONNECT_NO_INTERNAL_ERROR,
} from "./indexer.constants";

interface EventData {
  blockNumber: number;
  timestamp: number;
  transactionHash: string;
  hexData: string[];
  eventTypeHex: string;
}

export class IndexerService {
  private static readonly EVENT_KEYS = {
    redeemRequested: FieldElement.toHex(
      FieldElement.fromBigInt(starknetHash.getSelector("RedeemRequested"))
    ),
    redeemClaimed: FieldElement.toHex(
      FieldElement.fromBigInt(starknetHash.getSelector("RedeemClaimed"))
    ),
    report: FieldElement.toHex(
      FieldElement.fromBigInt(starknetHash.getSelector("Report"))
    ),
  };

  public lastBlockIndexedVault = 0;
  private url: string;
  private apibaraToken: string;
  private vaultFe: v1alpha2.IFieldElement;
  private logger: Logger;

  private redeemRequestedBuffer: any[] = [];
  private redeemClaimedBuffer: any[] = [];
  private reportBuffer: any[] = [];

  constructor(
    private readonly configService: ConfigService,
    private readonly prismaService: PrismaService
  ) {
    this.logger = Logger.create('IndexerService');
    this.url = "mainnet.starknet.a5a.ch";
    this.apibaraToken = this.configService.get("APIBARA_TOKEN") as string;

    const graceful = async () => {
      try {
        await this.flushAllBuffers();
      } finally {
        process.exit(0);
      }
    };
    process.on("SIGINT", graceful);
    process.on("SIGTERM", graceful);
  }

  async run() {
    await this.runVaultIndexer();
  }

  async runVaultIndexer() {
    const client = new StreamClient({
      url: this.url,
      token: this.apibaraToken,
      onReconnect: async (err, retryCount) => {
        this.logger.error('Connection lost', err, { retryCount, errorCode: err.code });
        if (err.code !== 13 && err.code !== 14) {
          // Code 13 = internal error, 14 = unavailable
          return { reconnect: false };
        }
        const base = Math.min(
          MIN_SLEEP_TIME_AFTER_RECONNECT_NO_INTERNAL_ERROR,
          1000 * 2 ** Math.min(retryCount, 6)
        );
        const jitter = Math.floor(Math.random() * 500);
        await new Promise((r) => setTimeout(r, base + jitter));
        return {
          reconnect: retryCount < MAX_RETRY_AFTER_RECONNECT_NO_INTERNAL_ERROR,
        };
      },
    });

    const filterBuilder = Filter.create().withHeader({ weak: false });

    const vaultAddress = this.configService.get('VAULT_ADDRESS') as string;
    try {
      this.vaultFe = FieldElement.fromBigInt(
        validateAndParseAddress(vaultAddress)
      );
    } catch (e) {
      this.logger.error('Invalid vault address', e, { vaultAddress });
      throw e;
    }

    [
      IndexerService.EVENT_KEYS.redeemRequested,
      IndexerService.EVENT_KEYS.redeemClaimed,
      IndexerService.EVENT_KEYS.report,
    ].forEach((keyHex) => {
      const key = FieldElement.fromBigInt(BigInt(keyHex));
      filterBuilder.addEvent((event) =>
        event
          .withFromAddress(this.vaultFe)
          .withIncludeTransaction(true)
          .withIncludeReceipt(true)
          .withKeys([key])
      );
    });

    let startBlock = Number(this.configService.get('START_BLOCK'));

    const [lastRedeemRequested, lastRedeemClaimed, lastReport] =
      await Promise.all([
        this.prismaService.fetchLastRedeemRequested(),
        this.prismaService.fetchLastRedeemClaimed(),
        this.prismaService.fetchLastReport(),
      ]);

    const maxBlock = Math.max(
      lastRedeemRequested?.blockNumber || 0,
      lastRedeemClaimed?.blockNumber || 0,
      lastReport?.blockNumber || 0,
      startBlock
    );

    startBlock = maxBlock + 1;

    this.logger.info(`📦 Resuming from block: ${startBlock} (maxFetchedBlock + 1)`, {
      startBlock,
      lastRedeemRequestedBlock: lastRedeemRequested?.blockNumber || 0,
      lastRedeemClaimedBlock: lastRedeemClaimed?.blockNumber || 0,
      lastReportBlock: lastReport?.blockNumber || 0,
    });

    const cursor = StarkNetCursor.createWithBlockNumber(startBlock);

    client.configure({
      filter: filterBuilder.encode(),
      finality: DataFinality.DATA_STATUS_ACCEPTED,
      cursor,
    });

    for await (const message of client) {
      if (message.data?.data) {
        for (let item of message.data.data) {
          const block = v1alpha2.Block.decode(item);
          const blockNumber = block.header?.blockNumber;
          const timestamp = block.header?.timestamp?.seconds;
          if (!blockNumber) {
            throw new Error("No block number");
          }

          const blockNum = +blockNumber;

          if (!timestamp) {
            throw new Error("No timestamp in block header");
          }

          this.logger.debug('Processing block', {
            blockNumber: blockNum,
            lastBlockIndexed: this.lastBlockIndexedVault,
            timestamp: Number(timestamp)
          });

          for (let event of block.events) {
            const hash = event.transaction?.meta?.hash;
            if (!hash) {
              throw new Error("No hash");
            }
            const hashHex = FieldElement.toHex(hash);

            const eventType = event.event?.keys?.[0];
            if (!eventType) {
              throw new Error("No event type");
            }
            const eventTypeHex = FieldElement.toHex(eventType);

            const data = event.event?.data;
            if (!data) {
              throw new Error("No data");
            }
            const hexData: string[] = data.map((item) => {
              try {
                return FieldElement.toHex(item);
              } catch (err) {
                throw new Error(`Invalid FieldElement item ${item} ${err}`);
              }
            });

            this.logger.debug('Processing event', {
              eventType: this.getEventTypeName(eventTypeHex),
              blockNumber: blockNum,
              transactionHash: hashHex,
              eventTypeHex
            });

            try {
              await this.processEvent(eventTypeHex, hexData, {
                blockNumber: blockNum,
                timestamp: Number(timestamp),
                transactionHash: hashHex,
                hexData,
                eventTypeHex,
              });
            } catch (error) {
              this.logger.error('Failed to process event', error, {
                blockNumber: blockNum,
                transactionHash: hashHex,
                eventType: this.getEventTypeName(eventTypeHex)
              });
              throw error;
            }
          }

          await this.flushAllBuffers();

          if (this.lastBlockIndexedVault < blockNum) {
            this.lastBlockIndexedVault = blockNum;
          }
        }
      }
    }

    await this.flushAllBuffers();
    throw new Error("Stream ended without reconnect");
  }

  private formatStarknetAddress(value: bigint): string {
    return "0x" + value.toString(16).padStart(64, "0");
  }

  private async processEvent(
    eventTypeHex: string,
    hexData: string[],
    eventData: EventData
  ): Promise<void> {
    const { blockNumber, timestamp, transactionHash } = eventData;

    if (eventTypeHex === IndexerService.EVENT_KEYS.redeemRequested) {
      await this.bufferRedeemRequestedEvent(
        hexData,
        blockNumber,
        timestamp,
        transactionHash
      );
    } else if (eventTypeHex === IndexerService.EVENT_KEYS.redeemClaimed) {
      await this.bufferRedeemClaimedEvent(
        hexData,
        blockNumber,
        timestamp,
        transactionHash
      );
    } else if (eventTypeHex === IndexerService.EVENT_KEYS.report) {
      await this.bufferReportEvent(
        hexData,
        blockNumber,
        timestamp,
        transactionHash
      );
    } else {
      this.logger.warn('Unknown event type', { eventTypeHex });
    }
  }

  private async bufferRedeemRequestedEvent(
    hexData: string[],
    blockNumber: number,
    timestamp: number,
    transactionHash: string
  ): Promise<void> {
    try {
      const redeemRequested = decodeRedeemRequestedEvent(hexData);
      const data = {
        blockNumber,
        timestamp,
        transactionHash,
        owner: validateAndParseAddress(
          this.formatStarknetAddress(redeemRequested.owner)
        ),
        receiver: validateAndParseAddress(
          this.formatStarknetAddress(redeemRequested.receiver)
        ),
        shares: redeemRequested.shares,
        assets: redeemRequested.assets,
        redeemId: redeemRequested.redeemId,
        epoch: redeemRequested.epoch,
      };

      this.redeemRequestedBuffer.push(data);

      if (this.redeemRequestedBuffer.length >= BATCH_SIZE) {
        await this.flushRedeemRequestedBuffer();
      }
    } catch (error) {
      this.logger.error('Failed to process RedeemRequested event', error, {
        blockNumber,
        transactionHash
      });
    }
  }

  private async bufferRedeemClaimedEvent(
    hexData: string[],
    blockNumber: number,
    timestamp: number,
    transactionHash: string
  ): Promise<void> {
    try {
      const redeemClaimed = decodeRedeemClaimedEvent(hexData);
      const data = {
        blockNumber,
        timestamp,
        transactionHash,
        receiver: validateAndParseAddress(
          this.formatStarknetAddress(redeemClaimed.receiver)
        ),
        redeemRequestNominal: redeemClaimed.redeemRequestNominal,
        assets: redeemClaimed.assets,
        redeemId: redeemClaimed.redeemId,
        epoch: redeemClaimed.epoch,
      };

      this.redeemClaimedBuffer.push(data);

      if (this.redeemClaimedBuffer.length >= BATCH_SIZE) {
        await this.flushRedeemClaimedBuffer();
      }
    } catch (error) {
      this.logger.error('Failed to process RedeemClaimed event', error, {
        blockNumber,
        transactionHash
      });
    }
  }

  private async bufferReportEvent(
    hexData: string[],
    blockNumber: number,
    timestamp: number,
    transactionHash: string
  ): Promise<void> {
    try {
      const report = decodeReportEvent(hexData);
      const data = {
        blockNumber,
        timestamp,
        transactionHash,
        newEpoch: report.newEpoch,
        newHandledEpochLen: report.newHandledEpochLen,
        totalSupply: report.totalSupply,
        totalAssets: report.totalAssets,
        managementFeeShares: report.managementFeeShares,
        performanceFeeShares: report.performanceFeeShares,
      };

      this.reportBuffer.push(data);

      if (this.reportBuffer.length >= BATCH_SIZE) {
        await this.flushReportBuffer();
      }
    } catch (error) {
      this.logger.error('Failed to process Report event', error, {
        blockNumber,
        transactionHash
      });
    }
  }

  private async flushRedeemRequestedBuffer(): Promise<void> {
    if (this.redeemRequestedBuffer.length === 0) return;

    try {
      await this.prismaService.redeemRequested.createMany({
        data: this.redeemRequestedBuffer,
        skipDuplicates: true,
      });
      this.logger.info('Flushed RedeemRequested events', {
        count: this.redeemRequestedBuffer.length
      });
      this.redeemRequestedBuffer = [];
    } catch (err) {
      this.logger.error('Failed to flush RedeemRequested buffer', err);
      throw err;
    }
  }

  private async flushRedeemClaimedBuffer(): Promise<void> {
    if (this.redeemClaimedBuffer.length === 0) return;

    try {
      await this.prismaService.redeemClaimed.createMany({
        data: this.redeemClaimedBuffer,
        skipDuplicates: true,
      });
      this.logger.info('Flushed RedeemClaimed events', {
        count: this.redeemClaimedBuffer.length
      });
      this.redeemClaimedBuffer = [];
    } catch (err) {
      this.logger.error('Failed to flush RedeemClaimed buffer', err);
      throw err;
    }
  }

  private async flushReportBuffer(): Promise<void> {
    if (this.reportBuffer.length === 0) return;

    try {
      await this.prismaService.report.createMany({
        data: this.reportBuffer,
        skipDuplicates: true,
      });
      this.logger.info('Flushed Report events', {
        count: this.reportBuffer.length
      });
      this.reportBuffer = [];
    } catch (err) {
      this.logger.error('Failed to flush Report buffer', err);
      throw err;
    }
  }

  private async flushAllBuffers(): Promise<void> {
    await Promise.all([
      this.flushRedeemRequestedBuffer(),
      this.flushRedeemClaimedBuffer(),
      this.flushReportBuffer(),
    ]);
  }

  private getEventTypeName(eventTypeHex: string): string {
    if (eventTypeHex === IndexerService.EVENT_KEYS.redeemRequested)
      return "RedeemRequested";
    if (eventTypeHex === IndexerService.EVENT_KEYS.redeemClaimed)
      return "RedeemClaimed";
    if (eventTypeHex === IndexerService.EVENT_KEYS.report) return "Report";
    return "Unknown";
  }

  getStatus() {
    return {
      lastBlockIndexedVault: this.lastBlockIndexedVault,
    };
  }
}
