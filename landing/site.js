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
    // The public notice must be approved before opening collection.
    document.querySelector("#privacy > p").textContent =
      "This preview doesn’t access your Mac’s files or system readings. This version of the page has no analytics or session-recording scripts.";
    document.getElementById("signup-privacy").textContent =
      "Our signup form is hosted by MailerLite. If you subscribe, MailerLite processes your email address and any information you choose to provide so we can send early-access invitations and occasional Pulse updates. You can unsubscribe using the link in our emails.";
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
