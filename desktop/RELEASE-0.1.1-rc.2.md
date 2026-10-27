# Asystec Desk 0.1.1 RC2 — ventana de datos de conexion

El instalador propio no habia incorporado la ventana de ID y contrasena que
existia en el instalador anterior de soporte. Esta version la abre al pulsar
Finalizar, con la opcion `Ver ID y contrasena de este equipo` marcada por defecto.

La ventana permite mostrar la contrasena, copiarla sola o copiar ID y contrasena.
Puede volver a abrirse desde Inicio > Asystec Desk > Ver datos de conexion.
La instalacion silenciosa configura los datos sin abrir la ventana.

## Credenciales por equipo

Se genera una contrasena aleatoria distinta por equipo, se exige la confirmacion
del cliente al guardarla y se verifica el modo de autorizacion. Se admite esa
contrasena permanente o la aceptacion manual de la conexion.

La copia recuperable se guarda con DPAPI LocalMachine en
`%ProgramData%\Asystec\Desk\credenciales.dat`, dentro de una carpeta accesible
solo a administradores y SYSTEM. Abrir la ventana solicita UAC si hace falta.
La contrasena no se escribe en los registros del instalador.

Una reinstalacion reutiliza y vuelve a aplicar la contrasena guardada. Un archivo
corrupto o de otro equipo produce un error sin reemplazarlo. El almacen es
independiente del instalador anterior de RustDesk.

La ventana muestra la contrasena gestionada por este instalador. Los cambios
manuales de contrasena dentro del cliente no se sincronizan con esta copia;
reinstalar vuelve a aplicar la contrasena gestionada.

## Validacion

SHA-256 del EXE probado:
`2085d0693c8144043f9b622b28c7247470449e53694ed6bb4cc3462401d097da`.
Version numerica del instalador: `0.1.1.2`.

- Tres pruebas locales: cifrado, unicidad y persistencia; rechazo de registros
  corruptos o de otro equipo; confirmacion de asignacion y errores sin secretos.
- Windows Sandbox: creacion inicial de las credenciales, permisos reales de
  la carpeta, servicio, ID, configuracion de servidor y puertos de Asystec.
- Reinstalacion y reinicio del servicio conservaron ID y contrasena.
- Asistente interactivo: Finalizar abrio la ventana; se observaron los botones
  de copia y su confirmacion visual, con la contrasena oculta inicialmente.
- Conexion autenticada desde el cliente del host usando la contrasena creada
  por el instalador: la interfaz confirmo relay cifrado por TCP.
- La contrasena no aparecio en los registros de instalacion exportados para QA.

El Sandbox tenia el cliente instalado por un intento previo; la creacion de
credenciales era nueva. La evidencia resumida esta en
`verification/installer-0.1.1-rc.2.json`. No se certifican otras versiones de
Windows ni el flujo de UAC con una cuenta administradora diferente.

## Superficie del cambio

Los cambios afectan al instalador Inno, a su auxiliar PowerShell y a la nueva
ventana `Connection-Details.ps1`. El auxiliar instala el visor, configura las
credenciales y crea el acceso del menu Inicio. Se establece un directorio de
trabajo existente al lanzar PowerShell y el cliente, evitando heredar la ruta
virtual Sysnative en procesos de 64 bits. El cliente Rust/Flutter de 0.1.0 no
necesito recompilarse.

Se publica como version preliminar, con fuentes y hashes. La causa del error
original comunicado desde otra computadora sigue pendiente de confirmacion;
esta entrega no cambia todavia el destino estable de la web.
