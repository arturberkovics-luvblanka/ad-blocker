(() => {
  const publish = value => {
    const encoded = JSON.stringify(value);
    if (document.documentElement) {
      document.documentElement.dataset.webExtensionReply = encoded;
      return;
    }
    document.addEventListener("DOMContentLoaded", () => {
      document.documentElement.dataset.webExtensionReply = encoded;
    }, { once: true });
  };

  browser.runtime.sendMessage({ type: "document-ready" }).then(
    reply => publish(reply),
    error => publish({ error: String(error) }),
  );
})();
