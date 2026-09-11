#!/usr/bin/env node

import { createRequire } from "node:module";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { earlyYoutubeScriptlets, earlyScriptletUniqueId } from "../extension-runtime/early-youtube-policy.mjs";
import { scriptlets as ScriptletsAPI } from "../vendor/SafariConverterLib/Extension/node_modules/@adguard/scriptlets/dist/index.js";

const codeDirectory = dirname(dirname(fileURLToPath(import.meta.url)));
const generatorPath = fileURLToPath(import.meta.url);
const upstreamDirectory = join(codeDirectory, "vendor", "SafariConverterLib", "Extension");
const extensionDirectory = join(codeDirectory, "extension");
const outputs = ["advanced-content-runtime.js", "advanced-background-runtime.js", "early-youtube.js"];
const require = createRequire(pathToFileURL(join(upstreamDirectory, "package.json")));
const upstreamPackage = JSON.parse(readFileSync(join(upstreamDirectory, "package.json"), "utf8"));
const runtimeBanner = [
  "/*",
  " * Bundled runtime: SafariConverterLib Extension 4.3.0,",
  ` * @adguard/extended-css ${upstreamPackage.dependencies["@adguard/extended-css"]} and @adguard/scriptlets ${upstreamPackage.dependencies["@adguard/scriptlets"]}.`,
  " * Each component is distributed under GPL-3.0.",
  " */",
].join("\n");

const { rollup } = require("rollup");
const commonjs = require("@rollup/plugin-commonjs");
const json = require("@rollup/plugin-json");
const { nodeResolve } = require("@rollup/plugin-node-resolve");
const typescript = require("@rollup/plugin-typescript");

const plugins = () => [
  json({ preferConst: true }),
  commonjs({ sourceMap: false }),
  nodeResolve({ browser: true, preferBuiltins: false }),
  typescript({
    tsconfig: join(upstreamDirectory, "tsconfig.json"),
    compilerOptions: { declaration: false, sourceMap: false },
  }),
];

async function build(entry, output, revision) {
  const bundle = await rollup({
    input: entry,
    external: ["webextension-polyfill"],
    plugins: plugins(),
    treeshake: true,
  });
  try {
    await bundle.write({
      file: join(codeDirectory, "extension", output),
      format: "iife",
      name: "AdBlockerAdvancedRuntime",
      globals: { "webextension-polyfill": "browser" },
      banner: runtimeBanner,
      footer: `Object.defineProperty(AdBlockerAdvancedRuntime, "revision", { value: ${JSON.stringify(revision)} });`,
      sourcemap: false,
    });
  } finally {
    await bundle.close();
  }
}

function rawScripts() {
  const rulesPath = join(codeDirectory, "filters", "generated", "adguard-base-advanced.txt");
  const scripts = new Set();
  for (const line of readFileSync(rulesPath, "utf8").split("\n")) {
    const marker = line.indexOf("#%#");
    if (marker < 0) continue;
    const source = line.slice(marker + 3);
    if (!source.trimStart().startsWith("//scriptlet(")) scripts.add(source);
  }
  return [...scripts];
}

function filesUnder(directory) {
  const files = [];
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) files.push(...filesUnder(path));
    else files.push(path);
  }
  return files;
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function sha256Files(paths, baseDirectory) {
  const hash = createHash("sha256");
  for (const path of [...paths].sort()) {
    hash.update(path.slice(baseDirectory.length + 1));
    hash.update("\0");
    hash.update(readFileSync(path));
    hash.update("\0");
  }
  return hash.digest("hex");
}

function buildInputs(contentEntry) {
  const upstreamSource = join(upstreamDirectory, "src");
  const advancedRules = join(codeDirectory, "filters", "generated", "adguard-base-advanced.txt");
  return {
    generator: sha256File(generatorPath),
    contentEntry: sha256File(contentEntry),
    frontendSource: sha256Files(filesUnder(extensionDirectory).filter(
      path => !outputs.some(name => path === join(extensionDirectory, name)),
    ), extensionDirectory),
    documentBackground: sha256File(join(
      codeDirectory,
      "extension-runtime",
      "document-background.mjs",
    )),
    earlyYoutubePolicy: sha256File(join(codeDirectory, "extension-runtime", "early-youtube-policy.mjs")),
    upstreamSource: sha256Files(filesUnder(upstreamSource), upstreamSource),
    upstreamPackage: sha256File(join(upstreamDirectory, "package.json")),
    upstreamTsconfig: sha256File(join(upstreamDirectory, "tsconfig.json")),
    upstreamLock: sha256File(join(upstreamDirectory, "pnpm-lock.yaml")),
    advancedRules: sha256File(advancedRules),
  };
}

