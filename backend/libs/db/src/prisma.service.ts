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
    const latest = await this.redeemRequested.findFirst({
      orderBy: { blockNumber: "desc" },
    });
    return latest as RedeemRequested | undefined;
  }

  async fetchLastReport(): Promise<Report | undefined> {
    const latest = await this.report.findFirst({
      orderBy: { blockNumber: "desc" },
    });
    return latest as Report | undefined;
  }

  async fetchLastReports(limit: number, offset?: number): Promise<Report[]> {
    const reports = await this.report.findMany({
      orderBy: { blockNumber: "desc" },
      take: limit,
      ...(offset && { skip: offset }),
    });
    return reports as Report[];
  }

  async fetchLastRedeemClaimed(): Promise<RedeemClaimed | undefined> {
    const latest = await this.redeemClaimed.findFirst({
      orderBy: { blockNumber: "desc" },
    });
    return latest as RedeemClaimed | undefined;
  }


  public async fetchPendingRedeemsForAddress(
    receiver: string,
    limit?: number,
    offset?: number
  ): Promise<RedeemRequested[]> {
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
  }
}
