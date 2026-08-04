"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const capture = require("../lib/capture-helpers.js");

test("canonicalizes X status links across supported legacy hosts", () => {
  assert.equal(
    capture.canonicalizeXPostURL("https://x.com/pinax_app/status/123456789/photo/1?ref_src=twsrc%5Etfw"),
    "https://x.com/pinax_app/status/123456789"
  );
  assert.equal(
    capture.canonicalizeXPostURL("https://mobile.twitter.com/DesignDaily/status/987654321?s=20"),
    "https://x.com/DesignDaily/status/987654321"
  );
});

test("resolves relative X status links against the current page", () => {
  assert.deepEqual(
    capture.parseXStatusURL("/rikuwikman/status/42/analytics", "https://x.com/home"),
    {
      handle: "rikuwikman",
      statusID: "42",
      url: "https://x.com/rikuwikman/status/42"
    }
  );
});

test("rejects lookalike and non-post X URLs", () => {
  assert.equal(capture.canonicalizeXPostURL("https://example.com/alice/status/123"), null);
  assert.equal(capture.canonicalizeXPostURL("https://x.com/home/status/123"), null);
  assert.equal(capture.canonicalizeXPostURL("javascript:alert(1)"), null);
});

test("normalizes safe page URLs without discarding meaningful queries", () => {
  assert.equal(
    capture.normalizeWebURL("/gallery?page=2#comments", "https://example.com/design/index.html"),
    "https://example.com/gallery?page=2"
  );
  assert.equal(capture.normalizeWebURL("file:///tmp/inspiration.png"), null);
});

test("classifies X and web sources", () => {
  assert.equal(capture.sourceForURL("https://x.com/explore"), "x");
  assert.equal(capture.sourceForURL("https://www.twitter.com/home"), "x");
  assert.equal(capture.sourceForURL("https://example.com/x.com"), "web");
  assert.equal(capture.sourceForURL("not a URL"), "web");
});

test("builds compact, useful titles for X posts", () => {
  assert.equal(
    capture.buildXTitle("@alice", "A lovely piece of interface design", "Alice"),
    "@alice: A lovely piece of interface design"
  );
  assert.equal(capture.buildXTitle("", "", "Alice Example"), "Post by Alice Example");

  const longTitle = capture.buildXTitle("alice", "x".repeat(200), "Alice");
  assert.equal(longTitle.startsWith("@alice: "), true);
  assert.equal(longTitle.endsWith("…"), true);
});

test("normalizes captured text while preserving paragraph breaks", () => {
  assert.equal(
    capture.normalizeWhitespace("  First   line \r\n\r\n\r\n Second\tline  "),
    "First line\n\nSecond line"
  );
  assert.equal(capture.truncateText("abcdef", 4), "abc…");
});

test("accepts useful HTTP images and rejects avatars or unsafe schemes", () => {
  assert.equal(capture.isUsefulImageURL("https://pbs.twimg.com/media/example.jpg"), true);
  assert.equal(capture.isUsefulImageURL("https://example.com/profile_images/user.png"), false);
  assert.equal(capture.isUsefulImageURL("https://abs.twimg.com/rweb/ssr/default/v2/og/image.png"), false);
  assert.equal(capture.isUsefulImageURL("data:image/png;base64,AAAA"), false);
});

test("promotes X media URLs to a stable large rendition", () => {
  assert.equal(
    capture.normalizeXMediaURL(
      "https://pbs.twimg.com/media/HN1QBejaQAAr6Jn?format=jpg&name=small",
      "https://x.com/pinax/status/123"
    ),
    "https://pbs.twimg.com/media/HN1QBejaQAAr6Jn?format=jpg&name=large"
  );
  assert.equal(
    capture.normalizeXMediaURL(
      "https://pbs.twimg.com/media/HN1QBejaQAAr6Jn.jpg:small",
      "https://x.com/pinax/status/123"
    ),
    "https://pbs.twimg.com/media/HN1QBejaQAAr6Jn.jpg:large"
  );
});

test("extracts a usable X image after invalid candidates and from srcset", () => {
  const invalid = fakeMedia({ src: "https://pbs.twimg.com/profile_images/avatar.jpg" });
  const responsive = fakeMedia({
    srcset: [
      "https://pbs.twimg.com/media/example?format=jpg&name=small 680w",
      "https://pbs.twimg.com/media/example?format=jpg&name=medium 1200w"
    ].join(", ")
  });
  const article = {
    querySelectorAll(selector) {
      return selector.startsWith('[data-testid="tweetPhoto"]')
        ? [invalid, responsive]
        : [];
    }
  };

  assert.equal(
    capture.extractXImage(article, "https://x.com/pinax/status/123"),
    "https://pbs.twimg.com/media/example?format=jpg&name=large"
  );
});

test("checks all Open Graph candidates instead of stopping at an avatar", () => {
  const documentObject = {
    images: [],
    querySelectorAll(selector) {
      if (selector === 'meta[property="og:image"]') {
        return [
          fakeMedia({ content: "https://pbs.twimg.com/profile_images/avatar.jpg" }),
          fakeMedia({ content: "https://pbs.twimg.com/media/post.jpg:large" })
        ];
      }
      return [];
    }
  };

  assert.equal(
    capture.firstUsefulImage(documentObject, "https://x.com/pinax/status/123"),
    "https://pbs.twimg.com/media/post.jpg:large"
  );
});

function fakeMedia(attributes) {
  return {
    currentSrc: attributes.currentSrc || "",
    src: attributes.src || "",
    srcset: attributes.srcset || "",
    style: { backgroundImage: attributes.backgroundImage || "" },
    getAttribute(name) {
      return attributes[name] || null;
    }
  };
}
