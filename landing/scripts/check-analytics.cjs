// Native Node checks: no real network requests or persistent browser identifiers.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const code = fs.readFileSync(require('node:path').join(__dirname, '../analytics.js'), 'utf8');
let uuid = 0;
function setup({ restricted = false, stored = {}, blockedStorage = false, pathname = '/', hostname = 'localhost', controls = false, dnt = false, guide = 'whats-taking-up-space-on-mac' } = {}) {
  const sent = [], storage = new Map(Object.entries(stored)), nodes = new Map(), events = {};
  function node(id) {
    if (!nodes.has(id)) nodes.set(id, { textContent: '', handlers: {}, addEventListener(name, fn) { this.handlers[name] = fn; }, getAttribute() { return null; }, closest() { return null; } });
    return nodes.get(id);
  }
  const window = { PULSE_SITE: { posthogToken: 'test', posthogHost: 'https://eu.i.posthog.com' }, addEventListener(name, fn) { events[name] = fn; } };
  vm.runInNewContext(code, { window, navigator: { globalPrivacyControl: restricted, doNotTrack: dnt ? '1' : '0' },
    document: { referrer: 'https://www.google.com/search?q=private-email@example.com', querySelector: () => controls ? node('controls') : null, getElementById: node,
      querySelectorAll: (selector) => selector === 'a[href$="#early-access"]' ? [node('early-access')] : selector === `[data-guide-product="${guide}"]` ? [node('guide-product')] : [] },
    location: { hostname, pathname, search: '?email=private-email@example.com' },
    localStorage: { getItem(key) { if (blockedStorage) throw Error(); return storage.get(key); }, setItem(key, value) { if (blockedStorage) throw Error(); storage.set(key, value); }, removeItem(key) { if (blockedStorage) throw Error(); storage.delete(key); } },
    crypto: { randomUUID: () => `page-load-${++uuid}` }, URL, URLSearchParams,
    fetch(url, options) { sent.push({ url, options, payload: JSON.parse(options.body) }); return Promise.resolve(); },
  });
  return { sent, storage, node, events };
}
const first = setup();
assert.equal(first.sent.length, 1); // Starts without any prompt or controls.
assert.equal(first.sent[0].payload.batch[0].event, '$pageview');
assert.equal(first.storage.size, 0);
const props = first.sent[0].payload.batch[0].properties;
assert.equal(props.source, 'google');
assert.equal(props.$process_person_profile, false);
assert.equal(props.$geoip_disable, true);
assert.equal(first.sent[0].options.credentials, 'omit');
assert.equal(first.sent[0].options.referrerPolicy, 'no-referrer');
first.node('signup-link').handlers.click();
assert.deepEqual(first.sent[1].payload.batch.map(e => e.event), ['early_access_click', 'waitlist_form_open']);
assert.equal(first.sent[1].payload.batch[0].properties.distinct_id, props.distinct_id);
const nextPage = setup();
assert.notEqual(nextPage.sent[0].payload.batch[0].properties.distinct_id, props.distinct_id);
assert(!JSON.stringify(first.sent).includes('private-email'));
const legacy = setup({ stored: { 'pulse-analytics-id': 'old-persistent-id', 'pulse-analytics-consent': 'allowed' } });
assert(!legacy.storage.has('pulse-analytics-id'));
assert(!JSON.stringify(legacy.sent).includes('old-persistent-id'));
assert.equal(legacy.sent.length, 1);
for (const options of [{ restricted: true }, { dnt: true }, { stored: { 'pulse-analytics-consent': 'denied' } }]) {
  assert.equal(setup(options).sent.length, 0);
}
assert.equal(setup({ blockedStorage: true }).sent.length, 1); // In-memory measurement doesn't need storage.
const privacy = setup({ pathname: '/privacy/', controls: true });
assert.equal(privacy.sent.length, 0);
privacy.node('analytics-deny').handlers.click();
assert.equal(privacy.storage.get('pulse-analytics-consent'), 'denied');
assert.equal(privacy.storage.has('pulse-analytics-id'), false);
privacy.node('analytics-allow').handlers.click();
assert.equal(privacy.sent.length, 0); // Preferences page never emits events.
const preference = setup({ controls: true });
preference.node('analytics-deny').handlers.click();
preference.node('signup-link').handlers.click();
assert.equal(preference.sent.length, 1);
preference.node('analytics-allow').handlers.click();
assert.equal(preference.sent.length, 1); // Don't double count the current page.
preference.node('guide-product').handlers.click();
assert.equal(preference.sent[1].payload.batch[0].event, 'guide_product_click');
preference.events.storage({ key: 'pulse-analytics-consent', newValue: 'denied' });
preference.node('guide-product').handlers.click();
assert.equal(preference.sent.length, 2);
const blockedPreference = setup({ controls: true, blockedStorage: true });
blockedPreference.node('analytics-deny').handlers.click();
assert(blockedPreference.node('analytics-status').textContent.includes('only to this page'));
const guidePath = '/pulse/guides/whats-taking-up-space-on-mac/';
for (const pathname of ['/', '/pulse/', '/guides/', '/pulse/guides/', '/guides/whats-taking-up-space-on-mac/', guidePath, '/guides/why-is-my-mac-so-slow/', '/pulse/guides/why-is-my-mac-so-slow/']) {
  const local = !pathname.startsWith('/pulse/');
  const route = setup({ pathname, hostname: local ? 'localhost' : 'venkateshdas.github.io' });
  assert.equal(route.sent.length, 1);
  assert.equal(route.sent[0].payload.batch[0].properties.page, local ? `/pulse${pathname}` : pathname);
  assert.equal(route.sent[0].payload.batch[0].properties.is_test, local);
}
for (const pathname of ['/private-person-name/', '/pulse/privacy/', '/pulse/thanks/', '/pulse/guides/private-draft/', '/toString', '/__proto__']) assert.equal(setup({ pathname }).sent.length, 0);
assert.equal(setup({ pathname: '/', hostname: 'venkateshdas.github.io' }).sent.length, 0);
const hub = setup({ pathname: '/guides/' });
hub.node('early-access').handlers.click();
assert.equal(hub.sent[1].payload.batch[0].event, 'early_access_click');
assert.equal(hub.sent[1].payload.batch[0].properties.page, '/pulse/guides/');
console.log('Default-on, per-page identity, legacy-ID removal, preference, browser-signal and route privacy checks passed.');

const slow = setup({ pathname: '/pulse/guides/why-is-my-mac-so-slow/', hostname: 'venkateshdas.github.io', guide: 'why-is-my-mac-so-slow' });
slow.node('guide-product').handlers.click();
assert.equal(slow.sent[1].payload.batch[0].properties.guide, 'why-is-my-mac-so-slow');
assert.equal(slow.sent[1].payload.batch[0].properties.page, '/pulse/guides/why-is-my-mac-so-slow/');
