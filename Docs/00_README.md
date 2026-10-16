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
formularios, borrar con confirmación y Deshacer). Lo siguiente es el paso 4.

Hoja de ruta hasta la primera versión usable:

| Paso | Contenido |
| --- | --- |
| 3 | ~~Pantallas de vehículos **y propietarios** (Riverpod + `go_router`) — un vehículo requiere un propietario~~ — hecho |
| 4 | Entradas básicas del historial: fecha, km, tipo, coste, notas; lista, filtros, deshacer al borrar |
| 5 | Cuentakilómetros: actualizar el km actual + historial `MileageReading` con sus reglas |
| 6 | Exportar / importar el archivo de la base de datos, y una clave fija de firma de release guardada fuera del repositorio |

Después, en el orden que se decida usando la app: ajustes, mantenimiento,
repostajes, documentos, fotos, recordatorios, informes PDF, copia de
seguridad en Google Drive.

Por qué importa la clave de firma: cada PC tiene su propia clave de debug, así
que instalar desde otro PC obliga a desinstalar la app, y eso borra los datos.
