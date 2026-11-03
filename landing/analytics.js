(() => {
  "use strict";
  // ponytail: explicit Capture API only; no SDK, replay, cookies or autocapture.
  const config = window.PULSE_SITE;
  if (!config?.posthogToken || config.posthogHost !== "https://eu.i.posthog.com") return;
  const controls = document.querySelector(".analytics-choices");
  const status = document.getElementById("analytics-status");
  const allow = document.getElementById("analytics-allow");
  const deny = document.getElementById("analytics-deny");
  const restricted = navigator.globalPrivacyControl || navigator.doNotTrack === "1";
  const consentKey = "pulse-analytics-consent";
  const idKey = "pulse-analytics-id";
  let allowed = !restricted;
  let preferenceSaved = true;
  try {
    allowed = allowed && localStorage.getItem(consentKey) !== "denied";
    // Remove the old persistent analytics identifier; never read or reuse it.
    localStorage.removeItem(idKey);
  } catch { /* Measurement needs no browser storage. */ }
  let visitor;
  let viewed = false;
  const test = location.hostname !== "venkateshdas.github.io" ||
    new URLSearchParams(location.search).get("pulse_test") === "1";
  // Explicit routes only: never send arbitrary paths, filenames or URL queries.
  const guidePath = "/pulse/guides/whats-taking-up-space-on-mac/";
  const slowGuidePath = "/pulse/guides/why-is-my-mac-so-slow/";
  const guidesPath = "/pulse/guides/";
  const pages = {
    "/pulse/": "/pulse/",
    [guidePath]: guidePath,
    [slowGuidePath]: slowGuidePath,
    [guidesPath]: guidesPath,
  };
  // Local preview omits the GitHub project prefix; public routes never do.
  const pathname = location.hostname !== "venkateshdas.github.io" &&
    ["/", "/guides/", "/guides/whats-taking-up-space-on-mac/", "/guides/why-is-my-mac-so-slow/"].includes(location.pathname)
    ? `/pulse${location.pathname}` : location.pathname;
  const page = Object.hasOwn(pages, pathname) ? pages[pathname] : null;
  // Privacy/preferences and unapproved paths never emit measurements.
  let source = "direct";
  try {
    const referrer = new URL(document.referrer).hostname;
    const sources = { "google.com": "google", "bing.com": "bing", "duckduckgo.com": "duckduckgo", "reddit.com": "reddit", "linkedin.com": "linkedin", "github.com": "github", "t.co": "x" };
    source = referrer === location.hostname ? "internal" : "other";
    for (const [host, label] of Object.entries(sources)) {
      if (referrer === host || referrer.endsWith(`.${host}`)) source = label;
    }
  } catch { /* No readable referrer is direct/unknown, not proof of direct acquisition. */ }
  function capture(events, properties = {}) {
    if (!allowed || restricted || !page) return;
    visitor ||= crypto.randomUUID(); // Fresh per page load; never persisted or fingerprinted.
    fetch(`${config.posthogHost}/batch/`, {
      method: "POST", credentials: "omit", referrerPolicy: "no-referrer", keepalive: true,
      // A simple request avoids a CORS preflight being cancelled on navigation.
      headers: { "Content-Type": "text/plain;charset=UTF-8" },
      body: JSON.stringify({ api_key: config.posthogToken, batch: [events].flat().map(event => ({ event, properties: {
        distinct_id: visitor, $process_person_profile: false, $geoip_disable: true,
        page, source, is_test: test, ...properties,
      } })) }),
    }).catch(() => {}); // Analytics failure must never interrupt signup.
  }
  function showChoice() {
    if (!controls) return;
    status.textContent = restricted ? "Website analytics are off to respect your browser’s privacy signal."
      : `Basic website analytics are ${allowed ? "on" : "off"}.${preferenceSaved ? "" : " This preference applies only to this page because browser storage is unavailable."}`;
    allow.disabled = Boolean(restricted || allowed);
    deny.disabled = !allowed;
  }
  function savePreference(value) {
    try { localStorage.setItem(consentKey, value); preferenceSaved = true; }
    catch { preferenceSaved = false; }
  }
  function view() {
    if (allowed && page && !viewed) { capture("$pageview"); viewed = true; }
  }
  if (controls) {
    controls.hidden = false;
    allow.addEventListener("click", () => {
      allowed = !restricted;
      if (!restricted) savePreference("allowed");
      view(); showChoice();
    });
    deny.addEventListener("click", () => {
      allowed = false;
      savePreference("denied");
      showChoice();
    });
  }
  view(); showChoice();
  window.addEventListener("storage", (event) => {
    if (event.key !== consentKey && event.key !== null) return;
    allowed = !restricted && event.newValue !== "denied";
    view(); showChoice();
  });
  document.querySelectorAll('a[href$="#early-access"]').forEach((link) => {
    link.addEventListener("click", () => capture("early_access_click", {
      position: link.closest("nav") ? "navigation" : link.closest(".hero") ? "hero" : "page",
    }));
  });
  document.getElementById("signup-link")?.addEventListener("click", () => {
    if (document.getElementById("signup-link").getAttribute("aria-disabled") === "true") return;
    // One request keeps the two observations together during navigation.
    capture(["early_access_click", "waitlist_form_open"], { position: "signup" });
  });
  for (const guide of ["whats-taking-up-space-on-mac", "why-is-my-mac-so-slow"]) {
    document.querySelectorAll(`[data-guide-product="${guide}"]`).forEach((link) => {
      link.addEventListener("click", () => capture("guide_product_click", { guide }));
    });
  }
  document.querySelectorAll('[role="tab"]').forEach((tab) => {
    tab.addEventListener("click", () => capture("preview_theme_selected", {
      theme: tab.textContent.trim() === "Dark" ? "dark" : "light",
    }));
  });
})();
