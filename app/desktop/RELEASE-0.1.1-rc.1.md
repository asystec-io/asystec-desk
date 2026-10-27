# Asystec Desk 0.1.1-rc.1 — diagnostico de instalacion

Version preliminar para investigar el error externo
`No se pudo verificar la instalacion de Asystec Desk. Codigo: 1`.
El fallo comunicado ocurrio en otra computadora y su causa sigue sin confirmar.
No se ha reproducido ese incidente en la computadora afectada.

## Cambios

El instalador ejecuta PowerShell de 64 bits, usa la carpeta nativa de programas
de Windows y establece la carpeta del paquete como directorio de trabajo.
Captura la salida del cliente interno, su codigo de salida, la ruta del servicio
y su estado. El mensaje de error conserva el motivo y la ubicacion del registro
`%TEMP%\Asystec-Desk-*.log`. Tambien se guardan stdout, stderr y el detalle del error.

El comando interno puede imprimir `Failed with error:` y devolver cero. Ahora
ese mensaje causa un fallo de instalacion, incluso si existe un servicio previo.
La comprobacion exige que el servicio apunte al ejecutable esperado y verifica
su hash. Los procesos de bandeja no deben bloquear la lectura del diagnostico.

No se recompilo ni modifico el cliente Rust/Flutter de 0.1.0. Los cambios de
ejecucion se limitan al bootstrap y `Install-Client.ps1`; el arnes de Sandbox
permite seleccionar el instalador exacto y conserva sus registros para QA.

## Verificacion

Instalador probado: SHA-256
`3a8406aeae2c6e9f741b85265aba50523b41d566b84a617a40dcd0f5fd68bc1a`.

- Windows Sandbox nuevo: instalacion, servicio automatico, perfil de servidor,
  ID valido, persistencia del ID al reiniciar el servicio y acceso TCP a los
  puertos 21115, 21116 y 21117 de Asystec.
- Actualizacion con RustDesk OSS 1.5.0 instalado: ambos servicios continuaron
  activos en rutas separadas; se comprobaron los hashes del EXE y DLL Asystec.
- Un cliente simulado que imprime un error y termina con cero fue rechazado;
  se conservaron el error y el registro.
- Un paquete de QA con el antiguo rechazo del nombre con espacios produjo
  codigo 12 y el motivo concreto en el registro de Setup.

Evidencia resumida: `verification/installer-0.1.1-rc.1.json`.
La prueba de paquetes fallidos es un caso de QA, no identifica la causa del
incidente externo. No se repitio una sesion remota autenticada para este cambio
del instalador; su evidencia anterior corresponde a 0.1.0.

## Prueba en el equipo afectado

Descargar el instalador desde la version preliminar `v0.1.1-rc.1` de GitHub,
ejecutarlo y, si falla, compartir el archivo `.log` indicado en el mensaje.
El registro puede contener rutas con el nombre del usuario; enviarlo por el
canal de soporte en lugar de publicarlo en una incidencia abierta.

Esta version no se marca Latest: la descarga estable de asystec.io sigue
apuntando a 0.1.0 hasta verificar el resultado en la computadora afectada.
No certifica otras versiones de Windows ni el reinicio completo del sistema.

Para repetir la prueba limpia desde un equipo con Windows Sandbox disponible:

```powershell
./desktop/Test-WindowsSandbox.ps1 -BundleDirectory dist/asystec-desk-v0.1.0 -RunName asystec-desk-0-1-1-clean -SetupPath .build/installer-0.1.1/Asystec-Desk-Setup.exe
```

La regresion de diagnostico se ejecuta dentro del Sandbox con
`desktop/tests/Sandbox-InstallerDiagnostics.ps1` y `Install-Client.ps1`
copiados al directorio de entrada indicado en el propio script.
