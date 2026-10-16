import fs from "node:fs/promises";
import path from "node:path";
import { createHash } from "node:crypto";
import { gunzipSync } from "node:zlib";

const option = (name) => process.argv[process.argv.indexOf(name) + 1];
if (!process.argv.includes("--inputs") || !process.argv.includes("--profile")) {
  throw new Error(
    "Usage: node tool/export-story-assets.mjs --inputs manifest.json --profile flutter/assets/profile",
  );
}
const manifestPath = path.resolve(option("--inputs"));
const inputRoot = path.dirname(manifestPath);
const outputRoot = path.resolve(option("--profile"));
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
if (
  manifest.schema !== "haneoka-story-profile-source-inputs-v1" ||
  !["jp", "intl"].includes(manifest.source.server)
) {
  throw new Error("Expected an official story profile source manifest");
}
async function read(reference) {
  const filename = path.resolve(inputRoot, reference.path);
  if (!filename.startsWith(`${inputRoot}${path.sep}`))
    throw new Error("Input path escapes its source directory");
  let bytes;
  try {
    bytes = await fs.readFile(filename);
  } catch (error) {
    if (error.code !== "ENOENT" || !reference.url) throw error;
    const response = await fetch(reference.url, {
      signal: AbortSignal.timeout(90000),
    });
    if (!response.ok)
      throw new Error(`Source HTTP ${response.status}: ${reference.url}`);
    bytes = Buffer.from(await response.arrayBuffer());
    if (digest(bytes) !== reference.sha256)
      throw new Error(`Source SHA256 mismatch: ${reference.url}`);
    await fs.mkdir(path.dirname(filename), { recursive: true });
    await fs.writeFile(filename, bytes);
  }
  if (digest(bytes) !== reference.sha256)
    throw new Error(`Input SHA256 mismatch: ${reference.path}`);
  return bytes;
}
async function write(relative, bytes) {
  const filename = path.resolve(outputRoot, relative);
  if (!filename.startsWith(`${outputRoot}${path.sep}`))
    throw new Error("Output path escapes profile");
  await fs.mkdir(path.dirname(filename), { recursive: true });
  await fs.writeFile(filename, bytes);
  return {
    path: relative,
    sha256: digest(bytes),
    bytes: Buffer.byteLength(bytes),
  };
}
const json = (value) => `${JSON.stringify(value)}\n`;
const descriptor = JSON.parse(await read(manifest.font.descriptor));
const archiveBytes = await read(manifest.font.archive);
if (
  descriptor.objectArchive.sha256 !== digest(archiveBytes) ||
  descriptor.objectArchive.format !== "haneoka-unity-objects-jsonl-v1"
) {
  throw new Error("Font archive differs from its descriptor");
}
const records = gunzipSync(archiveBytes)
  .toString("utf8")
  .trim()
  .split("\n")
  .map((line) =>
    JSON.parse(line, (key, value, context) =>
      typeof value === "number" &&
      Number.isInteger(value) &&
      !Number.isSafeInteger(value)
        ? context.source
        : value,
    ),
  );
