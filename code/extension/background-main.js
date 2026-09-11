"use strict";

const ADVANCED_GENERATION = "6e45fc354371732ec243cb4b5b205b31a9fc8d219e1970bf021047c1f57b9b02";
const EXTENSION_VERSION = "0.0.2";
const NATIVE_APPLICATION_ID = "org.local.adblocker";
const requestSequence = new Map();

function webUrl(value) {
  if (typeof value !== "string" || value.length > 16384) return null;
  try {
    const url = new URL(value);
    if ((url.protocol !== "http:" && url.protocol !== "https:") || !url.hostname) return null;
    if (url.username || url.password) return null;
    return url.href;
  } catch {
    return null;
  }
}

function senderIdentity(sender) {
  const tabId = sender?.tab?.id;
  const frameId = sender?.frameId;
  if (!Number.isInteger(tabId) || tabId < 0 || !Number.isInteger(frameId) || frameId < 0) {
    return null;
  }
  return { tabId, frameId };
}

function documentId(value) {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value.toLowerCase()
    : null;
}

async function frameInfo(tabId, frameId) {
  return browser.webNavigation.getFrame({ tabId, frameId });
}

async function blankFrameUrls(tabId, frameId, expectedDocumentId) {
  const blankFrame = await frameInfo(tabId, frameId);
  if (documentId(blankFrame?.documentId) !== expectedDocumentId) return null;
  // Only reached for a browser-verified blank/srcdoc sender. Safari can omit
  // getFrame's URL for that same document; its ID and web parent still must match.
  if (!["", "about:blank", "about:srcdoc"].includes(blankFrame.url)) return null;

  const topFrame = await frameInfo(tabId, 0);
  const topUrl = webUrl(topFrame?.url);
  if (!topUrl) return null;

  const visited = new Set([frameId]);
  let parentFrameId = blankFrame?.parentFrameId;
  while (Number.isInteger(parentFrameId) && parentFrameId >= 0 && !visited.has(parentFrameId)) {
    visited.add(parentFrameId);
    const parent = await frameInfo(tabId, parentFrameId);
    const parentUrl = webUrl(parent?.url);
    if (parentUrl) return { url: parentUrl, topUrl };
    if (parent?.url !== "about:blank" && parent?.url !== "about:srcdoc") return null;
    parentFrameId = parent?.parentFrameId;
  }
  return null;
}

async function targetFromSender(sender) {
  const identity = senderIdentity(sender);
  if (!identity) return { error: "invalid_sender" };
  const senderDocumentId = documentId(sender.documentId);
  if (!senderDocumentId) return { error: "document_unavailable" };

  const senderUrl = webUrl(sender.url);
  const topUrl = identity.frameId === 0 ? undefined : webUrl(sender.tab.url);
  if (senderUrl) {
    return { ...identity, documentId: senderDocumentId, url: senderUrl, topUrl, blankFrame: false };
  }
  const supportedBlankFrame = sender.url === "about:blank" || sender.url === "about:srcdoc";
  if (identity.frameId > 0 && supportedBlankFrame) {
    const urls = await blankFrameUrls(identity.tabId, identity.frameId, senderDocumentId);
    if (!urls) return { error: "blank_origin_unverified" };
    return { ...identity, documentId: senderDocumentId, ...urls, blankFrame: true };
  }
  return { error: "invalid_sender" };
}

function validStringArray(value) {
  return Array.isArray(value) && value.every(item => typeof item === "string");
}

function validPayload(payload) {
  return payload !== null && typeof payload === "object"
    && validStringArray(payload.css)
    && validStringArray(payload.extendedCss)
    && validStringArray(payload.js)
    && Array.isArray(payload.scriptlets)
    && payload.scriptlets.every(scriptlet => scriptlet !== null
      && typeof scriptlet === "object"
      && typeof scriptlet.name === "string"
      && validStringArray(scriptlet.args))
    && Number.isFinite(payload.engineTimestamp);
}

function hasRules(payload) {
  return payload.css.length > 0 || payload.extendedCss.length > 0
    || payload.js.length > 0 || payload.scriptlets.length > 0;
}

function limitations(payload) {
  return payload.css.length > 0 ? ["css_origin_limited"] : [];
}

async function currentTargetMatches(target) {
  const current = await frameInfo(target.tabId, target.frameId);
  if (documentId(current?.documentId) !== target.documentId) return false;
  if (!target.blankFrame) return webUrl(current?.url) === target.url;
  const urls = await blankFrameUrls(target.tabId, target.frameId, target.documentId);
  return urls?.url === target.url && urls.topUrl === target.topUrl;
}

