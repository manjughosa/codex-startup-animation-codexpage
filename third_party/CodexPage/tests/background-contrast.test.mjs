import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

test('native light and dark text stays readable over the opposite wallpaper extremes', {
  skip: process.platform !== 'win32',
}, async () => {
  const edge = path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe');
  await fs.access(edge);
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'skin-contrast-'));
  try {
    const css = await fs.readFile(new URL('../engine/assets/earth-background.css', import.meta.url), 'utf8');
    const file = path.join(directory, 'contrast.html');
    await fs.writeFile(file, `<!doctype html><html data-dream-skin="active"><head><style>${css}</style></head>
      <body><div id="codex-dream-skin-image"></div><div id="codex-dream-skin-video-overlay"></div>
      <main class="main-surface">Native text</main><pre id="result"></pre>
      <div id="new-composer" data-ds-part="composer">
        <div data-composer-body style="border-radius:22px;background:rgb(52,52,52)"></div>
      </div>
      <div id="old-composer" data-ds-part="composer"></div>
      <div data-app-shell-workspace>
        <div data-app-shell-surface-backing style="background-color: rgb(45, 45, 43)"></div>
        <div data-app-shell-workspace-row>
          <div>
            <div data-app-shell-active-page="true" data-rail-home-surface="home"></div>
          </div>
        </div>
      </div>
      <pre id="backing-result"></pre>
      <script>
      const backing = document.querySelector('[data-app-shell-surface-backing]');
      const homePage = document.querySelector('[data-rail-home-surface]');
      const composer = document.getElementById('new-composer');
      const oldComposer = document.getElementById('old-composer');
      const composerBody = composer.querySelector('[data-composer-body]');
      const backingColors = {};
      for (const surface of ['home', 'chatgpt-thread', 'local-thread', 'settings']) {
        homePage.dataset.railHomeSurface = surface;
        backingColors[surface] = getComputedStyle(backing).backgroundColor;
      }
      homePage.dataset.railHomeSurface = 'chatgpt-thread';
      homePage.dataset.appShellActivePage = 'false';
      backingColors.inactive = getComputedStyle(backing).backgroundColor;
      document.getElementById('backing-result').textContent = JSON.stringify(backingColors);
      </script><script>
      const results = [];
      const rgb = value => value.match(/[\\d.]+/g).map(Number);
      const luminance = channels => channels.slice(0, 3).map(v => {
        const s = v / 255; return s <= .04045 ? s / 12.92 : ((s + .055) / 1.055) ** 2.4;
      }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
      for (const [mode, foreground, artwork] of [['light', 0, 0], ['dark', 255, 255]]) {
        document.documentElement.setAttribute('data-dream-shell', mode);
        document.body.style.color = 'rgb(' + [foreground, foreground, foreground].join(',') + ')';
        const image = document.getElementById('codex-dream-skin-image');
        image.style.background = 'rgb(' + [artwork, artwork, artwork].join(',') + ')';
        const filter = getComputedStyle(image).filter;
        const brightness = filter.match(/brightness\\(([\\d.]+)\\)/)?.[1] ?? 1;
        const overlay = rgb(getComputedStyle(document.getElementById('codex-dream-skin-video-overlay')).backgroundColor);
        const alpha = overlay[3] ?? 1;
        const background = overlay.slice(0, 3).map(v => v * alpha + artwork * brightness * (1 - alpha));
        const text = rgb(getComputedStyle(document.querySelector('main')).color);
        const a = luminance(text), b = luminance(background);
        results.push({mode, foreground, nativeText: text, contrast: (Math.max(a,b) + .05) / (Math.min(a,b) + .05),
          composerOuter: getComputedStyle(composer).backgroundColor,
          composerBody: getComputedStyle(composerBody).backgroundColor,
          composerRadius: getComputedStyle(composerBody).borderRadius,
          oldComposer: getComputedStyle(oldComposer).backgroundColor});
      }
      document.getElementById('result').textContent = JSON.stringify(results);
      </script></body></html>`);
    const run = spawnSync(edge, ['--headless', '--disable-gpu', '--no-first-run',
      '--disable-background-networking', '--user-data-dir=' + path.join(directory, 'profile'),
      '--dump-dom', pathToFileURL(file).href], {
      encoding: 'utf8', timeout: 45000, maxBuffer: 2 * 1024 * 1024, windowsHide: true,
    });
    assert.ifError(run.error);
    assert.equal(run.status, 0, run.stderr);
    const backingMatch = run.stdout.match(/<pre id="backing-result">([^<]+)<\/pre>/);
    assert.ok(backingMatch, 'Headless browser did not execute the page background check');
    assert.deepEqual(JSON.parse(backingMatch[1]), {
      home: 'rgba(0, 0, 0, 0)',
      'chatgpt-thread': 'rgba(0, 0, 0, 0)',
      'local-thread': 'rgba(0, 0, 0, 0)',
      settings: 'rgb(45, 45, 43)',
      inactive: 'rgb(45, 45, 43)',
    });
    const match = run.stdout.match(/<pre id="result">([^<]+)<\/pre>/);
    assert.ok(match, 'Headless browser did not execute the contrast fixture');
    const results = JSON.parse(match[1]);
    assert.equal(results.length, 2);
    for (const result of results) {
      assert.deepEqual(result.nativeText.slice(0,3), Array(3).fill(result.foreground), 'Native text color changed');
      assert.ok(result.contrast >= 4.5, result.mode + ' wallpaper contrast was ' + result.contrast.toFixed(2));
      assert.equal(result.composerOuter, 'rgba(0, 0, 0, 0)');
      assert.equal(result.composerBody, 'rgb(52, 52, 52)');
      assert.equal(result.composerRadius, '22px');
      assert.equal(result.oldComposer, result.mode === 'light' ? 'rgba(255, 255, 255, 0.7)' : 'rgba(10, 18, 30, 0.7)');
    }
  } finally {
    // Only remove the temporary directory created by this test.
    assert.equal(path.dirname(directory), path.resolve(os.tmpdir()));
    assert.ok(path.basename(directory).startsWith('skin-contrast-'));
    await fs.rm(directory, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  }
});
