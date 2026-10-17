"""Export lossless SDF coverage without changing glyph coordinates or padding."""

import argparse
import gzip
import hashlib
import json
from pathlib import Path

from PIL import Image


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--profile", type=Path, required=True)
args = parser.parse_args()
root = args.profile.resolve()
fonts = root / "story-ui" / "fonts"
entries = {}
for font_path in sorted(fonts.glob("*.json")):
    font = json.loads(font_path.read_text())
    for atlas in font.get("atlases", []):
        source = fonts / atlas
        encoded = source.read_bytes()
        with Image.open(source) as image:
            coverage = image.convert("RGBA").getchannel("A").tobytes()
            width, height = image.size
        output = source.with_suffix(".r8.gz")
        compressed = gzip.compress(coverage, compresslevel=9, mtime=0)
        output.write_bytes(compressed)
        key = "packages/haneoka_render_profile_flutter/" + str(
            source.relative_to(root.parent.parent)
        )
        entries[key] = {
            "asset": "packages/haneoka_render_profile_flutter/"
            + str(output.relative_to(root.parent.parent)),
            "width": width,
            "height": height,
            "format": "r8",
            "coverageChannel": "red",
            "compression": "gzip",
            "decodedBytes": len(coverage),
            "decodedSHA256": hashlib.sha256(coverage).hexdigest(),
            "sourceSHA256": hashlib.sha256(encoded).hexdigest(),
        }
index = {"schema": "haneoka-profile-numeric-textures-v1", "textures": entries}
(root / "font-coverage.json").write_text(json.dumps(index, indent=2) + "\n")
print(json.dumps({"atlases": len(entries), "texelBytes": sum(
    entry["decodedBytes"] for entry in entries.values()
)}))
