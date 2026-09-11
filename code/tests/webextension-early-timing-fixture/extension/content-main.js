(() => {
  globalThis.__timingManifestStart = {
    bodyExisted: document.body !== null,
    readyState: document.readyState,
    timestamp: performance.now(),
  };
})();
