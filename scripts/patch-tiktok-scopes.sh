#!/usr/bin/env node
/**
 * Postiz hardcodes provider OAuth scopes that Google/TikTok now reject.
 *
 * TikTok: video.list / video.create are no longer offered ("scope" error).
 *   Strip them from quoted scope lists only — leave /v2/video/list/ API paths.
 *
 * YouTube: keep only the scopes submitted on the Google Cloud Console Data
 *   Access screen (plus non-sensitive userinfo for the OAuth handshake).
 *   Connect uses youtube.readonly (channels.list mine=true). Publish uses
 *   youtube.upload (resumable videos.insert + thumbnails.set), which also
 *   sets title, description, tags, privacy, and made-for-kids. Drop the
 *   rest: youtube (full manage), youtube.force-ssl, youtubepartner, and
 *   yt-analytics.readonly. Those extras fail Google's least-privilege
 *   review and are not needed for Autobus connect + post.
 */
const fs = require("fs");
const path = require("path");

function walk(dir, files) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (["proc", "sys", "dev", "node_modules"].includes(entry.name)) continue;
      walk(full, files);
    } else if (/\.(js|mjs|cjs|ts)$/.test(entry.name)) {
      files.push(full);
    }
  }
}

function collect(preferred) {
  const files = [];
  for (const file of preferred) {
    if (fs.existsSync(file)) files.push(file);
  }
  return files;
}

function stripQuoted(text, drop) {
  let next = text;
  for (const scope of drop) {
    const quoted = `['"]${scope.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}['"]`;
    next = next.replace(new RegExp(`${quoted}\\s*,\\s*`, "g"), "");
    next = next.replace(new RegExp(`,\\s*${quoted}`, "g"), "");
  }
  return next;
}

function patchJob({ name, preferred, drop, marker, alreadyOkMessage }) {
  let files = collect(preferred);
  if (files.length === 0) {
    for (const root of ["/app/apps", "/app/libraries", "/app"]) {
      if (fs.existsSync(root)) walk(root, files);
    }
  }

  let patched = 0;
  for (const file of files) {
    let original;
    try {
      original = fs.readFileSync(file, "utf8");
    } catch {
      continue;
    }
    if (!drop.some((scope) => original.includes(scope))) continue;
    if (marker && !original.includes(marker)) continue;
    const next = stripQuoted(original, drop);
    if (next === original) continue;
    fs.writeFileSync(file, next);
    console.log("patched", file);
    patched += 1;
  }

  if (patched > 0) {
    console.log(`${name}: removed ${drop.join(", ")} from ${patched} file(s)`);
    return;
  }

  const stillHas = files.some((file) => {
    try {
      const text = fs.readFileSync(file, "utf8");
      return (
        (!marker || text.includes(marker)) &&
        drop.some((scope) => text.includes(scope))
      );
    } catch {
      return false;
    }
  });
  if (stillHas) {
    console.error(`${name}: found scopes but could not patch them (${drop.join(", ")})`);
    process.exit(1);
  }
  console.log(alreadyOkMessage);
}

patchJob({
  name: "TikTok",
  preferred: [
    "/app/apps/backend/dist/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.js",
    "/app/apps/orchestrator/dist/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.js",
    "/app/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.ts",
  ],
  drop: ["video.list", "video.create"],
  marker: "user.info.basic",
  alreadyOkMessage:
    "TikTok providers already omit deprecated video.list / video.create scopes",
});

const YOUTUBE_SCOPES_KEEP = [
  "https://www.googleapis.com/auth/userinfo.profile",
  "https://www.googleapis.com/auth/userinfo.email",
  "https://www.googleapis.com/auth/youtube.readonly",
  "https://www.googleapis.com/auth/youtube.upload",
];

const YOUTUBE_SCOPES_DROP = [
  "https://www.googleapis.com/auth/youtube",
  "https://www.googleapis.com/auth/youtube.force-ssl",
  "https://www.googleapis.com/auth/youtubepartner",
  "https://www.googleapis.com/auth/yt-analytics.readonly",
];

function rewriteYoutubeScopesArray(text) {
  return text.replace(/scopes\s*([:=])\s*\[[\s\S]*?\]/, (match, eq) => {
    if (
      !match.includes("youtube.upload") &&
      !YOUTUBE_SCOPES_DROP.some((scope) => match.includes(scope))
    ) {
      return match;
    }
    const quote = match.includes("'") ? "'" : '"';
    const inner = YOUTUBE_SCOPES_KEEP.map((scope) => `${quote}${scope}${quote}`).join(
      ", "
    );
    return `scopes${eq}[${inner}]`;
  });
}

function quotedScopePresent(text, scope) {
  return text.includes(`"${scope}"`) || text.includes(`'${scope}'`);
}

function patchYoutubeScopes(preferred) {
  let files = collect(preferred);
  if (files.length === 0) {
    for (const root of ["/app/apps", "/app/libraries", "/app"]) {
      if (fs.existsSync(root)) walk(root, files);
    }
    files = files.filter(
      (file) =>
        /youtube\.provider\.(js|ts)$/.test(file) ||
        file.toLowerCase().includes("youtube.provider")
    );
  }

  let patched = 0;
  for (const file of files) {
    let original;
    try {
      original = fs.readFileSync(file, "utf8");
    } catch {
      continue;
    }
    if (
      !original.includes("youtube.upload") &&
      !YOUTUBE_SCOPES_DROP.some((scope) => original.includes(scope))
    ) {
      continue;
    }
    let next = rewriteYoutubeScopesArray(original);
    next = stripQuoted(next, YOUTUBE_SCOPES_DROP);
    if (next === original) continue;
    fs.writeFileSync(file, next);
    console.log("patched", file);
    patched += 1;
  }

  if (patched > 0) {
    console.log(
      `YouTube: limited OAuth scopes to readonly + upload (+ userinfo) in ${patched} file(s)`
    );
    return;
  }

  const stillHas = files.some((file) => {
    try {
      const text = fs.readFileSync(file, "utf8");
      return YOUTUBE_SCOPES_DROP.some((scope) => quotedScopePresent(text, scope));
    } catch {
      return false;
    }
  });
  if (stillHas) {
    console.error(
      `YouTube: found extra scopes but could not patch them (${YOUTUBE_SCOPES_DROP.join(", ")})`
    );
    process.exit(1);
  }
  console.log(
    "YouTube providers already request only youtube.readonly + youtube.upload (+ userinfo)"
  );
}

