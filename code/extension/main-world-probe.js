"use strict";

(() => {
if (location.origin !== "http://127.0.0.2:8765") return;
if (window.__adBlockerMainProbe?.version === "0.0.2") return;

window.__adBlockerMainProbe = {
  version: "0.0.2",
  startedAt: performance.now(),
  readyState: document.readyState,
};

function publishMainWorldProbe() {
  document.documentElement.dataset.adBlockerMainProbe = "ran";
  if (location.pathname === "/main-world-csp.html") {
    const result = document.getElementById("probe-result");
    if (result) result.textContent = "A statikus tesztscript lefutott a script-src 'none' CSP mellett.";
  }
}
if (document.documentElement) publishMainWorldProbe();
document.addEventListener("DOMContentLoaded", publishMainWorldProbe, { once: true });
})();
