(function pinaxBookmarkImport(root, factory) {
  const api = factory();

  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }

  if (root) {
    root.PinaxBookmarkImport = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function createPinaxBookmarkImport() {
  "use strict";

  // Saves the person's existing X bookmarks one post at a time, as they
  // scroll their Bookmarks page into view. It never scrolls or fetches
  // anything itself: posts come from `offer`, and each one is sent through
  // the same capture path as the mood. button.
  function createImporter(options) {
    const send = options?.send;
    if (typeof send !== "function") {
      throw new TypeError("A send function is required");
    }
    const onChange = typeof options.onChange === "function" ? options.onChange : () => {};
    const pauseMs = Number.isFinite(options.pauseMs) ? Math.max(0, options.pauseMs) : 120;
    const wait = typeof options.wait === "function"
      ? options.wait
      : (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

    const queue = [];
    const seen = new Set();
    const counts = { saved: 0, alreadySaved: 0, unreadable: 0 };
    let phase = "idle";
    let error = null;
    let isDraining = false;

    function snapshot() {
      return Object.freeze({
        phase,
        error,
        found: seen.size,
        queued: queue.length,
        saved: counts.saved,
        alreadySaved: counts.alreadySaved,
        unreadable: counts.unreadable
      });
    }

    function changed() {
      onChange(snapshot());
    }

    async function drain() {
      if (isDraining) {
        return;
      }
      isDraining = true;
      try {
        while (phase === "running" && queue.length > 0) {
          const entry = queue.shift();
          let item = null;
          try {
            item = entry.read();
          } catch (_error) {
            item = null;
          }
          if (!item) {
            counts.unreadable += 1;
            changed();
            continue;
          }

          try {
            const response = await send(item);
            if (response?.duplicate || response?.duplicateClient) {
              counts.alreadySaved += 1;
            } else {
              counts.saved += 1;
            }
          } catch (failure) {
            // Kept at the front, so trying again picks up with this post.
            queue.unshift(entry);
            phase = "failed";
            error = String(failure?.message || "Could not save to mood.");
            changed();
            break;
          }
          changed();
          if (phase === "running" && queue.length > 0) {
            await wait(pauseMs);
          }
        }
      } finally {
        isDraining = false;
      }
    }

    function start() {
      if (phase === "running") {
        return;
      }
      phase = "running";
      error = null;
      changed();
      drain();
    }

    function stop() {
      if (phase !== "running") {
        return;
      }
      phase = "stopped";
      changed();
    }

    // Queues a post the person has scrolled to. `read` is called when the
    // post's turn comes, so it can return the most complete version of it.
    function offer(key, read) {
      if (phase !== "running" || !key || seen.has(key) || typeof read !== "function") {
        return false;
      }
      seen.add(key);
      queue.push({ key, read });
      changed();
      drain();
      return true;
    }

    return Object.freeze({
      start,
      stop,
      offer,
      get state() {
        return snapshot();
      }
    });
  }

  function describeProgress(state) {
    const parts = [];
    if (state.saved > 0 || (state.alreadySaved === 0 && state.unreadable === 0)) {
      parts.push(`${state.saved} saved`);
    }
    if (state.alreadySaved > 0) {
      parts.push(`${state.alreadySaved} already in mood.`);
    }
    if (state.unreadable > 0) {
      parts.push(`${state.unreadable} couldn't be read`);
    }
    return parts.join(" · ");
  }

  return Object.freeze({
    createImporter,
    describeProgress
  });
});
