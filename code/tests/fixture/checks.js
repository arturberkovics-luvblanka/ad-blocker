"use strict";
let count = 0;
document.getElementById("counter").addEventListener("click", event => {
  event.currentTarget.textContent = `Működő gomb: ${++count}`;
});

window.testResults = () => ({
  controlLoaded: window.fixtureControlLoaded === true,
  networkBlocked: window.fixtureControlLoaded === true && window.fixtureAdLoaded !== true,
  cosmeticHidden: getComputedStyle(document.getElementById("fixture-ad-box")).display === "none",
  webExtension: document.documentElement.dataset.adBlockerExtension === "0.0.2",
  advancedPhase: document.documentElement.dataset.adBlockerAdvancedPhase ?? "unavailable",
  advancedError: document.documentElement.dataset.adBlockerAdvancedError ?? "",
  counter: count,
});

function renderResults() {
  const results = window.testResults();
  const checks = [
    ["Hasznos script betöltése", results.controlLoaded],
    ["Natív hálózati reklámblokkolás", results.networkBlocked],
    ["Natív reklámdoboz-elrejtés", results.cosmeticHidden],
    ["Safari Web Extension script", results.webExtension],
  ];
  const list = document.getElementById("results");
  list.replaceChildren(...checks.map(([name, passed]) => {
    const item = document.createElement("li");
    item.className = passed ? "pass" : "fail";
    item.textContent = `${passed ? "✓" : "✗"} ${name}: ${passed ? "sikeres" : "nem igazolt"}`;
    return item;
  }));
  const advanced = document.createElement("li");
  advanced.textContent = `Fejlett motor válasza: ${results.advancedPhase}${results.advancedError ? ` (${results.advancedError})` : ""}`;
  list.appendChild(advanced);
}
document.getElementById("refresh").addEventListener("click", renderResults);
window.addEventListener("load", renderResults);

// Optional localhost-only reporting for native-browser runs where the remote
// accessibility snapshot cannot expose the page. Only fixture state is sent.
const report = new URL(location.href).searchParams.get("report");
if (report && location.origin === "http://127.0.0.1:8765") {
  window.addEventListener("load", () => {
    for (const delay of [0, 1500, 5000]) {
      setTimeout(() => {
        const fields = new URLSearchParams({
          report: report.slice(0, 64),
          ...window.testResults(),
          runtimeRevision: document.documentElement.dataset.adBlockerRuntimeRevision ?? "",
          visibility: document.visibilityState,
          bodyDisplay: getComputedStyle(document.body).display,
        });
        // This existing static resource returns 200; the local server log
        // records the query without needing a second service or a new port.
        fetch(`/fixture-control.js?${fields}`, { cache: "no-store" }).catch(() => {});
      }, delay);
    }
  });
}
