"""Compile and exercise the actual installer name validator using a std-only shim."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
args = parser.parse_args()
text = (args.source / "src/platform/windows.rs").read_text(encoding="utf-8")
start = text.index("fn validate_install_app_name(")
brace = text.index("{", start)
depth = 1
end = brace + 1
while depth:
    depth += (text[end] == "{") - (text[end] == "}")
    end += 1
function = text[start:end]
harness = '''
type ResultType<T> = Result<T, String>;
macro_rules! bail { ($message:literal) => { return Err($message.to_string()) }; }
''' + function + '''
#[test] fn fixed_brand_is_supported() {
    assert!(validate_install_app_name("Asystec Desk").is_ok());
}
#[test] fn original_safe_names_remain_supported() {
    assert!(validate_install_app_name("RustDesk-Admin1").is_ok());
}
#[test] fn unsafe_names_remain_rejected() {
    for name in ["", "Other Brand", "Asystec Desk ", "Asystec Desk&whoami", "Asystec Desk|x", "Asystec Desk%PATH%", "Asystec Desk\\n", "RustDesk_Admin", "RustDesk应用"] {
        assert!(validate_install_app_name(name).is_err(), "accepted {name:?}");
    }
}
'''
with tempfile.TemporaryDirectory(prefix="asystec-name-test-") as directory:
    folder = Path(directory)
    file = folder / "install_name.rs"
    file.write_text(harness, encoding="utf-8")
    executable = folder / "install_name_tests.exe"
    subprocess.run(["rustc", "--edition", "2021", "--test", str(file), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
