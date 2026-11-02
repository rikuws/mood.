"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createImporter, describeProgress } = require("../lib/bookmark-import.js");

function post(id, extra = {}) {
  return {
    source: "x",
    url: `https://x.com/designer/status/${id}`,
    title: `@designer: Post ${id}`,
    text: `Post ${id}`,
    ...extra
  };
}

// Lets a test hold each send open and settle it when it's ready.
function controlledSend() {
  const calls = [];
  const send = (item) => new Promise((resolve, reject) => {
    calls.push({ item, resolve, reject });
  });
  return { send, calls };
}

async function settle() {
  for (let turn = 0; turn < 5; turn += 1) {
    await Promise.resolve();
  }
}

function makeImporter(send) {
  const states = [];
  const importer = createImporter({
    send,
    pauseMs: 0,
    wait: () => Promise.resolve(),
    onChange: (state) => states.push(state)
  });
  return { importer, states };
}

test("ignores posts offered before it starts", () => {
  const { importer } = makeImporter(() => Promise.resolve({ ok: true }));
  assert.equal(importer.offer("a", () => post(1)), false);
  assert.equal(importer.state.found, 0);
});

test("saves offered posts one at a time and counts new and existing ones", async () => {
  const { send, calls } = controlledSend();
  const { importer } = makeImporter(send);
  importer.start();
  importer.offer("one", () => post(1));
  importer.offer("two", () => post(2));
  await settle();

  assert.equal(calls.length, 1, "the second post waits for the first");
  calls[0].resolve({ ok: true, duplicate: false });
  await settle();
  assert.equal(calls.length, 2);
  calls[1].resolve({ ok: true, duplicate: true });
  await settle();

  assert.deepEqual(
    { saved: importer.state.saved, alreadySaved: importer.state.alreadySaved, queued: importer.state.queued },
    { saved: 1, alreadySaved: 1, queued: 0 }
  );
  assert.equal(calls[0].item.url, "https://x.com/designer/status/1");
});

test("offers the same post only once, even after a scroll brings it back", async () => {
  const sent = [];
  const { importer } = makeImporter((item) => {
    sent.push(item.url);
    return Promise.resolve({ ok: true });
  });
  importer.start();
  assert.equal(importer.offer("one", () => post(1)), true);
  assert.equal(importer.offer("one", () => post(1)), false);
  await settle();
  assert.equal(importer.offer("one", () => post(1)), false);
  await settle();
  assert.deepEqual(sent, ["https://x.com/designer/status/1"]);
  assert.equal(importer.state.found, 1);
});

test("reads each post when its turn comes, not when it's offered", async () => {
  const { send, calls } = controlledSend();
  const { importer } = makeImporter(send);
  let second = post(2);
  importer.start();
  importer.offer("one", () => post(1));
  importer.offer("two", () => second);
  // The second post's image loads while the first is still saving.
  second = post(2, { imageURL: "https://pbs.twimg.com/media/late.jpg?name=large" });
  await settle();
  calls[0].resolve({ ok: true });
  await settle();
  assert.equal(calls[1].item.imageURL, "https://pbs.twimg.com/media/late.jpg?name=large");
});

test("counts a post that can't be read and moves on", async () => {
  const sent = [];
  const { importer } = makeImporter((item) => {
    sent.push(item.url);
    return Promise.resolve({ ok: true });
  });
  importer.start();
  importer.offer("broken", () => {
    throw new Error("No status link");
  });
  importer.offer("empty", () => null);
  importer.offer("good", () => post(3));
  await settle();
  assert.equal(importer.state.unreadable, 2);
  assert.equal(importer.state.saved, 1);
  assert.deepEqual(sent, ["https://x.com/designer/status/3"]);
});

test("pauses on a failed save and tries that post again first", async () => {
  const { send, calls } = controlledSend();
  const { importer } = makeImporter(send);
  importer.start();
  importer.offer("one", () => post(1));
  importer.offer("two", () => post(2));
  await settle();

  calls[0].reject(new Error("Open mood. once to finish browser setup."));
  await settle();
  assert.equal(importer.state.phase, "failed");
  assert.equal(importer.state.error, "Open mood. once to finish browser setup.");
  assert.equal(importer.state.queued, 2);
  assert.equal(importer.offer("three", () => post(3)), false, "nothing new is taken while paused");

  importer.start();
  await settle();
  assert.equal(importer.state.phase, "running");
  assert.equal(importer.state.error, null);
  assert.equal(calls[1].item.url, "https://x.com/designer/status/1");
});

test("stopping lets the current save finish and holds the rest", async () => {
  const { send, calls } = controlledSend();
  const { importer } = makeImporter(send);
  importer.start();
  importer.offer("one", () => post(1));
  importer.offer("two", () => post(2));
  await settle();

  importer.stop();
  calls[0].resolve({ ok: true });
  await settle();
  assert.equal(importer.state.phase, "stopped");
  assert.equal(importer.state.saved, 1);
  assert.equal(importer.state.queued, 1);
  assert.equal(calls.length, 1);

  importer.start();
  await settle();
  assert.equal(calls.length, 2);
  assert.equal(calls[1].item.url, "https://x.com/designer/status/2");
});

test("reports every change", async () => {
  const { importer, states } = makeImporter(() => Promise.resolve({ ok: true }));
  importer.start();
  importer.offer("one", () => post(1));
  await settle();
  importer.stop();
  assert.deepEqual(
    states.map((state) => state.phase),
    ["running", "running", "running", "stopped"]
  );
  assert.equal(states.at(-1).saved, 1);
});

test("describes progress in a short line", () => {
  const base = { saved: 0, alreadySaved: 0, unreadable: 0 };
  assert.equal(describeProgress(base), "0 saved");
  assert.equal(describeProgress({ ...base, saved: 12 }), "12 saved");
  assert.equal(describeProgress({ ...base, alreadySaved: 3 }), "3 already in mood.");
  assert.equal(
    describeProgress({ saved: 12, alreadySaved: 3, unreadable: 1 }),
    "12 saved · 3 already in mood. · 1 couldn't be read"
  );
});

test("requires a send function", () => {
  assert.throws(() => createImporter({}), TypeError);
});
