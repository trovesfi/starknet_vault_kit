import "reflect-metadata";
import { ConfigService, validate } from "@forge/config";
import { PrismaService } from "@forge/db";
import { IndexerService } from "./indexer.service";

async function bootstrap() {
  // Validate environment variables
  const config = validate(process.env);
  
  // Create services
  const configService = new ConfigService({});
  const prismaService = new PrismaService();
  
  // Connect to database
  await prismaService.$connect();
  
  console.log("🔥 Starting StarkNet Vault Kit Indexer...");
  
  // Create and start indexer
  const indexer = new IndexerService(configService, prismaService);
  
  try {
    await indexer.run();
  } catch (error) {
    console.error("❌ Indexer failed:", error);
    await prismaService.$disconnect();
    process.exit(1);
  }
}

bootstrap().catch((error) => {
  console.error("❌ Bootstrap failed:", error);
  process.exit(1);
});