(() => {
  browser.runtime.sendMessage({ type: "apply-delayed-core-youtube-rules" }).then(
    reply => {
      document.documentElement.dataset.earlyYoutubeFixReply = JSON.stringify(reply);
    },
    error => {
      document.documentElement.dataset.earlyYoutubeFixReply = JSON.stringify({ error: String(error) });
    },
  );
})();
