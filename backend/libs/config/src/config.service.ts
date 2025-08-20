import { ConfigService as ConfigServiceSource } from "@nestjs/config";
import { EnvironmentVariables } from "./env.validation";

export class ConfigService extends ConfigServiceSource<EnvironmentVariables> {
  public get<T extends keyof EnvironmentVariables>(
    key: T
  ): EnvironmentVariables[T] {
    return super.get(key, { infer: true }) as EnvironmentVariables[T];
  }
}