import { Injectable, OnModuleInit, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient, RedeemClaimed } from "@prisma/client";
import { Report, RedeemRequested } from "@prisma/client";

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }

  async fetchLastRedeemRequested(): Promise<RedeemRequested | undefined> {
    try {
      const latest = await this.redeemRequested.findFirst({
        orderBy: { blockNumber: "desc" },
      });
      return latest as RedeemRequested | undefined;
    } catch (error) {
      // Table doesn't exist yet, return undefined
      return undefined;
    }
  }

  async fetchLastReport(): Promise<Report | undefined> {
    try {
      const latest = await this.report.findFirst({
        orderBy: { blockNumber: "desc" },
      });
      return latest as Report | undefined;
    } catch (error) {
      // Table doesn't exist yet, return undefined
      return undefined;
    }
  }

  async fetchLastReports(limit: number, offset?: number): Promise<Report[]> {
    try {
      const reports = await this.report.findMany({
        orderBy: { blockNumber: "desc" },
        take: limit,
        ...(offset && { skip: offset }),
      });
      return reports as Report[];
    } catch (error) {
      // Table doesn't exist yet, return empty array
      return [];
    }
  }

  async fetchLastRedeemClaimed(): Promise<RedeemClaimed | undefined> {
    try {
      const latest = await this.redeemClaimed.findFirst({
        orderBy: { blockNumber: "desc" },
      });
      return latest as RedeemClaimed | undefined;
    } catch (error) {
      // Table doesn't exist yet, return undefined
      return undefined;
    }
  }


  public async fetchPendingRedeemsForAddress(
    receiver: string,
    limit?: number,
    offset?: number
  ): Promise<RedeemRequested[]> {
    try {
      // Get all claimed redeem IDs for this address
      const claimedRedeemIds = await this.redeemClaimed.findMany({
        where: { receiver },
        select: { redeemId: true },
      });
      
      const claimedIds = claimedRedeemIds.map(r => r.redeemId);
      
      // Find all requested redeems that are NOT in the claimed list
      return this.redeemRequested.findMany({
        where: {
          receiver,
          redeemId: {
            notIn: claimedIds,
          },
        },
        orderBy: {
          redeemId: "desc",
        },
        ...(limit && { take: limit }),
        ...(offset && { skip: offset }),
      });
    } catch (error) {
      // Tables don't exist yet, return empty array
      return [];
    }
  }
}
