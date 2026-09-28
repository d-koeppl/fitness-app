// Drives the web build that start.sh serves: signs in through the Auth
// emulator's Google popup, then screenshots each section, or runs your own
// steps instead.
//
//   node drive.mjs [--size 1280x800] [--tag desktop] [--email demo@example.com]
//                  [--steps my-steps.mjs]
//
// --steps names a module whose default export is
// `async ({ page, shot, nav, W, H }) => {}`; it runs after sign-in in place
// of the section tour. Screenshots go to build/run-app/shots/<tag>-<name>.png.
import { createRequire } from 'module';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/opt/node22/lib/node_modules/playwright');

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : fallback;
};
const [W, H] = arg('size', '1280x800').split('x').map(Number);
const tag = arg('tag', W >= 800 ? 'desktop' : 'phone');
const email = arg('email', 'demo@example.com');
const steps = arg('steps');

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const out = path.join(repo, 'build/run-app');
fs.mkdirSync(`${out}/shots`, { recursive: true });
fs.mkdirSync(`${out}/cdn-cache`, { recursive: true });

// Software WebGL for CanvasKit; there is no GPU.
const browser = await chromium.launch({ args: ['--no-sandbox', '--enable-unsafe-swiftshader'] });
// A locale is required: with none, the app dies at start with "Incorrect
// locale information provided". en-GB/Vienna is what the formatting targets.
const ctx = await browser.newContext({
  locale: 'en-GB', timezoneId: 'Europe/Vienna', viewport: { width: W, height: H },
});

// Chromium's own connections to Google's CDNs (Firebase JS SDK, fonts) fail
// intermittently in the cloud container, so Node fetches every external file
// through the session proxy (run with NODE_USE_ENV_PROXY=1) and caches it.
// accounts.google.com is blocked by the network policy; the emulator
// sign-in does not need it.
await ctx.route(url => !/^https?:\/\/(127\.0\.0\.1|localhost)[:/]/.test(url.href), async route => {
  const url = route.request().url();
  const f = `${out}/cdn-cache/` + crypto.createHash('sha1').update(url).digest('hex');
  if (!fs.existsSync(f)) {
    let res;
    try { res = await fetch(url); } catch (e) { return route.abort(); }
    if (!res.ok) {
      if (!url.includes('accounts.google.com')) console.log('external', res.status, url);
      return route.fulfill({ status: res.status });
    }
    fs.writeFileSync(f + '.type', res.headers.get('content-type') || 'application/octet-stream');
    fs.writeFileSync(f, Buffer.from(await res.arrayBuffer()));
  }
  route.fulfill({
    status: 200, body: fs.readFileSync(f), contentType: fs.readFileSync(f + '.type', 'utf8'),
    headers: { 'access-control-allow-origin': '*' },
  });
});

const page = await ctx.newPage();
page.on('pageerror', e => console.log('pageerror', e.message.slice(0, 300)));
page.on('console', m => {
  if (m.type() === 'error' && !m.location().url.includes('accounts.google.com')) {
    console.log('console error', m.text().slice(0, 200), m.location().url);
  }
});
page.on('response', r => {
  if (r.url().includes(':5001/') && r.status() >= 400) console.log('api', r.status(), r.url());
});

const shot = async name => {
  await page.waitForTimeout(2500); // charts animate in
  const file = `${out}/shots/${tag}-${name}.png`;
  await page.screenshot({ path: file });
  console.log('shot', file);
};

// Centres of the nav items. Flutter paints to a canvas, so these are
// positions, not selectors: the side rail from 800 px up, the icon-only
// bottom bar below. Re-measure from a screenshot if the shell changes.
const nav = W >= 800
  ? { today: [94, 90], fitness: [94, 138], health: [94, 186], coach: [94, 234] }
  : { today: [51, H - 53], fitness: [152, H - 53], health: [257, H - 53], coach: [360, H - 53] };

await page.goto('http://127.0.0.1:5050/');
await page.waitForSelector('flutter-view', { state: 'attached', timeout: 90000 });
await page.waitForTimeout(6000);
// Turns on Flutter's semantics tree, which gives the buttons roles and names.
await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
await shot('01-signin');

const [popup] = await Promise.all([
  page.waitForEvent('popup'),
  page.getByRole('button', { name: /sign in with google/i }).click(),
]);
await popup.waitForLoadState();
await popup.getByText(/add new account/i).click();
// Auto-generate fills a random email; the one typed afterwards wins. Only
// an address in ALLOWED_EMAILS (functions/.env.local) gets past the gate.
const auto = popup.getByText(/auto-generate user information/i);
if (await auto.count()) await auto.click();
await popup.locator('input#email-input, input[type=email]').first().fill(email);
await popup.getByRole('button', { name: /sign in/i }).click();
await page.waitForTimeout(8000);

if (steps) {
  const run = (await import(pathToFileURL(path.resolve(steps)))).default;
  await run({ page, shot, nav, W, H });
} else {
  await shot('02-today');
  for (const [i, name] of ['fitness', 'health', 'coach'].entries()) {
    await page.mouse.click(...nav[name]);
    await shot(`0${i + 3}-${name}`);
  }
}
await browser.close();
