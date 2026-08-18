"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const extensionRoot = path.resolve(__dirname, "..");
const manifest = JSON.parse(
  fs.readFileSync(path.join(extensionRoot, "manifest.json"), "utf8")
);
const serviceWorker = fs.readFileSync(
  path.join(extensionRoot, "background/service-worker.js"),
  "utf8"
);
const xContent = fs.readFileSync(
  path.join(extensionRoot, "content/x-content.js"),
  "utf8"
);

test("presents mood. as a general visual moodboard", () => {
  assert.equal(manifest.name, "mood.");
  assert.equal(manifest.action.default_title, "Save to mood.");
  assert.deepEqual(manifest.icons, {
    16: "icons/icon-16.png",
    32: "icons/icon-32.png",
    48: "icons/icon-48.png",
    128: "icons/icon-128.png"
  });
  assert.deepEqual(manifest.action.default_icon, {
    16: "icons/icon-16.png",
    32: "icons/icon-32.png"
  });
  for (const relativePath of Object.values(manifest.icons)) {
    assert.ok(fs.statSync(path.join(extensionRoot, relativePath)).isFile());
  }
  assert.match(manifest.description, /visual references/i);
  assert.doesNotMatch(manifest.description, /UI|design inspiration/i);
  assert.match(xContent, /tooltip\.textContent = "Save to mood\."/);
  assert.match(xContent, /aria-label", "Save to mood"/);
  assert.match(xContent, /viewBox: "0 0 32 16"/);
  assert.match(xContent, /createSVGElement\("circle"/);
  assert.doesNotMatch(xContent, /M7\.75 4\.25h8\.5/);
  assert.doesNotMatch(xContent, /x_bookmark/);
  assert.doesNotMatch(serviceWorker, /x_bookmark/);
});

test("keeps browser capture identities compatible", () => {
  assert.match(serviceWorker, /NATIVE_HOST_NAME = "com\.pinax\.native_host"/);
  assert.match(serviceWorker, /message\?\.type !== "pinax\.capture"/);
  assert.equal(typeof manifest.key, "string");
  assert.ok(manifest.key.length > 100);
});
