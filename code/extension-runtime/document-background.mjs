import { scriptlets as ScriptletsAPI } from "../vendor/SafariConverterLib/Extension/node_modules/@adguard/scriptlets/dist/index.js";
import { SCRIPTLET_ENGINE_NAME } from "../vendor/SafariConverterLib/Extension/src/common.ts";
import extensionPackage from "../vendor/SafariConverterLib/Extension/package.json";
import { earlyScriptletUniqueId } from "./early-youtube-policy.mjs";

function injectionTarget(tabId, documentId) {
  return { tabId, documentIds: [documentId] };
}

async function executeScript(tabId, documentId, options) {
  const results = await browser.scripting.executeScript({
    ...options,
    target: injectionTarget(tabId, documentId),
    injectImmediately: true,
  });
  if (results.length !== 1) throw new Error("Missing injection result");
  const [result] = results;
  if (result.documentId !== undefined && result.documentId !== documentId) {
    throw new Error("Injection reached a different document");
  }
  if (result.error || result.result === false) throw new Error("Script injection failed");
}

export class DocumentBackgroundScript {
  constructor(registeredScripts = new Map()) {
    this.registeredScripts = registeredScripts;
  }

  async applyConfiguration(tabId, documentId, configuration) {
    await Promise.all([
      this.insertCss(tabId, documentId, configuration.css),
      this.insertExtendedCss(tabId, documentId, configuration.extendedCss),
      this.runScripts(tabId, documentId, configuration.js),
      this.runScriptlets(tabId, documentId, configuration.scriptlets),
    ]);
  }

  async insertCss(tabId, documentId, css) {
    if (css.length === 0) return;
    await executeScript(tabId, documentId, {
      func: (rules = []) => {
        try {
          adguard.contentScript.insertCss(rules);
          return true;
        } catch {
          return false;
        }
      },
      args: [css],
      world: "ISOLATED",
    });
  }

  async insertExtendedCss(tabId, documentId, extendedCss) {
    if (extendedCss.length === 0) return;
    await executeScript(tabId, documentId, {
      func: (rules = []) => {
        try {
          adguard.contentScript.insertExtendedCss(rules);
          return true;
        } catch {
          return false;
        }
      },
      args: [extendedCss],
      world: "ISOLATED",
    });
  }

  async runScripts(tabId, documentId, scripts) {
    for (const script of scripts) {
      const registered = this.registeredScripts.get(script);
      if (registered) {
        await executeScript(tabId, documentId, { func: registered, world: "MAIN" });
      } else {
        await executeScript(tabId, documentId, {
          func: (source = []) => {
            try {
              adguard.contentScript.runScripts(source);
              return true;
            } catch {
              return false;
            }
          },
          args: [[script]],
          world: "ISOLATED",
        });
      }
    }
  }

  async runScriptlets(tabId, documentId, scriptlets) {
    for (const scriptlet of scriptlets) {
      const scriptletFunction = ScriptletsAPI.getScriptletFunction(scriptlet.name);
      if (!scriptletFunction) throw new Error(`Unknown scriptlet: ${scriptlet.name}`);
      const source = {
        engine: SCRIPTLET_ENGINE_NAME,
        name: scriptlet.name,
        args: scriptlet.args,
        version: extensionPackage.version,
        verbose: false,
        uniqueId: earlyScriptletUniqueId(
          scriptlet, globalThis.AdBlockerAdvancedRuntime?.revision,
        ),
      };
      await executeScript(tabId, documentId, {
        func: scriptletFunction,
        args: [source, scriptlet.args],
        world: "MAIN",
      });
    }
  }
}
