import { CronJob } from 'cron';
import { Logger } from "@forge/logger";
import { ExampleJob } from '../jobs/example-job';

export class SchedulerService {
  private logger = Logger.create('SchedulerService');
  private jobs: CronJob[] = [];

  constructor(private exampleJob: ExampleJob) {}

  start(): void {
    this.logger.log('Starting scheduler service...');

    // Example: run example job every 5 minutes
    const exampleJobCron = new CronJob(
      '*/5 * * * *',
      async () => {
        try {
          await this.exampleJob.execute();
        } catch (error) {
          this.logger.error('Example job failed:', error);
        }
      },
      null,
      false,
      'UTC'
    );

    this.jobs.push(exampleJobCron);
    
    // Start all jobs
    this.jobs.forEach(job => job.start());
    
    this.logger.log(`Started ${this.jobs.length} scheduled jobs`);
  }

  stop(): void {
    this.logger.log('Stopping scheduler service...');
    this.jobs.forEach(job => job.stop());
    this.jobs = [];
  }
}