importScripts("advanced-background-runtime.js");

const committedDocuments = new Map();

browser.webNavigation.onCommitted.addListener(details => {
  committedDocuments.set(`${details.tabId}:${details.frameId}`, details);
});

function outcome(results) {
  const first = results?.[0];
  return {
    documentId: first?.documentId ?? null,
    error: first?.error ? String(first.error) : null,
    result: first?.result ?? null,
  };
}

async function attempt(options) {
  try {
    return outcome(await browser.scripting.executeScript(options));
  } catch (error) {
    return { documentId: null, error: String(error), result: null };
  }
}

browser.runtime.onMessage.addListener(async (message, sender) => {
  if (message?.type !== "document-ready") return undefined;

  const tabId = sender.tab?.id;
  const frameId = sender.frameId;
  const senderDocumentId = sender.documentId;
  if (!Number.isInteger(tabId) || !Number.isInteger(frameId) || typeof senderDocumentId !== "string") {
    return { error: "missing_sender_identity" };
  }

  const proof = {
    tabId,
    frameId,
    senderUrl: sender.url ?? null,
    senderDocumentId,
    frameDocumentId: null,
    parentFrameId: null,
    committedDocumentId: null,
    frameUrl: null,
    committedUrl: null,
    runtimeRevision: globalThis.AdBlockerAdvancedRuntime?.revision ?? null,
  };

  try {
    const frame = await browser.webNavigation.getFrame({ tabId, frameId });
    const committed = committedDocuments.get(`${tabId}:${frameId}`);
    Object.assign(proof, {
      frameDocumentId: frame?.documentId ?? null,
      parentFrameId: frame?.parentFrameId ?? null,
      committedDocumentId: committed?.documentId ?? null,
      frameUrl: frame?.url ?? null,
      committedUrl: committed?.url ?? null,
    });

    const target = { tabId, documentIds: [senderDocumentId] };
    const isolated = await attempt({
      target,
      world: "ISOLATED",
      injectImmediately: true,
      func: () => {
        document.documentElement.dataset.documentIsolatedReached = "true";
        return {
          locationHref: location.href,
          windowName: window.name,
          parserContent: document.getElementById("parser-content")?.textContent ?? null,
        };
      },
    });
    const mainBefore = await attempt({
      target,
      world: "MAIN",
      injectImmediately: true,
      func: () => {
        const state = globalThis.__webExtensionMainStart;
        if (state) {
          state.executeScriptRuns += 1;
          state.events.push("document-id-main-before-runtime");
        }
        return {
          stateMissing: !state,
          daiAbsentBefore: typeof globalThis.google?.ima?.dai?.api?.StreamManager !== "function",
          locationHref: location.href,
          windowName: window.name,
          parserContent: document.getElementById("parser-content")?.textContent ?? null,
        };
      },
    });

    const Runtime = globalThis.AdBlockerAdvancedRuntime;
    let runtimeError = null;
    if (typeof Runtime?.DocumentBackgroundScript !== "function") {
      runtimeError = "missing_advanced_background_runtime";
    } else {
      try {
        await new Runtime.DocumentBackgroundScript(Runtime.registeredScripts).applyConfiguration(
          tabId,
          senderDocumentId,
          {
            css: [],
            extendedCss: [],
            js: [],
            scriptlets: [{ name: "google-ima3-dai", args: [] }],
            engineTimestamp: 1,
          },
        );
      } catch (error) {
        runtimeError = String(error);
      }
    }

    const mainAfter = await attempt({
      target,
      world: "MAIN",
      injectImmediately: true,
      func: () => {
        const StreamManager = globalThis.google?.ima?.dai?.api?.StreamManager;
        let daiInstanceWorks = false;
        if (typeof StreamManager === "function") {
          try {
            daiInstanceWorks = new StreamManager(null, null, null).getAdSkippableState() === true;
          } catch {}
        }
        return {
          daiStreamManager: typeof StreamManager === "function",
          daiInstanceWorks,
          locationHref: location.href,
          windowName: window.name,
          parserContent: document.getElementById("parser-content")?.textContent ?? null,
        };
      },
    });

    return { ...proof, isolated, mainBefore, runtimeError, mainAfter };
  } catch (error) {
    return { ...proof, error: String(error) };
  }
});
