# 06 — Ajustes e idiomas

## Pantalla de Ajustes

Contiene las configuraciones generales de la app (tabla `Settings`, doc 02):

- **Idioma** de la interfaz (ver abajo)
- **Tema**: Sistema / Claro / Oscuro (predeterminado: Sistema — ver
  `07_design_and_theming.md`)
- **Nube / Google Drive**:
  - vincular / desvincular cuenta de Google
  - estado de la última copia de seguridad (versión + fecha)
  - acciones: Subir a la nube / Descargar de la nube
  - activar/desactivar el uso de la nube
- **Unidades** de medida: un preajuste (Internacional / Imperial) y las
  cinco magnitudes una a una (ver "Unidades de medida", abajo)
- Posibles preferencias futuras (formato de fecha, etc.)

**La moneda no es configurable**: es siempre el euro (ver doc 02). Del idioma
elegido solo depende el *formato* con el que se muestra el importe.

## Tabla de ajustes (`settings`)

Los ajustes se guardan en la base de datos, en la tabla `settings` (esquema
v6): una fila por clave.

| Columna | Contenido |
| --- | --- |
| `key` | Código estable del ajuste (clave primaria), p. ej. `last_export_at` |
| `value` | Valor como texto; `NULL` si se ha borrado. Cada clave define su formato (un instante va en ISO-8601 UTC) |
| `updated_at` | Instante UTC de la última escritura |

- Sin borrado lógico y **sin historial de operaciones**: un ajuste no es un
  dato del usuario y sobrescribirlo no pierde nada que no pueda volver a
  elegir.
- Las claves son códigos fijos en el código (nunca el nombre de un valor de
  Dart), así que renombrar algo en el código no cambia lo que hay en disco.
- Claves actuales:

  | Clave | Valores | Sin fila |
  | --- | --- | --- |
  | `last_export_at` | Instante de la última exportación del paquete de copia (ver `05_sync_and_storage.md`) | nunca exportado |
  | `language` | `system`, `it`, `es`, `en` | `system` |
  | `theme` | `system`, `light`, `dark` | `system` |
  | `unit_distance` | `km`, `mi` | `km` |
  | `unit_volume` | `l`, `gal_us`, `gal_uk` | `l` |
  | `unit_temperature` | `c`, `f` | `c` |
  | `unit_pressure` | `bar`, `psi` | `bar` |
  | `unit_consumption` | `l_100km`, `km_l`, `mpg_us`, `mpg_uk` | `l_100km` |
  | `drive_account` | Email de la cuenta de Google vinculada (no es un secreto: los tokens nunca van a esta tabla) | sin cuenta |
  | `drive_auth_mode` | `system` (cuenta del teléfono) / `manual` (vinculada en el navegador; su refresh token está en `flutter_secure_storage`) | `system` |
  | `drive_device_id` | UUID de este teléfono en las copias que sube | se crea al primer uso |
  | `drive_mobile_data` | `true` / `false`: la copia automática puede usar datos móviles | `false` |
  | `drive_sync_account`, `drive_sync_local_stamp`, `drive_sync_upload_id`, `drive_sync_at`, `drive_sync_direction` | El último punto en común con la copia de Drive (cuenta, sello local o `none`, `upload_id`, instante, `upload` / `download`); incompleto = no hay | sin punto en común |

  Los valores también son códigos fijos. Un valor desconocido (por ejemplo,
  escrito por una versión más nueva de la app) se lee como `system`.
- La tabla viaja dentro del paquete de copia como el resto de la base de
  datos: al importar un paquete llegan también su idioma y su tema, y la app
  cambia en ese mismo momento, sin reiniciar. Cada clave tiene un **ámbito**
  (`SettingScope`): las compartidas (`last_export_at`, `language`, `theme`
  y las cinco `unit_*`) llegan con el paquete; las del teléfono (`drive_account`,
  `drive_auth_mode`, `drive_device_id`, `drive_mobile_data`) se conservan;
  las del punto en
  común (`drive_sync_*`) se borran (ver `05_sync_and_storage.md`).

## Idioma y tema: cómo se aplican

- **Al momento.** Elegir un idioma o un tema en Ajustes cambia toda la app
  enseguida, sin reiniciar. Con el idioma cambian también las fechas, los
  números y los importes (formato de `intl` del idioma elegido).
- **Sistema** sigue al dispositivo: su idioma (con el inglés como respaldo,
  ver abajo) o su modo claro / oscuro. Es el valor si no hay fila.
- **Arranque.** Los ajustes se leen cuando la base de datos ya está abierta;
  hasta entonces (la pantalla de carga) la app usa el idioma y el tema del
  sistema. Así no aparece un idioma equivocado después del splash. Si la
  lectura falla, se usa `system` y el error queda en el log.
- **Importar un paquete.** Mientras la base de datos se reabre, la app
  mantiene el idioma y el tema que tenía; después pasa a los del paquete.
- Los temas claro y oscuro son los de `07_design_and_theming.md`: el ajuste
  solo elige cuál se usa.

## Unidades de medida

Desde el paso 11 el usuario elige en qué unidades **escribe y lee** cada
magnitud física. Lo que cambia es solo lo que se ve; lo que hay guardado no.