patchYoutubeScopes([
  "/app/apps/backend/dist/libraries/nestjs-libraries/src/integrations/social/youtube.provider.js",
  "/app/apps/orchestrator/dist/libraries/nestjs-libraries/src/integrations/social/youtube.provider.js",
  "/app/libraries/nestjs-libraries/src/integrations/social/youtube.provider.ts",
]);

const CREATOR_INFO_MARKER = "autobus-tiktok-creator-info";
const CREATOR_INFO_SNIPPET = `
/* ${CREATOR_INFO_MARKER} */
(function () {
  function attach(proto) {
    if (!proto || proto.queryCreatorInfo) return;
    proto.queryCreatorInfo = async function (accessToken) {
      const res = await fetch(
        "https://open.tiktokapis.com/v2/post/publish/creator_info/query/",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json; charset=UTF-8",
            Authorization: "Bearer " + accessToken,
          },
        }
      );
      return await res.json();
    };
    proto.getCreatorInfo = proto.queryCreatorInfo;
    proto.fetchPublishStatus = async function (accessToken, data) {
      const publishId =
        (data && (data.publish_id || data.publishId)) ||
        (data && data.data && data.data.publish_id);
      const res = await fetch(
        "https://open.tiktokapis.com/v2/post/publish/status/fetch/",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json; charset=UTF-8",
            Authorization: "Bearer " + accessToken,
          },
          body: JSON.stringify({ publish_id: publishId }),
        }
      );
      return await res.json();
    };
  }
  try {
    if (typeof exports !== "undefined" && exports.TiktokProvider) {
      attach(exports.TiktokProvider.prototype);
    }
  } catch (e) {}
})();
`;

function injectCreatorInfo(preferred) {
  let files = collect(preferred);
  if (files.length === 0) {
    for (const root of ["/app/apps", "/app/libraries", "/app"]) {
      if (fs.existsSync(root)) walk(root, files);
    }
    files = files.filter(
      (file) =>
        /tiktok\.provider\.(js|ts)$/.test(file) ||
        file.toLowerCase().includes("tiktok.provider")
    );
  }

  let patched = 0;
  for (const file of files) {
    let original;
    try {
      original = fs.readFileSync(file, "utf8");
    } catch {
      continue;
    }
    if (!/TiktokProvider/.test(original)) continue;
    if (original.includes(CREATOR_INFO_MARKER)) continue;
    fs.writeFileSync(file, original + "\n" + CREATOR_INFO_SNIPPET);
    console.log("injected creator_info into", file);
    patched += 1;
  }
  if (patched > 0) {
    console.log(`TikTok creator_info: injected into ${patched} file(s)`);
    return;
  }
  console.log("TikTok creator_info helper already present or provider not found");
}

injectCreatorInfo([
  "/app/apps/backend/dist/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.js",
  "/app/apps/orchestrator/dist/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.js",
  "/app/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.ts",
]);

const GET_CREATOR_ALIAS_MARKER = "autobus-tiktok-getCreatorInfo-alias";
const GET_CREATOR_ALIAS_SNIPPET = `
/* ${GET_CREATOR_ALIAS_MARKER} */
(function () {
  try {
    var proto =
      typeof exports !== "undefined" && exports.TiktokProvider
        ? exports.TiktokProvider.prototype
        : null;
    if (proto && proto.queryCreatorInfo && !proto.getCreatorInfo) {
      proto.getCreatorInfo = proto.queryCreatorInfo;
    }
  } catch (e) {}
})();
`;

function aliasGetCreatorInfo(preferred) {
  let files = collect(preferred);
  if (files.length === 0) {
    for (const root of ["/app/apps", "/app/libraries", "/app"]) {
      if (fs.existsSync(root)) walk(root, files);
    }
    files = files.filter(
      (file) =>
        /tiktok\.provider\.(js|ts)$/.test(file) ||
        file.toLowerCase().includes("tiktok.provider")
    );
  }

  let patched = 0;
  for (const file of files) {
    let original;
    try {
      original = fs.readFileSync(file, "utf8");
    } catch {
      continue;
    }
    if (!/TiktokProvider/.test(original)) continue;
    if (original.includes(GET_CREATOR_ALIAS_MARKER)) continue;
    fs.writeFileSync(file, original + "\n" + GET_CREATOR_ALIAS_SNIPPET);
    console.log("aliased getCreatorInfo in", file);
    patched += 1;
  }
  if (patched > 0) {
    console.log(`TikTok getCreatorInfo alias: injected into ${patched} file(s)`);
    return;
  }
  console.log("TikTok getCreatorInfo alias already present or provider not found");
}

aliasGetCreatorInfo([
  "/app/apps/backend/dist/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.js",
  "/app/apps/orchestrator/dist/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.js",
  "/app/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.ts",
]);

