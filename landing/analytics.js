(() => {
  "use strict";
  // ponytail: explicit Capture API only; no SDK, replay, cookies or autocapture.
  const config = window.PULSE_SITE;
  const controls = document.querySelector(".analytics-choices");
  if (!controls || !config?.posthogToken || config.posthogHost !== "https://eu.i.posthog.com") return;
  const status = document.getElementById("analytics-status");
  const allow = document.getElementById("analytics-allow");
  const deny = document.getElementById("analytics-deny");
  const restricted = navigator.globalPrivacyControl || navigator.doNotTrack === "1";
  const consentKey = "pulse-analytics-consent";
  const idKey = "pulse-analytics-id";
  let allowed = false;
  let visitor;
  let viewed = false;
  const test = location.hostname !== "venkateshdas.github.io" ||
    new URLSearchParams(location.search).get("pulse_test") === "1";
  const page = "/pulse/";
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
    if (!allowed || restricted) return;
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
    status.textContent = restricted ? "Analytics are off to respect your browser’s privacy signal."
      : allowed ? "Optional analytics are on. You can turn them off at any time."
      : "Optional analytics are off. Signup and previews work normally.";
    allow.disabled = Boolean(restricted || allowed);
    deny.textContent = allowed ? "Turn analytics off" : "Keep analytics off";
  }
  function enable() {
    if (restricted) { showChoice(); return; }
    try {
      const saved = localStorage.getItem(idKey);
      visitor = /^[0-9a-f-]{36}$/i.test(saved || "") ? saved : crypto.randomUUID();
      localStorage.setItem(idKey, visitor);
      localStorage.setItem(consentKey, "allowed");
      allowed = !restricted;
    } catch { allowed = false; }
    if (allowed && !viewed) { capture("$pageview"); viewed = true; }
    showChoice();
  }
  controls.hidden = false;
  allow.addEventListener("click", enable);
  deny.addEventListener("click", () => {
    allowed = false;
    visitor = undefined;
    viewed = false;
    try { localStorage.setItem(consentKey, "denied"); localStorage.removeItem(idKey); } catch {}
    showChoice();
  });
  try { if (!restricted && localStorage.getItem(consentKey) === "allowed") enable(); } catch {}
  showChoice();
  window.addEventListener("storage", (event) => {
    if (event.key !== consentKey && event.key !== null) return;
    if (event.newValue === "allowed") return;
    allowed = false;
    visitor = undefined;
    viewed = false;
    showChoice();
  });
  document.querySelectorAll('a[href="#early-access"]').forEach((link) => {
    link.addEventListener("click", () => capture("early_access_click", {
      position: link.closest("nav") ? "navigation" : link.closest(".hero") ? "hero" : "page",
    }));
  });
  document.getElementById("signup-link").addEventListener("click", () => {
    if (document.getElementById("signup-link").getAttribute("aria-disabled") === "true") return;
    // One request keeps the two observations together during navigation.
    capture(["early_access_click", "waitlist_form_open"], { position: "signup" });
  });
  document.querySelectorAll('[role="tab"]').forEach((tab) => {
    tab.addEventListener("click", () => capture("preview_theme_selected", {
      theme: tab.textContent.trim() === "Dark" ? "dark" : "light",
    }));
  });
})();
