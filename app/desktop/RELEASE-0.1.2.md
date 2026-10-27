# Asystec Desk 0.1.2 — identidad final

Integra el paquete final de logo "Dos ventanas" suministrado por Asystec.
La ventana de ID y contrasena y las correcciones del instalador de RC2 se
conservan en esta entrega.

## Marca aplicada

- Icono del EXE, bandeja y accesos de Windows: ICO original de seis tamanos.
  Se conservan los dibujos simplificados para 16, 32 y 48 px.
- Logo horizontal principal para tema claro y negativo para tema oscuro.
  El texto Poppins esta convertido a trazos en los originales suministrados.
- Azul Asystec `#064589` en los elementos previamente personalizados del cliente.
- Instalador con icono final y panel lateral navy, logo blanco y verde.
- Ventana de datos de conexion con logo horizontal, titulo navy y boton
  principal azul. El logo se carga de los recursos de la aplicacion instalada.

Los archivos originales estan en `desktop/branding`. `IMPORT.json` registra
el hash del ZIP recibido y de cada archivo. `make_assets.py` prepara los
recursos sin redibujar el logo ni volver a generar los tamanos pequenos del ICO.

## Superficie del cambio

En el cliente nativo cambian los recursos de `flutter/assets`, el icono de
`flutter/windows/runner/resources`, los iconos de `res`, y los tres colores
ya personalizados en `common.dart` y `desktop_setting_page.dart`.

En el instalador cambian `Asystec-Desk.iss` y la presentacion de
`Show-DeviceCredential` en `Connection-Details.ps1`. La configuracion de
servidor, el servicio, la autenticacion y el almacenamiento de credenciales
mantienen su comportamiento anterior. Los scripts de `app/desktop` reflejan
la version actual de `desktop` para distribuir fuentes correspondientes.

`Build-Windows.ps1` fuerza la recompilacion de `Runner.rc`: MSBuild conservaba
el icono anterior cuando solo cambiaba el ICO referenciado. Tanto el build
como `Build-Setup.ps1` verifican el icono visible integrado en el EXE contra
el ICO suministrado mediante `Verify-WindowsBranding.ps1`, antes de distribuirlo.

## Limite conservado de RC2

La ventana muestra la contrasena gestionada por el instalador. Un cambio
manual de contrasena dentro del cliente no se sincroniza con esa copia;
reinstalar vuelve a aplicar la contrasena gestionada.

## Validacion de la entrega

Instalador probado: SHA-256
`8f62dfe25583f3165bf9e2bc5745e9ac8ab2e3fd017761c0b9e5e0520fd184cd`.
Cliente probado: SHA-256
`628d59131e3b31e2583d0560c3480a9c5258dc6a9db47513301b9bd9db7da395`.

- Cinco pruebas de fuentes y tres de credenciales aprobaron.
- Preparar desde upstream reproduce los assets finales; se verificaron las
  seis resoluciones del ICO y la copia exacta de los originales.
- La verificacion del icono integrado rechaza el primer candidato que aun
  contenia AD y acepta el cliente y el instalador finales.
- Windows Sandbox limpio: 13 comprobaciones aprobaron, incluyendo instalacion,
  servicio automatico, servidor/clave/relay, credenciales cifradas, permisos,
  reinstalacion y conservacion del ID tras reiniciar el servicio.
- Se revisaron el icono del escritorio, el logo del cliente en tema oscuro,
  el asistente y su panel final, y la ventana de credenciales. Los dos botones
  de copia confirmaron la accion, sin mostrar la contrasena en pantalla.
- Finalizar abrio la ventana de datos de conexion. Una sesion independiente
  se autentico con las credenciales del instalador y confirmo relay cifrado TCP.

Evidencia resumida en `verification/branding-0.1.2.json`. La prueba limpia fue
en Windows Sandbox; no certifica todas las versiones de Windows ni resuelve
por si sola la causa del error original informado desde otra computadora.
El instalador no tiene firma Authenticode propia.
