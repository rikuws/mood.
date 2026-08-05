(function pinaxCaptureHelpers(root, factory) {
  const api = factory();

  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }

  if (root) {
    root.PinaxCapture = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function createPinaxCaptureHelpers() {
  "use strict";

  const X_HOSTS = new Set([
    "x.com",
    "www.x.com",
    "mobile.x.com",
    "twitter.com",
    "www.twitter.com",
    "mobile.twitter.com"
  ]);

  const RESERVED_X_PATHS = new Set([
    "compose",
    "explore",
    "home",
    "i",
    "intent",
    "messages",
    "notifications",
    "search",
    "settings",
    "share"
  ]);

  function normalizeWhitespace(value) {
    return String(value || "")
      .replace(/\r\n?/g, "\n")
      .replace(/[\t\f\v ]+/g, " ")
      .replace(/ *\n */g, "\n")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  }

  function truncateText(value, maximumLength) {
    const text = normalizeWhitespace(value);
    const limit = Number.isFinite(maximumLength) ? Math.max(1, maximumLength) : 10_000;

    if (text.length <= limit) {
      return text;
    }

    if (limit === 1) {
      return "…";
    }

    return `${text.slice(0, limit - 1).trimEnd()}…`;
  }

  function toHTTPURL(value, baseURL) {
    if (!value) {
      return null;
    }

    try {
      const url = new URL(String(value), baseURL || undefined);
      if (url.protocol !== "http:" && url.protocol !== "https:") {
        return null;
      }
      url.username = "";
      url.password = "";
      return url;
    } catch (_error) {
      return null;
    }
  }

  function normalizeWebURL(value, baseURL) {
    const url = toHTTPURL(value, baseURL);
    if (!url) {
      return null;
    }

    url.hash = "";
    return url.href;
  }

  function isXHostname(hostname) {
    return X_HOSTS.has(String(hostname || "").toLowerCase());
  }

  function parseXStatusURL(value, baseURL) {
    const url = toHTTPURL(value, baseURL);
    if (!url || !isXHostname(url.hostname)) {
      return null;
    }

    const match = url.pathname.match(/^\/([A-Za-z0-9_]{1,20})\/status\/(\d+)(?:\/|$)/i);
    if (!match || RESERVED_X_PATHS.has(match[1].toLowerCase())) {
      return null;
    }

    return {
      handle: match[1],
      statusID: match[2],
      url: `https://x.com/${match[1]}/status/${match[2]}`
    };
  }

  function canonicalizeXPostURL(value, baseURL) {
    return parseXStatusURL(value, baseURL)?.url || null;
  }

  function sourceForURL(value, baseURL) {
    const url = toHTTPURL(value, baseURL);
    return url && isXHostname(url.hostname) ? "x" : "web";
  }

  function buildXTitle(authorHandle, text, authorName) {
    const handle = normalizeWhitespace(authorHandle).replace(/^@/, "");
    const name = normalizeWhitespace(authorName);
    const excerpt = truncateText(text, 96);
    const byline = handle ? `@${handle}` : name || "X post";
    return excerpt ? `${byline}: ${excerpt}` : `Post by ${byline}`;
  }

  function isUsefulImageURL(value, baseURL) {
    const url = toHTTPURL(value, baseURL);
    if (!url) {
      return false;
    }

    const path = url.pathname.toLowerCase();
    if (/\.(svg|ico)(?:$|\?)/.test(path)) {
      return false;
    }

    if (url.hostname.toLowerCase() === "abs.twimg.com" && /\/rweb\/ssr\/default\//i.test(path)) {
      return false;
    }

    return !/(emoji|profile_images|favicon|avatar)/i.test(url.href);
  }

  function normalizeXMediaURL(value, baseURL) {
    const normalized = normalizeWebURL(value, baseURL);
    const url = toHTTPURL(normalized);
    if (!url) {
      return null;
    }

    if (url.hostname.toLowerCase() === "pbs.twimg.com" && url.pathname.startsWith("/media/")) {
      url.pathname = url.pathname.replace(/:(?:thumb|small|medium|large)$/i, ":large");
      if (url.searchParams.has("name")) {
        url.searchParams.set("name", "large");
      }
    }
    return url.href;
  }

  function imageCandidateValues(element) {
    if (!element) {
      return [];
    }

    const values = [
      element.getAttribute?.("poster"),
      element.currentSrc,
      element.src,
      element.getAttribute?.("src"),
      element.getAttribute?.("data-src")
    ];
    const srcset = element.getAttribute?.("srcset") || element.srcset;
    if (srcset) {
      values.push(
        ...String(srcset)
          .split(",")
          .map((entry) => entry.trim().split(/\s+/, 1)[0])
          .reverse()
      );
    }

    const background = element.style?.backgroundImage || element.getAttribute?.("style") || "";
    const backgroundMatch = String(background).match(/url\(\s*(["']?)(.*?)\1\s*\)/i);
    if (backgroundMatch?.[2]) {
      values.push(backgroundMatch[2]);
    }
    return values.filter(Boolean);
  }

  function firstUsefulElementImage(elements, baseURL) {
    for (const element of elements) {
      for (const value of imageCandidateValues(element)) {
        const normalized = normalizeXMediaURL(value, baseURL);
        if (normalized && isUsefulImageURL(normalized, baseURL)) {
          return normalized;
        }
      }
    }
    return null;
  }

  function elementText(element) {
    if (!element) {
      return "";
    }
    return normalizeWhitespace(element.innerText || element.textContent || "");
  }

  function metaContent(documentObject, selectors) {
    for (const selector of selectors) {
      const value = documentObject.querySelector(selector)?.getAttribute("content");
      if (normalizeWhitespace(value)) {
        return normalizeWhitespace(value);
      }
    }
    return "";
  }

  function firstUsefulImage(documentObject, baseURL) {
    const metaSelectors = [
      'meta[property="og:image"]',
      'meta[property="og:image:secure_url"]',
      'meta[name="twitter:image"]',
      'meta[name="twitter:image:src"]'
    ];
    for (const selector of metaSelectors) {
      for (const meta of documentObject.querySelectorAll(selector)) {
        const normalized = normalizeXMediaURL(meta.getAttribute("content"), baseURL);
        if (normalized && isUsefulImageURL(normalized, baseURL)) {
          return normalized;
        }
      }
    }

    const images = Array.from(documentObject.images || []);
    const image = images.find((candidate) => {
      const source = imageCandidateValues(candidate)[0];
      const width = Number(candidate.naturalWidth || candidate.width || 0);
      const height = Number(candidate.naturalHeight || candidate.height || 0);
      return isUsefulImageURL(source, baseURL) && width >= 200 && height >= 120;
    });

    return image ? normalizeXMediaURL(imageCandidateValues(image)[0], baseURL) : null;
  }

  function findXPostLink(article, baseURL) {
    const timeLink = article.querySelector("time")?.closest("a[href]");
    const candidates = [
      timeLink,
      ...article.querySelectorAll('a[href*="/status/"]')
    ].filter(Boolean);

    for (const link of candidates) {
      const parsed = parseXStatusURL(link.getAttribute("href"), baseURL);
      if (parsed) {
        return parsed;
      }
    }

    return parseXStatusURL(baseURL);
  }

  function extractXAuthor(article, parsedPost) {
    const userName = article.querySelector('[data-testid="User-Name"]');
    let handle = parsedPost?.handle || "";

    if (!handle && userName) {
      for (const link of userName.querySelectorAll("a[href]")) {
        const path = toHTTPURL(link.getAttribute("href"), "https://x.com")?.pathname || "";
        const match = path.match(/^\/([A-Za-z0-9_]{1,20})\/?$/);
        if (match && !RESERVED_X_PATHS.has(match[1].toLowerCase())) {
          handle = match[1];
          break;
        }
      }
    }

    const rawLines = elementText(userName)
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);
    const expectedHandle = handle ? `@${handle}`.toLowerCase() : "";
    const authorName = rawLines.find((line) => {
      const lower = line.toLowerCase();
      return !line.startsWith("@") && lower !== expectedHandle && line !== "·";
    }) || "";

    if (!handle) {
      const handleLine = rawLines.find((line) => /^@[A-Za-z0-9_]{1,20}$/.test(line));
      handle = handleLine ? handleLine.slice(1) : "";
    }

    return {
      authorName: truncateText(authorName, 160),
      authorHandle: truncateText(handle.replace(/^@/, ""), 32)
    };
  }

  function extractXImage(article, baseURL) {
    const selectors = [
      '[data-testid="tweetPhoto"] img, [data-testid="tweetPhoto"] source, [data-testid="tweetPhoto"][style*="background-image"]',
      'video[poster]',
      '[data-testid="videoPlayer"] video, [data-testid="videoPlayer"] [style*="background-image"]',
      '[data-testid="card.wrapper"] img, [data-testid="card.wrapper"] source, [data-testid="card.wrapper"] [style*="background-image"]',
      'a[href*="/photo/"] img, a[href*="/photo/"] source',
      'img[src*="pbs.twimg.com/media"], img[srcset*="pbs.twimg.com/media"]'
    ];

    for (const selector of selectors) {
      const normalized = firstUsefulElementImage(
        Array.from(article.querySelectorAll(selector)),
        baseURL
      );
      if (normalized) {
        return normalized;
      }
    }

    return null;
  }

  function extractXPost(article, pageURL) {
    if (!article || typeof article.querySelector !== "function") {
      throw new TypeError("A post article element is required");
    }

    const post = findXPostLink(article, pageURL);
    if (!post) {
      throw new Error("Could not find the canonical URL for this X post");
    }

    const text = truncateText(elementText(article.querySelector('[data-testid="tweetText"]')), 10_000);
    const author = extractXAuthor(article, post);
    const imageURL = extractXImage(article, pageURL);
    const item = {
      source: "x",
      url: post.url,
      title: buildXTitle(author.authorHandle, text, author.authorName),
      text
    };

    if (author.authorName) {
      item.authorName = author.authorName;
    }
    if (author.authorHandle) {
      item.authorHandle = author.authorHandle;
    }
    if (imageURL) {
      item.imageURL = imageURL;
    }

    return item;
  }

  function extractPage(documentObject, pageURL) {
    if (!documentObject || typeof documentObject.querySelector !== "function") {
      throw new TypeError("A document is required");
    }

    const baseURL = normalizeWebURL(pageURL || documentObject.location?.href);
    if (!baseURL) {
      throw new Error("mood. can only save HTTP or HTTPS pages");
    }

    const focusedElement = documentObject.activeElement;
    const focusedArticle = focusedElement?.closest?.('article[data-testid="tweet"]');
    const pagePost = parseXStatusURL(baseURL);
    const matchingArticle = pagePost
      ? Array.from(documentObject.querySelectorAll('article[data-testid="tweet"]')).find((article) => {
        return findXPostLink(article, baseURL)?.statusID === pagePost.statusID;
      })
      : null;
    const xArticle = focusedArticle
      || matchingArticle
      || (pagePost ? documentObject.querySelector('article[data-testid="tweet"]') : null);
    if (xArticle) {
      try {
        return extractXPost(xArticle, baseURL);
      } catch (_error) {
        // Fall back to capturing the page when X has not finished rendering the post.
      }
    }

    const canonicalCandidate = documentObject.querySelector('link[rel~="canonical"][href]')?.getAttribute("href")
      || metaContent(documentObject, ['meta[property="og:url"]'])
      || baseURL;
    const canonicalURL = canonicalizeXPostURL(canonicalCandidate, baseURL)
      || normalizeWebURL(canonicalCandidate, baseURL)
      || baseURL;
    const selectedText = normalizeWhitespace(documentObject.defaultView?.getSelection?.().toString());
    const description = metaContent(documentObject, [
      'meta[property="og:description"]',
      'meta[name="description"]',
      'meta[name="twitter:description"]'
    ]);
    const fallbackText = elementText(documentObject.querySelector("main article, article, main p, article p"));
    const text = truncateText(selectedText || description || fallbackText, 10_000);
    const title = truncateText(
      metaContent(documentObject, ['meta[property="og:title"]', 'meta[name="twitter:title"]'])
        || documentObject.title
        || canonicalURL,
      300
    );
    const authorName = truncateText(metaContent(documentObject, [
      'meta[name="author"]',
      'meta[property="article:author"]'
    ]), 160);
    const imageURL = firstUsefulImage(documentObject, baseURL);
    const item = {
      source: sourceForURL(baseURL),
      url: canonicalURL,
      title,
      text
    };

    if (authorName) {
      item.authorName = authorName;
    }
    if (imageURL) {
      item.imageURL = imageURL;
    }

    return item;
  }

  return Object.freeze({
    buildXTitle,
    canonicalizeXPostURL,
    extractPage,
    extractXImage,
    extractXPost,
    firstUsefulImage,
    isUsefulImageURL,
    isXHostname,
    normalizeXMediaURL,
    normalizeWebURL,
    normalizeWhitespace,
    parseXStatusURL,
    sourceForURL,
    truncateText
  });
});
