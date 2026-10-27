# Asystec Desk 0.1.0 — primera compilación Windows x64

Compilación y pruebas realizadas el 26 de octubre de 2026, hora de Costa Rica.
Basado en RustDesk OSS 1.5.0, commit
`fada664df7a294d1d1a9ca3e7cd3637069122f17`, con licencia AGPL-3.0.

## Entrega

- Instalador: `dist/Asystec-Desk-Setup.exe`, 29 838 937 bytes.
- SHA-256 del instalador:
  `03e5e7dafbaf9c42e70f6a302842d47abed37d2c842a306addcfe719c38528c1`.
- Cliente y DLL: `dist/asystec-desk-v0.1.0/`.
- SHA-256 de `Asystec Desk.exe`:
  `7254fef9e6711c29a92e39c452f0341b701e8fa0e0168c1f71243045d43a0730`.
- Fuentes de la compilación: `dist/asystec-desk-v0.1.0/Asystec-Desk-source.zip`.
- Fuentes con los scripts de QA y documentación actualizados:
  `dist/Asystec-Desk-source.zip`.

El instalador tiene el nombre e icono de Asystec Desk. Solicita administración,
instala el servicio con inicio automático y verifica el hash instalado.
No está firmado con un certificado de Asystec. El icono AD es provisional.

## Resultado verificado

En Windows Sandbox se instaló el mismo EXE identificado arriba. Pasaron las
diez comprobaciones automáticas de `verification/windows-final.json`:
marca Windows, instalación y servicio con nombre que contiene un espacio,
inicio automático, servidor/relay/clave/API vacía, ID válido, contraseña única
de QA, persistencia del ID al reiniciar el servicio y acceso TCP al servidor
en 21115, 21116 y 21117.

Desde el cliente Asystec Desk compilado en el host se intentó conectar al ID
del Sandbox, forzando relay. La contraseña incorrecta fue rechazada. Con la
credencial de prueba correcta se abrió la sesión y la interfaz identificó
explícitamente una **conexión retransmitida y cifrada (TCP)**. Se comprobó
además una conexión TCP establecida del proceso del cliente hacia
`184.197.59.221:21117`. No se utilizaron servidores públicos como relay.

Evidencias originales en `dist/asystec-desk-final-qa-results/`:
`verification.json`, `remote-negative.txt`, `remote-authenticated.txt` y
`relay-connections.json`. La credencial de QA se exportó cifrada con RSA;
la clave privada de prueba permanece protegida con DPAPI fuera de los fuentes.

También pasaron cinco pruebas de preparación/integridad y tres pruebas del
validador real de nombres. Un paquete que fallaba la instalación produjo
el código no cero 12, comprobando que el bootstrap ya propaga el error.

## Correcciones necesarias durante la compilación

Se entrecomillaron nombres de servicio, ejecutables y claves de registro;
se normalizó el esquema URI sin espacios. La validación original de nombres
se conserva, con una excepción exacta para `Asystec Desk`. No se aceptan otros
nombres con espacios ni metacaracteres. La identidad de instalación tiene
un GUID independiente del identificador heredado de RustDesk.

En el arnés de QA se evitó el nombre `Cli`, que colisionaba con un alias de
Windows PowerShell. Estos cambios del arnés no modifican el cliente compilado.

## Alcance

Se verificaron instalación, reinicio de servicio, autenticación y transporte
por relay en Windows Sandbox. No se certifican todavía todas las funciones
de control manual, aceptación manual, transferencia de archivos, impresión,
reinicio completo de Windows, migración desde RustDesk ni otras versiones
de Windows. La descarga pública anterior no fue sustituida.
