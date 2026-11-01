// Native Node smoke checks; no browser dependency and no network traffic.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const code = fs.readFileSync(require('node:path').join(__dirname, '../analytics.js'), 'utf8');
function setup({ restricted = false, stored = {}, blockedStorage = false, pathname = "/", hostname = "localhost", noSignup = false, dnt = false } = {}) {
  const sent = [], storage = new Map(Object.entries(stored)), nodes = new Map(), events = {};
  function node(id) {
    if (!nodes.has(id)) nodes.set(id, { textContent: '', handlers: {},
      addEventListener(name, fn) { this.handlers[name] = fn; },
      getAttribute() { return null; }, closest() { return null; } });
    return nodes.get(id);
  }
  const window = { PULSE_SITE: { posthogToken: 'test', posthogHost: 'https://eu.i.posthog.com' },
    addEventListener(name, fn) { events[name] = fn; } };
  vm.runInNewContext(code, { window, navigator: { globalPrivacyControl: restricted, doNotTrack: dnt ? "1" : "0" },
    document: { referrer: 'https://www.google.com/search?q=private-email@example.com',
      querySelector: node, getElementById: (id) => noSignup && id === 'signup-link' ? null : node(id),
      querySelectorAll: (selector) => selector.startsWith('[data-guide-product=') ? [node('guide-product')] : [] },
    location: { hostname, pathname, search: '?email=private-email@example.com' },
    localStorage: { getItem(key) { if (blockedStorage) throw Error(); return storage.get(key); },
      setItem(key, value) { if (blockedStorage) throw Error(); storage.set(key, value); },
      removeItem(key) { storage.delete(key); } },
    crypto: { randomUUID: () => 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }, URL, URLSearchParams,
    fetch(url, options) { sent.push({ url, options, payload: JSON.parse(options.body) }); return Promise.resolve(); },
  });
  return { sent, storage, node, events };
}
const test = setup();
assert.equal(test.sent.length, 0); // No request or visitor ID before permission.
assert.equal(test.storage.size, 0);
test.node('analytics-allow').handlers.click();
assert.equal(test.sent.length, 1);
assert.equal(test.sent[0].payload.batch[0].event, '$pageview');
assert.equal(test.sent[0].payload.batch[0].properties.source, 'google');
assert.equal(test.sent[0].payload.batch[0].properties.is_test, true);
assert.equal(test.sent[0].payload.batch[0].properties.$process_person_profile, false);
assert.equal(test.sent[0].options.referrerPolicy, 'no-referrer');
assert(!JSON.stringify(test.sent).includes('private-email'));
test.node('analytics-allow').handlers.click();
assert.equal(test.sent.length, 1); // No duplicate view on repeated permission.
test.node('signup-link').handlers.click();
assert.deepEqual(test.sent.slice(1).flatMap(x => x.payload.batch.map(e => e.event)), ['early_access_click', 'waitlist_form_open']);
test.node('analytics-deny').handlers.click();
test.node('signup-link').handlers.click();
assert.equal(test.sent.length, 2);
assert.equal(test.storage.has('pulse-analytics-id'), false);
test.node('analytics-allow').handlers.click();
test.events.storage({ key: 'pulse-analytics-consent', newValue: 'denied' });
test.node('signup-link').handlers.click();
assert.equal(test.sent.length, 3); // Re-opt-in records a view; cross-tab withdrawal stops capture.
const restricted = setup({ restricted: true });
restricted.node('analytics-allow').handlers.click();
assert.equal(restricted.sent.length, 0);
assert.equal(restricted.storage.size, 0);
const blocked = setup({ blockedStorage: true });
blocked.node('analytics-allow').handlers.click();
assert.equal(blocked.sent.length, 0);
console.log('Analytics privacy and event smoke checks passed.');

const guidePath = '/pulse/guides/whats-taking-up-space-on-mac/';
for (const pathname of ['/', '/pulse/', '/guides/whats-taking-up-space-on-mac/', guidePath]) {
  const route = setup({ pathname, hostname: pathname.startsWith('/pulse/') ? 'venkateshdas.github.io' : 'localhost' });
  route.node('analytics-allow').handlers.click();
  const props = route.sent[0].payload.batch[0].properties;
  assert.equal(props.page, pathname.includes('guides/') ? guidePath : '/pulse/');
  assert.equal(props.is_test, !pathname.startsWith('/pulse/'));
  route.node('guide-product').handlers.click();
  assert.equal(route.sent[1].payload.batch[0].event, 'guide_product_click');
  assert.equal(route.sent[1].payload.batch[0].properties.guide, 'whats-taking-up-space-on-mac');
  route.node('analytics-deny').handlers.click();
  route.node('guide-product').handlers.click();
  assert.equal(route.sent.length, 2);
  assert(!JSON.stringify(route.sent).includes('private-email'));
}
for (const pathname of ['/private-person-name/', '/pulse/thanks/', '/pulse/guides/private-draft/', '/toString', '/__proto__']) {
  const unknown = setup({ pathname, stored: { 'pulse-analytics-consent': 'allowed' } });
  assert.equal(unknown.sent.length, 0);
  assert.equal(unknown.node('analytics-allow').handlers.click, undefined);
}
const noSignup = setup({ noSignup: true });
noSignup.node('analytics-allow').handlers.click();
assert.equal(noSignup.sent.length, 1);
console.log('Guide routes, product interest, opt-out and unknown-path checks passed.');

const publicRoot = setup({ pathname: '/', hostname: 'venkateshdas.github.io', stored: { 'pulse-analytics-consent': 'allowed' } });
assert.equal(publicRoot.sent.length, 0);

const guideDnt = setup({ pathname: guidePath, dnt: true });
guideDnt.node('analytics-allow').handlers.click();
assert.equal(guideDnt.sent.length, 0);
assert.equal(guideDnt.storage.size, 0);
