"use strict";

const NATIVE_HOST_NAME = "com.pinax.native_host";
const PROTOCOL_VERSION = 1;
const RAPID_CAPTURE_WINDOW_MS = 1_800;
const NATIVE_RESPONSE_TIMEOUT_MS = 15_000;
const VALID_TRIGGERS = new Set(["toolbar", "pinax_button"]);
const recentCaptures = new Map();

class PinaxCaptureError extends Error {
  constructor(message, code = "capture_failed") {
    super(message);
    this.name = "PinaxCaptureError";
    this.code = code;
  }
}

function makeRequestID() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

function normalizeString(value, maximumLength) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, maximumLength);
}

function validatedItem(value) {
  if (!value || typeof value !== "object") {
    throw new PinaxCaptureError("Nothing on this page could be saved.", "invalid_capture");
  }

  let url;
  try {
    url = new URL(value.url);
  } catch (_error) {
    throw new PinaxCaptureError("This page does not have a valid web address.", "invalid_url");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new PinaxCaptureError("mood. can only save web pages.", "unsupported_url");
  }

  const source = value.source === "x" ? "x" : "web";
  const item = {
    source,
    url: url.href,
    title: normalizeString(value.title, 300) || url.hostname,
    text: normalizeString(value.text, 10_000)
  };

  const authorName = normalizeString(value.authorName, 160);
  const authorHandle = normalizeString(value.authorHandle, 32).replace(/^@/, "");
  const imageURL = normalizeString(value.imageURL, 4_096);
  if (authorName) {
    item.authorName = authorName;
  }
  if (authorHandle) {
    item.authorHandle = authorHandle;
  }
  if (imageURL) {
    try {
      const parsedImageURL = new URL(imageURL, item.url);
      if (parsedImageURL.protocol === "http:" || parsedImageURL.protocol === "https:") {
        item.imageURL = parsedImageURL.href;
      }
    } catch (_error) {
      // An invalid preview should not prevent the rest of the capture from saving.
    }
  }

  return item;
}

function nativeErrorMessage(rawMessage) {
  const message = String(rawMessage || "");
  if (/host not found|not registered|specified native messaging host/i.test(message)) {
    return "Open mood. once to finish browser setup.";
  }
  if (/forbidden|not allowed|access.*denied/i.test(message)) {
    return "mood. is not authorized for this browser. Reopen mood. to repair the connection.";
  }
  if (/exited|broken pipe|disconnected|closed/i.test(message)) {
    return "mood. stopped responding. Open the app and try again.";
  }
  return "Could not reach mood. Make sure the app is installed, then try again.";
}

function sendNativeMessage(message) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const timeout = setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new PinaxCaptureError("mood. took too long to respond.", "native_timeout"));
      }
    }, NATIVE_RESPONSE_TIMEOUT_MS);

    try {
      chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message, (response) => {
        const lastError = chrome.runtime.lastError;
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeout);

        if (lastError) {
          reject(new PinaxCaptureError(nativeErrorMessage(lastError.message), "native_unavailable"));
          return;
        }
        if (!response || typeof response !== "object") {
          reject(new PinaxCaptureError("mood. returned an empty response.", "invalid_native_response"));
          return;
        }
        if (response.ok !== true) {
          const responseMessage = normalizeString(response.error?.message, 500)
            || "mood. could not save this visual.";
          const responseCode = normalizeString(response.error?.code, 80) || "native_rejected";
          reject(new PinaxCaptureError(responseMessage, responseCode));
          return;
        }

        resolve({
          ok: true,
          ...(typeof response.itemId === "string" ? { itemId: response.itemId } : {}),
          duplicate: response.duplicate === true
        });
      });
    } catch (error) {
      clearTimeout(timeout);
      settled = true;
      reject(new PinaxCaptureError(nativeErrorMessage(error?.message), "native_unavailable"));
    }
  });
}

function pruneRecentCaptures(now) {
  for (const [key, entry] of recentCaptures) {
    if (now - entry.startedAt > RAPID_CAPTURE_WINDOW_MS * 3) {
      recentCaptures.delete(key);
    }
  }
}

async function captureItem(rawItem, rawTrigger) {
  const item = validatedItem(rawItem);
  const trigger = VALID_TRIGGERS.has(rawTrigger) ? rawTrigger : "toolbar";
  const key = `${item.source}:${item.url}`;
  const now = Date.now();
  pruneRecentCaptures(now);

  const recent = recentCaptures.get(key);
  if (recent && now - recent.startedAt < RAPID_CAPTURE_WINDOW_MS) {
    const result = await recent.promise;
    return { ...result, duplicateClient: true };
  }

  const request = {
    protocolVersion: PROTOCOL_VERSION,
    type: "capture",
    requestId: makeRequestID(),
    capturedAt: new Date().toISOString(),
    item,
    context: {
      trigger,
      browser: "chromium-extension",
      extensionVersion: chrome.runtime.getManifest().version
    }
  };
  const promise = sendNativeMessage(request);
  recentCaptures.set(key, { startedAt: now, promise });

  try {
    return await promise;
  } catch (error) {
    recentCaptures.delete(key);
    throw error;
  }
}

