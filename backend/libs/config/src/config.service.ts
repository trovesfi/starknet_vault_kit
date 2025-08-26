import { ConfigService as ConfigServiceSource } from "@nestjs/config";

export class ConfigService extends ConfigServiceSource {
  public get(key: string): string | number | undefined {
    return super.get(key, { infer: true });
  }
}