async function handleLookup(message, sender) {
  const identity = senderIdentity(sender);
  if (!identity) return { generation: ADVANCED_GENERATION, error: "invalid_sender" };
  const key = `${identity.tabId}:${identity.frameId}`;
  const sequence = (requestSequence.get(key) ?? 0) + 1;
  requestSequence.set(key, sequence);

  let target;
  try {
    target = await targetFromSender(sender);
  } catch {
    return { generation: ADVANCED_GENERATION, error: "navigation_unverified" };
  }
  if (requestSequence.get(key) !== sequence) {
    return { generation: ADVANCED_GENERATION, error: "stale_navigation" };
  }
  if (target.error) return { generation: ADVANCED_GENERATION, error: target.error };

  let response;
  try {
    response = await browser.runtime.sendNativeMessage(NATIVE_APPLICATION_ID, {
      type: "lookup",
      url: target.url,
      ...(target.topUrl ? { topUrl: target.topUrl } : {}),
    });
  } catch {
    return { generation: ADVANCED_GENERATION, error: "native_lookup_failed" };
  }

  if (requestSequence.get(key) !== sequence) {
    return { generation: ADVANCED_GENERATION, error: "stale_navigation" };
  }
  if (response?.generation !== ADVANCED_GENERATION) {
    return { generation: ADVANCED_GENERATION, error: "generation_mismatch" };
  }
  if (typeof response.error === "string") {
    return { generation: ADVANCED_GENERATION, error: response.error };
  }
  if (!validPayload(response.payload)) {
    return { generation: ADVANCED_GENERATION, error: "invalid_payload" };
  }

  try {
    if (!(await currentTargetMatches(target))) {
      return { generation: ADVANCED_GENERATION, error: "stale_navigation" };
    }
  } catch {
    return { generation: ADVANCED_GENERATION, error: "navigation_unverified" };
  }
  if (requestSequence.get(key) !== sequence) {
    return { generation: ADVANCED_GENERATION, error: "stale_navigation" };
  }

  if (!hasRules(response.payload)) {
    return {
      generation: ADVANCED_GENERATION,
      payload: response.payload,
      delivery: "no_matching_rules",
    };
  }
  if (target.blankFrame) {
    return {
      generation: ADVANCED_GENERATION,
      payload: response.payload,
      applyInContent: true,
      delivery: "content_attempt_required",
      limitations: limitations(response.payload),
    };
  }

  try {
    const Runtime = globalThis.AdBlockerAdvancedRuntime;
    if (typeof Runtime?.DocumentBackgroundScript !== "function") throw new Error("Missing runtime");
    await new Runtime.DocumentBackgroundScript(Runtime.registeredScripts).applyConfiguration(
      target.tabId,
      target.documentId,
      response.payload,
    );
  } catch {
    return { generation: ADVANCED_GENERATION, error: "apply_failed" };
  }
  if (requestSequence.get(key) !== sequence) {
    return { generation: ADVANCED_GENERATION, error: "stale_navigation" };
  }

  // The upstream runtime can log and swallow individual injection errors.
  // Report the attempt without claiming that every rule became active.
  return {
    generation: ADVANCED_GENERATION,
    payload: response.payload,
    delivery: "background_attempted_unverified",
    limitations: limitations(response.payload),
  };
}

function validSelfTestEvidence(value) {
  return value !== null && typeof value === "object"
    && value.generation === ADVANCED_GENERATION
    && value.runtimeRevision === globalThis.AdBlockerAdvancedRuntime?.revision
    && value.advancedPhase === "background_attempted_unverified"
    && value.advancedError === "";
}

async function handleSelfTest(message, sender) {
  if (typeof message?.nonce !== "string" || !/^[0-9a-f]{64}$/.test(message.nonce)
      || !validSelfTestEvidence(message.evidence)) {
    return { accepted: false };
  }
  let target;
  try {
    target = await targetFromSender(sender);
  } catch {
    return { accepted: false };
  }
  if (target.error || target.frameId !== 0) return { accepted: false };
  try {
    if (!(await currentTargetMatches(target))) return { accepted: false };
  } catch {
    return { accepted: false };
  }
  const url = new URL(target.url);
  if (url.protocol !== "http:" || url.hostname !== "127.0.0.1"
      || url.username || url.password
      || url.pathname !== `/session/${message.nonce}/`
      || url.search || url.hash) {
    return { accepted: false };
  }
  const reportURL = new URL(`session/${message.nonce}/extension-report`, url.origin + "/");
  const report = {
    schema: 1,
    nonce: message.nonce,
    extensionVersion: EXTENSION_VERSION,
    generation: ADVANCED_GENERATION,
    runtimeRevision: globalThis.AdBlockerAdvancedRuntime?.revision ?? "",
    contentGeneration: message.evidence.generation,
    contentRuntimeRevision: message.evidence.runtimeRevision,
    advancedPhase: message.evidence.advancedPhase,
    advancedError: message.evidence.advancedError,
  };
  try {
    const response = await fetch(reportURL.href, {
      method: "POST",
      cache: "no-store",
      credentials: "omit",
      headers: { "Content-Type": "text/plain;charset=UTF-8" },
      body: JSON.stringify(report),
    });
    return { accepted: response.ok };
  } catch {
    return { accepted: false };
  }
}

browser.runtime.onMessage.addListener((message, sender) => {
  if (message?.type === "adblocker:metadata") {
    return Promise.resolve({
      generation: ADVANCED_GENERATION,
      runtimeRevision: globalThis.AdBlockerAdvancedRuntime?.revision,
    });
  }
  if (message?.type === "adblocker:selftest") return handleSelfTest(message, sender);
  if (message?.type !== "lookup") return undefined;
  return handleLookup(message, sender);
});

browser.tabs.onRemoved?.addListener(tabId => {
  for (const key of requestSequence.keys()) {
    if (key.startsWith(`${tabId}:`)) requestSequence.delete(key);
  }
});