function publicError(error) {
  return {
    ok: false,
    error: {
      code: normalizeString(error?.code, 80) || "capture_failed",
      message: normalizeString(error?.message, 500) || "Could not save to mood."
    }
  };
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "pinax.capture" || sender.id !== chrome.runtime.id) {
    return false;
  }

  captureItem(message.item, message.trigger)
    .then(sendResponse)
    .catch((error) => sendResponse(publicError(error)));
  return true;
});

function setActionFeedback(tabId, state) {
  const values = {
    saving: { text: "…", color: "#536471", title: "Saving to mood.…" },
    success: { text: "✓", color: "#00A36C", title: "Saved to mood." },
    error: { text: "!", color: "#E5484D", title: "Could not save to mood." },
    idle: { text: "", color: "#536471", title: "Save to mood." }
  };
  const value = values[state] || values.idle;

  for (const operation of [
    chrome.action.setBadgeBackgroundColor({ tabId, color: value.color }),
    chrome.action.setBadgeText({ tabId, text: value.text }),
    chrome.action.setTitle({ tabId, title: value.title })
  ]) {
    operation?.catch?.(() => {});
  }
}

function renderPageFeedback(message, kind) {
  const existing = document.querySelector("[data-pinax-page-feedback]");
  existing?.remove();

  const host = document.createElement("div");
  host.dataset.pinaxPageFeedback = "true";
  host.style.setProperty("all", "initial", "important");
  host.style.setProperty("position", "fixed", "important");
  host.style.setProperty("top", "18px", "important");
  host.style.setProperty("right", "18px", "important");
  host.style.setProperty("z-index", "2147483647", "important");
  const shadow = host.attachShadow({ mode: "open" });
  const toast = document.createElement("div");
  toast.textContent = message;
  toast.setAttribute("role", kind === "error" ? "alert" : "status");
  toast.style.cssText = [
    "box-sizing:border-box",
    "max-width:360px",
    "padding:11px 14px",
    "border:1px solid rgba(255,255,255,.14)",
    "border-radius:12px",
    `background:${kind === "error" ? "#b4232c" : "#16202a"}`,
    "box-shadow:0 8px 30px rgba(0,0,0,.28)",
    "color:#fff",
    "font:600 13px/1.35 -apple-system,BlinkMacSystemFont,\"Segoe UI\",sans-serif",
    "letter-spacing:0",
    "opacity:0",
    "transform:translateY(-6px)",
    "transition:opacity 150ms ease,transform 150ms ease"
  ].join(";");
  shadow.append(toast);
  document.documentElement.append(host);

  requestAnimationFrame(() => {
    toast.style.opacity = "1";
    toast.style.transform = "translateY(0)";
  });
  setTimeout(() => {
    toast.style.opacity = "0";
    toast.style.transform = "translateY(-6px)";
    setTimeout(() => host.remove(), 180);
  }, kind === "error" ? 4_600 : 2_400);
}

async function showToolbarResult(tabId, message, kind) {
  try {
    await chrome.scripting.executeScript({
      target: { tabId },
      func: renderPageFeedback,
      args: [message, kind]
    });
  } catch (_error) {
    // The action badge remains visible on pages where Chromium forbids injection.
  }
}

function extractPageInTab() {
  try {
    if (!globalThis.PinaxCapture?.extractPage) {
      throw new Error("mood. capture helpers are unavailable");
    }
    return {
      ok: true,
      item: globalThis.PinaxCapture.extractPage(document, location.href)
    };
  } catch (error) {
    return {
      ok: false,
      error: {
        code: "extraction_failed",
        message: String(error?.message || "Nothing on this page could be saved.")
      }
    };
  }
}

chrome.action.onClicked.addListener(async (tab) => {
  const tabId = tab.id;
  if (typeof tabId !== "number") {
    return;
  }

  setActionFeedback(tabId, "saving");
  try {
    const pageURL = new URL(tab.url || "");
    if (pageURL.protocol !== "http:" && pageURL.protocol !== "https:") {
      throw new PinaxCaptureError("mood. can only save web pages.", "unsupported_url");
    }

    await chrome.scripting.executeScript({
      target: { tabId },
      files: ["lib/capture-helpers.js"]
    });
    const results = await chrome.scripting.executeScript({
      target: { tabId },
      func: extractPageInTab
    });
    const capture = results.find((entry) => entry.frameId === 0)?.result;
    if (!capture?.ok) {
      throw new PinaxCaptureError(
        normalizeString(capture?.error?.message, 500) || "Nothing on this page could be saved.",
        normalizeString(capture?.error?.code, 80) || "extraction_failed"
      );
    }

    const result = await captureItem(capture.item, "toolbar");
    const message = result.duplicate || result.duplicateClient ? "Already in mood." : "Saved to mood.";
    setActionFeedback(tabId, "success");
    await showToolbarResult(tabId, message, "success");
    setTimeout(() => setActionFeedback(tabId, "idle"), 2_500);
  } catch (error) {
    const failure = publicError(error);
    setActionFeedback(tabId, "error");
    await showToolbarResult(tabId, failure.error.message, "error");
    setTimeout(() => setActionFeedback(tabId, "idle"), 5_000);
  }
});