- **La base de datos no conoce unidades.** Toda magnitud se guarda en SI:
  distancias en **km**, volúmenes en **litros**, temperaturas en **°C**,
  presiones en **bar**, consumos en **L/100 km**. Las tablas, los
  repositorios, las reglas de dominio (lecturas no decrecientes, umbral de
  50.000 km, etc.) y el paquete de copia trabajan siempre en esas unidades.
  Cambiar el ajuste **nunca toca un dato guardado**: dos teléfonos con
  unidades distintas ven exactamente los mismos datos.
- **La conversión vive solo en el borde de la interfaz**, en un único
  formateador (`UnitFormatter`): al interpretar lo que el usuario escribe
  (de su unidad a SI) y al mostrar un valor (de SI a su unidad). Ninguna
  pantalla escribe un símbolo de unidad a mano: lo pide al formateador. Los
  símbolos son textos traducibles.
- **Precisión.** Lo escrito en millas se guarda como su valor exacto en km
  (100 mi = 160,9344 km; las columnas de distancia son `REAL` desde el
  esquema v9) y vuelve a mostrarse como 100 mi, no como 100,04. Un valor
  guardado en km enteros se muestra en millas redondeado a entero; volver a
  escribir exactamente lo que se muestra devuelve el valor guardado, para
  que un redondeo nunca quede "por debajo de la última lectura". Decimales
  mostrados: distancia 0, volumen 2, temperatura 1, presión 1 en bar y 0
  en psi, consumo 1.
- **Factores** (fijos en el código): 1 mi = 1,609344 km; 1 gal EE. UU. =
  3,785411784 L; 1 gal imperial = 4,54609 L; °F = °C × 9/5 + 32; 1 bar =
  14,503773773 psi. Los consumos se derivan de ellos (mpg EE. UU. con el
  galón estadounidense, mpg imperial con el británico).
- **Cinco claves** en `settings` (tabla de arriba), una por magnitud; sin
  fila = unidad SI. Son una preferencia que viaja con los datos, como el
  idioma y el tema: importar un paquete trae también sus unidades.
- **Preajustes, nunca guardados.** La pantalla de Ajustes calcula cada vez
  cuál está activo a partir de las cinco claves: **Internacional** = km, L,
  °C, bar, L/100 km; **Imperial** = mi, gal EE. UU., °F, psi, mpg EE. UU.;
  cualquier otra combinación es **Personalizado**, que se muestra pero no se
  puede elegir. Tocar un preajuste escribe las cinco claves a la vez;
  cambiar una magnitud escribe solo esa clave (y el preajuste pasa a
  Personalizado, o vuelve a Internacional / Imperial si las cinco coinciden
  otra vez). El galón imperial y los mpg imperiales solo están en los
  selectores por magnitud, nunca en un preajuste.
- **Volumen y consumo son independientes.** Cambiar el volumen no cambia la
  unidad de consumo; si no casan (galones con L/100 km), una nota discreta
  bajo el selector de consumo lo dice y nada más.
- **Dónde se aplica.** En todo lo que muestra o pide una distancia: lecturas
  del cuentakilómetros (pestaña Kilometraje, lectura inicial, km finales
  del archivo), el km de cada entrada, la oferta "¿Actualizar el
  cuentakilómetros?", la confirmación del salto grande, el banner y el chip
  de archivo, la cabecera del vehículo y las listas. Los campos llevan el
  símbolo de la unidad como sufijo y aceptan **números enteros en esa
  unidad**. Los umbrales que se enseñan al usuario se redondean a una cifra
  amigable: la regla de los 50.000 km se muestra como "30.000 mi" en millas
  (por dentro se siguen comparando 50.000 km). Temperatura, presión y consumo
  no tienen pantallas todavía (pasos 12 y 14): existen el ajuste, el
  formateador y sus pruebas.
- La moneda sigue siendo el euro, fijo: con el volumen en galones se verá
  "€/gal", y es lo esperado.

## Idiomas

La app admite tres idiomas, seleccionables por el usuario:

- **Italiano** (it)
- **Español** (es)
- **Inglés** (en)

El **inglés** es el idioma de la plantilla ARB (`app_en.arb`, el archivo que
define todas las claves) y el **idioma de respaldo**: si el idioma del
dispositivo no es ninguno de los tres, la app se muestra en inglés.

### Reglas técnicas para la localización

- Todos los textos mostrados al usuario deben estar **fuera del código**, en
  archivos de traducción (enfoque ARB + `flutter_localizations` / gen_l10n).
  Nunca cadenas visibles "escritas a fuego" en el código.
- El código, los nombres de variables y los comentarios se mantienen en
  **inglés** (ver `CLAUDE.md`); la localización afecta solo a los textos
  dirigidos al usuario.
- Atención a números, fechas, monedas y unidades: deben formatearse según el
  idioma elegido.

## Nota

La documentación del proyecto (esta carpeta `Docs/`) está en **español**. Los
textos de la interfaz se traducen a los tres idiomas (IT / ES / EN). El código
está en inglés. Son tres planos distintos y no deben confundirse.
