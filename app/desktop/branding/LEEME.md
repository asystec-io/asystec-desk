# Asystec Desk · Paquete final de logo (Propuesta B · Dos ventanas)

Bryan eligió la Propuesta B el 26/10/2026. Esta carpeta es el paquete final. Las propuestas A y C quedaron en `../_descartadas/`.

**Concepto:** dos pantallas enlazadas por la señal verde de Asystec: tu equipo y el del técnico, conectados.

## Refinamiento respecto a la propuesta
- Hay una separación limpia entre la ventana trasera y la delantera. Así las dos ventanas no se funden en tamaños chicos.
- Las ondas de señal quedan contenidas dentro de la pantalla.
- La ventana trasera del ícono usa un azul pálido (`#B9CCEA`) para que contraste con el marco blanco.
- Hay dos versiones simplificadas del ícono, dibujadas sobre una grilla de 16 px (1 px = 64 unidades):
  - `icono_pequeno_32-48`: dos ondas, sin los puntitos de la barra. Se usa en 32 y 48 px.
  - `icono_pequeno_16`: una onda y un punto, con trazos de 1 px o más. Se usa en 16 px.
- Todo es 100 % vectorial: sin máscaras ni imágenes incrustadas, y el texto está convertido a trazos. Por eso los SVG y PDF no necesitan la fuente instalada.

## Colores
| Nombre | Hex | Uso |
|---|---|---|
| Azul Asystec | `#064589` | «Desk» en la versión principal |
| Azul claro | `#0A4E99` | Degradado (arriba) |
| Azul profundo | `#012A62` | Degradado (abajo), pantalla del ícono |
| Azul cara | `#1E4280` | Ventana trasera en la versión principal |
| Verde señal | `#89C541` | Señal, «Desk» en negativo |
| Navy | `#0F1F45` | «Asystec», fondos oscuros, monocromo |
| Azul pálido | `#B9CCEA` | Ventana trasera en negativo y en el ícono |
| Blanco | `#FFFFFF` | Marco, negativo y monocromo blanco |

Los colores se midieron en los píxeles del isotipo oficial de Asystec.

**Tipografía:** Poppins. «Asystec» va en Bold y «Desk» en Medium. Para textos de apoyo se usan Poppins Regular y SemiBold.

**Área de protección:** 1X alrededor del logo, donde X es la altura de la «A» de Asystec. Los PNG ya traen un margen de 0,5X.

**Tamaño mínimo:**
- Horizontal: 120 px o 30 mm.
- Vertical: 64 px o 18 mm.
- Ícono: 16 px. Entre 16 y 48 px se usa la versión simplificada.

## Archivos
- `asystec-desk_hoja-de-marca_1920x1080.png`: hoja de marca con colores, tipografía, área de protección, tamaño mínimo, versiones y usos incorrectos.
- `asystec-desk_mockup_barra-y-ventana_1920x1080.png`: mockup ilustrativo con la barra de tareas y la ventana de la app. Lleva la leyenda «Ilustración. No es una captura del sistema.» y no tiene marcas de terceros.
- `logo_horizontal/` y `logo_vertical/`: cada uno trae las variantes `principal`, `negativo` (sobre navy), `mono-navy` y `mono-blanco`, cada una en `.svg`, `.pdf` y `_2048.png`. El PNG es transparente y mide 2048 px en su lado largo.
- `isotipo/`: las mismas 4 variantes en `.svg` y `_2048.png` transparente.
- `icono_app/`:
  - `asystec-desk_icono_1024_maestro.svg/.png`: cuadrado redondeado, esquinas transparentes.
  - `asystec-desk_icono_1024_tienda_sin-esquinas.svg/.png`: cuadrado completo, sin transparencia, para tiendas de apps.
  - `asystec-desk_icono_512/256/128/64.png`: salen del diseño maestro.
  - `asystec-desk_icono_48/32.png`: salen de la versión simplificada de dos ondas (`asystec-desk_icono_pequeno_32-48.svg`).
  - `asystec-desk_icono_16.png`: sale de la versión simplificada de una onda (`asystec-desk_icono_pequeno_16.svg`).
  - `asystec-desk.ico`: Windows, con 16, 32, 48, 64, 128 y 256 px.
  - `asystec-desk.icns`: macOS, con 16 a 512 px, incluido @2x.
- `favicon/`: `favicon-16x16.png`, `favicon-32x32.png` y `favicon.ico` (16 y 32 px).
- `_src/`: `marca.py` (geometría y colores), `build_final.py` (exporta todo) y `hoja_mockup.py`. Para regenerar: `cd _src && python3 build_final.py && python3 hoja_mockup.py`.

## Qué se evitó
- Nada que recuerde a AnyDesk o TeamViewer.
- Ningún logo de terceros, en particular ningún logo de sistema operativo en el mockup.
- Ningún robot ni precio.
