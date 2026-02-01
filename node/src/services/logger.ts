// src/services/logger.ts — structured logging for backend
import { Logger } from 'tslog';

export const logger = new Logger({
  name: 'clonar-backend',
  minLevel: 'info',
  prettyLogTemplate: '{{yyyy}}-{{mm}}-{{dd}} {{hh}}:{{MM}}:{{ss}} {{logLevelName}} ',
  type: 'pretty',
});
