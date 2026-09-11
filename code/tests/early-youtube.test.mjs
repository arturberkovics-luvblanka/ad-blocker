import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFileSync } from "node:fs";
import {
  earlyYoutubeScriptlets, reviewedGeneration,
} from "../extension-runtime/early-youtube-policy.mjs";

const read = path => readFileSync(new URL(path, import.meta.url), "utf8");
const early = read("../extension/early-youtube.js");
const background = read("../extension/advanced-background-runtime.js");
const rules = read("../filters/generated/adguard-base-advanced.txt");
const scriptlets = earlyYoutubeScriptlets(rules, reviewedGeneration);
const documentId = "11111111-1111-4111-8111-111111111111";

function page({ hostname = "www.youtube.com", pathname = "/watch", protocol = "https:", child = false } = {}) {
  const context = vm.createContext({ console });
  // A plain Window instance avoids Node's context-global accessor semantics.
  // Real Window/global-object behavior is covered separately by the WebKit test.
  vm.runInContext(`
    class Window {}
    globalThis.Window = Window;
    globalThis.window = new Window();
    window.top = ${child ? "{}" : "window"};
    globalThis.location = ${JSON.stringify({ hostname, pathname, protocol })};
    globalThis.document = { currentScript: null };
  `, context);
  return context;
}

function assignPlayer(context, id) {
  vm.runInContext(`
    window.ytInitialPlayerResponse = {
      adPlacements: [1], adSlots: [2], playerAds: [3],
      videoDetails: { videoId: ${JSON.stringify(id)} }, streamingData: { formats: [7] }
    };
    window.playerResponse = { adPlacements: [4], useful: 42 };
  `, context);
}

function snapshot(context) {
  return JSON.parse(vm.runInContext("JSON.stringify([window.ytInitialPlayerResponse, window.playerResponse])", context));
}

async function applyLate(context) {
  const sandbox = { console, browser: { scripting: {
    executeScript: async injection => {
      assert.equal(injection.world, "MAIN");
      assert.deepEqual(Array.from(injection.target.documentIds), [documentId]);
      const result = vm.runInContext(`(${injection.func.toString()})(...${JSON.stringify(injection.args)})`, context);
      return [{ documentId, result }];
    },
  } } };
  vm.runInNewContext(background, sandbox);
  const Runtime = sandbox.AdBlockerAdvancedRuntime;
  await new Runtime.DocumentBackgroundScript().applyConfiguration(1, documentId, {
    css: [], extendedCss: [], js: [], scriptlets, engineTimestamp: 1,
  });
}

test("early player rules preserve useful data on first assignment and object replacement", () => {
  const context = page();
  vm.runInContext(early, context);
  for (const id of ["first", "replacement"]) {
    assignPlayer(context, id);
    assert.deepEqual(snapshot(context), [
      { videoDetails: { videoId: id }, streamingData: { formats: [7] } }, { useful: 42 },
    ]);
  }
});

test("actual late runtime deduplicates early traps and still works without the early script", async () => {
  const context = page();
  vm.runInContext(early, context);
  vm.runInContext(`before = ['ytInitialPlayerResponse', 'playerResponse'].map(
    name => Object.getOwnPropertyDescriptor(window, name));`, context);
  await applyLate(context);
  assert.equal(vm.runInContext(`['ytInitialPlayerResponse', 'playerResponse'].every((name, i) => {
    const after = Object.getOwnPropertyDescriptor(window, name);
    return after.get === before[i].get && after.set === before[i].set;
  })`, context), true);
  assignPlayer(context, "after-late");
  assert.equal(snapshot(context)[0].adPlacements, undefined);
  assert.equal(snapshot(context)[0].adSlots, undefined);
  assert.equal(snapshot(context)[0].playerAds, undefined);
  assert.equal(snapshot(context)[1].adPlacements, undefined);

  const fallback = page();
  await applyLate(fallback);
  assignPlayer(fallback, "fallback");
  assert.deepEqual(snapshot(fallback), [
    { videoDetails: { videoId: "fallback" }, streamingData: { formats: [7] } }, { useful: 42 },
  ]);
});

test("early script does not change excluded routes, other hosts, or embedded frames", () => {
  for (const options of [
    { pathname: "/my_video_ad" }, { pathname: "/watchlater" }, { pathname: "/shorts/test" },
    { hostname: "m.youtube.com" }, { hostname: "youtube-nocookie.com" },
    { hostname: "www.youtube.com.example.com" }, { protocol: "file:" }, { child: true },
  ]) {
    const context = page(options);
    vm.runInContext(early, context);
    assert.equal(vm.runInContext("Object.hasOwn(window, 'ytInitialPlayerResponse')", context), false);
    assignPlayer(context, "untouched");
    assert.deepEqual(snapshot(context)[0].adPlacements, [1]);
    assert.deepEqual(snapshot(context)[0].adSlots, [2]);
    assert.deepEqual(snapshot(context)[0].playerAds, [3]);
  }
  const manifest = JSON.parse(read("../extension/manifest.json"));
  const declaration = manifest.content_scripts.find(entry => entry.js.includes("early-youtube.js"));
  assert.deepEqual(declaration.matches, ["*://www.youtube.com/watch*"]);
  assert.equal(declaration.world, "MAIN");
  assert.equal(declaration.run_at, "document_start");
  assert.equal(declaration.all_frames, false);
});

test("early rule generation refuses unreviewed lists, missing rules, or duplicates", () => {
  assert.throws(() => earlyYoutubeScriptlets(rules, "a".repeat(64)), /Review early/);
  const line = rules.split("\n").find(line => line.endsWith("'ytInitialPlayerResponse.adSlots', 'undefined')"));
  assert.throws(() => earlyYoutubeScriptlets(rules.replace(line, ""), reviewedGeneration), /Expected one/);
  assert.throws(() => earlyYoutubeScriptlets(`${rules}\n${line}`, reviewedGeneration), /Expected one/);
});
