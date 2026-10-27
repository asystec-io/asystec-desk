"""Package an already compiled Windows Release and its actual source tree."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import zipfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_files(source):
    for root, directories, files in os.walk(source, followlinks=False):
        relative = Path(root).relative_to(source)
        directories[:] = [d for d in directories if d not in {
            ".git", ".dart_tool", "__pycache__", ".plugin_symlinks", "ephemeral"
        } and (relative / d).as_posix() not in {"target", "flutter/build"}]
        for name in files:
            file = Path(root) / name
            if file.name != "ASYSTEC-SOURCE-MANIFEST.json":
                yield file


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
source = args.source.resolve()
output = args.output.resolve()
release = source / "flutter/build/windows/x64/runner/Release"
for required in ("rustdesk.exe", "librustdesk.dll", "flutter_windows.dll", "dylib_virtual_display.dll", "data"):
    if not (release / required).exists():
        raise FileNotFoundError(f"Incomplete Release: {required}")
if output.exists():
    raise FileExistsError(output)
shutil.copytree(release, output)
(output / "rustdesk.exe").rename(output / "Asystec Desk.exe")
for filename in ("LICENCE", "ASYSTEC-NOTICE.txt"):
    shutil.copy2(source / filename, output / filename)
files = sorted(source_files(source))
manifest = {
    "status": "ACTUAL_BUILT_SOURCE",
    "at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "profile": json.loads((source / "desktop/profile.json").read_text(encoding="utf-8-sig")),
    "files": {f.relative_to(source).as_posix(): digest(f) for f in files},
}
manifest_file = source / "ASYSTEC-SOURCE-MANIFEST.json"
manifest_file.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
archive = output / "Asystec-Desk-source.zip"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as package:
    for file in [*files, manifest_file]:
        package.write(file, "Asystec-Desk-source/" + file.relative_to(source).as_posix())
build = {
    "status": "COMPILED_NOT_RUNTIME_TESTED",
    "at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "source": str(source),
    "files": [{"path": f.relative_to(output).as_posix(), "sha256": digest(f)}
              for f in sorted(output.rglob("*")) if f.is_file()],
}
(output / "build-manifest.json").write_text(json.dumps(build, indent=2), encoding="utf-8")
print(json.dumps({"output": str(output), "source_files": len(files)}, indent=2))
