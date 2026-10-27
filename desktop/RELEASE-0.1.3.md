# Asystec Desk 0.1.3 — instalacion simplificada

La pantalla obligatoria con el texto completo de la licencia y las opciones
"Acepto / No acepto" se sustituye por una bienvenida breve. Siguiente esta
habilitado desde el inicio y el aviso explica la aceptacion al continuar.

"Ver licencia AGPL-3.0" abre el texto completo incluido en el instalador,
en una ventana de solo lectura, sin conexion a Internet. Se conservan la
licencia y los avisos del software libre, las fuentes publicas y la atribucion.
No se agregan terminos comerciales ni condiciones de privacidad nuevas.

## Superficie del cambio

Solo cambia `desktop/Asystec-Desk.iss` y su copia en las fuentes distribuidas:
pagina de bienvenida, enlace al texto incluido y version del instalador.
El cliente nativo, el servicio, el servidor configurado y la ventana de ID y
contrasena son los mismos binarios y auxiliares probados en 0.1.2.

## Validacion

- 13 comprobaciones aprobadas en Windows Sandbox: instalacion limpia,
  servicio automatico, configuracion del servidor, ID, credenciales cifradas,
  acceso directo, reinstalacion, reinicio y conectividad TCP con Asystec.
- Recorrido visual: bienvenida sin casillas, licencia local legible con
  boton Cerrar y avance con Siguiente hasta la instalacion. Finalizar abre
  la ventana de ID y contrasena con la contrasena oculta inicialmente.
- Icono integrado del instalador verificado contra el ICO final.
- Integridad y atribucion de las fuentes verificadas con las cinco pruebas
  existentes. Se adjunta `installer-0.1.3.json` con los resultados.

El instalador sigue sin firma Authenticode. Esta validacion en Sandbox no
cubre todas las versiones de Windows. La sesion remota no se repitio para
este cambio del asistente: el cliente nativo es identico al que aprobo
la conexion cifrada por relay en 0.1.2.
