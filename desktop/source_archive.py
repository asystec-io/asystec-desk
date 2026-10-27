"""Export actual source, permitting documentation/QA updates after compilation."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import zipfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_files(source):
    for root, directories, files in os.walk(source, followlinks=False):
        relative = Path(root).relative_to(source)
        directories[:] = [d for d in directories if d not in {
            ".git", ".dart_tool", "__pycache__", ".plugin_symlinks", "ephemeral", "target"
        } and (relative / d).as_posix() != "flutter/build"]
        for name in files:
            file = Path(root) / name
            if file.name != "ASYSTEC-SOURCE-MANIFEST.json":
                yield file


def export(source, destination, verify_runtime=True):
    previous = json.loads((source / "ASYSTEC-SOURCE-MANIFEST.json").read_text())
    if verify_runtime:
        for name, expected in previous["files"].items():
            if name.startswith(("src/", "libs/", "flutter/")):
                if digest(source / name) != expected:
                    raise ValueError(f"Runtime source changed after compilation: {name}")
    files = sorted(source_files(source))
    manifest = {
        "status": "ACTUAL_BUILT_SOURCE",
        "at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "runtime_source_verified_unchanged": verify_runtime,
        "profile": json.loads((source / "desktop/profile.json").read_text(encoding="utf-8-sig")),
        "files": {f.relative_to(source).as_posix(): digest(f) for f in files},
    }
    manifest_file = source / "ASYSTEC-SOURCE-MANIFEST.json"
    manifest_file.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for file in [*files, manifest_file]:
            archive.write(file, "Asystec-Desk-source/" + file.relative_to(source).as_posix())
    return {"path": str(destination), "sha256": digest(destination), "source_files": len(files)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    print(json.dumps(export(args.source.resolve(), args.destination.resolve()), indent=2))
