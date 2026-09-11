import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../Resources/SelfTest/self-test.js", import.meta.url), "utf8");
const nonce = "a".repeat(64);

async function runPage(blockedMode) {
  const elements = new Map();
  for (const id of ["useful-control", "summary", "control-state", "network-state",
    "native-state", "advanced-state", "extension-state"]) {
    elements.set(id, { id, className: "", textContent: id === "useful-control" ? "Működő próbagomb: 0" : "Ellenőrzés…" });
  }
  const button = elements.get("useful-control");
  button.addEventListener = (_, handler) => { button.handler = handler; };
  button.click = () => button.handler();
  const reports = [];
  let onload;
  class FakeImage {
    set src(value) {
      if (value.includes("allowed.svg")) this.onload();
      else if (blockedMode === "error") this.onerror();
    }
  }
  const document = {
    documentElement: { dataset: { adBlockerSelfTestExtension: "reported" } },
    getElementById: id => elements.get(id),
    querySelector: () => ({}),
  };
  const context = {
    document,
    location: { hostname: "127.0.0.1", pathname: `/session/${nonce}/` },
    Image: FakeImage,
    getComputedStyle: () => ({ display: "none" }),
    setTimeout: callback => { queueMicrotask(callback); return 1; },
    clearTimeout: () => {},
    fetch: async (_, options) => { reports.push(JSON.parse(options.body)); return { ok: true }; },
  };
  context.window = { addEventListener: (_, handler) => { onload = handler; } };
  vm.runInNewContext(source, context);
  onload();
  for (let i = 0; i < 5; i += 1) await new Promise(resolve => setImmediate(resolve));
  return reports[0];
}

test("self-test page accepts an explicit blocked-resource error with controls on both sides", async () => {
  const report = await runPage("error");
  assert.equal(report.allowedLoaded, true);
  assert.equal(report.blockedRejected, true);
  assert.equal(report.nativeCosmeticHidden, true);
  assert.equal(report.advancedEffectHidden, true);
  assert.equal(report.usefulControlWorked, true);
});

test("self-test page never treats a blocked-resource timeout as successful blocking", async () => {
  const report = await runPage("timeout");
  assert.equal(report.allowedLoaded, true);
  assert.equal(report.blockedRejected, false);
});
