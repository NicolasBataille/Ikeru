// Render every design-rig screen to PNG so design work can be reviewed visually.
// Usage: node design-rig/screenshot.mjs [screenName ...]
import { createRequire } from 'module';
import { readdirSync, mkdirSync } from 'fs';
import { resolve, dirname, basename } from 'path';
import { fileURLToPath } from 'url';

const rigDir = dirname(fileURLToPath(import.meta.url));

// Resolve playwright from a local install or a global lib dir.
const require = createRequire(import.meta.url);
const { chromium } = (() => {
  for (const spec of ['playwright', '/opt/node22/lib/node_modules/playwright/index.js']) {
    try {
      return require(spec);
    } catch { /* try next */ }
  }
  throw new Error('playwright not found — npm i -g playwright or npm i playwright');
})();
const shotsDir = resolve(rigDir, 'shots');
mkdirSync(shotsDir, { recursive: true });

const only = process.argv.slice(2);
const screens = readdirSync(resolve(rigDir, 'screens'))
  .filter((f) => f.endsWith('.html'))
  .map((f) => basename(f, '.html'))
  .filter((n) => only.length === 0 || only.includes(n));

const launch = async () => {
  try {
    return await chromium.launch();
  } catch {
    return await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  }
};

const browser = await launch();
const page = await browser.newPage({
  viewport: { width: 500, height: 980 },
  deviceScaleFactor: 2,
  colorScheme: 'dark',
});

for (const name of screens) {
  const url = 'file://' + resolve(rigDir, 'screens', `${name}.html`);
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForTimeout(400); // font + layout settle
  await page.screenshot({ path: resolve(shotsDir, `${name}.png`) });
  console.log(`shot: shots/${name}.png`);
}

// gallery
await page.setViewportSize({ width: 1100, height: 900 });
await page.goto('file://' + resolve(rigDir, 'index.html'), { waitUntil: 'networkidle' });
await page.waitForTimeout(300);
await page.screenshot({ path: resolve(shotsDir, 'index.png'), fullPage: true });
console.log('shot: shots/index.png');

await browser.close();
