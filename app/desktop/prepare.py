"""Prepare a pinned, branded RustDesk source tree. Python 3.10+, stdlib only.

Never modifies an existing checkout or installs/runs a remote desktop service.
"""
import argparse
import base64
import difflib
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch(repo, commit, expected, cache):
    archive = cache / f"{repo}-{commit}.zip"
    if not archive.exists():
        request = urllib.request.Request(
            f"https://codeload.github.com/rustdesk/{repo}/zip/{commit}",
            headers={"User-Agent": "Asystec-Desk-Source-Builder"},
        )
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"SHA-256 incorrecto: {repo}")
        archive.write_bytes(data)
    if sha256(archive) != expected:
        raise ValueError(f"Cache alterado: {archive}")
    return archive


def unpack(archive, destination):
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            resolved = (destination / entry.filename).resolve()
            if not resolved.is_relative_to(destination.resolve()):
                raise ValueError("Ruta insegura en el archivo fuente")
        package.extractall(destination)
    folders = list(destination.iterdir())
    if len(folders) != 1 or not folders[0].is_dir():
        raise ValueError("Estructura inesperada del archivo fuente")
    return folders[0]


def brand(source, profile, assets):
    originals = {}

    def replace(path, old, new, count=1):
        target = source / path
        before = target.read_text(encoding="utf-8")
        originals.setdefault(path, before)
        if before.count(old) != count:
            raise ValueError(f"Upstream cambio: {path}: esperaba {count} coincidencias de {old!r}")
        after = before.replace(old, new)
        target.write_text(after, encoding="utf-8", newline="\n")

    config = "libs/hbb_common/src/config.rs"
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    replace(config, 'RwLock::new("RustDesk".to_owned())',
            f'RwLock::new({quote(profile["name"])}.to_owned())')
    replace(config, 'pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];',
            f'pub const RENDEZVOUS_SERVERS: &[&str] = &[{quote(profile["id_server"])}];')
    replace(config, 'pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";',
            f'pub const RS_PUB_KEY: &str = {quote(profile["public_key"])};')
    network = {
        "custom-rendezvous-server": profile["id_server"],
        "relay-server": profile["relay_server"],
        "key": profile["public_key"],
        "api-server": profile["api_server"],
    }
    entries = ",\n".join(f"        ({quote(k)}.to_owned(), {quote(v)}.to_owned())" for k, v in network.items())
    replace(config,
            'pub static ref OVERWRITE_SETTINGS: RwLock<HashMap<String, String>> = Default::default();',
            '// Asystec Desk: network identity compiled into the OSS client; no passwords.\n'
            '    pub static ref OVERWRITE_SETTINGS: RwLock<HashMap<String, String>> = RwLock::new(HashMap::from([\n'
            + entries + '\n    ]));')
    # Display name contains a space; URI schemes cannot contain spaces.
    replace("src/common.rs", 'format!("{}://", get_app_name().to_lowercase())',
            'format!("{}://", get_app_name().to_lowercase().replace(\' \', ""))')
    windows = "src/platform/windows.rs"
    replace(windows, 'fn validate_install_app_name(app_name: &str) -> ResultType<()> {',
            'fn validate_install_app_name(app_name: &str) -> ResultType<()> {\n'
            '    // Fixed brand; other application names retain the upstream validation.\n'
            '    if app_name == "Asystec Desk" {\n'
            '        return Ok(());\n'
            '    }')
    replace(windows, '{54E86BC2-6C85-41F3-A9EB-1A94AC9B1F93}_is1',
            '{4F5AA15E-727C-4428-9B57-6E092D1189BD}_is1')
    # The upstream batch commands assume an application name without spaces.
    for verb, count in (("stop", 5), ("delete", 4), ("create", 2), ("start", 2)):
        replace(windows, f'sc {verb} {{app_name}}', f'sc {verb} \\"{{app_name}}\\"', count)
    replace(windows, '/IM {app_name}.exe', '/IM \\"{app_name}.exe\\"', count=4)
    replace(windows, 'format!("sc start {}", &app_name)', 'format!("sc start \\"{}\\"", &app_name)')
    replace(windows, 'app_name.to_lowercase()', 'app_name.to_lowercase().replace(\' \', "")', count=5)
    replace(windows, 'reg add {subkey}', 'reg add \\"{subkey}\\"', count=21)
    replace(windows, 'reg delete {subkey}', 'reg delete \\"{subkey}\\"')
    replace(windows, 'reg add {} /f /v DisplayIcon', 'reg add \\"{}\\" /f /v DisplayIcon')
    replace("flutter/windows/runner/main.cpp", 'std::wstring app_name = L"RustDesk";',
            'std::wstring app_name = L"Asystec Desk";')
    rc = "flutter/windows/runner/Runner.rc"
    for old, new in [
        ('"CompanyName", "Purslane Tech Pte. Ltd."', '"CompanyName", "Asystec"'),
        ('"FileDescription", "RustDesk Remote Desktop"', '"FileDescription", "Asystec Desk - Remote Support"'),
        ('"ProductName", "RustDesk"', '"ProductName", "Asystec Desk"'),
        ('"OriginalFilename", "rustdesk.exe"', '"OriginalFilename", "Asystec Desk.exe"'),
    ]:
        replace(rc, old, new)
    # Preserve original copyright, license, crate names, DLL ABI and protocol.
    settings = "flutter/lib/desktop/pages/desktop_setting_page.dart"
    replace(settings, "title: translate('About RustDesk')", "title: 'Acerca de Asystec Desk'")
    replace(settings, "launchUrlString('https://rustdesk.com/privacy.html');",
            "launchUrlString('https://github.com/rustdesk/rustdesk/blob/1.5.0/LICENCE');")
    replace(settings, "translate('Privacy Statement'),", "'Licencia AGPL-3.0',")
    replace(settings, "launchUrlString('https://rustdesk.com');",
            f"launchUrlString({quote(profile['website'])});")
    replace(settings, "translate('Slogan_tip'),",
            "'Asystec Desk · basado en RustDesk\\nModificaciones Asystec, 26-10-2026 · AGPL-3.0',")
    replace("flutter/lib/common.dart", "0xFF2C8CFF", "0xFF064589", count=2)
    replace(settings, "0xFF2c8cff", "0xFF064589")
    for filename in ("icon.png", "icon.svg", "logo.png", "logo_light.png", "logo_dark.png"):
        shutil.copy2(assets / filename, source / "flutter/assets" / filename)
    for filename in ("icon.png", "icon.ico", "tray-icon.ico"):
        shutil.copy2(assets / filename, source / "res" / filename)
    shutil.copy2(assets / "icon.ico", source / "flutter/windows/runner/resources/app_icon.ico")
    changes = []
    for path, before in originals.items():
        changes.extend(difflib.unified_diff(
            before.splitlines(True), (source / path).read_text(encoding="utf-8").splitlines(True),
            fromfile=f"a/{path}", tofile=f"b/{path}",
        ))
    return "".join(changes)


