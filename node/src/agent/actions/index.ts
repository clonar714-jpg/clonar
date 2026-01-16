/**
 * ✅ PERPLEXICA-STYLE: Action Registration
 * Registers all research actions with the ActionRegistry
 */

import ActionRegistry from './registry';
import academicSearchAction from './academicSearchAction';
import doneAction from './doneAction';
import reasoningPreambleAction from './reasoningPreambleAction';
import scrapeURLAction from './scrapeURLAction';
import socialSearchAction from './socialSearchAction';
import uploadsSearchAction from './uploadsSearchAction';
import webSearchAction from './webSearchAction';

// Register all actions
ActionRegistry.register(doneAction);
ActionRegistry.register(academicSearchAction);
ActionRegistry.register(reasoningPreambleAction);
ActionRegistry.register(scrapeURLAction);
ActionRegistry.register(socialSearchAction);
ActionRegistry.register(uploadsSearchAction);
ActionRegistry.register(webSearchAction);

export { ActionRegistry };
export default ActionRegistry;

