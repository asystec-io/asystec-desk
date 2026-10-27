# Asystec Desk para Windows — desarrollo 0.1.0

Versión propia basada en RustDesk OSS 1.5.0, bajo AGPL-3.0. Esta carpeta inicia
el cliente modificado; `clients/` conserva el instalador anterior que utiliza
binarios oficiales de RustDesk. No son el mismo producto ni comparten pruebas.

## Estado

**EXE Windows x64 compilado y probado contra el servidor de Asystec.**
El resultado final y los hashes están en `RELEASE-0.1.0.md` y
`verification/windows-final.json`. La carpeta de esta versión es
`dist/asystec-desk-v0.1.0/`; `dist/asystec-desk-dev/` conserva el primer intento.
El servidor existente de Asystec
respondió las ocho pruebas externas de protocolo y relay el 26 de octubre de
2026, hora de Costa Rica. Esa comprobación no valida una sesión de escritorio
con este cliente nuevo. Evidencia: `verification/server-2026-10-26.json`.

El nombre visible será Asystec Desk. El icono AD y la paleta verde azulado son
provisionales; no representan un logotipo oficial aprobado de Asystec.

## Cambios en el código

- Nombre de aplicación, identidad de configuración/servicio e información de
  producto Windows. Se mantienen los nombres internos de crates y DLL para
  conservar la integración Rust/Flutter.
- Iconos de Windows y bandeja; logotipo para tema claro y oscuro.
- Configuración de red compilada: ID `184.197.59.221`, relay
  `184.197.59.221:21117`, clave pública del servidor existente y API vacía.
  Las opciones de red quedan sobrescritas por el perfil compilado. No se
  incorpora ninguna contraseña ni clave privada.
- Servidor y clave de respaldo de la biblioteca común apuntan a Asystec.
- Esquema de enlaces `asystecdesk://`, sin espacios.
- Pantalla Acerca de con atribución a RustDesk y licencia AGPL. Se conserva el
  copyright original; el enlace de licencia sustituye la política de privacidad
  de RustDesk, que no debe presentarse como política de Asystec.
- Se conserva el mecanismo upstream que evita la búsqueda automática de
  actualizaciones oficiales en clientes con nombre personalizado. El canal
  propio de actualizaciones queda pendiente.

No se cambia la autenticación ni se establece una contraseña común. El nuevo
nombre usa una identidad independiente: no se promete migrar IDs, contraseñas,
servicios o datos de instalaciones RustDesk anteriores. Debe comprobarse en VM.

## Preparar las fuentes

Requiere Python 3.10 o posterior; no necesita SDK de Windows para este paso.
Desde la raíz del proyecto:

```powershell
python desktop/prepare.py
powershell -NoProfile -File desktop/Build-Windows.ps1 -CheckOnly
python -m unittest discover -s desktop/tests -v
```

`prepare.py` descarga dos archivos oficiales fijados por commit, verifica
SHA-256, integra el submódulo `hbb_common` y aplica cambios con coincidencias
exactas. Rechaza caché alterada, cambios inesperados y salida ya existente.
No utiliza un clon Git ni cambia la rama activa. Salida:
`.build/asystec-desk-source/`, con licencia original, parche legible,
`ASYSTEC-NOTICE.txt` y manifiesto de hashes. Los scripts y assets de esta carpeta
también se copian dentro del árbol fuente.

`profile.json` contiene solo información pública. Para cambiar servidor o clave
se prepara y compila una versión nueva; no se regenera la identidad del servidor.
Los PNG e ICO están incluidos; regenerarlos con `make_assets.py` requiere Pillow
y la fuente Segoe UI Semibold de Windows.

## Compilar Windows x64

Las herramientas se instalaron en `%LOCALAPPDATA%\Asystec\DeskBuild`, Rust en
`%USERPROFILE%\.cargo` y Visual Studio Build Tools en `C:\BuildTools`.
`verification/build-tools.json` registra versiones, commits y hashes.
Requisitos tomados del workflow de la versión upstream fijada:

