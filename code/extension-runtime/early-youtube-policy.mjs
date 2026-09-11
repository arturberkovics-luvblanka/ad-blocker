// Deliberately narrow: only the four reviewed, unconditional player-data rules.
// Review exceptions again when updating the filter generation.
export const reviewedGeneration = "6e45fc354371732ec243cb4b5b205b31a9fc8d219e1970bf021047c1f57b9b02";
export const earlyYoutubeProperties = [
  "ytInitialPlayerResponse.adPlacements",
  "ytInitialPlayerResponse.adSlots",
  "ytInitialPlayerResponse.playerAds",
  "playerResponse.adPlacements",
];

export function earlyYoutubeScriptlets(rules, generation) {
  if (generation !== reviewedGeneration) {
    throw new Error("Review early YouTube rules and exceptions for the new filter generation");
  }
  const lines = rules.split("\n");
  return earlyYoutubeProperties.map(property => {
    const rule = `youtubekids.com,youtube-nocookie.com,youtube.com#%#//scriptlet('set-constant', '${property}', 'undefined')`;
    if (lines.filter(line => line === rule).length !== 1) {
      throw new Error(`Expected one reviewed early rule: ${property}`);
    }
    return { name: "set-constant", args: [property, "undefined"] };
  });
}

export function earlyScriptletUniqueId(scriptlet, runtimeRevision) {
  if (scriptlet.name !== "set-constant" || scriptlet.args.length !== 2
      || scriptlet.args[1] !== "undefined"
      || typeof runtimeRevision !== "string" || !/^[a-f0-9]{64}$/.test(runtimeRevision)
      || !earlyYoutubeProperties.includes(scriptlet.args[0])) return undefined;
  // Scriptlets' own wrapper skips identical successful invocations in one MAIN world.
  // JSON preserves argument boundaries, unlike its built-in underscore-joined suffix.
  return `org.local.adblocker:${runtimeRevision}:${JSON.stringify([scriptlet.name, scriptlet.args])}:`;
}
