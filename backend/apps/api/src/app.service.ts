import { Injectable, OnModuleInit } from "@nestjs/common";
import { validateAndParseAddress } from "starknet";
import { PendingRedeem } from "./types/strategy";
import { PrismaService } from "@forge/db";
import { StarknetService } from "./starknet/starknet.service";
import Decimal from "decimal.js";
import { ConfigService } from "@forge/config";
import { Logger } from "@forge/logger";

@Injectable()
export class AppService implements OnModuleInit {
  strategyDecimals: number;
  private readonly logger = Logger.create("AppService");

  constructor(
    private readonly prismaService: PrismaService,
    private readonly starknetService: StarknetService,
    private readonly configService: ConfigService
  ) {}

  async onModuleInit() {
    try {
      const vaultAddress = this.configService.get("VAULT_ADDRESS") as string;
      this.logger.info("Initializing AppService", { vaultAddress });

      this.strategyDecimals = Number(
        await this.starknetService.vault_decimals(vaultAddress)
      );

      this.logger.info("AppService initialized successfully", {
        strategyDecimals: this.strategyDecimals,
      });
    } catch (error) {
      this.logger.error("Failed to initialize AppService", error);
      throw error;
    }
  }

  getApiInfo() {
    return {
      name: "StarkNet Vault Kit API",
      version: "1.0.0",
      description: "Backend API for StarkNet Vault Kit",
      endpoints: {
        health: "/health",
        pendingRedeems: "/pending-redeems/:address",
        lastReport: "/reports/last",
        redeemById: "/redeems/:id",
      },
      documentation: "/api",
    };
  }

  public async getPendingRedeems(
    address: string,
    limit?: number,
    offset?: number
  ): Promise<PendingRedeem[]> {
    try {
      const addressToUse = validateAndParseAddress(address);
      this.logger.info("Fetching pending redeems", {
        address: addressToUse,
        limit,
        offset,
      });

      // Fetch pending redeems directly from PrismaService
      const pendingRedeemsForStrategy =
        await this.prismaService.fetchPendingRedeemsForAddress(
          addressToUse,
          limit,
          offset
        );

      this.logger.debug("Found pending redeems from database", {
        count: pendingRedeemsForStrategy.length,
      });

      // Map database results to PendingRedeem type with parallel processing
      const pendingRedeemPromises = pendingRedeemsForStrategy.map(
        async (redeem) => {
          try {
            const vaultAddress = this.configService.get(
              "VAULT_ADDRESS"
            ) as string;
            const dueAssets =
              await this.starknetService.vault_due_assets_from_id(
                vaultAddress,
                Number(redeem.redeemId)
              );

            return {
              epoch: Number(redeem.epoch),
              sharesBurn: this.formatBigIntToDecimal(redeem.shares),
              nominal: this.formatBigIntToDecimal(redeem.assets),
              assets: this.formatBigIntToDecimal(dueAssets),
              redeemId: redeem.redeemId.toString(),
              timestamp: redeem.timestamp,
              transactionHash: redeem.transactionHash,
            };
          } catch (error) {
            this.logger.error("Failed to process pending redeem", error, {
              redeemId: redeem.redeemId.toString(),
            });
            throw error;
          }
        }
      );

      const resolvedPendingRedeems = await Promise.all(pendingRedeemPromises);

      this.logger.info("Successfully processed pending redeems", {
        address: addressToUse,
        count: resolvedPendingRedeems.length,
      });

      return resolvedPendingRedeems;
    } catch (error) {
      this.logger.error("Failed to get pending redeems", error, { address });
      throw error;
    }
  }

  public async getLastReport() {
    try {
      this.logger.debug("Fetching last report");

      const lastReport = await this.prismaService.fetchLastReport();
      if (!lastReport) {
        this.logger.info("No reports found in database");
        return null;
      }

      const result = {
        id: lastReport.id,
        blockNumber: lastReport.blockNumber,
        timestamp: lastReport.timestamp,
        transactionHash: lastReport.transactionHash,
        newEpoch: lastReport.newEpoch.toString(),
        newHandledEpochLen: lastReport.newHandledEpochLen.toString(),
        totalSupply: this.formatBigIntToDecimal(lastReport.totalSupply),
        totalAssets: this.formatBigIntToDecimal(lastReport.totalAssets),
        managementFeeShares: this.formatBigIntToDecimal(
          lastReport.managementFeeShares
        ),
        performanceFeeShares: this.formatBigIntToDecimal(
          lastReport.performanceFeeShares
        ),
      };

      this.logger.info("Successfully fetched last report", {
        reportId: result.id,
        blockNumber: result.blockNumber,
        epoch: result.newEpoch,
      });

      return result;
    } catch (error) {
      this.logger.error("Failed to get last report", error);
      throw error;
    }
  }

  public async getRedeemById(redeemId: string) {
    try {
      this.logger.info("Fetching redeem by ID", { redeemId });

      const redeemRequested =
        await this.prismaService.redeemRequested.findUnique({
          where: { redeemId: BigInt(redeemId) },
        });

      if (!redeemRequested) {
        this.logger.info("Redeem request not found", { redeemId });
        return null;
      }

      const redeemClaimed = await this.prismaService.redeemClaimed.findUnique({
        where: { redeemId: BigInt(redeemId) },
      });

      // Get current due assets from the contract (only if not claimed yet)
      let currentDueAssets: bigint | null = null;
      if (!redeemClaimed) {
        try {
          const vaultAddress = this.configService.get(
            "VAULT_ADDRESS"
          ) as string;
          currentDueAssets =
            await this.starknetService.vault_due_assets_from_id(
              vaultAddress,
              Number(redeemId)
            );
          this.logger.debug("Fetched current due assets from contract", {
            redeemId,
            dueAssets: currentDueAssets?.toString(),
          });
        } catch (error) {
          this.logger.warn("Failed to fetch due assets for redeem ID", {
            redeemId,
            error: error.message,
          });
        }
      }

      const result = {
        redeemId: redeemRequested.redeemId.toString(),
        owner: redeemRequested.owner,
        receiver: redeemRequested.receiver,
        epoch: redeemRequested.epoch.toString(),
        sharesBurn: this.formatBigIntToDecimal(redeemRequested.shares),
        nominal: this.formatBigIntToDecimal(redeemRequested.assets),
        assets: currentDueAssets
          ? this.formatBigIntToDecimal(currentDueAssets)
          : null,
        requestTimestamp: redeemRequested.timestamp,
        requestTransactionHash: redeemRequested.transactionHash,
        claimedTimestamp: redeemClaimed?.timestamp,
        claimedTransactionHash: redeemClaimed?.transactionHash,
        claimedAssets: redeemClaimed
          ? this.formatBigIntToDecimal(redeemClaimed.assets)
          : null,
      };

      this.logger.info("Successfully fetched redeem details", {
        redeemId,
        isClaimed: !!redeemClaimed,
        owner: result.owner,
      });

      return result;
    } catch (error) {
      this.logger.error("Failed to get redeem by ID", error, { redeemId });
      throw error;
    }
  }

  formatBigIntToDecimal = (value: bigint): string => {
    return new Decimal(value.toString())
      .div(new Decimal(10).pow(this.strategyDecimals))
      .toString();
  };
}
