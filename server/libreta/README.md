# Libreta personal de Asystec Desk

Cada técnico tiene una cuenta. Puede iniciar sesión en varias PC y sincronizar ID, alias, etiquetas y notas. Desde el cliente 0.1.9, el menú del equipo también permite guardar su contraseña en la libreta personal. Esta versión admite la libreta personal.

### Contraseña guardada en la libreta

En Windows, abrí la libreta, pulsá los tres puntos del equipo y elegí **Guardar contraseña en la libreta**. Ingresá la contraseña permanente del equipo. Al iniciar sesión con esa misma cuenta en otra PC y pulsar **Conectar**, el cliente recupera la contraseña por HTTPS. **Administrar contraseña en la libreta** permite reemplazarla o quitarla. Eliminar un equipo elimina también su contraseña guardada.

La API usa AES-256-GCM con un nonce aleatorio por escritura y vincula cada valor al identificador de la libreta y al ID del equipo. La sincronización habitual solo entrega el estado y la revisión de la contraseña. La API puede descifrarla y las sesiones autorizadas de esa cuenta pueden usarla. El respaldo de la base y el de la clave deben guardarse por separado. Quien tenga ambos puede descifrar los valores.

Para actualizar una instalación del servicio, ejecutá `sudo bash enable-credentials.sh` desde la carpeta de la API que contiene el código nuevo. La clave se conserva en `/etc/asystec-book/vault.key` con acceso exclusivo de root y systemd la entrega al proceso de la API. Respaldala en el gestor de secretos antes de depender de la función. Para restaurar en otro servidor, recuperá la misma clave junto con la base. Los clientes anteriores pueden seguir editando alias y notas sin sobrescribir contraseñas.

### Alta de equipos durante la instalación

Desde la versión 0.1.7, el instalador ofrece agregar el ID y el nombre de la PC a la libreta de `asystec`. La opción viene marcada. Si el equipo está sin conexión o el servidor aún no ha reconocido su ID, Windows reintenta al minuto y después cada cinco minutos hasta recibir confirmación. Una reinstalación conserva las ediciones y eliminaciones de soporte. Para excluir un equipo, desmarcá la opción o usá `/MERGETASKS="!enrollbook"` en una instalación silenciosa.

Después de desplegar la API y sus reglas Nginx con `deploy.sh`, ejecutá `sudo bash enable-enrollment.sh` en el servidor HBBS. El script vincula el alta a la cuenta existente por su identificador y crea el temporizador `asystec-peer-index.timer`. Ese índice contiene verificadores derivados de los equipos registrados en HBBS. El instalador envía una prueba derivada del identificador de Windows, junto con el ID de soporte y el nombre del equipo, por HTTPS. El alta no entrega una sesión ni permite leer la libreta. Para suspender las altas, desactivá el temporizador y retirale al servicio de libreta la variable `BOOK_ENROLL_GUID` antes de reiniciarlo.

## Prueba con el servidor Asystec

El instalador configura `https://184.197.59.221` (instancia Lightsail `asystec-desk`). En la primera PC, abre **Libreta → Iniciar sesión → Crear cuenta**, elige un usuario y una contraseña de 12 a 128 caracteres y confirma el registro. La aplicación inicia sesión y abre tu libreta personal. En la segunda PC, inicia sesión con los mismos datos. Al agregar un equipo a la libreta en una PC, aparecerá en la otra.

En Ubuntu, Nginx termina HTTPS y reenvía las solicitudes a Waitress en loopback. El servicio `asystec-book.service` usa la base `/var/lib/asystec-book/libreta.sqlite3`. El temporizador `asystec-book-renew.timer` comprueba el certificado dos veces al día y recarga Nginx al renovarlo. Para verificar el acceso desde otra red, consulta `https://184.197.59.221/api/login-options` y espera la respuesta `[]`.

El script `deploy.sh` se ejecuta desde el directorio de la API en Ubuntu, con Nginx, Python venv y Certbot 5.4+ instalado en `/opt/asystec-book/acme`. Requiere TCP 80 y 443 entrantes en Lightsail. Diagnóstico: `journalctl -u asystec-book`, `systemctl list-timers asystec-book-renew.timer` y `/opt/asystec-book/acme/bin/certbot renew --cert-name asystec-book --dry-run`. Para retirar únicamente la API, deshabilita el servicio y el temporizador, retira las configuraciones Nginx `asystec-book-{http,tls}.conf` y recarga Nginx tras `nginx -t`. Conserva la base y las reglas de RustDesk.

## Prueba local

Desde este directorio, con Python 3.11 o superior:

```powershell
py -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
$env:BOOK_DB = Join-Path (Get-Location) 'libreta.sqlite3'
.\.venv\Scripts\python -m flask --app service:create_app create-user tecnico
.\.venv\Scripts\waitress-serve --listen=127.0.0.1:8787 --call service:create_app
```

En el cliente compilado con este cambio, abre **Configuración → Red → Servidor ID/Relay** y escribe `http://127.0.0.1:8787` en **Servidor API**. Esta dirección sirve para probar la API desde la misma PC. En la pestaña **Libreta**, inicia sesión con la cuenta creada y agrega un equipo.

## Uso desde varias PC

Ejecuta el servicio con una cuenta del sistema dedicada. Define `BOOK_DB` con la ruta absoluta de la base en un directorio privado. Mantén Waitress en loopback y publica el servicio detrás de un proxy HTTPS con un certificado válido. Limita los intentos de `POST /api/login` por IP en el proxy. Usa esa misma URL HTTPS como **Servidor API** en cada PC de soporte. El relay de escritorio remoto funciona por separado. Para respaldar la base en uso utiliza la operación de backup de SQLite, que incluye los cambios del WAL. La base contiene los nombres de clientes y notas de soporte.

## Comprobar la sincronización

1. Inicia sesión con la misma cuenta en dos PC. Agrega un equipo en la primera. En la segunda debe aparecer al abrir la libreta o tras el refresco automático de unos diez segundos.
2. Desconecta la primera PC, cambia un alias y reinicia la aplicación. Debe conservar el cambio pendiente. Al reconectar debe pasar a **Sincronizado**.
3. Cambia el mismo equipo en las dos PC antes de sincronizar. La aplicación conserva la edición local y ofrece usar la versión de la nube o conservar el cambio. Las actualizaciones del lote se aplican juntas después de resolver sus conflictos.
4. Elimina el equipo y comprueba la eliminación en la otra PC. Una copia antigua no debe restaurarlo automáticamente.
5. Inicia sesión con otro usuario. Debe ver únicamente su libreta personal.

Para ejecutar las pruebas HTTP con dos sesiones y una base temporal:

```powershell
.\.venv\Scripts\python -m unittest test_service
```
