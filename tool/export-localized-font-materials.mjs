import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';

const option = name => process.argv[process.argv.indexOf(name) + 1];
if (!process.argv.includes('--inputs') || !process.argv.includes('--profile')) {
  throw new Error('Usage: node tool/export-localized-font-materials.mjs --inputs inputs.json --profile flutter/assets/profile');
}
const inputsPath = resolve(option('--inputs'));
const inputs = JSON.parse(readFileSync(inputsPath));
const root = resolve(option('--profile'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const original = JSON.parse(readFileSync(join(root, 'story-ui/fonts/materials.json')));
const materials = {}, sources = {};
for (const input of inputs.fonts) {
  const bytes = readFileSync(resolve(dirname(inputsPath), input.archive));
  if (hash(bytes) !== input.archiveSHA256) throw new Error(`Font archive SHA256: ${input.id}`);
  const records = gunzipSync(bytes).toString().trim().split('\n').map(line => JSON.parse(line,
    (key, value, context) => typeof value === 'number' && Number.isInteger(value) && !Number.isSafeInteger(value)
      ? context.source : value));
  if (records[0].bundleSha256 !== input.bundleSHA256) throw new Error(`Font bundle: ${input.id}`);
  const fonts = records.filter(row => row.type === 'MonoBehaviour' && row.data?.m_GlyphTable);
  if (fonts.length !== 1) throw new Error(`Font identity: ${input.id}`);
  const font = fonts[0];
  const compactBytes = readFileSync(join(root, `story-ui/fonts/${input.id}.json`));
  const compact = JSON.parse(compactBytes);
  if (font.data.m_AtlasWidth !== compact.atlasWidth || font.data.m_AtlasHeight !== compact.atlasHeight ||
      font.data.m_GlyphTable.length !== Object.keys(compact.glyphs).length) throw new Error(`Font metrics: ${input.id}`);
  for (const glyph of font.data.m_GlyphTable) {
    const actual = compact.glyphs[glyph.m_Index];
    const rect = ['X', 'Y', 'Width', 'Height'].map(key => glyph.m_GlyphRect[`m_${key}`]);
    if (!actual || JSON.stringify(actual.rect) !== JSON.stringify(rect) || actual.atlas !== glyph.m_AtlasIndex) {
      throw new Error(`Font glyph binding: ${input.id}/${glyph.m_Index}`);
    }
  }
  const proofs = {};
  for (const row of records.filter(row => row.type === 'Material')) {
    const key = `${input.id}:${row.data.m_Name}`, saved = row.data.m_SavedProperties;
    materials[key] = {
      floats: Object.fromEntries(saved.m_Floats ?? []),
      colors: Object.fromEntries((saved.m_Colors ?? []).map(([k, v]) => [k, [v.r, v.g, v.b, v.a]])),
      keywords: row.data.m_ValidKeywords ?? [],
    };
    proofs[key] = { pathId: row.pathId, serializedFile: row.serializedFile,
      name: row.data.m_Name, shader: row.data.m_Shader, textures: saved.m_TexEnvs };
  }
  const byType = type => Object.keys(materials).find(key => key.startsWith(`${input.id}:`) && key.endsWith(` - ${type}`));
  for (const [alias, type] of [['default', 'Default'], ['outline', 'OutlineAdvCommon'], ['center', 'OutlineLightGray']]) {
    const key = byType(type);
    if (key) materials[`${input.id}-${alias}`] = materials[key];
  }
  const defaultKey = byType('Default');
  if (!defaultKey) throw new Error(`Localized Default material: ${input.id}`);
  materials[`${input.id}-base`] = materials[defaultKey];
  sources[input.id] = { ...input, compactSHA256: hash(compactBytes), fontIdentity: {
    pathId: font.pathId, serializedFile: font.serializedFile, name: font.data.m_Name,
    atlasTextures: font.data.m_AtlasTextures, fallbackFonts: font.data.m_FallbackFontAssetTable,
  }, materials: proofs };
}
// Formal LocalizeManager.GetMaterialType: preset suffix after " - "; otherwise Default.
const presets = {};
for (const key of Object.keys(original).filter(key => /^(dialogue|chat):/.test(key))) {
  const name = key.slice(key.indexOf(':') + 1), separator = name.indexOf(' - ');
  const type = separator < 0 ? 'Default' : name.slice(separator + 3).replaceAll(' (Instance)', '');
  const targets = {};
  for (const id of Object.keys(sources)) {
    const matches = Object.keys(materials).filter(key => key.startsWith(`${id}:`) && key.endsWith(` - ${type}`));
    if (matches.length === 1) targets[id] = matches[0];
  }
  presets[name] = targets;
}
const result = { schema: 'haneoka-localized-font-materials-v1', nativeSource: inputs.nativeSource, sources, materials, presets };
writeFileSync(join(root, 'story-ui/source-bindings/localized-font-materials.json'), JSON.stringify(result) + '\n');
console.log(JSON.stringify({ fonts: Object.keys(sources), materials: Object.keys(materials).length, presets: Object.keys(presets).length }));
