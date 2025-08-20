import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { ConfigModule } from '@forge/config';
import { PrismaModule } from '@forge/db';
import { StarknetModule } from './starknet';
import { HealthModule } from './health';
import { AppController } from './app.controller';
import { AppService } from './app.service';

@Module({
  imports: [
    ConfigModule,
    ScheduleModule.forRoot(),
    PrismaModule,
    StarknetModule,
    HealthModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}