# 02 — Modelo de datos

Este documento describe las tablas de la base de datos **local** (SQLite a
través de Drift, en el teléfono) y sus relaciones. La copia de seguridad en
Google Drive es un plano separado, tratado en `05_sync_and_storage.md`: no hay
que confundir el esquema local con el archivo de copia de seguridad.

Todos los nombres de tabla y campo aquí están en español por claridad
conceptual. En el **código** los nombres reales estarán en inglés (ver
`CLAUDE.md`); junto a cada tabla indico el nombre en inglés sugerido.

## Campos técnicos comunes a (casi) todas las tablas

Para hacer posible la sincronización y el historial de operaciones, cada
registro principal lleva consigo:

- `id` — identificador único (UUID, no un simple número incremental, para
  evitar colisiones entre dispositivos distintos).
- `created_at` — fecha/hora de creación.
- `updated_at` — fecha/hora de la última modificación.
- `deleted` — indicador de **borrado lógico**. Una entrada borrada no se
  destruye de inmediato: se marca como borrada. Sirve para poder recuperar
  errores y para que la copia de seguridad sepa que el elemento se eliminó a
  propósito.

## Moneda e importes

Todos los importes están en **euros**. La moneda es fija: no existe un campo
de moneda en el esquema y no es configurable por el usuario. La app está
pensada para uso personal en la zona euro, y admitir varias monedas requeriría
también los tipos de cambio históricos para que los informes tuvieran sentido
— una complejidad que no compensa el beneficio.

El *formato*, en cualquier caso, sigue el idioma elegido (ver doc 06): el mismo
importe aparece como `1.234,56 €` en italiano y español y como `€1,234.56` en
inglés.

## Tablas

### Owner (propietario)

Ficha de la persona propietaria de uno o varios vehículos.

- Nombre (**obligatorio**), apellidos
- Fecha de nacimiento (fecha de calendario, sin hora ni zona horaria)
- Nacionalidad (texto libre)
- Foto
- Contactos: teléfono, email
- Notas libres

Todo es opcional salvo el nombre. Teléfono y email se guardan tal como se
escriben (sin espacios al principio ni al final), sin validar el formato.
La foto es una ruta opcional **relativa** a la carpeta de documentos de la app
(elegir, copiar y mostrar imágenes llegará más adelante).

Un Owner puede tener **varios vehículos**. Un vehículo tiene **un** Owner.

**Borrar un Owner** no se permite mientras tenga vehículos no borrados: la app
lo rechaza y no escribe nada. Primero hay que borrar o reasignar sus vehículos.

### OwnerDocument (documento del propietario)

Documentos personales vinculados a un Owner. Cada uno es un archivo
(foto/escaneo) con sus datos y su vencimiento, de modo que puede generar
recordatorios.

- Tipo: permiso de conducir, documento de identidad, permiso de residencia,
  otro
- Número de documento
- Fecha de expedición
- Fecha de vencimiento
- Categorías (para el permiso de conducir: B, A, C, etc.)
- Archivo/foto
- Notas

Un Owner puede tener varios OwnerDocument.

### Vehicle (vehículo)

El vehículo. Es la entidad central: casi todo lo demás está vinculado a ella.

- Matrícula (identificador principal, **obligatoria**)
- Nombre común (opcional)
- Foto de perfil (opcional, ruta relativa como la del Owner)
- Referencia al Owner (**obligatoria**: todo vehículo tiene exactamente uno)
- **Km actual** (el último valor conocido del cuentakilómetros total)
- Especificaciones de fábrica: tipo de combustible, aceite de motor
  recomendado, y cualquier nota útil del fabricante (ver
  `04_maintenance_logic.md`)

Reglas:

- **Matrícula**: se guarda sin espacios al principio ni al final y en
  mayúsculas. Es **única entre los vehículos no borrados**: la matrícula de un
  vehículo borrado se puede volver a usar.
- **Km actual**: obligatorio al crear el vehículo, número entero, nunca
  negativo. **No se modifica desde el formulario del vehículo**: cambiarlo
  corresponde a la futura función de kilometraje, con las reglas de
  `MileageReading` (ver `04_maintenance_logic.md`).
- **Tipo de combustible**: obligatorio, uno de: gasolina, diésel,
  gasolina + GLP, gasolina + GNC (metano), híbrido, híbrido enchufable,
  eléctrico, otro. Los bifuel GLP / GNC son comunes en Italia.
- Aceite de motor recomendado y notas del fabricante: texto libre opcional.

### LogEntry (entrada del historial) — núcleo de la app

La "entrada base", igual para todo tipo de evento. Cada fila del historial es
una LogEntry. Los campos extra específicos de algunos tipos están en tablas
vinculadas (EntryImage, Measurement) o en campos opcionales, para que esta
tabla se mantenga limpia.

Campos siempre presentes:

- Referencia al Vehicle
- **Fecha**
- **Km** (kilometraje en el momento del evento; obligatorio donde tiene
  sentido, omitido donde no lo tiene — p. ej. pago del impuesto de
  circulación). **Nota importante:** este km se queda *dentro de la entrada* y
  NO alimenta el historial de kilometraje (`MileageReading`). Los dos
  registros son independientes.
- **Tipo** de entrada (ver lista abajo)
- **Texto** / descripción libre
- **Coste** total (opcional), en euros
- **Recordatorio** opcional (fecha futura + eventual umbral de km) que genera
  una notificación

Tipos de entrada previstos:

