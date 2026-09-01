#!/usr/bin/env node
/**
 * Postiz hardcodes provider OAuth scopes that Google/TikTok now reject.
 *
 * TikTok: video.list / video.create are no longer offered ("scope" error).
 *   Strip them from quoted scope lists only — leave /v2/video/list/ API paths.
 *
 * YouTube: youtubepartner is a restricted CMS/Content ID scope. Regular
 *   channels cannot grant it. Google then shows "Sorry, something went wrong"
 *   plus a security alert, even for OAuth testers. Uploading only needs
 *   youtube / youtube.upload / youtube.force-ssl.
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

patchJob({
  name: "YouTube",
  preferred: [
    "/app/apps/backend/dist/libraries/nestjs-libraries/src/integrations/social/youtube.provider.js",
    "/app/apps/orchestrator/dist/libraries/nestjs-libraries/src/integrations/social/youtube.provider.js",
    "/app/libraries/nestjs-libraries/src/integrations/social/youtube.provider.ts",
  ],
  drop: ["https://www.googleapis.com/auth/youtubepartner"],
  marker: "youtube.upload",
  alreadyOkMessage:
    "YouTube providers already omit restricted youtubepartner scope",
});
