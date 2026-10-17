import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'flutter');
if (process.argv.slice(2).some((value) => value !== '--check')) {
  throw new Error('Usage: node tool/build-manifest.mjs [--check]');
}
const target = join(root, 'assets', 'profile', 'manifest.json');
const names = [];
function collect(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (path === target) continue;
    if (entry.isDirectory()) collect(path);
    else if (entry.isFile()) names.push(path);
    else throw new Error(`Unexpected profile asset: ${path}`);
  }
}
collect(join(root, 'assets', 'profile'));
names.push(join(root, 'shaders', 'haneoka.shaderbundle'));
const entries = names.map((path) => [
  `packages/haneoka_render_profile_flutter/${relative(root, path).split(sep).join('/')}`,
  path,
]).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
const files = Object.fromEntries(entries.map(([key, path]) => {
  const bytes = readFileSync(path);
  return [key, {
    bytes: bytes.length,
    sha256: createHash('sha256').update(bytes).digest('hex'),
  }];
}));
const source = JSON.parse(readFileSync(join(root, 'assets', 'profile', 'effects', 'components.json')));
for (const field of ['server', 'sourceId', 'releaseId']) {
  if (typeof source[field] !== 'string' || source[field].length === 0) {
    throw new Error(`Missing profile packet provenance: ${field}`);
  }
}
const manifest = {
  schema: 'haneoka-render-profile-manifest-v1',
  id: 'our-notes',
  version: 'formal-1.0.3',
  capabilities: ['haneoka-story-commands-v1', 'our-notes-chart-v1'],
  packetSource: { server: source.server, sourceId: source.sourceId, releaseId: source.releaseId },
  numericTextures: JSON.parse(readFileSync(join(root, 'assets', 'profile', 'font-coverage.json'))).textures,
  files,
};
const json = `${JSON.stringify(manifest, null, 2)}\n`;
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== json) throw new Error('Profile manifest needs rebuilding');
} else {
  writeFileSync(target, json);
}
console.log(JSON.stringify({ files: names.length, bytes: Object.values(files).reduce((sum, row) => sum + row.bytes, 0) }));
