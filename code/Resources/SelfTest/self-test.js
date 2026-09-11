"use strict";

(() => {
  const match = location.pathname.match(/^\/session\/([0-9a-f]{64})\/$/);
  if (!match || location.hostname !== "127.0.0.1") return;
  const nonce = match[1];
  let clicks = 0;
  const button = document.getElementById("useful-control");
  button.addEventListener("click", () => {
    clicks += 1;
    button.textContent = `Működő próbagomb: ${clicks}`;
  });

  function imageResult(path) {
    return new Promise(resolve => {
      const image = new Image();
      const timer = setTimeout(() => resolve("timeout"), 4000);
      const finish = value => { clearTimeout(timer); resolve(value); };
      image.onload = () => finish("loaded");
      image.onerror = () => finish("rejected");
      image.src = path;
    });
  }

  function hidden(selector) {
    const element = document.querySelector(selector);
    return Boolean(element) && getComputedStyle(element).display === "none";
  }

  function render(id, passed) {
    const item = document.getElementById(id);
    item.className = passed ? "pass" : "fail";
    item.textContent = `${passed ? "✓" : "✗"} ${item.textContent.replace(/^[✓✗] /, "")
      .replace(/…$/, "")}: ${passed ? "sikeres" : "nem igazolt"}`;
  }

  async function report() {
    button.click();
    const allowedBefore = await imageResult(`/allowed.svg?session=${nonce}&phase=before`);
    const blockedResult = await imageResult(`/adblocker-self-test-blocked.svg?session=${nonce}`);
    const allowedAfter = await imageResult(`/allowed.svg?session=${nonce}&phase=after`);
    const allowedLoaded = allowedBefore === "loaded" && allowedAfter === "loaded";
    const blockedRejected = blockedResult === "rejected";
    let advancedEffectHidden = false;
    for (let attempt = 0; attempt < 20 && !advancedEffectHidden; attempt += 1) {
      advancedEffectHidden = hidden(".adblocker-self-test-advanced");
      if (!advancedEffectHidden) await new Promise(resolve => setTimeout(resolve, 100));
    }
    let extensionReported = false;
    for (let attempt = 0; attempt < 20 && !extensionReported; attempt += 1) {
      extensionReported = document.documentElement.dataset.adBlockerSelfTestExtension === "reported";
      if (!extensionReported) await new Promise(resolve => setTimeout(resolve, 100));
    }
    const result = {
      schema: 1,
      nonce,
      allowedLoaded,
      blockedRejected,
      nativeCosmeticHidden: hidden(".adblocker-self-test-native"),
      advancedEffectHidden,
      usefulControlWorked: clicks === 1 && button.textContent.endsWith("1"),
    };
    render("control-state", result.allowedLoaded && result.usefulControlWorked);
    render("network-state", result.blockedRejected);
    render("native-state", result.nativeCosmeticHidden);
    render("advanced-state", result.advancedEffectHidden);
    render("extension-state", extensionReported);
    try {
      const response = await fetch(`${location.pathname}page-report`, {
        method: "POST",
        cache: "no-store",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(result),
      });
      document.getElementById("summary").textContent = response.ok
        ? "Az eredményt az Ad Blocker alkalmazás ellenőrzi. Visszatérhetsz az apphoz."
        : "A próba eredményét az alkalmazás nem fogadta el. Indítsd újra az ellenőrzést.";
    } catch {
      document.getElementById("summary").textContent = "A helyi próba megszakadt. Indítsd újra az alkalmazásból.";
    }
  }

  window.addEventListener("load", () => { void report(); }, { once: true });
})();
