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
