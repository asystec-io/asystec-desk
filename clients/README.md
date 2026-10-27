# Paquetes Windows de Asystec

Descarga pública del instalador probado:
https://asystec-apps.s3.us-east-2.amazonaws.com/updates/herramientas/Asystec-Soporte-Setup.exe

La descarga se verificó completa contra el SHA-256 de `dist/exe-manifest.json`.
La evidencia está en `dist/publication/exe-public-verification.json`.

`Build-Exe.ps1` genera `dist/Asystec-Soporte-Setup.exe` con Inno Setup 6.7.3.
Incluye el MSI oficial y el mismo script de configuración de los ZIP. Presenta
un asistente en español, solicita UAC y solo finaliza con éxito cuando el script
confirma todos los ajustes. No registra un segundo desinstalador: RustDesk se
desinstala desde Aplicaciones de Windows. Los archivos extraídos se eliminan
al cerrar el asistente; los registros quedan en TEMP.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clients\Build-Exe.ps1
# Solo en una máquina de prueba o un equipo que deba configurarse:
.\dist\Asystec-Soporte-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /RESTARTEXITCODE=3010
# Verificar el MSI incluido sin instalar ni configurar:
.\dist\Asystec-Soporte-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /VALIDATEONLY
```

El modo silencioso no abre la ventana de credenciales. El modo normal ofrece
abrirla al terminar. El código 3010 indica éxito con reinicio pendiente cuando
se usa `/RESTARTEXITCODE=3010`; nunca se fuerza el reinicio. Una configuración
fallida produce un error del asistente y un código distinto de cero.

La compilación instala Inno Setup únicamente para el usuario que compila,
verificando SHA-256 publicado por GitHub y firma del editor Pyrsys B.V.
Puede usarse otro compilador instalado con `-CompilerPath`. El manifiesto
`dist/exe-manifest.json` identifica el EXE, sus entradas y el compilador por
SHA-256. El EXE Asystec no está firmado; sus binarios RustDesk internos sí.

`Test-ExeInVM.ps1` crea un punto de recuperación de WindowsTest antes de intentar
las pruebas de instalación real. Requiere acceso administrativo al host y una
credencial válida del invitado para PowerShell Direct. Las pruebas comprueban
instalación, servicio, configuración, DPAPI/ACL, repetición, error real ante
credenciales corruptas, recuperación y reinicio del servicio. El estado y los
resultados se guardan en `dist/vm-test/`; un fallo de conexión no cuenta como
una instalación probada.

`Test-ExeInSandbox.ps1` ejecuta las mismas pruebas en un Windows Sandbox limpio.
Comparte la carpeta de entrada como solo lectura y exporta los resultados a
`dist/sandbox-test/`. No requiere la contraseña de WindowsTest.
`-RunName final-exe-test` conserva una ejecución en otra carpeta de `dist/`.
Al reiniciar el invitado, una marca evita repetir las pruebas e instalar de
nuevo, para poder comprobar la persistencia de forma independiente.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clients\Test-ExeInSandbox.ps1
```

`Build-Packages.ps1` genera dos ZIP en `dist/` desde archivos oficiales:
instalador MSI con script de configuración y portable con configuración en su
nombre. Las URLs, hashes, versión y servidor están en `windows/Instalar-Asystec.ps1`.

El script de instalación:

1. Comprueba Windows x64 y solicita elevación UAC para cambios reales.
2. Verifica el MSI incluido o descarga la versión fijada del GitHub oficial.
3. Verifica SHA-256 y firma PURSLANE; instala o reutiliza una versión igual/posterior.
4. Inicia el servicio y espera una respuesta del cliente por IPC.
5. Guarda una copia de los ajustes de servidor existentes.
6. Ejecuta `--config` con JSON codificado como Base64 URL-safe sin padding y
   caracteres invertidos, según el parser oficial.
7. Lee nuevamente los cuatro ajustes con `--option` y solo informa éxito si coinciden.
8. Genera 24 caracteres con CSPRNG (144 bits) una sola vez por Windows y guarda
   una copia cifrada con DPAPI LocalMachine bajo `%ProgramData%\Asystec\RustDesk`.
   La carpeta tiene ACL exclusiva para Administradores y SYSTEM. Un bloqueo
   exclusivo serializa generación y aplicación. Un archivo corrupto o ajeno
   produce error sin sustituir la contraseña.
9. Aplica `--password`, exige la respuesta `Done!` del cliente, activa
   `verification-method=use-permanent-password` y `approve-mode=password-click`,
   y verifica ambos valores con lectura posterior.
10. Muestra ID y contraseña en una ventana con botones para revelar/copiar.
    `VER-CREDENCIALES.cmd` permite volver a verla con elevación.

Repetir el instalador vuelve a aplicar la contraseña cifrada existente, incluso
si se cambió manualmente dentro de RustDesk. La copia queda guardada antes de
la asignación para recuperar una ejecución interrumpida; el visor exige que
se haya completado al menos una asignación. La contraseña no se escribe en los
logs ni se incorpora al ZIP. El CLI oficial requiere pasarla brevemente como
argumento al proceso RustDesk. No se envía a ningún sistema de inventario.
El modo `-ValidateOnly` permite comprobar descarga e integridad sin instalar.

Se usa el MSI con `/norestart`, accesos directos y sin impresora virtual.
El modo de autorización admite contraseña permanente o aceptación manual.
El usuario debe ejecutar el instalador fuera de una sesión de soporte activa.

`Test-Packages.ps1` usa Windows PowerShell 5.1 y una pequeña aplicación de prueba
para validar el paso de argumentos a procesos. Extrae los ZIP en una carpeta
temporal y comprueba sus binarios sin instalarlos. También comprueba DPAPI,
persistencia entre ejecuciones, rechazo de archivos corruptos/ajenos, definición
de ACL y respuesta CLI con un ejecutable de prueba.

El EXE 1.5.0.3 se instaló correctamente en Windows 11 Enterprise limpio dentro
de Windows Sandbox el 20 de octubre de 2026. Las 13 comprobaciones de instalación
y configuración pasaron, incluyendo repetición, fallo real y recuperación.
Además se autenticó una conexión real desde el host con la contraseña generada:
RustDesk confirmó conexión retransmitida y cifrada por TCP y mostró el escritorio
del invitado y su ventana de credenciales. Evidencias y límites:
`dist/final-exe-test/verification.json` y `dist/exe-test-report.md`.
El asistente se recorrió en modo interactivo hasta abrir el visor; se comprobó
también un reinicio completo de Windows sin volver a ejecutar el instalador
y una conexión con control remoto después de ese reinicio.

## Fuentes verificadas para RustDesk 1.5.0

- [Release y archivos originales](https://github.com/rustdesk/rustdesk/releases/tag/1.5.0).
- [Parser de configuración y nombre portable](https://github.com/rustdesk/rustdesk/blob/1.5.0/src/custom_server.rs).
- [Comandos config y option](https://github.com/rustdesk/rustdesk/blob/1.5.0/src/core_main.rs).
- [Lectura del nombre portable en Windows](https://github.com/rustdesk/rustdesk/blob/1.5.0/src/platform/windows.rs).
- [Guía de despliegue](https://rustdesk.com/docs/en/self-host/client-deployment/).
- [Modos de contraseña y autorización](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/#verification-method).
- [ACK del servicio al guardar contraseña](https://github.com/rustdesk/rustdesk/blob/1.5.0/src/ipc.rs).
- [Parámetros MSI](https://rustdesk.com/docs/en/client/windows/msi/).
