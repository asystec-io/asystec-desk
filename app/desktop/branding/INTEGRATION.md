# Integracion en Asystec Desk

Los originales de este directorio proceden de `Asystec-Desk_logo_final.zip`.
El archivo `LEEME.md` se conserva sin editar como documentacion del paquete.
La carpeta `_src` que menciona ese documento no estaba incluida en el ZIP;
los maestros SVG suministrados si estan disponibles.

`../make_assets.py` copia los logos y el ICO a `../assets` y adapta el logo
vertical negativo al panel lateral de Inno Setup, conservando proporciones.
El ICO original contiene los tamanos 16, 32, 48, 64, 128 y 256 px.

`../prepare.py` aplica estos recursos al cliente desde las fuentes fijadas.
El wordmark mantiene Poppins trazada en los assets; los controles del programa
conservan su tipografia de interfaz. No se instala ninguna fuente del sistema.
