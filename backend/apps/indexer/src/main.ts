import "reflect-metadata";
import { ConfigService, validateIndexerConfig } from "@forge/config";
import { PrismaService } from "@forge/db";
import { Logger, LogLevel, LoggerConfig } from "@forge/logger";
import { IndexerService } from "./indexer.service";

async function bootstrap() {
  // Configure global logger
  const loggerConfig: LoggerConfig = {
    level: (process.env.LOG_LEVEL as LogLevel) || LogLevel.INFO,
    service: 'vault-indexer',
    enableConsole: true,
    enableFile: process.env.NODE_ENV === 'production',
    logDir: process.env.LOG_DIR || 'logs',
    format: process.env.NODE_ENV === 'production' ? 'json' : 'simple',
  };
  
  Logger.configure(loggerConfig);
  const logger = Logger.create('Bootstrap');

  try {
    // Validate environment variables
    const config = validateIndexerConfig(process.env);
    logger.info('Environment configuration validated successfully');

    // Create services
    const configService = new ConfigService({});
    const prismaService = new PrismaService();

    // Connect to database
    await prismaService.$connect();
    logger.info('Database connection established');

    logger.info('🔥 Starting StarkNet Vault Kit Indexer...');

    // Create and start indexer
    const indexer = new IndexerService(configService, prismaService);

    await indexer.run();
  } catch (error) {
    logger.error('❌ Indexer failed', error);
    
    // Attempt graceful cleanup
    try {
      const prismaService = new PrismaService();
      await prismaService.$disconnect();
      logger.info('Database connection closed gracefully');
    } catch (cleanupError) {
      logger.error('Failed to cleanup database connection', cleanupError);
    }
    
    process.exit(1);
  }
}

bootstrap().catch((error) => {
  const logger = Logger.create('Bootstrap');
  logger.error('❌ Bootstrap failed', error);
  process.exit(1);
});
