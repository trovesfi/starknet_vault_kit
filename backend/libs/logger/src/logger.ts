export class Logger {
  private context: string;

  constructor(context?: string) {
    this.context = context || 'Application';
  }

  log(message: string, ...optionalParams: any[]) {
    console.log(`[${this.context}] ${message}`, ...optionalParams);
  }

  error(message: string, ...optionalParams: any[]) {
    console.error(`[${this.context}] ${message}`, ...optionalParams);
  }

  warn(message: string, ...optionalParams: any[]) {
    console.warn(`[${this.context}] ${message}`, ...optionalParams);
  }

  debug(message: string, ...optionalParams: any[]) {
    console.debug(`[${this.context}] ${message}`, ...optionalParams);
  }

  static create(context?: string): Logger {
    return new Logger(context);
  }
}