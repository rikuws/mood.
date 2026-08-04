(() => {
  "use strict";

  const capture = globalThis.PinaxCapture;
  if (!capture?.extractXPost) {
    return;
  }

  const ARTICLE_SELECTOR = 'article[data-testid="tweet"]';
  const SLOT_ATTRIBUTE = "data-pinax-slot";
  const BUTTON_ATTRIBUTE = "data-pinax-save";
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

  function createSaveButton() {
    const slot = document.createElement("div");
    slot.setAttribute(SLOT_ATTRIBUTE, "true");
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute(BUTTON_ATTRIBUTE, "true");
    button.setAttribute("aria-label", "Save to Pinax");
    button.dataset.state = "idle";

    const icon = createSVGElement("svg", {
      viewBox: "0 0 24 24",
      "aria-hidden": "true"
    });
    icon.append(
      createSVGElement("path", { d: "M7.75 4.25h8.5a1.5 1.5 0 0 1 1.5 1.5v14l-5.75-4-5.75 4v-14a1.5 1.5 0 0 1 1.5-1.5Z" }),
      createSVGElement("path", { d: "M12 7.5v5M9.5 10h5" })
    );
    const tooltip = document.createElement("span");
    tooltip.setAttribute("data-pinax-tooltip", "true");
    tooltip.textContent = "Save to Pinax";
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
    const labels = {
      idle: "Save to Pinax",
      saving: "Saving to Pinax",
      success: "Saved to Pinax",
      error: "Could not save to Pinax"
    };
    button.setAttribute("aria-label", labels[state] || labels.idle);
    const tooltip = button.querySelector("[data-pinax-tooltip]");
    if (tooltip) {
      tooltip.textContent = labels[state] || labels.idle;
    }
  }

  function sendCaptureMessage(item, trigger) {
    return new Promise((resolve, reject) => {
      chrome.runtime.sendMessage({ type: "pinax.capture", item, trigger }, (response) => {
        const lastError = chrome.runtime.lastError;
        if (lastError) {
          reject(new Error("Could not connect to the Pinax extension. Reload X and try again."));
          return;
        }
        if (!response || typeof response !== "object") {
          reject(new Error("Pinax did not respond. Try again."));
          return;
        }
        if (response.ok !== true) {
          reject(new Error(response.error?.message || "Could not save to Pinax."));
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
        showToast(wasDuplicate ? "Already in Pinax" : "Saved to Pinax", "success");
        setTimeout(() => setButtonState(button, "idle"), 1_800);
        return response;
      })
      .catch((error) => {
        setButtonState(button, "error");
        showToast(error?.message || "Could not save to Pinax.", "error");
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

  function waitForBookmarkConfirmation(article, actionRow, control, expectedURL) {
    return new Promise((resolve) => {
      let settled = false;
      let observer;
      let timeout;

      const finish = (confirmed) => {
        if (settled) {
          return;
        }
        settled = true;
        observer?.disconnect();
        clearTimeout(timeout);
        resolve(confirmed);
      };

      const isConfirmed = () => {
        const currentRow = actionRow.isConnected ? actionRow : findActionRow(article);
        const hasRemoveControl = control.getAttribute("data-testid") === "removeBookmark"
          || Boolean(currentRow?.querySelector('[data-testid="removeBookmark"]'));
        if (!hasRemoveControl || !article.isConnected) {
          return false;
        }
        try {
          return capture.extractXPost(article, location.href).url === expectedURL;
        } catch (_error) {
          return false;
        }
      };

      observer = new MutationObserver(() => {
        if (isConfirmed()) {
          finish(true);
        }
      });
      observer.observe(article, {
        attributes: true,
        attributeFilter: ["data-testid", "aria-pressed"],
        childList: true,
        subtree: true
      });
      timeout = setTimeout(() => finish(false), 2_500);
      setTimeout(() => {
        if (isConfirmed()) {
          finish(true);
        }
      }, 0);
    });
  }

  function elementInComposedPath(event, selector) {
    for (const node of event.composedPath()) {
      if (node instanceof Element) {
        if (node.matches(selector)) {
          return node;
        }
        const match = node.closest(selector);
        if (match) {
          return match;
        }
      }
    }
    return null;
  }

  document.addEventListener("click", (event) => {
    // X changes data-testid to removeBookmark after a successful add. Matching
    // only bookmark makes removal clicks a deliberate no-op.
    const addBookmarkControl = elementInComposedPath(event, '[data-testid="bookmark"]');
    if (!addBookmarkControl || elementInComposedPath(event, `[${BUTTON_ATTRIBUTE}]`)) {
      return;
    }

    const article = addBookmarkControl.closest(ARTICLE_SELECTOR)
      || elementInComposedPath(event, ARTICLE_SELECTOR);
    if (!article) {
      return;
    }

    // Read the post synchronously before X can recycle its DOM, but only send
    // it after X confirms the add by changing Bookmark to Remove bookmark.
    // Failed/aborted bookmark requests therefore never create Pinax items.
    let item;
    try {
      item = capture.extractXPost(article, location.href);
    } catch (error) {
      showToast(error?.message || "Could not read this post.", "error");
      return;
    }
    const actionRow = findActionRow(article);
    if (!actionRow) {
      return;
    }
    waitForBookmarkConfirmation(article, actionRow, addBookmarkControl, item.url)
      .then((confirmed) => {
        if (confirmed) {
          return captureExtractedItem(item, "x_bookmark", null);
        }
        return null;
      });
  }, true);

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
