import { execFileSync } from 'node:child_process';
import { readFileSync, renameSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const compiler = process.argv[process.argv.indexOf('--compiler') + 1];
if (!process.argv.includes('--compiler') || !compiler) {
  throw new Error('Usage: node tool/build-shaders.mjs --compiler /path/to/impellerc');
}
const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'flutter');
const target = join(root, 'shaders', 'haneoka.shaderbundle');
const temporary = `${target}.building`;
try {
  execFileSync(compiler, [
    '--metal-desktop', '--metal-ios', '--opengl-desktop', '--opengl-es', '--vulkan',
    `--shader-bundle=${readFileSync(join(root, 'shaders', 'shaderbundle.json'), 'utf8')}`,
    '--include=shaders', `--sl=${temporary}`,
  ], { cwd: root, stdio: 'inherit' });
  renameSync(temporary, target);
} finally {
  rmSync(temporary, { force: true });
}
