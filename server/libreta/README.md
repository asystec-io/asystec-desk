# Libreta personal de Asystec Desk

Cada técnico tiene una cuenta. Puede iniciar sesión en varias PC y sincronizar ID, alias, etiquetas y notas. Las contraseñas de acceso remoto se administran en cada equipo. Esta versión admite la libreta personal.

## Prueba con el servidor Asystec

El instalador de prueba configura y verifica `https://184.197.59.221` (instancia Lightsail `asystec-desk`). Instala el mismo paquete en las dos PC, entra en **Libreta** con la misma cuenta y agrega un equipo desde una de ellas. La cuenta se entrega por separado del instalador.

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
