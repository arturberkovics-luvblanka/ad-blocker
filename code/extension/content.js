"use strict";

(() => {
const CONTENT_RUNTIME_GUARD = "__adBlockerContentRuntimeV1";
if (globalThis[CONTENT_RUNTIME_GUARD]?.initialized === true
    || typeof globalThis.adguard?.contentScript?.applyConfiguration === "function") {
  return;
}
globalThis[CONTENT_RUNTIME_GUARD] = { initialized: true, version: "0.0.1" };

const ADVANCED_GENERATION = "fc68ee1ce9fa6a7eabd48a644785d45c87afb403931e9b6dcb1efadb292a873c";
// Capture this document's runtime before a later extension update can replace it.
const RUNTIME_REVISION = globalThis.AdBlockerAdvancedRuntime?.revision;
let advancedState = { phase: "starting" };

// A handshake proves script access only, never native blocking or total protection.
browser.runtime.onMessage.addListener(message => {
  if (message?.type === "adblocker:status") {
    return Promise.resolve({
      version: "0.0.1", generation: ADVANCED_GENERATION,
      runtimeRevision: RUNTIME_REVISION,
      scriptAvailable: true, advanced: advancedState,
    });
  }
  return undefined;
});

async function startAdvancedRules() {
  const Runtime = globalThis.AdBlockerAdvancedRuntime;
  if (typeof Runtime?.ContentScript !== "function"
      || typeof Runtime?.setupDelayedEventDispatcher !== "function") {
    advancedState = { phase: "error", error: "runtime_unavailable" };
    publishFixtureState();
    return;
  }

  globalThis.adguard = { contentScript: new Runtime.ContentScript() };
  const releaseDelayedEvents = Runtime.setupDelayedEventDispatcher(1000);
  const requestedUrl = location.href;
  const requestedAt = Date.now();
  try {
    const response = await browser.runtime.sendMessage({ type: "lookup" });
    const lookupMilliseconds = Date.now() - requestedAt;
    if (response?.generation !== ADVANCED_GENERATION) throw new Error("generation_mismatch");
    if (typeof response.error === "string") throw new Error(response.error);
    if (response.applyInContent === true) {
      if (location.href !== requestedUrl) throw new Error("stale_navigation");
      globalThis.adguard.contentScript.applyConfiguration(response.payload);
      advancedState = {
        phase: "content_attempted_unverified",
        limitations: response.limitations ?? [],
        lookupMilliseconds,
        responseAfterDelayWindow: lookupMilliseconds > 1000,
      };
    } else {
      advancedState = {
        phase: response.delivery ?? "ready",
        limitations: response.limitations ?? [],
        lookupMilliseconds,
        responseAfterDelayWindow: lookupMilliseconds > 1000,
      };
    }
  } catch (error) {
    advancedState = {
      phase: "error",
      error: error instanceof Error ? error.message : "lookup_failed",
      lookupMilliseconds: Date.now() - requestedAt,
    };
  } finally {
    releaseDelayedEvents();
    publishFixtureState();
  }
}

function isFixturePage() {
  return location.origin === "http://127.0.0.1:8765" && location.pathname === "/";
}

function publishFixtureState() {
  if (!isFixturePage()) return;
  const markFixture = () => {
    document.documentElement.dataset.adBlockerExtension = "0.0.1";
    document.documentElement.dataset.adBlockerAdvancedPhase = advancedState.phase;
    document.documentElement.dataset.adBlockerRuntimeRevision = RUNTIME_REVISION ?? "";
    document.documentElement.dataset.adBlockerAdvancedError = advancedState.error ?? "";
    document.documentElement.dataset.adBlockerAdvancedLimitations = (
      advancedState.limitations ?? []
    ).join(",");
    document.documentElement.dataset.adBlockerLookupMilliseconds = String(
      advancedState.lookupMilliseconds ?? "",
    );
  };
  if (document.documentElement) markFixture();
  else document.addEventListener("DOMContentLoaded", markFixture, { once: true });
}

// The production web is not mutated by this diagnostic layer.
publishFixtureState();
void startAdvancedRules();
})();