function writeEarlyYoutube(revision, generation) {
  const rules = readFileSync(join(codeDirectory, "filters/generated/adguard-base-advanced.txt"), "utf8");
  const scriptlets = earlyYoutubeScriptlets(rules, generation);
  const source = scriptlet => ({
    engine: "safari-extension",
    name: scriptlet.name,
    args: scriptlet.args,
    version: upstreamPackage.version,
    verbose: false,
    uniqueId: earlyScriptletUniqueId(scriptlet, revision),
  });
  const fn = ScriptletsAPI.getScriptletFunction("set-constant");
  if (typeof fn !== "function") throw new Error("Missing early set-constant runtime");
  writeFileSync(join(extensionDirectory, "early-youtube.js"), [
    runtimeBanner,
    `// Runtime revision: ${revision}`,
    "(() => {",
    '  if (window.top !== window || location.hostname !== "www.youtube.com"',
    '      || location.pathname !== "/watch" || !["http:", "https:"].includes(location.protocol)) return;',
    `  const run = ${fn.toString()};`,
    ...scriptlets.map(scriptlet => `  run(${JSON.stringify(source(scriptlet))}, ${JSON.stringify(scriptlet.args)});`),
    "})();",
    "",
  ].join("\n"));
}

function writeBuildManifest(inputs, revision) {
  const manifest = {
    schemaVersion: 2,
    generation: inputs.advancedRules,
    runtimeRevision: revision,
    inputs,
    outputs: Object.fromEntries(outputs.map(name => [
      name,
      sha256File(join(codeDirectory, "extension", name)),
    ])),
  };
  writeFileSync(
    join(codeDirectory, "extension-runtime", "build-manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
}

function writeBackgroundEntry() {
  const sourcePath = join(
    upstreamDirectory,
    "src",
    "background-script.ts",
  );
  const logPath = join(upstreamDirectory, "src", "log.ts");
  const documentBackgroundPath = join(
    codeDirectory,
    "extension-runtime",
    "document-background.mjs",
  );
  const entries = rawScripts().map(source => [
    `  [${JSON.stringify(source)}, function registeredScript() {`,
    source,
    "  }],",
  ].join("\n"));
  const output = join(tmpdir(), `adblocker-background-entry-${process.pid}.mjs`);
  writeFileSync(output, [
    `import { BackgroundScript } from ${JSON.stringify(sourcePath)};`,
    `import { ConsoleLogger, LoggingLevel, setLogger } from ${JSON.stringify(logPath)};`,
    `import { DocumentBackgroundScript } from ${JSON.stringify(documentBackgroundPath)};`,
    "setLogger(new ConsoleLogger('[Ad Blocker]', LoggingLevel.Error));",
    "export { BackgroundScript, DocumentBackgroundScript };",
    "export const registeredScripts = new Map([",
    ...entries,
    "]);",
    "",
  ].join("\n"));
  return output;
}

const contentEntry = join(codeDirectory, "extension-runtime", "content-entry.mjs");
const inputs = buildInputs(contentEntry);
// Fixed field order is shared with the offline Python verifier.
const revision = createHash("sha256").update(JSON.stringify(inputs)).digest("hex");
writeEarlyYoutube(revision, inputs.advancedRules);
const backgroundEntry = writeBackgroundEntry();
await build(contentEntry, "advanced-content-runtime.js", revision);
try {
  await build(backgroundEntry, "advanced-background-runtime.js", revision);
} finally {
  rmSync(backgroundEntry, { force: true });
}
writeBuildManifest(inputs, revision);
console.log(`Elkészült a két runtime és a korai YouTube-script; ${rawScripts().length} nyers JS-szabály regisztrálva.`);
process.exit(0);
