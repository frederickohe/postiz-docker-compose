#!/usr/bin/env node
/**
 * Postiz hardcodes TikTok OAuth scopes including video.list / video.create.
 * TikTok no longer offers those scopes, so authorize fails with "scope".
 * Strip them from quoted scope lists only — leave /v2/video/list/ API paths.
 */
const fs = require("fs");
const path = require("path");

const DROP = ["video.list", "video.create"];

function patchText(text) {
  let next = text;
  for (const scope of DROP) {
    const quoted = `['"]${scope.replace(".", "\\.")}['"]`;
    next = next.replace(new RegExp(`${quoted}\\s*,\\s*`, "g"), "");
    next = next.replace(new RegExp(`,\\s*${quoted}`, "g"), "");
  }
  return next;
}

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

const preferred = [
  "/app/apps/backend/dist/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.js",
  "/app/apps/orchestrator/dist/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.js",
  "/app/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.ts",
];

const files = [];
for (const file of preferred) {
  if (fs.existsSync(file)) files.push(file);
}

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
  if (!DROP.some((scope) => original.includes(scope))) continue;
  if (!original.includes("user.info.basic")) continue;
  const next = patchText(original);
  if (next === original) continue;
  fs.writeFileSync(file, next);
  console.log("patched", file);
  patched += 1;
}

if (patched === 0) {
  console.error("No Postiz TikTok scope bundles were patched");
  process.exit(1);
}

console.log(`Removed deprecated TikTok scopes from ${patched} file(s)`);
