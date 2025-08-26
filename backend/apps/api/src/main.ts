import { NestFactory } from "@nestjs/core";
import { ValidationPipe } from "@nestjs/common";
import { SwaggerModule, DocumentBuilder } from "@nestjs/swagger";
import { validateApiConfig } from "@forge/config";
import { Logger, LogLevel, LoggerConfig } from "@forge/logger";
import { AppModule } from "./app.module";

async function bootstrap() {
  // Configure global logger
  const loggerConfig: LoggerConfig = {
    level: (process.env.LOG_LEVEL as LogLevel) || LogLevel.INFO,
    service: "vault-api",
    enableConsole: true,
    enableFile: process.env.NODE_ENV === "production",
    logDir: process.env.LOG_DIR || "logs",
    format: process.env.NODE_ENV === "production" ? "json" : "simple",
  };

  Logger.configure(loggerConfig);
  const logger = Logger.create("Bootstrap");

  try {
    // Validate environment variables
    const envConfig = validateApiConfig(process.env);
    logger.info("Environment configuration validated successfully");

    const app = await NestFactory.create(AppModule);

    // Configure global validation pipes
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      })
    );
    logger.info("Global validation pipes configured");

    // Enable CORS
    app.enableCors();
    logger.info("CORS enabled");

    // Setup Swagger documentation
    const config = new DocumentBuilder()
      .setTitle("StarkNet Vault Kit API")
      .setDescription("API for StarkNet Vault Kit indexer and services")
      .setVersion("1.0")
      .build();

    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup("api", app, document);
    logger.info("Swagger documentation configured at /api");

    const port = process.env.PORT || 3000;
    await app.listen(port);

    logger.info("🚀 StarkNet Vault Kit API started successfully", {
      port,
      environment: process.env.NODE_ENV || "development",
      apiUrl: `http://localhost:${port}`,
      docsUrl: `http://localhost:${port}/api`,
    });
  } catch (error) {
    logger.error("❌ Failed to start API server", error);
    process.exit(1);
  }
}

bootstrap();
