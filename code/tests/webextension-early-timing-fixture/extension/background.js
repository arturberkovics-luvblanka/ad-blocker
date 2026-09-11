importScripts("advanced-background-runtime.js");

const MODELED_NATIVE_DELAY_MS = 1500;

browser.runtime.onMessage.addListener(async (message, sender) => {
  if (message?.type !== "apply-modeled-delayed-rules") return undefined;

  const tabId = sender.tab?.id;
  const frameId = sender.frameId;
  const senderDocumentId = sender.documentId;
  if (!Number.isInteger(tabId) || !Number.isInteger(frameId) || typeof senderDocumentId !== "string") {
    return { error: "missing_sender_identity" };
  }

  const delayStartedAt = Date.now();
  await new Promise(resolve => setTimeout(resolve, MODELED_NATIVE_DELAY_MS));

  try {
    const frame = await browser.webNavigation.getFrame({ tabId, frameId });
    if (frame?.documentId !== senderDocumentId) {
      return { error: "document_changed_during_modeled_delay" };
    }

    const Runtime = globalThis.AdBlockerAdvancedRuntime;
    if (typeof Runtime?.DocumentBackgroundScript !== "function") {
      return { error: "missing_advanced_background_runtime" };
    }
    await new Runtime.DocumentBackgroundScript(Runtime.registeredScripts).applyConfiguration(
      tabId,
      senderDocumentId,
      {
        css: [],
        extendedCss: [],
        js: [],
        scriptlets: [{ name: "set-constant", args: ["google_ad_status", "1"] }],
        engineTimestamp: 1,
      },
    );

    const late = await browser.scripting.executeScript({
      target: { tabId, documentIds: [senderDocumentId] },
      world: "MAIN",
      injectImmediately: true,
      func: () => {
        globalThis.__timingLateSnapshot = {
          googleAdStatus: globalThis.google_ad_status,
          timestamp: performance.now(),
        };
        return globalThis.__timingLateSnapshot;
      },
    });

    return {
      modeledNativeDelayMs: MODELED_NATIVE_DELAY_MS,
      observedDelayMs: Date.now() - delayStartedAt,
      senderDocumentId,
      frameDocumentId: frame.documentId,
      injectionDocumentId: late[0]?.documentId ?? null,
      lateSnapshot: late[0]?.result ?? null,
      runtimeRevision: Runtime.revision ?? null,
    };
  } catch (error) {
    return { error: String(error) };
  }
});
