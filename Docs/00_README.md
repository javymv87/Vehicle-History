# Documentación — App de gestión del historial de vehículos

Documento general de concepto, redactado **antes** de escribir código. Es la
fuente de verdad compartida. La documentación está en **español**; el código
estará en **inglés** y la interfaz se traduce a IT / ES / EN (ver
`../CLAUDE.md`).

## Índice

1. [`01_concept_overview.md`](01_concept_overview.md) — Visión general, a quién
   sirve, principio guía, límites de la versión 1, secciones de la app.
2. [`02_data_model.md`](02_data_model.md) — Tablas de la base de datos local,
   campos, relaciones, campos técnicos para la sincronización y el historial de
   operaciones.
3. [`03_features.md`](03_features.md) — Historial, filtros,
   recordatorios/notificaciones, informes, gastos en el mantenimiento, reglas UX
   de los mensajes, fotos.
4. [`04_maintenance_logic.md`](04_maintenance_logic.md) — Catálogo de tipos,
   criterios por vehículo, vencimientos por km/tiempo, frenos por eje, control
   frente a sustitución, controles con medición, repostajes/consumos, historial
   de kilometraje.
5. [`05_sync_and_storage.md`](05_sync_and_storage.md) — Almacenamiento local y
   copia de seguridad en Google Drive (Strada A con control de versión),
   preparación para el futuro.
6. [`06_settings_and_i18n.md`](06_settings_and_i18n.md) — Ajustes e idiomas
   IT/ES/EN.
7. [`07_design_and_theming.md`](07_design_and_theming.md) — Sistema de diseño
   Material 3, temas claro/oscuro, principios de legibilidad y color.

## Resumen en una frase

App móvil monousuario (Flutter, primero Android, iOS posible más adelante) para
llevar el historial completo de uno o varios vehículos — mantenimientos,
repostajes, gastos, controles, vencimientos y documentos — sin conexión, con
copia de seguridad manual en Google Drive e informes exportables a PDF.

## Estado

Concepto completo y proyecto Flutter configurado: la estructura de carpetas, las
reglas de lint, la CI y esta documentación ya están en el repositorio. El tema
Material 3 (semilla única, claro/oscuro, colores de estado) y el esqueleto de
localización con `gen_l10n` (IT / ES / EN) ya están hechos, igual que la capa
de datos Drift para propietarios y vehículos (con el historial de operaciones,
migraciones de esquema desde la v1 y repositorios) y las pantallas de
vehículos y propietarios (Riverpod + `go_router`: listas, fichas,
formularios, borrar con confirmación y Deshacer). El paso 3b añadió el tipo
de vehículo (coche, furgoneta, moto, ciclomotor), el catálogo de marcas y
modelos, el año, la versión y el selector de nacionalidad, con la primera
migración real del esquema (v1 → v2). El paso 4 añadió el historial de
cada vehículo (esquema v3): el vehículo se abre en su historial, con
creación rápida de entradas, agrupación por mes, detalle, edición, borrado
con Deshacer y filtros por fechas, tipo y texto. El paso 5 añadió el
cuentakilómetros (esquema v4): pestaña Kilometraje con las lecturas, lectura
inicial por vehículo, "Actualizar km", borrar la última con Deshacer, la
oferta de actualizar desde las entradas y las fechas futuras según el tipo.
El paso 5b añadió la papelera (esquema v5): `deleted_at` en las tablas, el
diálogo de borrado con lo que se va con el vehículo, la pantalla Papelera
(restaurar, eliminar definitivamente, vaciar) y la limpieza automática a los
30 días al arrancar. El paso 6 añadió el paquete de copia (exportar e
importar todos los datos como un `.zip`, con validación, rechazo de los
esquemas más recientes, migración de los anteriores y una copia de seguridad
que se restaura si la importación falla), la tabla `settings` (esquema v6),
la pantalla Copia de seguridad y una clave fija de firma para debug y
release. El paso 7 añadió la pantalla Ajustes: idioma (Sistema, Italiano,
Español, English) y tema (Sistema, Claro, Oscuro), que se aplican al
momento y viajan dentro del paquete de copia. El paso 8 añadió los
adjuntos (esquema v7): fotos y documentos de las entradas, los vehículos
(pestaña Documentos) y los propietarios, desde la cámara, la galería o un
archivo, con visor, "Guardar en…" y su borrado físico con la papelera; el
paquete de copia lleva ahora todos los archivos, se exporta en streaming
con un "guardar como" nativo y la importación restaura también la carpeta
de adjuntos si algo falla. El paso 9 añadió la copia en Google Drive:
vincular la cuenta del teléfono, Subir a Drive y Restaurar desde Drive (por
la misma importación con su red de seguridad), las 3 últimas copias en una
carpeta visible, el control de versión con su línea de estado (y un banner
en la pantalla principal cuando otro teléfono subió una copia más reciente)
y una única acción automática: subir al arrancar cuando solo ha cambiado
este teléfono. El paso 9b añadió la segunda forma de vincular la cuenta:
iniciar sesión en el navegador (OAuth + PKCE) con una cuenta que no se
añade al teléfono. El refresh token se guarda solo en el almacén seguro, y
al desvincular se revoca en Google. El paso 10 añadió el archivo de
vehículos (esquema v8): archivar un vehículo vendido, desguazado, robado…
con motivo, fecha, km finales (que se guardan como una lectura normal del
cuentakilómetros) y nota; sale de la lista principal a una fila
"Archivados (n)", se ve entero en solo lectura con un banner y se reactiva
cuando se quiera; independiente de la papelera. Lo siguiente es el paso 11
(recordatorios), que se construye sabiendo qué vehículos están archivados.

Hoja de ruta hasta la primera versión usable:

| Paso | Contenido |
| --- | --- |
| 3 | ~~Pantallas de vehículos **y propietarios** (Riverpod + `go_router`) — un vehículo requiere un propietario~~ — hecho |
| 3b | ~~Tipo de vehículo, catálogo de marcas / modelos, año, versión, selector de nacionalidad (esquema v2)~~ — hecho |
| 4 | ~~Entradas básicas del historial: fecha, km, tipo, coste, notas; lista, filtros, deshacer al borrar (esquema v3)~~ — hecho |
| 5 | ~~Cuentakilómetros: actualizar el km actual + historial `MileageReading` con sus reglas (esquema v4)~~ — hecho |
| 5b | ~~Papelera: vehículos borrados, restaurar, borrado definitivo, limpieza a los 30 días (esquema v5)~~ — hecho |
| 6 | ~~Exportar / importar como paquete, tabla `settings` (esquema v6), clave fija de firma para debug y release~~ — hecho |
| 7 | ~~Pantalla de ajustes: idioma y tema dentro de la app~~ — hecho |
| 8 | ~~Adjuntos (entradas, vehículos, propietarios), paquete de copia con los archivos (esquema v7)~~ — hecho |
| 9 | ~~Copia de seguridad en Google Drive con control de versión al arrancar~~ — hecho |
| 9b | ~~Vincular una cuenta manualmente (navegador, OAuth + PKCE, token en el almacén seguro)~~ — hecho |
| 10 | ~~Archivo de vehículos: motivo, fecha, km finales como lectura, solo lectura, reactivar (esquema v8)~~ — hecho |
| 11 | Recordatorios y notificaciones (excluyendo los vehículos archivados) |

Después, en el orden que se decida usando la app: mantenimiento, repostajes,
documentos, informes PDF.

Por qué importa la clave de firma: cada PC tiene su propia clave de debug, así
que instalar desde otro PC obliga a desinstalar la app, y eso borra los datos.
