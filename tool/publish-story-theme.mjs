import fs from "node:fs/promises";
import path from "node:path";
import { createHash } from "node:crypto";

const option = (name) => process.argv[process.argv.indexOf(name) + 1];
if (!process.argv.includes("--profile") || !process.argv.includes("--theme")) {
  throw new Error(
    "Usage: node tool/publish-story-theme.mjs --profile flutter/assets/profile --theme /path/to/vega-theme-haneoka",
  );
}
const profile = path.resolve(option("--profile"));
const theme = path.resolve(option("--theme"));
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const provenanceBytes = await fs.readFile(
  path.join(profile, "story-ui/source-bindings/resource-provenance.json"),
);
const provenance = JSON.parse(provenanceBytes);
if (provenance.schema !== "haneoka-story-profile-resource-provenance-v1")
  throw new Error("Expected a verified story profile export");
const font = JSON.parse(
  await fs.readFile(path.join(profile, "story-ui/fonts/chinese.json"), "utf8"),
);
const files = ["chinese.json", ...font.atlases, "materials.json"];
const copied = [];
for (const filename of files) {
  if (filename.includes("/") || filename.includes(".."))
    throw new Error("Font output is not a local asset");
  const relative = `story-ui/fonts/${filename}`;
  const proof = provenance.assets.find((asset) => asset.path === relative);
  const bytes = await fs.readFile(path.join(profile, relative));
  if (!proof || sha256(bytes) !== proof.sha256)
    throw new Error(`Profile output SHA256 differs: ${filename}`);
  const destination = path.join(theme, "assets/fonts", filename);
  await fs.writeFile(destination, bytes);
  copied.push({
    source: relative,
    destination: `assets/fonts/${filename}`,
    sha256: proof.sha256,
  });
}
for (const filename of await fs.readdir(path.join(theme, "assets/fonts"))) {
  if (!/^chinese-[0-9]+\.png$/.test(filename)) continue;
  if (font.atlases.includes(filename)) continue;
  await fs.rm(path.join(theme, "assets/fonts", filename), { force: true });
}
const assetsFile = path.join(theme, "src/fontAssets.ts");
const source = await fs.readFile(assetsFile, "utf8");
const lines = font.atlases
  .map(
    (filename) =>
      `      new URL("../assets/fonts/${filename}", import.meta.url).href,`,
  )
  .join("\n");
const declaration = /(  chinese: \{\s*data: new URL\("\.\.\/assets\/fonts\/chinese\.json", import\.meta\.url\)\.href,\s*atlases: )\[[\s\S]*?\](,\s*\})/;
if (!declaration.test(source))
  throw new Error("Chinese asset declaration is missing");
const next = source.replace(
  declaration,
  (_, prefix, suffix) => `${prefix}[\n${lines}\n    ]${suffix}`,
);
await fs.writeFile(assetsFile, next);
console.log(
  JSON.stringify({
    source: provenance.source,
    provenanceSHA256: sha256(provenanceBytes),
    copied,
    assetDeclaration: { path: "src/fontAssets.ts", sha256: sha256(next) },
  }),
);