- Mantenimiento ordinario
- Reparación / extraordinario
- Vencimiento legal (impuesto de circulación, inspección técnica obligatoria,
  seguro)
- Repostaje (campos extra: litros, precio/litro, km recorridos — ver doc 04)
- Gasto genérico (peajes, lavado, accesorios...)
- Control con medición (campos extra en Measurement)
- Control genérico no clasificado (nota libre)
- Nota / evento (accidentes, multas, recordatorios libres)

### EntryImage (imagen de una entrada)

Las fotos adjuntas a una LogEntry. Una entrada puede tener **varias** imágenes.

- Referencia a la LogEntry
- Archivo de imagen
- Pie de foto opcional

### Measurement (control con medición)

Campo extra para las entradas de tipo "control con medición". Registra un valor
numérico inspeccionado, alimentando el historial de valores a lo largo del
tiempo.

- Referencia a la LogEntry
- Magnitud medida (p. ej. dibujo del neumático, grosor de las pastillas,
  tensión de la batería)
- Valor numérico
- Unidad de medida (mm, V, ...)
- **Umbral de alarma** opcional: si el valor baja del umbral, la app avisa.

### Document (documento del vehículo)

Documentos del vehículo que representan un **estado actual**, distintos de los
eventos del historial.

- Referencia al Vehicle
- Tipo: permiso de circulación, seguro en vigor, otro
- Archivo/foto
- Fecha de vencimiento (opcional, para los recordatorios)
- Notas

### MaintenanceType (catálogo de tipos de mantenimiento)

Catálogo **común** y modificable de los tipos de mantenimiento disponibles,
agrupados por familia. Se comparte entre todos los vehículos.

- Nombre (p. ej. "Aceite de motor", "Frenos delanteros", "Rotación de
  neumáticos")
- Grupo/familia: Fluidos, Filtros, Neumáticos, Batería, Motor, Frenos, Otro
- Naturaleza de la intervención: control / sustitución (puede valer ambas)
- Precargado por el sistema o creado por el usuario

### MaintenanceRule (criterio de mantenimiento por vehículo)

El criterio de mantenimiento **configurado para un vehículo concreto**,
tomando un tipo del catálogo y asignándole los intervalos de ese vehículo.
Un tipo ya asignado a un vehículo no vuelve a aparecer entre las opciones para
el mismo vehículo (pero sigue disponible para los demás).

- Referencia al Vehicle
- Referencia al MaintenanceType
- **Vencimiento en km** (opcional)
- **Vencimiento en tiempo** (opcional, en meses)
- Regla "vence el primero de los dos" cuando están presentes ambos
- Última intervención conocida (fecha + km) para calcular el próximo
  vencimiento
- Notas

**Caso frenos** (ver detalle en `04_maintenance_logic.md`): para los tipos
"Frenos delanteros" / "Frenos traseros" la regla lleva consigo el tipo de
sistema (disco+pastillas o tambor+zapatas) y **dos subvencimientos
independientes**: el elemento que se desgasta (pastilla/zapata) y el elemento
que lo contiene (disco/tambor), cada uno con su propio vencimiento en km y/o
tiempo. Esto se modela como estructura interna de la regla, no como una tabla
nueva.

### MileageReading (historial de kilometraje)

Registro **independiente** de las lecturas del cuentakilómetros total a lo
largo del tiempo. Sirve para el informe "km recorridos frente a tiempo".

- Referencia al Vehicle
- Fecha
- Km (valor del cuentakilómetros total)

Reglas lógicas (detalle en `04_maintenance_logic.md`):

- Una nueva lectura **no puede ser inferior** a la última válida.
- Un valor enormemente más alto (probable error tipográfico) pide
  confirmación, no se prohíbe.
- Solo se puede borrar **la última** lectura; después la penúltima pasa a ser
  la última y a su vez se puede borrar (comportamiento "deshacer hacia
  atrás"). Nunca borrar lecturas en medio de la serie.
- Se actualiza **solo** cuando el usuario actualiza el cuentakilómetros total
  de forma explícita. El km escrito en cada entrada NO entra aquí.

### AuditLog (historial de operaciones)

Registro ligero de todas las operaciones realizadas sobre las entradas,
consultable y útil también en el futuro. Existe **desde la primera versión
del esquema**: cada creación, modificación y borrado de un Owner o un Vehicle
añade su fila en la misma transacción. Es solo de añadir: sus filas no se
modifican ni se borran.

- Qué: referencia a la entidad (qué entrada/vehículo)
- Operación: creación / modificación / eliminación
- Cuándo: fecha y hora

### Settings (ajustes)

Configuración de la app, no vinculada a un vehículo.

- Idioma (IT / ES / EN)
- Tema (Sistema / Claro / Oscuro)
- Configuración de la nube / Google Drive (cuenta, activo sí/no)
- Metadatos de la copia de seguridad: **número de versión** de la base de datos
  y **fecha de la última modificación**, usados para el control de versión al
  abrir la app (ver `05_sync_and_storage.md`).

## Resumen de relaciones

- Owner 1 — N Vehicle
- Owner 1 — N OwnerDocument
- Vehicle 1 — N LogEntry
- Vehicle 1 — N Document
- Vehicle 1 — N MaintenanceRule
- Vehicle 1 — N MileageReading
- LogEntry 1 — N EntryImage
- LogEntry 1 — 1 Measurement (solo para el tipo "control con medición")
- MaintenanceType 1 — N MaintenanceRule (el catálogo alimenta las reglas)
- AuditLog y Settings son transversales / globales
