import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = path => readFileSync(new URL(path, import.meta.url), "utf8");
const source = read("../filters/adguard-base.txt").split(/\r?\n/);
const local = read("../filters/local-rules.txt").split(/\r?\n/);
const originals = source.filter(line => line.endsWith("$popup,third-party")
  && (line.includes("(35|104)") || line.includes("146\\.59\\.211")));
const projected = local.filter(line => line.endsWith("$popup,third-party"));
const expression = rule => rule.slice(1, rule.lastIndexOf("/$"));
const oldRegex = originals.map(rule => new RegExp(expression(rule), "i"));
const newRegex = projected.map(rule => new RegExp(expression(rule), "i"));

test("popup regex projection preserves original URL matching and third-party modifiers", () => {
  assert.equal(originals.length, 2);
  assert.equal(projected.length, 3);
  const numeric = ["0", "1", "12", "123", "255", "999", "1234", "01", "001", "", "x"];
  const check = url => assert.equal(newRegex.some(re => re.test(url)), oldRegex.some(re => re.test(url)), url);
  for (const scheme of ["http:", "https:", "ftp:"]) {
    for (const prefix of ["35", "104", "146", "350", "1040", "34", "105"]) {
      for (const a of numeric) for (const b of ["1", "59", "999", "1234", ""]) for (const c of numeric) {
        for (const suffix of ["/", "/test", "?x=1", ":80/", "x/test"]) {
          check(`${scheme}//${prefix}.${a}.${b}.${c}${suffix}`);
        }
      }
    }
  }
  for (const url of [
    "https://146.59.211.2/", "https://146.59.211.1234/", "https://146.59.211.2x/test",
    "https://146.59.212.2/", "https://example.com/",
  ]) check(url);
});

test("generated popup projections preserve document fallback and add popup blocking with third-party scope", () => {
  const native = JSON.parse(read("../filters/blockerList.json"));
  for (const rule of projected) {
    const matches = native.filter(entry => entry.action.type === "block"
      && entry.trigger["url-filter"] === expression(rule));
    assert.equal(matches.length, 1, rule);
    assert.deepEqual([...matches[0].trigger["resource-type"]].sort(), ["document", "popup"]);
    assert.deepEqual(matches[0].trigger["load-type"], ["third-party"]);
  }
});
