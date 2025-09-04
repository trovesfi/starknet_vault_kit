import { Module } from '@nestjs/common';
import { ConfigModule } from '@forge/config';
import { PrismaModule } from '@forge/db';
import { StarknetModule } from '@forge/starknet';
import { IndexerService } from './indexer.service';

@Module({
  imports: [ConfigModule, PrismaModule, StarknetModule],
  providers: [IndexerService],
  exports: [IndexerService],
})
export class IndexerModule {}
