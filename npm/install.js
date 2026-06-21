#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const pkg = require('./package.json');
const version = pkg.version;

if (version === '0.0.0') {
  console.log('Skipping binary download for development placeholder version.');
  process.exit(0);
}

if (process.platform !== 'darwin') {
  console.log('macvision is only available on macOS; skipping binary download.');
  process.exit(0);
}

const binDir = path.join(__dirname, 'bin');
const binaryPath = path.join(binDir, 'macvision-binary');
const tarPath = path.join(__dirname, `macvision-darwin-universal.tar.xz`);
const baseUrl = `https://github.com/ljh-sh/macvision/releases/download/v${version}`;

fs.mkdirSync(binDir, { recursive: true });

async function download(url) {
  const res = await fetch(url, {
    headers: { 'User-Agent': 'macvision-npm-installer' },
    redirect: 'follow',
  });
  if (!res.ok) {
    throw new Error(`Download failed: HTTP ${res.status} for ${url}`);
  }
  return Buffer.from(await res.arrayBuffer());
}

async function getExpectedSha256() {
  try {
    const buf = await download(`${baseUrl}/SHA256SUMS`);
    const line = buf.toString('utf8')
      .split('\n')
      .find((l) => l.trim().endsWith('macvision-darwin-universal.tar.xz'));
    return line ? line.trim().split(/\s+/)[0].toLowerCase() : null;
  } catch {
    return null;
  }
}

function sha256Buffer(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

(async () => {
  try {
    console.log(`Downloading macvision v${version} for macOS...`);
    const tarball = await download(`${baseUrl}/macvision-darwin-universal.tar.xz`);

    const expected = await getExpectedSha256();
    if (expected) {
      const actual = sha256Buffer(tarball);
      if (actual !== expected) {
        throw new Error(`SHA256 mismatch: expected ${expected}, got ${actual}`);
      }
      console.log('SHA256 checksum verified.');
    }

    fs.writeFileSync(tarPath, tarball);

    const tmpDir = fs.mkdtempSync(path.join(__dirname, 'tmp-'));
    try {
      execFileSync('tar', ['xJf', tarPath, '-C', tmpDir], { stdio: 'inherit' });
      const extracted = path.join(tmpDir, 'bin', 'macvision');
      if (!fs.existsSync(extracted)) {
        throw new Error('macvision binary not found in downloaded tarball');
      }
      fs.renameSync(extracted, binaryPath);
      fs.chmodSync(binaryPath, 0o755);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
      fs.rmSync(tarPath, { force: true });
    }

    console.log('macvision installed successfully.');
  } catch (err) {
    console.error(`Failed to install macvision: ${err.message}`);
    process.exit(1);
  }
})();
