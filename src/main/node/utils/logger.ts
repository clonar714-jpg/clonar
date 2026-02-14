import { Logger } from 'tslog';

export const logger = new Logger({
  name: 'clonar-backend',
  minLevel: 3, // info
  prettyLogTemplate: '{{yyyy}}-{{mm}}-{{dd}} {{hh}}:{{MM}}:{{ss}} {{logLevelName}} ',
  type: 'pretty',
});