def prepare(output):
    profile = json.loads((ROOT / "desktop/profile.json").read_text(encoding="utf-8"))
    if len(base64.b64decode(profile["public_key"], validate=True)) != 32:
        raise ValueError("La clave publica debe ser Ed25519 de 32 bytes")
    upstream = profile["upstream"]
    output = output.resolve()
    if output.exists():
        raise FileExistsError(f"No se sobrescribe un arbol existente: {output}")
    cache = ROOT / ".build/cache"
    cache.mkdir(parents=True, exist_ok=True)
    source_zip = fetch("rustdesk", upstream["commit"], upstream["archive_sha256"], cache)
    common_zip = fetch("hbb_common", upstream["hbb_common_commit"], upstream["hbb_common_archive_sha256"], cache)
    with tempfile.TemporaryDirectory(prefix="asystec-source-") as temporary:
        stage = Path(temporary)
        source = unpack(source_zip, stage / "main")
        common = unpack(common_zip, stage / "common")
        shutil.copytree(common, source / "libs/hbb_common", dirs_exist_ok=True)
        patch = brand(source, profile, ROOT / "desktop/assets")
        (source / "ASYSTEC-CHANGES.patch").write_text(patch, encoding="utf-8")
        (source / "ASYSTEC-NOTICE.txt").write_text(
            "Asystec Desk 0.1.2, basado en RustDesk 1.5.0.\n"
            "Modificaciones Asystec: 26-10-2026. Licencia: AGPL-3.0.\n"
            "Se conservan los derechos y avisos de los autores originales.\n"
            "Distribuir el codigo correspondiente junto al binario, incluidos scripts y assets.\n"
            "Identidad Asystec Desk: Dos ventanas, paquete final suministrado por Asystec.\n"
            "No es un producto oficial ni esta avalado por RustDesk.\n",
            encoding="utf-8",
        )
        shutil.copytree(ROOT / "desktop", source / "desktop", ignore=shutil.ignore_patterns("__pycache__"))
        manifest = {"profile": profile, "status": "SOURCE_PREPARED_NOT_COMPILED", "files": {}}
        for file in sorted(source.rglob("*")):
            if file.is_file():
                manifest["files"][file.relative_to(source).as_posix()] = sha256(file)
        (source / "ASYSTEC-SOURCE-MANIFEST.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, output)
    print(json.dumps({"source": str(output), "status": manifest["status"], "files": len(manifest["files"])}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/asystec-desk-source")
    prepare(parser.parse_args().output)
