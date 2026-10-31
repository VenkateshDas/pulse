(() => {
  "use strict";
  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  function selectTab(tab, focus = false) {
    tabs.forEach((item) => {
      const selected = item === tab;
      item.setAttribute("aria-selected", String(selected));
      item.tabIndex = selected ? 0 : -1;
      document.getElementById(item.getAttribute("aria-controls")).hidden =
        !selected;
    });
    if (focus) tab.focus();
  }
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => selectTab(tab));
    tab.addEventListener("keydown", (event) => {
      const index = tabs.indexOf(tab);
      let next;
      if (event.key === "ArrowDown" || event.key === "ArrowRight")
        next = (index + 1) % tabs.length;
      if (event.key === "ArrowUp" || event.key === "ArrowLeft")
        next = (index - 1 + tabs.length) % tabs.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = tabs.length - 1;
      if (next !== undefined) {
        event.preventDefault();
        selectTab(tabs[next], true);
      }
    });
  });
  document.querySelectorAll('.native-pan').forEach((panel) => {
    panel.addEventListener('keydown', (event) => {
      if (event.target !== panel || panel.scrollWidth <= panel.clientWidth) return;
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      event.preventDefault();
      panel.scrollBy({ left: panel.clientWidth * (event.key === 'ArrowRight' ? 0.8 : -0.8), behavior: 'auto' });
    });
  });
  const signup = document.getElementById("signup-link");
  const status = document.getElementById("signup-status");
  let waitlistUrl;
  try {
    const candidate = new URL(window.PULSE_SITE?.waitlistUrl || "");
    // MailerLite also supports branded form URLs. Only verified HTTPS links.
    if (
      candidate.protocol === "https:" &&
      !candidate.username &&
      !candidate.password
    )
      waitlistUrl = candidate.href;
  } catch {
    /* An empty/invalid setting leaves signup closed. */
  }
  if (waitlistUrl) {
    signup.href = waitlistUrl;
    status.textContent =
      "Continue to our signup form, then confirm your email to join.";
    document.getElementById("signup-note").textContent =
      "Early-access invitations and occasional updates. Unsubscribe at any time.";
  } else {
    signup.setAttribute("aria-disabled", "true");
    signup.textContent = "Early access opens soon";
    signup.addEventListener("click", (event) => {
      event.preventDefault();
      status.textContent =
        "Signup isn’t open yet. No email address has been collected.";
    });
  }
})();
