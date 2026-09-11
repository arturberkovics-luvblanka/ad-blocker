importScripts("advanced-background-runtime.js");

const MODELED_NATIVE_DELAY_MS = 1500;
const CORE_SCRIPTLETS = [
  { name: "set-constant", args: ["ytInitialPlayerResponse.adPlacements", "undefined"] },
  { name: "set-constant", args: ["ytInitialPlayerResponse.adSlots", "undefined"] },
  { name: "set-constant", args: ["ytInitialPlayerResponse.playerAds", "undefined"] },
  { name: "set-constant", args: ["playerResponse.adPlacements", "undefined"] },
];

browser.runtime.onMessage.addListener(async (message, sender) => {
  if (message?.type !== "apply-delayed-core-youtube-rules") return undefined;

  const tabId = sender.tab?.id;
  const frameId = sender.frameId;
  const senderDocumentId = sender.documentId;
  if (!Number.isInteger(tabId) || frameId !== 0 || typeof senderDocumentId !== "string") {
    return { error: "unexpected_sender" };
  }

  const delayStartedAt = Date.now();
  await new Promise(resolve => setTimeout(resolve, MODELED_NATIVE_DELAY_MS));
  const delayFinishedAt = Date.now();

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
        scriptlets: CORE_SCRIPTLETS,
        engineTimestamp: 1,
      },
    );

    const late = await browser.scripting.executeScript({
      target: { tabId, documentIds: [senderDocumentId] },
      world: "MAIN",
      injectImmediately: true,
      func: () => {
        const earlyDescriptors = globalThis.__earlyYoutubeDescriptors;
        const currentYtDescriptor = Object.getOwnPropertyDescriptor(
          globalThis, "ytInitialPlayerResponse",
        );
        const currentPlayerDescriptor = Object.getOwnPropertyDescriptor(
          globalThis, "playerResponse",
        );
        const accessor = descriptor => typeof descriptor?.get === "function"
          && typeof descriptor?.set === "function";
        const descriptorsStable = accessor(earlyDescriptors?.ytInitialPlayerResponse)
          && accessor(earlyDescriptors?.playerResponse)
          && earlyDescriptors.ytInitialPlayerResponse.get === currentYtDescriptor?.get
          && earlyDescriptors.ytInitialPlayerResponse.set === currentYtDescriptor?.set
          && earlyDescriptors.playerResponse.get === currentPlayerDescriptor?.get
          && earlyDescriptors.playerResponse.set === currentPlayerDescriptor?.set;

        globalThis.ytInitialPlayerResponse = {
          adPlacements: ["late-ad-placement"],
          adSlots: ["late-ad-slot"],
          playerAds: ["late-player-ad"],
          videoDetails: { videoId: "late-video" },
          streamingData: { formats: ["late-format"] },
        };
        globalThis.playerResponse = {
          adPlacements: ["late-player-response-ad"],
          videoDetails: { videoId: "late-player-response-video" },
          streamingData: { serverAbrStreamingUrl: "https://media.invalid/late" },
        };

        return {
          descriptorsStable,
          reassignmentSnapshot: JSON.parse(JSON.stringify({
            ytInitialPlayerResponse: globalThis.ytInitialPlayerResponse,
            playerResponse: globalThis.playerResponse,
          })),
        };
      },
    });

    return {
      modeledNativeDelayMs: MODELED_NATIVE_DELAY_MS,
      observedModeledDelayMs: delayFinishedAt - delayStartedAt,
      totalBackgroundMs: Date.now() - delayStartedAt,
      senderDocumentId,
      frameDocumentId: frame.documentId,
      injectionDocumentId: late[0]?.documentId ?? null,
      lateResult: late[0]?.result ?? null,
      runtimeRevision: Runtime.revision ?? null,
    };
  } catch (error) {
    return { error: String(error) };
  }
});
