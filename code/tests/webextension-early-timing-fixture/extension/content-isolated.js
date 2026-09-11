(() => {
  browser.runtime.sendMessage({ type: "apply-modeled-delayed-rules" }).then(
    reply => {
      document.documentElement.dataset.timingBackgroundReply = JSON.stringify(reply);
    },
    error => {
      document.documentElement.dataset.timingBackgroundReply = JSON.stringify({ error: String(error) });
    },
  );
})();
