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
- Posibles preferencias futuras (unidades de medida, formato de fecha, etc.)

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
  | `drive_account` | Email de la cuenta de Google vinculada (no es un secreto: no se guarda ningún token) | sin cuenta |
  | `drive_device_id` | UUID de este teléfono en las copias que sube | se crea al primer uso |
  | `drive_mobile_data` | `true` / `false`: la copia automática puede usar datos móviles | `false` |
  | `drive_sync_account`, `drive_sync_local_stamp`, `drive_sync_upload_id`, `drive_sync_at`, `drive_sync_direction` | El último punto en común con la copia de Drive (cuenta, sello local o `none`, `upload_id`, instante, `upload` / `download`); incompleto = no hay | sin punto en común |

  Los valores también son códigos fijos. Un valor desconocido (por ejemplo,
  escrito por una versión más nueva de la app) se lee como `system`.
- La tabla viaja dentro del paquete de copia como el resto de la base de
  datos: al importar un paquete llegan también su idioma y su tema, y la app
  cambia en ese mismo momento, sin reiniciar. Cada clave tiene un **ámbito**
  (`SettingScope`): las compartidas (`last_export_at`, `language`, `theme`)
  llegan con el paquete; las del teléfono (`drive_account`,
  `drive_device_id`, `drive_mobile_data`) se conservan; las del punto en
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
