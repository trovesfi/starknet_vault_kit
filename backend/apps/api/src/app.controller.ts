import { Controller, Get } from "@nestjs/common";
import { ApiTags, ApiResponse } from "@nestjs/swagger";
import { AppService } from "./app.service";

@ApiTags("health")
@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  @ApiResponse({ status: 200, description: "Health check endpoint" })
  getHello(): string {
    return this.appService.getHello();
  }

  @Get("health")
  @ApiResponse({ status: 200, description: "Application health status" })
  getHealth() {
    return {
      status: "ok",
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
    };
  }
}