const header = records[0];
if (
  header.record !== "header" ||
  !descriptor.candidateBundles.some(
    (bundle) => bundle.sha256 === header.bundleSha256,
  )
) {
  throw new Error("Font archive bundle differs from its descriptor");
}
const candidates = records.filter(
  (record) => record.type === "MonoBehaviour" && record.data?.m_GlyphTable,
);
if (candidates.length !== 1) throw new Error("Expected one TMP font object");
const fontRecord = candidates[0];
const raw = fontRecord.data;
const face = raw.m_FaceInfo;
const id = manifest.font.id;
if (!/^[a-z]+$/.test(id)) throw new Error("Invalid font identifier");
const beforeFontPath = path.join(outputRoot, "story-ui", "fonts", `${id}.json`);
const beforeFont = JSON.parse(await fs.readFile(beforeFontPath, "utf8"));
const outputs = new Map(
  descriptor.outputs.map((output) => [output.objectId, output]),
);
const assetProofs = [];
const atlases = [];
for (const [index, pointer] of raw.m_AtlasTextures.entries()) {
  const objectId = pointer.reference?.pathId ?? String(pointer.m_PathID);
  if (objectId === "0") continue;
  const output = outputs.get(objectId);
  const input = manifest.font.outputs.find(
    (item) => item.objectId === objectId,
  );
  if (
    !output ||
    output.type !== "Texture2D" ||
    !input ||
    input.outputPath !== output.path ||
    input.file.sha256 !== output.sha256
  ) {
    throw new Error(`Missing verified font atlas ${objectId}`);
  }
  const atlasName = `${id}-${index}.png`;
  const result = await write(
    `story-ui/fonts/${atlasName}`,
    await read(input.file),
  );
  atlases.push(atlasName);
  assetProofs.push({
    ...result,
    sourcePath: descriptor.basePath,
    sourceOutput: output.path,
    objectId,
  });
}
// The compact field layout is the formal-source font_lineage.py export format.
const compact = {
  id,
  size: face.m_PointSize,
  ascent: face.m_AscentLine,
  descent: face.m_DescentLine,
  lineHeight: face.m_LineHeight,
  padding: raw.m_AtlasPadding,
  scale: face.m_Scale,
  atlasWidth: raw.m_AtlasWidth,
  atlasHeight: raw.m_AtlasHeight,
  normalWeight: raw.normalStyle ?? 0,
  boldWeight: raw.boldStyle ?? 0.75,
  boldSpacing: raw.boldSpacing ?? 0,
  characters: Object.fromEntries(
    raw.m_CharacterTable.map((row) => [
      String(row.m_Unicode),
      [row.m_GlyphIndex, row.m_Scale ?? 1],
    ]),
  ),
  glyphs: Object.fromEntries(
    raw.m_GlyphTable.map((row) => [
      String(row.m_Index),
      {
        index: row.m_Index,
        atlas: row.m_AtlasIndex,
        rect: ["X", "Y", "Width", "Height"].map(
          (key) => row.m_GlyphRect[`m_${key}`],
        ),
        metrics: [
          "Width",
          "Height",
          "HorizontalBearingX",
          "HorizontalBearingY",
          "HorizontalAdvance",
        ].map((key) => row.m_Metrics[`m_${key}`]),
        scale: row.m_Scale,
      },
    ]),
  ),
  atlases,
};
const pairs = raw.m_FontFeatureTable?.m_GlyphPairAdjustmentRecords ?? [];
if (pairs.length) {
  compact.pairs = pairs.map((pair) => {
    const first = pair.m_FirstAdjustmentRecord;
    const second = pair.m_SecondAdjustmentRecord;
    const vector = (record) =>
      ["XPlacement", "YPlacement", "XAdvance", "YAdvance"].map(
        (key) => record.m_GlyphValueRecord[`m_${key}`] ?? 0,
      );
    return [
      first.m_GlyphIndex,
      second.m_GlyphIndex,
      vector(first),
      vector(second),
    ];
  });
}
for (const glyph of Object.values(compact.glyphs)) {
  if (glyph.atlas >= atlases.length)
    throw new Error("Glyph refers to a missing atlas");
}
const fontOutput = await write(`story-ui/fonts/${id}.json`, json(compact));
assetProofs.push({
  ...fontOutput,
  sourcePath: descriptor.basePath,
  objectId: fontRecord.pathId,
});
for (const old of beforeFont.atlases) {
  if (atlases.includes(old)) continue;
  if (!new RegExp(`^${id}-[0-9]+\\.png$`).test(old))
    throw new Error("Old font atlas path is not local");
  await fs.rm(path.join(outputRoot, "story-ui", "fonts", old));
}
const materialPath = path.join(
  outputRoot,
  "story-ui",
  "fonts",
  "materials.json",
);
const materials = JSON.parse(await fs.readFile(materialPath, "utf8"));
for (const key of Object.keys(materials))
  if (key.startsWith(`${id}:`) || key.startsWith(`${id}-`))
    delete materials[key];
