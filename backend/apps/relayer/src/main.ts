import "reflect-metadata";
import { ConfigService, validate } from "@forge/config";
import { PrismaService } from "@forge/db";
import { Logger } from "@forge/logger";
import { ExampleJob } from "./jobs/example-job";
import { SchedulerService } from "./services/scheduler.service";

async function bootstrap() {
  const logger = Logger.create("RelayerBootstrap");

  try {
    // Validate environment variables
    const config = validate(process.env);

    // Create services
    const configService = new ConfigService({});
    const prismaService = new PrismaService();

    // Connect to database
    await prismaService.$connect();
    logger.log("Connected to database");

    // Create jobs
    const exampleJob = new ExampleJob(prismaService);

    // Create and start scheduler
    const scheduler = new SchedulerService(exampleJob);

    logger.log("🔥 Starting StarkNet Vault Kit Relayer...");
    scheduler.start();

    // Handle graceful shutdown
    const gracefulShutdown = async (signal: string) => {
      logger.log(`Received ${signal}, shutting down gracefully...`);
      scheduler.stop();
      await prismaService.$disconnect();
      process.exit(0);
    };

    process.on("SIGINT", () => gracefulShutdown("SIGINT"));
    process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));

    logger.log("✅ Relayer started successfully");
  } catch (error) {
    logger.error("❌ Bootstrap failed:", error);
    process.exit(1);
  }
}

bootstrap();
