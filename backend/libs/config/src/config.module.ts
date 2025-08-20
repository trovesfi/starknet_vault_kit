import { Module } from "@nestjs/common";
import { ConfigModule as NestConfigModule } from "@nestjs/config";
import { ConfigService } from "./config.service";
import { validate } from "./env.validation";

@Module({
  imports: [
    NestConfigModule.forRoot({
      isGlobal: true,
      validate,
    }),
  ],
  providers: [ConfigService],
  exports: [ConfigService],
})
export class ConfigModule {}