const aliases = [
  [" - Default", "default"],
  [" - OutlineAdvCommon", "outline"],
  [" - OutlineLightGray", "center"],
  [" SDF Material", "base"],
];
for (const record of records.filter((record) => record.type === "Material")) {
  const name = record.data.m_Name;
  const properties = record.data.m_SavedProperties;
  const material = {
    floats: Object.fromEntries(properties.m_Floats ?? []),
    colors: Object.fromEntries(
      (properties.m_Colors ?? []).map(([key, value]) => [
        key,
        [value.r, value.g, value.b, value.a],
      ]),
    ),
  };
  materials[`${id}:${name}`] = material;
  for (const [suffix, alias] of aliases)
    if (name.endsWith(suffix)) materials[`${id}-${alias}`] = material;
}
const materialOutput = await write(
  "story-ui/fonts/materials.json",
  json(materials),
);
assetProofs.push({
  ...materialOutput,
  sourcePath: descriptor.basePath,
  materialPrefix: `${id}:`,
});
const spriteDescriptorBytes = await read(manifest.sprites.descriptor);
const spriteDescriptor = JSON.parse(spriteDescriptorBytes);
const spriteOutputs = new Map(
  spriteDescriptor.outputs.map((output) => [output.objectId, output]),
);
for (const sprite of manifest.sprites.assets) {
  const source = spriteOutputs.get(sprite.objectId);
  if (
    !source ||
    source.type !== "Sprite" ||
    source.path !== sprite.outputPath ||
    source.sha256 !== sprite.file.sha256 ||
    !/^story-ui\/ui\/[^/]+\.png$/.test(sprite.assetPath)
  ) {
    throw new Error(
      `Sprite input differs from descriptor: ${sprite.assetPath}`,
    );
  }
  const result = await write(sprite.assetPath, await read(sprite.file));
  assetProofs.push({
    ...result,
    sourcePath: spriteDescriptor.basePath,
    sourceOutput: source.path,
    objectId: source.objectId,
  });
}
async function replaceHash(relative, key, expected) {
  const filename = path.join(outputRoot, relative);
  const content = await fs.readFile(filename, "utf8");
  const pattern = new RegExp(`("${key}"\\s*:\\s*")[a-f0-9]{64}("[},])`);
  if (!pattern.test(content))
    throw new Error(`Missing digest ${key}: ${relative}`);
  const next = content.replace(
    pattern,
    (_, prefix, suffix) => `${prefix}${expected}${suffix}`,
  );
  await fs.writeFile(filename, next);
  return digest(next);
}
const bindingHash = await replaceHash(
  "story-ui/source-bindings/font-material-bindings.json",
  "materialSHA256",
  materialOutput.sha256,
);
await replaceHash(
  "story-ui/source-bindings/front-font-materials.json",
  "materialSHA256",
  materialOutput.sha256,
);
await replaceHash(
  "story-ui/source-bindings/front-font-materials.json",
  "existingFontBindingsSHA256",
  bindingHash,
);
const frontPath = path.join(
  outputRoot,
  "story-ui/source-bindings/front-sprites.json",
);
const frontText = await fs.readFile(frontPath, "utf8");
const front = JSON.parse(frontText);
let nextFront = frontText;
for (const value of Object.values(front.nativeAssets)) {
  const updated = assetProofs.find(
    (asset) => asset.path === `story-ui/${value.assetPath}`,
  );
  if (updated && value.SHA256 !== updated.sha256)
    nextFront = nextFront.replace(value.SHA256, updated.sha256);
}
await fs.writeFile(frontPath, nextFront);
const provenance = {
  schema: "haneoka-story-profile-resource-provenance-v1",
  source: manifest.source,
  inputManifestSHA256: digest(await fs.readFile(manifestPath)),
  producer: "tool/export-story-assets.mjs",
  descriptors: [
    {
      path: descriptor.descriptor,
      sourcePath: descriptor.basePath,
      sha256: manifest.font.descriptor.sha256,
    },
    {
      path: spriteDescriptor.descriptor,
      sourcePath: spriteDescriptor.basePath,
      sha256: manifest.sprites.descriptor.sha256,
    },
  ],
  fontArchive: {
    path: descriptor.objectArchive.path,
    sha256: descriptor.objectArchive.sha256,
  },
  assets: assetProofs,
};
await write(
  "story-ui/source-bindings/resource-provenance.json",
  json(provenance),
);
console.log(
  JSON.stringify({
    font: id,
    characters: raw.m_CharacterTable.length,
    glyphs: raw.m_GlyphTable.length,
    atlases,
    sprites: manifest.sprites.assets.length,
    materialHash: materialOutput.sha256,
  }),
);
