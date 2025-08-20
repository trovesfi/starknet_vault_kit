import { plainToClass, Transform } from "class-transformer";
import { IsNumber, IsOptional, validateSync, IsString } from "class-validator";

export class EnvironmentVariables {
  @IsOptional()
  @IsNumber()
  @Transform(({ value }) => Number(value))
  PORT = 3000;

  @IsString()
  STARKNET_RPC_URL: string;

  @IsString()
  APIBARA_TOKEN: string;
}

export function validate(config: Record<string, unknown>) {
  const validatedConfig = plainToClass(EnvironmentVariables, config);

  const validatorOptions = { skipMissingProperties: false };
  const errors = validateSync(validatedConfig, validatorOptions);

  if (errors.length > 0) {
    console.error(errors.toString());
    process.exit(1);
  }

  return validatedConfig;
}
