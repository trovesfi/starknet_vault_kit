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

  async fetchLastRedeemClaimed(): Promise<RedeemClaimed | undefined> {
    const latest = await this.redeemClaimed.findFirst({
      orderBy: { blockNumber: "desc" },
    });
    return latest as RedeemClaimed | undefined;
  }
}