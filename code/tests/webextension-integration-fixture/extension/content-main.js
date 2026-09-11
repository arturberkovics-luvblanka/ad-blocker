(() => {
  globalThis.__webExtensionMainStart = {
    bodyExisted: document.body !== null,
    readyState: document.readyState,
    locationHref: location.href,
    windowName: window.name,
    daiAbsentBefore: typeof globalThis.google?.ima?.dai?.api?.StreamManager !== "function",
    events: ["manifest-main-document-start"],
    executeScriptRuns: 0,
  };
  document.addEventListener("DOMContentLoaded", () => {
    globalThis.__webExtensionMainStart.events.push("dom-content-loaded");
  }, { once: true });
})();
