# Asystec Desk

Asystec Desk es una versión modificada de RustDesk OSS 1.5.0, bajo AGPL-3.0.
Se conservan las atribuciones, licencias y derechos de los autores originales.
No es un producto oficial ni está avalado por RustDesk o Purslane.

Las modificaciones iniciales de Asystec son del 26 de octubre de 2026 e incluyen
marca, recursos gráficos, configuración del servidor y ajustes de instalación
Windows para el nombre Asystec Desk. El icono AD es provisional.

`app/` contiene las fuentes reales de la compilación, incluido `hbb_common`,
el puente Rust/Flutter generado y los archivos de bloqueo de dependencias.
No requiere inicializar submódulos Git. El origen y los cambios están en
`app/ASYSTEC-SOURCE-MANIFEST.json` y `app/ASYSTEC-CHANGES.patch`.

Las únicas adaptaciones del snapshot para su almacenamiento en este repositorio
son los tres archivos `.gitattributes`, que conservan los bytes de las fuentes
al clonar en Windows. No cambian el código compilado.

`desktop/` contiene los scripts mantenidos de preparación, compilación, empaquetado
y QA de Asystec. `app/desktop/` conserva la copia incluida en el snapshot de la
versión. La infraestructura y los paquetes anteriores están en `server/` y `clients/`.

El texto de la licencia principal está en `LICENSE` y en `app/LICENCE`.
Las dependencias conservan sus licencias y avisos correspondientes.
