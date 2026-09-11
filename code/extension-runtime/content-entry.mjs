import {
  ContentScript,
  ConsoleLogger,
  LoggingLevel,
  setLogger,
  setupDelayedEventDispatcher,
} from "../vendor/SafariConverterLib/Extension/src/index.ts";

setLogger(new ConsoleLogger("[Ad Blocker]", LoggingLevel.Error));

export { ContentScript, setupDelayedEventDispatcher };