- Visual Studio 2022, carga Desktop development with C++ y Windows SDK.
- Rust 1.75, CMake, NASM, Git y Python en PATH.
- Flutter 3.24.5 en PATH, con soporte Windows habilitado.
- LLVM 15.0.6; `LIBCLANG_PATH` apunta a la carpeta que contiene `libclang.dll`.
- vcpkg en commit `9e593bb18ea69cc5095e012465dcd675a822ed0d`, con `VCPKG_ROOT`.
- `cargo install cargo-expand --version 1.0.95 --locked`.
- `cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked`.

Ejecutar desde una consola de desarrollo x64 de Visual Studio:

```powershell
. ./desktop/Enter-BuildEnvironment.ps1
./desktop/Build-Windows.ps1
./desktop/Build-Setup.ps1
```

El script comprueba las fuentes, resuelve dependencias vcpkg y Flutter, genera
el puente Rust/Flutter, compila y exige los binarios esperados. Conserva el
nombre interno `rustdesk.exe` durante el build y lo entrega como
`Asystec Desk.exe` junto a todas sus DLL y `data/`; no se distribuye el EXE suelto.
También genera el ZIP de fuentes correspondientes y un manifiesto con hashes.
No instala ni ejecuta el cliente en el equipo de compilación.

Se aplicó el engine Flutter personalizado de RustDesk y su parche de dropdown.
El hash del engine utilizado está en `verification/build-tools.json`.
Para generar el puente se proporciona `--llvm-path` a la raíz de LLVM;
`LIBCLANG_PATH` apunta a su subcarpeta `bin`.
Referencia exacta:
https://github.com/rustdesk/rustdesk/blob/fada664df7a294d1d1a9ca3e7cd3637069122f17/.github/workflows/flutter-build.yml

## Antes de entregar a clientes

1. Completar y ejecutar la compilación en el entorno Windows adecuado.
2. Revisar marca real en la interfaz, icono, diálogos UAC y bandeja.
3. Probar instalación, servicio, aceptación manual, rechazo de contraseña
   incorrecta, conexión por relay, reinicio y desinstalación en Windows limpio.
4. Verificar convivencia/migración con RustDesk y con el instalador anterior.
5. Preparar instalador propio, política de privacidad y canal de actualización.
6. Firmar con certificado de Asystec; la firma de PURSLANE no se transfiere al fork.
7. Entregar las fuentes correspondientes junto con cada binario y conservar
   licencia/atribuciones, incluyendo las dependencias y avisos que correspondan.

El instalador `Asystec-Desk-Setup.exe` incluye todos los archivos del cliente,
verifica el servicio y el hash instalado y devuelve un código de error si falla.
Se mantiene la validación original de nombres seguros, con una excepción exacta
para `Asystec Desk` y comandos de servicio/registro debidamente entrecomillados.
`test_install_name.py` ejecuta el validador real en tres pruebas de regresión.
`Test-WindowsSandbox.ps1` instala el EXE en Sandbox; `Connect-QASandbox.ps1`
utiliza la credencial de QA cifrada y fuerza una conexión por relay.
`package.py` permite empaquetar una Release ya compilada con sus fuentes reales.

Ejecutar las pruebas sobre esta versión local:

```powershell
./desktop/Test-WindowsSandbox.ps1 -BundleDirectory dist/asystec-desk-v0.1.0 -RunName asystec-desk-final-qa
./desktop/Connect-QASandbox.ps1 -BundleDirectory dist/asystec-desk-v0.1.0 -RunName asystec-desk-final-qa
```

No se incorporó ninguna contraseña compartida al instalador. La contraseña
permanente aleatoria usada en las pruebas pertenece únicamente al Sandbox.
La instalación normal conserva los mecanismos de autorización de RustDesk.

Las pruebas históricas de `clients/` no certifican este nuevo cliente.
Los cambios actuales no publican ni sustituyen la descarga existente.
