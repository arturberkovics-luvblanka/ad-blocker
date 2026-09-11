import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFileSync } from "node:fs";

const generation = "fc68ee1ce9fa6a7eabd48a644785d45c87afb403931e9b6dcb1efadb292a873c";
const runtimeRevision = "a".repeat(64);
const pageDocumentId = "11111111-1111-4111-8111-111111111111";
const blankDocumentId = "22222222-2222-4222-8222-222222222222";
const content = readFileSync(new URL("../extension/content.js", import.meta.url), "utf8");
const background = readFileSync(new URL("../extension/background-main.js", import.meta.url), "utf8");
const backgroundRuntime = readFileSync(
  new URL("../extension/advanced-background-runtime.js", import.meta.url),
  "utf8",
);
const popup = readFileSync(new URL("../extension/popup.js", import.meta.url), "utf8");
const mainWorldProbe = readFileSync(
  new URL("../extension/main-world-probe.js", import.meta.url),
  "utf8",
);
const manifest = JSON.parse(readFileSync(
  new URL("../extension/manifest.json", import.meta.url),
  "utf8",
));
const youtubeNativeJs = JSON.parse(readFileSync(
  new URL("./fixture/youtube-native-js.json", import.meta.url),
  "utf8",
));


function boundOrigin(serverPath) {
  const source = readFileSync(new URL(serverPath, import.meta.url), "utf8");
  const bind = source.match(/ThreadingHTTPServer\(\("([^"]+)",\s*(\d+)\)/);
  assert.ok(bind, `Cannot read the actual fixture bind address: ${serverPath}`);
  return new URL(`http://${bind[1]}:${bind[2]}`);
}
const fixtureOrigin = boundOrigin("../scripts/serve_fixture.py");

const emptyPayload = {
  css: [], extendedCss: [], js: [], scriptlets: [], engineTimestamp: 17,
};

async function settle() {
  await new Promise(resolve => setImmediate(resolve));
  await new Promise(resolve => setImmediate(resolve));
}

function runContent({
  origin = "https://example.com",
  href = `${origin}/`,
  pathname = "/",
  root = { dataset: {} },
  response = { generation, payload: emptyPayload, delivery: "no_matching_rules" },
  runtime = true,
  clock = Date,
} = {}) {
  const listeners = [];
  const applied = [];
  let domReady;
  let releases = 0;
  let setupCalls = 0;
  let lookupCalls = 0;
  const location = { origin, href, pathname };
  const document = {
    documentElement: root,
    addEventListener: (event, fn) => {
      if (event === "DOMContentLoaded") domReady = fn;
    },
  };
  const context = {
    console,
    Date: clock,
    document,
    location,
    browser: { runtime: {
      onMessage: { addListener: fn => listeners.push(fn) },
      sendMessage: async () => {
        lookupCalls += 1;
        return response;
      },
    } },
  };
  if (runtime) {
    context.AdBlockerAdvancedRuntime = {
      revision: runtimeRevision,
      ContentScript: class {
        applyConfiguration(payload) { applied.push(payload); }
      },
      setupDelayedEventDispatcher: () => {
        setupCalls += 1;
        return () => { releases += 1; };
      },
    };
  }
  vm.runInNewContext(content, context);
  return {
    applied,
    context,
    document,
    get listenerCount() { return listeners.length; },
    get lookupCalls() { return lookupCalls; },
    get releases() { return releases; },
    get setupCalls() { return setupCalls; },
    ready: () => domReady(),
    rerun: () => vm.runInNewContext(content, context),
    status: () => listeners[0]({ type: "adblocker:status" }),
  };
}

function runBackground({
  nativeResponse,
  nativeHandler,
  currentUrl,
  currentDocumentId = pageDocumentId,
  tabUrl,
  frameHandler,
  applyError,
} = {}) {
  let listener;
  const nativeCalls = [];
  const applyCalls = [];
  const browser = {
    runtime: {
      onMessage: { addListener: fn => { listener = fn; } },
      sendNativeMessage: async (applicationId, message) => {
        nativeCalls.push({ applicationId, message });
        if (nativeHandler) return nativeHandler(message);
        return nativeResponse ?? { generation, payload: emptyPayload };
      },
    },
    webNavigation: {
      getFrame: async details => {
        if (frameHandler) return frameHandler(details);
        return {
          url: details.frameId === 0
            ? tabUrl ?? currentUrl ?? "https://example.com/page"
            : currentUrl ?? "https://example.com/page",
          documentId: currentDocumentId,
          parentFrameId: details.frameId === 0 ? -1 : 0,
        };
      },
    },
    tabs: {
      get: async () => ({ url: tabUrl ?? "https://example.com/top" }),
    },
  };
  const context = {
    browser,
    console,
    URL,
    AdBlockerAdvancedRuntime: {
      revision: runtimeRevision,
      DocumentBackgroundScript: class {
        async applyConfiguration(...args) {
          applyCalls.push(args);
          if (applyError) throw applyError;
        }
      },
    },
  };
  vm.runInNewContext(background, context);
  return { applyCalls, listener, nativeCalls };
}

test("bundled upstream background runtime includes compile-time raw JS functions", () => {
  const context = { browser: {}, console };
  vm.runInNewContext(backgroundRuntime, context);
  const Runtime = context.AdBlockerAdvancedRuntime;
  assert.equal(typeof Runtime.BackgroundScript, "function");
  assert.ok(Runtime.registeredScripts.size >= 200);
  assert.ok([...Runtime.registeredScripts.keys()].some(source => (
    source.includes("window.Promise.prototype.then")
  )));
});

test("bundled runtime sends a registered raw rule to the MAIN world", async () => {
  const injections = [];
  const context = {
    browser: { scripting: {
      executeScript: async injection => {
        injections.push(injection);
        return [{ result: null }];
      },
      insertCSS: async () => {},
    } },
    console,
  };
  vm.runInNewContext(backgroundRuntime, context);
  const Runtime = context.AdBlockerAdvancedRuntime;
  const source = [...Runtime.registeredScripts.keys()].find(value => (
    value.includes("window.Promise.prototype.then")
  ));
  await new Runtime.BackgroundScript(Runtime.registeredScripts).applyConfiguration(9, 0, {
    ...emptyPayload,
    js: [source],
  });
  assert.equal(injections.length, 1);
  assert.equal(injections[0].world, "MAIN");
  assert.equal(injections[0].func, Runtime.registeredScripts.get(source));
});

test("bundled background runtime disables verbose scriptlet tracing", async () => {
  const injections = [];
  const context = {
    browser: { scripting: {
      executeScript: async injection => {
        injections.push(injection);
        return [{ result: null }];
      },
      insertCSS: async () => {},
    } },
    console,
  };
  vm.runInNewContext(backgroundRuntime, context);
  const Runtime = context.AdBlockerAdvancedRuntime;
  await new Runtime.BackgroundScript(Runtime.registeredScripts).applyConfiguration(9, 0, {
    ...emptyPayload,
    scriptlets: [{ name: "log", args: ["test"] }],
  });
  assert.equal(injections.length, 1);
  assert.equal(injections[0].world, "MAIN");
  assert.equal(injections[0].args[0].verbose, false);
});

test("document runtime binds every injection to the requested document", async () => {
  const injections = [];
  const context = {
    browser: { scripting: {
      executeScript: async injection => {
        injections.push(injection);
        return [{ documentId: pageDocumentId, result: null }];
      },
    } },
    console,
  };
  vm.runInNewContext(backgroundRuntime, context);
  const Runtime = context.AdBlockerAdvancedRuntime;
  await new Runtime.DocumentBackgroundScript(Runtime.registeredScripts).applyConfiguration(
    9,
    pageDocumentId,
    { ...emptyPayload, scriptlets: [{ name: "log", args: ["test"] }] },
  );
  assert.equal(injections.length, 1);
  assert.deepEqual(
    JSON.parse(JSON.stringify(injections[0].target)),
    { tabId: 9, documentIds: [pageDocumentId] },
  );
  assert.equal(injections[0].world, "MAIN");
  assert.equal(injections[0].args[0].verbose, false);
});

test("every raw JS string returned by the native YouTube lookup has an exact registered function", () => {
  const context = { browser: {}, console };
  vm.runInNewContext(backgroundRuntime, context);
  assert.equal(youtubeNativeJs.generation, generation);
  assert.equal(youtubeNativeJs.js.length, 9);
  for (const source of youtubeNativeJs.js) {
    assert.equal(typeof context.AdBlockerAdvancedRuntime.registeredScripts.get(source), "function");
  }
});

test("manifest loads the runtime before content code and declares native execution permissions", () => {
  assert.equal(manifest.background.service_worker, "background.js");
  assert.deepEqual(manifest.content_scripts.find(entry => entry.js.includes("main-world-probe.js")), {
    matches: [
      "http://127.0.0.1/main-world.html",
      "http://127.0.0.1/main-world-csp.html",
    ],
    js: ["main-world-probe.js"],
    run_at: "document_start",
    all_frames: false,
    world: "MAIN",
  });
  const contentEntry = manifest.content_scripts.find(entry => entry.js.includes("content.js"));
  assert.deepEqual(contentEntry.js, ["advanced-content-runtime.js", "content.js"]);
  assert.equal(contentEntry.run_at, "document_start");
  assert.equal(contentEntry.all_frames, true);
  assert.ok(manifest.permissions.includes("nativeMessaging"));
  assert.ok(manifest.permissions.includes("scripting"));
  assert.ok(manifest.permissions.includes("webNavigation"));
  for (const entry of manifest.content_scripts) {
    assert.ok(Array.isArray(entry.matches) && entry.matches.length > 0);
    for (const match of entry.matches) {
      assert.match(match, /^(?:https?|\*):\/\/[^/:]+\/[^:]*$/);
    }
  }
});

test("MAIN-world probe is exact-origin guarded and idempotent", () => {
  const listeners = [];
  const document = {
    readyState: "loading",
    documentElement: { dataset: {} },
    getElementById: () => null,
    addEventListener: (...args) => listeners.push(args),
  };
  const context = {
    document,
    location: { origin: fixtureOrigin.origin, pathname: "/main-world.html" },
    performance: { now: () => 42 },
  };
  context.window = context;
  vm.runInNewContext(mainWorldProbe, context);
  const firstProbe = context.__adBlockerMainProbe;
  assert.equal(firstProbe.startedAt, 42);
  assert.equal(document.documentElement.dataset.adBlockerMainProbe, "ran");
  assert.equal(listeners.length, 1);
  assert.doesNotThrow(() => vm.runInNewContext(mainWorldProbe, context));
  assert.equal(context.__adBlockerMainProbe, firstProbe);
  assert.equal(listeners.length, 1);

  const rejected = {
    document: {
      readyState: "loading",
      documentElement: { dataset: {} },
      addEventListener: () => { throw new Error("must not register"); },
    },
    location: { origin: "http://127.0.0.1:9999", pathname: "/main-world.html" },
    performance: { now: () => 0 },
  };
  rejected.window = rejected;
  vm.runInNewContext(mainWorldProbe, rejected);
  assert.equal(rejected.__adBlockerMainProbe, undefined);
  assert.deepEqual(rejected.document.documentElement.dataset, {});
});

test("content script requests lookup without sending a page-controlled URL", async () => {
  const page = runContent();
  await settle();
  assert.equal(page.releases, 1);
  assert.deepEqual((await page.status()).advanced.phase, "no_matching_rules");
  assert.deepEqual(page.document.documentElement.dataset, {});
});

test("loading content.js twice in one world is idempotent", async () => {
  const payload = { ...emptyPayload, scriptlets: [{ name: "log", args: ["once"] }] };
  const page = runContent({ response: { generation, payload, applyInContent: true } });
  assert.doesNotThrow(() => page.rerun());
  await settle();
  assert.equal(page.listenerCount, 1);
  assert.equal(page.setupCalls, 1);
  assert.equal(page.lookupCalls, 1);
  assert.equal(page.releases, 1);
  assert.deepEqual(page.applied, [payload]);
});

test("content status preserves the document-bound CSS origin limitation", async () => {
  const page = runContent({
    response: {
      generation,
      payload: { ...emptyPayload, css: [".advert"] },
      delivery: "background_attempted_unverified",
      limitations: ["css_origin_limited"],
    },
  });
  await settle();
  assert.deepEqual(
    JSON.parse(JSON.stringify((await page.status()).advanced.limitations)),
    ["css_origin_limited"],
  );
});

test("content fallback applies only a matching generation on the same navigation", async () => {
  const payload = { ...emptyPayload, css: [".advert"] };
  const page = runContent({ response: { generation, payload, applyInContent: true } });
  await settle();
  assert.deepEqual(page.applied, [payload]);
  assert.equal((await page.status()).advanced.phase, "content_attempted_unverified");

  let resolveResponse;
  const pending = new Promise(resolve => { resolveResponse = resolve; });
  const stale = runContent({ response: pending });
  stale.context.location.href = "https://example.com/next";
  resolveResponse({ generation, payload, applyInContent: true });
  await settle();
  assert.equal(stale.applied.length, 0);
  assert.equal((await stale.status()).advanced.error, "stale_navigation");
});

test("content script exposes missing runtime and generation failures", async () => {
  const missing = runContent({ runtime: false });
  assert.equal((await missing.status()).advanced.error, "runtime_unavailable");

  const mismatch = runContent({ response: { generation: "old", payload: emptyPayload } });
  await settle();
  assert.equal((await mismatch.status()).advanced.error, "generation_mismatch");
  assert.equal(mismatch.releases, 1);
});

test("content status identifies a response outside the early event-delay window", async () => {
  const times = [100, 1601];
  const page = runContent({ clock: { now: () => times.shift() ?? 1601 } });
  await settle();
  const state = (await page.status()).advanced;
  assert.equal(state.lookupMilliseconds, 1501);
  assert.equal(state.responseAfterDelayWindow, true);
});

test("fixture publishes advanced diagnostics and stays restricted to the exact local origin", async () => {
  const page = runContent({ origin: fixtureOrigin.origin, href: fixtureOrigin.href, root: null });
  page.document.documentElement = { dataset: {} };
  page.ready();
  await settle();
  assert.equal(page.document.documentElement.dataset.adBlockerExtension, "0.0.2");
  assert.equal(page.document.documentElement.dataset.adBlockerAdvancedPhase, "no_matching_rules");
  assert.equal(page.document.documentElement.dataset.adBlockerAdvancedError, "");
  assert.equal(page.document.documentElement.dataset.adBlockerAdvancedLimitations, "");
  assert.match(page.document.documentElement.dataset.adBlockerLookupMilliseconds, /^\d+$/);
  assert.deepEqual(runContent({ origin: "http://127.0.0.1:8766" }).document.documentElement.dataset, {});
});

test("background ignores message URL and derives lookup URLs from sender", async () => {
  const run = runBackground({ currentUrl: "https://trusted.example/frame" });
  const response = await run.listener(
    { type: "lookup", url: "https://attacker.invalid/" },
    {
      tab: { id: 4, url: "https://trusted.example/top" },
      frameId: 3,
      documentId: pageDocumentId,
      url: "https://trusted.example/frame",
    },
  );
  assert.deepEqual(JSON.parse(JSON.stringify(run.nativeCalls)), [{
    applicationId: "org.local.adblocker",
    message: {
      type: "lookup",
      url: "https://trusted.example/frame",
      topUrl: "https://trusted.example/top",
    },
  }]);
  assert.equal(response.delivery, "no_matching_rules");
});

test("background rejects invalid senders, generations, and payloads before applying", async () => {
  const sender = {
    tab: { id: 1, url: "https://example.com/page" },
    frameId: 0,
    documentId: pageDocumentId,
    url: "https://example.com/page",
  };
  const invalidSender = runBackground();
  assert.equal((await invalidSender.listener({ type: "lookup" }, { tab: { id: 1 } })).error, "invalid_sender");
  assert.equal((await invalidSender.listener(
    { type: "lookup" },
    { tab: { id: 1, url: "https://example.com/" }, frameId: 0, url: "https://example.com/" },
  )).error, "document_unavailable");
  assert.equal((await invalidSender.listener(
    { type: "lookup" },
    {
      tab: { id: 1, url: "https://example.com/" },
      frameId: 2,
      documentId: pageDocumentId,
      url: "data:text/html,test",
    },
  )).error, "invalid_sender");

  const mismatch = runBackground({ nativeResponse: { generation: "old", payload: emptyPayload } });
  assert.equal((await mismatch.listener({ type: "lookup" }, sender)).error, "generation_mismatch");

  const invalid = runBackground({ nativeResponse: { generation, payload: { ...emptyPayload, css: "bad" } } });
  assert.equal((await invalid.listener({ type: "lookup" }, sender)).error, "invalid_payload");
  assert.equal(invalid.applyCalls.length, 0);
});

test("background rechecks navigation and rejects stale pages", async () => {
  const run = runBackground({ currentUrl: "https://example.com/new" });
  const response = await run.listener(
    { type: "lookup" },
    {
      tab: { id: 2, url: "https://example.com/old" },
      frameId: 0,
      documentId: pageDocumentId,
      url: "https://example.com/old",
    },
  );
  assert.equal(response.error, "stale_navigation");
  assert.equal(run.applyCalls.length, 0);
});

test("a newer lookup supersedes an older response for the same frame", async () => {
  const resolvers = [];
  const run = runBackground({
    currentUrl: "https://example.com/page",
    nativeHandler: () => new Promise(resolve => resolvers.push(resolve)),
  });
  const sender = {
    tab: { id: 5, url: "https://example.com/page" },
    frameId: 0,
    documentId: pageDocumentId,
    url: "https://example.com/page",
  };
  const older = run.listener({ type: "lookup" }, sender);
  const newer = run.listener({ type: "lookup" }, sender);
  await settle();
  resolvers[0]({ generation, payload: emptyPayload });
  assert.equal((await newer).delivery, "no_matching_rules");
  assert.equal((await older).error, "stale_navigation");
});

test("a newer lookup supersedes an older request while its URL check is pending", async () => {
  const nativeResolvers = [];
  let resolveOldFrame;
  let frameChecks = 0;
  const payload = { ...emptyPayload, css: [".advert"] };
  const run = runBackground({
    nativeHandler: () => new Promise(resolve => nativeResolvers.push(resolve)),
    frameHandler: () => {
      frameChecks += 1;
      if (frameChecks === 1) return new Promise(resolve => { resolveOldFrame = resolve; });
      return {
        url: "https://example.com/page",
        documentId: pageDocumentId,
        parentFrameId: -1,
      };
    },
  });
  const sender = {
    tab: { id: 8, url: "https://example.com/page" },
    frameId: 0,
    documentId: pageDocumentId,
    url: "https://example.com/page",
  };
  const older = run.listener({ type: "lookup" }, sender);
  await settle();
  nativeResolvers[0]({ generation, payload });
  await settle();
  const newer = run.listener({ type: "lookup" }, sender);
  await settle();
  nativeResolvers[1]({ generation, payload });
  assert.equal((await newer).delivery, "background_attempted_unverified");
  resolveOldFrame({
    url: "https://example.com/page",
    documentId: pageDocumentId,
    parentFrameId: -1,
  });
  assert.equal((await older).error, "stale_navigation");
  assert.equal(run.applyCalls.length, 1);
});

test("blank frame lookup inherits its nearest web parent, not the top tab URL", async () => {
  const frames = new Map([
    [0, {
      url: "https://publisher.example/article",
      documentId: pageDocumentId,
      parentFrameId: -1,
    }],
    [2, {
      url: "https://www.youtube.com/embed/video",
      documentId: "33333333-3333-4333-8333-333333333333",
      parentFrameId: 0,
    }],
    [3, { url: "about:blank", documentId: blankDocumentId, parentFrameId: 2 }],
  ]);
  const run = runBackground({ frameHandler: ({ frameId }) => frames.get(frameId) });
  const response = await run.listener(
    { type: "lookup" },
    {
      tab: { id: 10, url: "https://publisher.example/article" },
      frameId: 3,
      documentId: blankDocumentId,
      url: "about:blank",
    },
  );
  assert.equal(response.delivery, "no_matching_rules");
  assert.deepEqual(JSON.parse(JSON.stringify(run.nativeCalls[0].message)), {
    type: "lookup",
    url: "https://www.youtube.com/embed/video",
    topUrl: "https://publisher.example/article",
  });
});

test("blank frame lookup rejects an unverifiable non-web parent", async () => {
  const frames = new Map([
    [0, {
      url: "https://publisher.example/article",
      documentId: pageDocumentId,
      parentFrameId: -1,
    }],
    [2, {
      url: "data:text/html,parent",
      documentId: "33333333-3333-4333-8333-333333333333",
      parentFrameId: 0,
    }],
    [3, { url: "about:blank", documentId: blankDocumentId, parentFrameId: 2 }],
  ]);
  const run = runBackground({ frameHandler: ({ frameId }) => frames.get(frameId) });
  const response = await run.listener(
    { type: "lookup" },
    {
      tab: { id: 11, url: "https://publisher.example/article" },
      frameId: 3,
      documentId: blankDocumentId,
      url: "about:blank",
    },
  );
  assert.equal(response.error, "blank_origin_unverified");
  assert.equal(run.nativeCalls.length, 0);
});

test("verified blank senders tolerate Safari's empty getFrame URL without trusting unknown ancestors", async () => {
  for (const url of ["about:blank", "about:srcdoc"]) {
    for (const parentUrl of ["https://publisher.example/article", ""]) {
      const run = runBackground({
        nativeResponse: { generation, payload: { ...emptyPayload, css: [".advert"] } },
        frameHandler: ({ frameId }) => frameId === 0
          ? { url: parentUrl, documentId: pageDocumentId, parentFrameId: -1 }
          : { url: "", documentId: blankDocumentId, parentFrameId: 0 },
      });
      const response = await run.listener({ type: "lookup" }, {
        tab: { id: 12, url: "https://publisher.example/article" },
        frameId: 34359738370, documentId: blankDocumentId, url,
      });
      if (parentUrl) {
        assert.equal(response.applyInContent, true);
        assert.equal(run.nativeCalls.length, 1);
        assert.equal(run.nativeCalls[0].message.url, parentUrl);
        assert.equal(run.applyCalls.length, 0);
      } else {
        assert.equal(response.error, "blank_origin_unverified");
        assert.equal(run.nativeCalls.length, 0);
      }
    }
  }
});

test("empty frame URL never excuses a changed document or a non-blank sender", async () => {
  for (const senderUrl of ["about:blank", "data:text/html,test"]) {
    const run = runBackground({
      frameHandler: ({ frameId }) => frameId === 0
        ? { url: "https://publisher.example/article", documentId: pageDocumentId, parentFrameId: -1 }
        : { url: "", documentId: pageDocumentId, parentFrameId: 0 },
    });
    const response = await run.listener({ type: "lookup" }, {
      tab: { id: 12, url: "https://publisher.example/article" },
      frameId: 2, documentId: blankDocumentId, url: senderUrl,
    });
    assert.equal(typeof response.error, "string");
    assert.equal(run.nativeCalls.length, 0);
  }
});

test("normal and blank frames use the intended path without claiming active success", async () => {
  const payload = {
    ...emptyPayload,
    css: [".advert { display:none!important; }"],
    scriptlets: [{ name: "log", args: ["test"] }],
  };
  const normal = runBackground({ nativeResponse: { generation, payload } });
  const normalResponse = await normal.listener(
    { type: "lookup" },
    {
      tab: { id: 6, url: "https://example.com/page" },
      frameId: 0,
      documentId: pageDocumentId,
      url: "https://example.com/page",
    },
  );
  assert.equal(normal.applyCalls.length, 1);
  assert.equal(normalResponse.delivery, "background_attempted_unverified");
  assert.deepEqual(
    JSON.parse(JSON.stringify(normalResponse.limitations)),
    ["css_origin_limited"],
  );
  assert.equal("active" in normalResponse, false);

  const blank = runBackground({
    nativeResponse: { generation, payload },
    tabUrl: "https://example.com/top",
    frameHandler: ({ frameId }) => frameId === 0
      ? {
        url: "https://example.com/top",
        documentId: pageDocumentId,
        parentFrameId: -1,
      }
      : { url: "about:blank", documentId: blankDocumentId, parentFrameId: 0 },
  });
  const blankResponse = await blank.listener(
    { type: "lookup" },
    {
      tab: { id: 6, url: "https://example.com/top" },
      frameId: 2,
      documentId: blankDocumentId,
      url: "about:blank",
    },
  );
  assert.equal(blank.applyCalls.length, 0);
  assert.equal(blankResponse.applyInContent, true);
  assert.deepEqual(
    JSON.parse(JSON.stringify(blankResponse.limitations)),
    ["css_origin_limited"],
  );
  assert.equal("active" in blankResponse, false);
});

test("upstream apply rejection is returned as an error", async () => {
  const payload = { ...emptyPayload, css: [".advert"] };
  const run = runBackground({ nativeResponse: { generation, payload }, applyError: new Error("injection") });
  const response = await run.listener(
    { type: "lookup" },
    {
      tab: { id: 7, url: "https://example.com/page" },
      frameId: 0,
      documentId: pageDocumentId,
      url: "https://example.com/page",
    },
  );
  assert.equal(response.error, "apply_failed");
  assert.equal("active" in response, false);
});

async function runPopup(response, tabs = [{ id: 3 }], metadata = { generation, runtimeRevision }) {
  const status = { textContent: "", dataset: {} };
  const sendCalls = [];
  vm.runInNewContext(popup, {
    document: { getElementById: () => status },
    browser: { runtime: {
      sendMessage: async message => {
        assert.equal(message.type, "adblocker:metadata");
        if (metadata instanceof Error) throw metadata;
        return metadata;
      },
    }, tabs: {
      query: async () => tabs,
      sendMessage: async (...args) => {
        sendCalls.push(args);
        if (response instanceof Error) throw response;
        return response;
      },
    } },
  });
  await settle();
  status.sendCalls = sendCalls;
  return status;
}

test("popup distinguishes availability, loading, and advanced runtime failure", async () => {
  const available = await runPopup({ version: "0.0.2", generation, runtimeRevision, scriptAvailable: true });
  assert.match(available.textContent, /elérhető/);
  assert.deepEqual(JSON.parse(JSON.stringify(available.sendCalls[0])), [
    3,
    { type: "adblocker:status" },
    { frameId: 0 },
  ]);
  assert.match((await runPopup({
    version: "0.0.2", generation, runtimeRevision, scriptAvailable: true, advanced: { phase: "starting" },
  })).textContent, /betöltése folyamatban/);
  const failed = await runPopup({
    version: "0.0.2", generation, runtimeRevision, scriptAvailable: true, advanced: { phase: "error" },
  });
  assert.equal(failed.dataset.state, "unavailable");
  assert.match(failed.textContent, /hibát jelzett/);
  const late = await runPopup({
    version: "0.0.2", generation, runtimeRevision, scriptAvailable: true,
    advanced: { phase: "background_attempted_unverified", responseAfterDelayWindow: true },
  });
  assert.equal(late.dataset.state, "unavailable");
  assert.match(late.textContent, /késve érkeztek/);
  const limited = await runPopup({
    version: "0.0.2", generation, runtimeRevision, scriptAvailable: true,
    advanced: { phase: "background_attempted_unverified", limitations: ["css_origin_limited"] },
  });
  assert.equal(limited.dataset.state, "unavailable");
  assert.match(limited.textContent, /korlátozott prioritással/);
  for (const response of [undefined, {}, { version: "0.1.0", scriptAvailable: true }, new Error("denied")]) {
    assert.match((await runPopup(response)).textContent, /nem érhető el/);
  }
});

test("status handshake identifies the rule generation without another lookup", async () => {
  const contentRun = runContent();
  await settle();
  assert.equal((await contentRun.status()).generation, generation);
  assert.equal((await contentRun.status()).runtimeRevision, runtimeRevision);
  contentRun.context.AdBlockerAdvancedRuntime.revision = "b".repeat(64);
  assert.equal((await contentRun.status()).runtimeRevision, runtimeRevision);
  assert.equal(contentRun.lookupCalls, 1);
  const backgroundRun = runBackground();
  const metadata = await backgroundRun.listener({ type: "adblocker:metadata" }, {});
  assert.equal(metadata.generation, generation);
  assert.equal(metadata.runtimeRevision, runtimeRevision);
  assert.equal(backgroundRun.nativeCalls.length, 0);
});

test("popup requests a refresh for a page from an older rule generation", async () => {
  for (const oldGeneration of [undefined, "old-generation"]) {
    const status = await runPopup({
      version: "0.0.2", scriptAvailable: true, generation: oldGeneration, runtimeRevision,
      advanced: { phase: "background_attempted_unverified" },
    });
    assert.equal(status.dataset.state, "unavailable");
    assert.match(status.textContent, /frissítsd a lapot/i);
  }
});

test("popup requests a refresh after a runtime-only update", async () => {
  for (const oldRevision of [undefined, "b".repeat(64)]) {
    const status = await runPopup({
      version: "0.0.2", generation, scriptAvailable: true, runtimeRevision: oldRevision,
    });
    assert.equal(status.dataset.state, "unavailable");
    assert.match(status.textContent, /frissítsd a lapot/i);
  }
});

test("bundled background runtime exposes its verified build revision", () => {
  const build = JSON.parse(readFileSync(new URL("../extension-runtime/build-manifest.json", import.meta.url), "utf8"));
  assert.match(build.runtimeRevision, /^[a-f0-9]{64}$/);
  const context = { browser: {}, console };
  vm.runInNewContext(backgroundRuntime, context);
  assert.equal(context.AdBlockerAdvancedRuntime.revision, build.runtimeRevision);
});

test("every scriptlet name used by the pinned rules is available in the bundled runtime", async () => {
  const rules = readFileSync(new URL("../filters/generated/adguard-base-advanced.txt", import.meta.url), "utf8");
  const names = [...new Set([...rules.matchAll(/#%#\/\/scriptlet\(["']([^"']+)["']/g)].map(match => match[1]))];
  assert.ok(names.includes("google-ima3-dai"));
  let injections = 0;
  const context = {
    console,
    browser: { scripting: { executeScript: async options => {
      assert.equal(typeof options.func, "function");
      assert.equal(options.world, "MAIN");
      injections += 1;
      return [{ documentId: pageDocumentId, result: true }];
    } } },
  };
  vm.runInNewContext(backgroundRuntime, context);
  await new context.AdBlockerAdvancedRuntime.DocumentBackgroundScript().runScriptlets(
    1, pageDocumentId, names.map(name => ({ name, args: [] })),
  );
  assert.equal(injections, names.length);
});

test("popup never accepts a missing current-generation response", async () => {
  for (const metadata of [null, {}, { generation: "invalid" }, new Error("background unavailable")]) {
    const status = await runPopup({
      version: "0.0.2", generation, scriptAvailable: true,
    }, [{ id: 3 }], metadata);
    assert.equal(status.dataset.state, "unavailable");
    assert.match(status.textContent, /nem érhető el/);
  }
});


test("fixture server addresses agree with native rules and extension manifests", () => {
  const rules = JSON.parse(readFileSync(new URL("../filters/blockerList.json", import.meta.url), "utf8"));
  const sentinel = rules.find(rule => rule.trigger["url-filter"].includes("fixture-ad"));
  assert.ok(sentinel && new RegExp(sentinel.trigger["url-filter"]).test(`${fixtureOrigin.origin}/fixture-ad.js`));
  const cosmetic = rules.find(rule => rule.action.selector === "#fixture-ad-box");
  assert.deepEqual(cosmetic.trigger["if-domain"], [fixtureOrigin.hostname]);
  const probe = manifest.content_scripts.find(entry => entry.js.includes("main-world-probe.js"));
  assert.deepEqual(probe.matches.map(pattern => new URL(pattern).hostname),
    probe.matches.map(() => fixtureOrigin.hostname));
  for (const fixture of ["webextension-integration-fixture", "webextension-early-timing-fixture"]) {
    const origin = boundOrigin(`./${fixture}/server.py`);
    const data = JSON.parse(readFileSync(new URL(`./${fixture}/extension/manifest.json`, import.meta.url), "utf8"));
    for (const pattern of [...data.host_permissions, ...data.content_scripts.flatMap(entry => entry.matches)]) {
      assert.equal(new URL(pattern).hostname, origin.hostname, `${fixture}: ${pattern}`);
    }
  }
});
