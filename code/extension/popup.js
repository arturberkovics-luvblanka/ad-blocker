"use strict";

async function inspectPage() {
  const status = document.getElementById("status");
  try {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    if (!tab || !Number.isInteger(tab.id)) throw new Error("No active tab");
    const [response, metadata] = await Promise.all([
      browser.tabs.sendMessage(tab.id, { type: "adblocker:status" }, { frameId: 0 }),
      browser.runtime.sendMessage({ type: "adblocker:metadata" }),
    ]);
    if (response?.scriptAvailable !== true || response.version !== "0.0.2") {
      throw new Error("Missing or outdated content script");
    }
    if (typeof metadata?.generation !== "string" || !/^[a-f0-9]{64}$/.test(metadata.generation)
        || typeof metadata.runtimeRevision !== "string" || !/^[a-f0-9]{64}$/.test(metadata.runtimeRevision)) {
      throw new Error("Missing current rule generation");
    }
    if (response.generation !== metadata.generation || response.runtimeRevision !== metadata.runtimeRevision) {
      status.dataset.state = "unavailable";
      status.textContent = "Frissült a bővítmény; frissítsd a lapot az új védelem használatához.";
      return;
    }
    if (response.advanced?.phase === "error") {
      status.dataset.state = "unavailable";
      status.textContent = "Az oldalellenőrzés elérhető, de a fejlett szűrés hibát jelzett.";
      return;
    }
    if (response.advanced?.responseAfterDelayWindow === true) {
      status.dataset.state = "unavailable";
      status.textContent = "A fejlett szabályok késve érkeztek; frissítsd a lapot az újrapróbáláshoz.";
      return;
    }
    if (response.advanced?.limitations?.includes("css_origin_limited")) {
      status.dataset.state = "unavailable";
      status.textContent = "Egyes fejlett CSS-szabályok korlátozott prioritással futnak ezen a lapon.";
      return;
    }
    status.dataset.state = "available";
    status.textContent = response.advanced?.phase === "starting"
      ? "Oldalellenőrzés elérhető; a fejlett szabályok betöltése folyamatban."
      : "Oldalellenőrzés elérhető.";
  } catch {
    status.dataset.state = "unavailable";
    status.textContent = "Az oldalellenőrzés nem érhető el. Engedélyezd a hozzáférést, majd frissítsd a lapot.";
  }
}
inspectPage();
