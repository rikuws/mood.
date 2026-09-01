(() => {
  "use strict";

  const capture = globalThis.PinaxCapture;
  if (!capture?.extractXPost) {
    return;
  }

  const ARTICLE_SELECTOR = 'article[data-testid="tweet"], article[itemtype*="SocialMediaPosting"]';
  const SLOT_ATTRIBUTE = "data-pinax-slot";
  const BUTTON_ATTRIBUTE = "data-pinax-save";
  const MOOD_MARK_PATH = "M26.57 15.4L19.23 15.39L19.23 14.64L19.87 14.54L20.45 14.21L20.88 13.26L21 6.09L20.88 4.59L20.52 3.61L19.87 2.96L18.95 2.66L18.19 2.66L17.39 2.9L16.44 3.5L15.74 4.25L15.86 13.2L16.04 13.83L16.32 14.24L16.75 14.48L17.45 14.64L17.45 15.39L10.11 15.4L10.16 14.64L10.74 14.54L11.35 14.18L11.63 13.72L11.81 12.97L11.87 5.4L11.74 4.36L11.23 3.32L10.8 2.96L10.17 2.66L9.53 2.63L8.26 3.02L7.63 3.47L6.91 4.25L6.96 13.08L7.15 13.83L7.57 14.32L8.61 14.64L8.61 15.38L1.27 15.4L1.27 14.64L1.91 14.54L2.43 14.27L2.79 13.72L2.92 13.2L3.03 11.58L3.03 5.57L2.98 4.59L2.73 3.67L2.08 3.08L1.11 2.92L1.09 2.34L6.3 0.84L6.59 0.94L6.62 1.13L6.89 1.3L6.99 2.7L8.07 1.71L9.24 1L10.98 0.52L12.3 0.52L13.52 0.82L14.41 1.3L15.02 1.91L15.6 2.94L16.4 2.14L17.33 1.46L19 0.71L20.04 0.52L21.14 0.52L22.29 0.77L23.05 1.11L24.16 2.17L24.56 2.92L24.79 3.73L24.92 4.94L24.98 13.2L25.17 13.83L25.41 14.19L25.88 14.48L26.58 14.64Z";
  const pendingCaptures = new Map();
  const pendingArticles = new Set();
  let scanScheduled = false;
  let lastKnownURL = location.href;

  function createSVGElement(name, attributes) {
    const element = document.createElementNS("http://www.w3.org/2000/svg", name);
    for (const [key, value] of Object.entries(attributes || {})) {
      element.setAttribute(key, value);
    }
    return element;
  }

  function createMoodMark() {
    const icon = createSVGElement("svg", {
      viewBox: "0 0 32 16",
      "aria-hidden": "true"
    });
    icon.append(
      createSVGElement("path", { d: MOOD_MARK_PATH }),
      createSVGElement("circle", { cx: "29.14", cy: "13.69", r: "1.76" })
    );
    return icon;
  }

  function createSaveButton() {
    const slot = document.createElement("div");
    slot.setAttribute(SLOT_ATTRIBUTE, "true");
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute(BUTTON_ATTRIBUTE, "true");
    button.setAttribute("aria-label", "Save to mood");
    button.dataset.state = "idle";

    const icon = createMoodMark();
    const tooltip = document.createElement("span");
    tooltip.setAttribute("data-pinax-tooltip", "true");
    tooltip.textContent = "Save to mood.";
    button.append(icon, tooltip);
    slot.append(button);
    return slot;
  }

  function directChildOf(node, ancestor) {
    let candidate = node;
    while (candidate && candidate.parentElement !== ancestor) {
      candidate = candidate.parentElement;
    }
    return candidate?.parentElement === ancestor ? candidate : null;
  }

  function findActionRow(article) {
    const replyControl = article.querySelector('[data-testid="reply"]');
    if (replyControl) {
      const replyGroup = replyControl.closest('[role="group"]');
      if (replyGroup && article.contains(replyGroup)) {
        return replyGroup;
      }
    }

    return Array.from(article.querySelectorAll('[role="group"]')).find((group) => {
      return group.querySelector('[data-testid="like"], [data-testid="unlike"]')
        && group.querySelector('[data-testid="bookmark"], [data-testid="removeBookmark"], [data-testid="share"]');
    }) || null;
  }

  function installButton(article) {
    const actionRow = findActionRow(article);
    if (!actionRow || actionRow.querySelector(`:scope > [${SLOT_ATTRIBUTE}]`)) {
      return;
    }

    const slot = createSaveButton();
    const button = slot.querySelector(`[${BUTTON_ATTRIBUTE}]`);
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      captureArticle(article, "pinax_button", button);
    });

    const bookmark = actionRow.querySelector('[data-testid="bookmark"], [data-testid="removeBookmark"]');
    const share = actionRow.querySelector('[data-testid="share"]');
    const insertionPoint = directChildOf(bookmark || share, actionRow);
    actionRow.insertBefore(slot, insertionPoint || null);
  }

  function scanForPosts() {
    scanScheduled = false;
    const articles = pendingArticles.size > 0
      ? Array.from(pendingArticles)
      : Array.from(document.querySelectorAll(ARTICLE_SELECTOR));
    pendingArticles.clear();
    for (const article of articles) {
      if (!article.isConnected) {
        continue;
      }
      installButton(article);
    }
  }

  function scheduleScan() {
    if (scanScheduled) {
      return;
    }
    scanScheduled = true;
    requestAnimationFrame(scanForPosts);
  }

  function scheduleFullScan() {
    pendingArticles.clear();
    scheduleScan();
  }

  function queueAffectedArticles(records) {
    for (const record of records) {
      const ownerArticle = record.target instanceof Element
        ? record.target.closest(ARTICLE_SELECTOR)
        : null;
      if (ownerArticle) {
        pendingArticles.add(ownerArticle);
      }

      for (const node of record.addedNodes) {
        if (!(node instanceof Element)) {
          continue;
        }
        if (node.matches(ARTICLE_SELECTOR)) {
          pendingArticles.add(node);
        }
        for (const article of node.querySelectorAll(ARTICLE_SELECTOR)) {
          pendingArticles.add(article);
        }
      }
    }
    if (pendingArticles.size > 0) {
      scheduleScan();
    }
  }

  function showToast(message, kind) {
    let region = document.querySelector("[data-pinax-toast-region]");
    if (!region) {
      region = document.createElement("div");
      region.setAttribute("data-pinax-toast-region", "true");
      region.setAttribute("aria-live", "polite");
      document.documentElement.append(region);
    }

    region.replaceChildren();
    const toast = document.createElement("div");
    toast.setAttribute("data-pinax-toast", "true");
    toast.dataset.kind = kind;
    toast.setAttribute("role", kind === "error" ? "alert" : "status");
    toast.textContent = message;
    region.append(toast);
    requestAnimationFrame(() => {
      toast.dataset.visible = "true";
    });

    const visibleDuration = kind === "error" ? 4_600 : 2_400;
    setTimeout(() => {
      toast.dataset.visible = "false";
      setTimeout(() => {
        if (toast.isConnected) {
          toast.remove();
        }
      }, 180);
    }, visibleDuration);
  }

  function setButtonState(button, state) {
    if (!button?.isConnected) {
      return;
    }
    button.dataset.state = state;
    button.disabled = state === "saving";
    const visibleLabels = {
      idle: "Save to mood.",
      saving: "Saving to mood.…",
      success: "Saved to mood.",
      error: "Could not save to mood."
    };
    const spokenLabels = {
      idle: "Save to mood",
      saving: "Saving to mood",
      success: "Saved to mood",
      error: "Could not save to mood"
    };
    button.setAttribute("aria-label", spokenLabels[state] || spokenLabels.idle);
    const tooltip = button.querySelector("[data-pinax-tooltip]");
    if (tooltip) {
      tooltip.textContent = visibleLabels[state] || visibleLabels.idle;
    }
  }

  function sendCaptureMessage(item, trigger) {
    return new Promise((resolve, reject) => {
      chrome.runtime.sendMessage({ type: "pinax.capture", item, trigger }, (response) => {
        const lastError = chrome.runtime.lastError;
        if (lastError) {
          reject(new Error("Could not connect to the mood. extension. Reload X and try again."));
          return;
        }
        if (!response || typeof response !== "object") {
          reject(new Error("mood. did not respond. Try again."));
          return;
        }
        if (response.ok !== true) {
          reject(new Error(response.error?.message || "Could not save to mood."));
          return;
        }
        resolve(response);
      });
    });
  }

  async function captureExtractedItem(item, trigger, button) {
    const key = item.url;
    const existing = pendingCaptures.get(key);
    if (existing) {
      return existing;
    }

    setButtonState(button, "saving");
    const operation = sendCaptureMessage(item, trigger)
      .then((response) => {
        const wasDuplicate = response.duplicate || response.duplicateClient;
        setButtonState(button, "success");
        showToast(wasDuplicate ? "Already in mood." : "Saved to mood.", "success");
        setTimeout(() => setButtonState(button, "idle"), 1_800);
        return response;
      })
      .catch((error) => {
        setButtonState(button, "error");
        showToast(error?.message || "Could not save to mood.", "error");
        setTimeout(() => setButtonState(button, "idle"), 2_800);
        return null;
      })
      .finally(() => {
        setTimeout(() => {
          if (pendingCaptures.get(key) === operation) {
            pendingCaptures.delete(key);
          }
        }, 1_800);
      });
    pendingCaptures.set(key, operation);
    return operation;
  }

  async function captureArticle(article, trigger, button) {
    let item;
    try {
      item = capture.extractXPost(article, location.href);
    } catch (error) {
      setButtonState(button, "error");
      showToast(error?.message || "Could not read this post.", "error");
      setTimeout(() => setButtonState(button, "idle"), 2_000);
      return;
    }
    return captureExtractedItem(item, trigger, button);
  }

  const observer = new MutationObserver(queueAffectedArticles);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener("popstate", scheduleFullScan);
  window.addEventListener("hashchange", scheduleFullScan);

  setInterval(() => {
    if (location.href !== lastKnownURL) {
      lastKnownURL = location.href;
      scheduleFullScan();
    }
  }, 750);

  scheduleFullScan();
})();
