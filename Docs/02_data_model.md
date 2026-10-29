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
- `deleted_at` — **cuándo** se borró (instante en UTC, texto ISO-8601);
  vacío (`NULL`) mientras el registro está vivo. Existe desde el esquema v5
  en `owners`, `vehicles`, `log_entries` y `mileage_readings`. Se escribe
  siempre junto con `deleted` y se vacía junto con él al restaurar.

### Borrado lógico, papelera y borrado físico (esquema v5)

- **Borrar** es siempre lógico: `deleted = 1` y `deleted_at = ahora`.
  **Restaurar** (Deshacer, o "Restaurar" desde la papelera) pone
  `deleted = 0` y `deleted_at = NULL`.
- La migración v4 → v5 añadió `deleted_at` y lo rellenó con `updated_at` en
  las filas ya borradas: hasta la v4 cada borrado escribía su instante en
  `updated_at`, y una fila borrada no se puede modificar. Las filas vivas
  quedaron con `NULL`. No cambió nada más.
- **Papelera:** solo para **vehículos**. Un vehículo borrado está en la
  papelera durante **30 días** y se lleva consigo sus entradas y lecturas
  (no se marcan como borradas: simplemente no se ven, como antes). Las
  entradas, las lecturas y los propietarios sueltos no tienen papelera: solo
  el Deshacer de unos segundos.
- **Borrado físico** (`DELETE` real, irreversible) solo en estos casos:
  1. "Eliminar definitivamente" un vehículo o "Vaciar papelera": se borran
     el vehículo y **todas** sus entradas y lecturas, sea cual sea su propio
     indicador, en una sola transacción (primero entradas y lecturas, porque
     las claves externas son `RESTRICT`).
  2. La **limpieza al arrancar la app**, una vez abierta y migrada la base
     de datos, en una sola transacción: los vehículos borrados hace 30 días o
     más (como en el punto 1); las entradas y lecturas borradas hace 30 días
     o más de vehículos vivos; y los propietarios borrados hace 30 días o más
     a los que ya no apunta **ningún** vehículo (vivo o borrado). Si algo
     falla, se deshace todo, se anota en el registro y la app arranca igual.
- El historial de operaciones guarda una fila `purge` por cada elemento
  borrado físicamente por sí mismo: cada vehículo y cada propietario, y,
  desde la 0.8.1, cada entrada, lectura y adjunto que la limpieza de los 30
  días elimina sueltos. Lo que se va **con** su padre (las entradas y
  lecturas de un vehículo, los adjuntos de un vehículo, entrada o
  propietario eliminados) no tiene fila propia: la del padre lo cubre. Así
  la fecha de última modificación de los datos (`last_modified_at`, ver
  `05_sync_and_storage.md`) nunca retrocede. Las filas anteriores del
  historial que apuntan a lo borrado se quedan (no hay clave externa).
- **Adjuntos (desde el esquema v7):** se van con lo que borra el punto 1 (los
  del vehículo y los de sus entradas, sea cual sea su indicador) y con los
  propietarios y las entradas que borra la limpieza; además la limpieza borra
  los adjuntos borrados hace 30 días o más que no viajan con un vehículo de
  la papelera. Con la fila se borra su archivo (ver "Attachment").

### Archivo de vehículos (esquema v8)

Un vehículo que ya no es del usuario o ya no se usa (vendido, desguazado,
robado…) se **archiva**: conserva todo su historial (entradas, lecturas,
adjuntos, estado de papelera) y sale de la lista principal. El archivo
**no es la papelera**: la papelera es un error, se vacía a los 30 días; el
archivo es un final, se conserva para siempre y es de **solo lectura**
hasta que se reactiva. Los dos estados son independientes.

- Cuatro columnas en `vehicles`, todas vacías (`NULL`) mientras el vehículo
  está activo: `archived_at` (**fecha de calendario** `yyyy-MM-dd`, como la
  de las lecturas: el día que se eligió, nunca un instante), `archive_reason`
  (código fijo: `none`, `sold`, `scrapped`, `stolen`, `destroyed`,
  `given_away`, `lease_ended`, `other`; nunca texto libre, "otro" + nota es
  la salida), `archive_note` (texto opcional) y `archived_km` (número en
  km, opcional, ≥ 0; `REAL` desde la v9). La migración v7 → v8 solo añade
  las columnas.
- **Km finales = lectura del cuentakilómetros.** Si al archivar se indica un
  km (el diálogo lo rellena con la última lectura), el archivo inserta una
  lectura normal con ese valor y la fecha de archivo, **por el mismo camino
  y con las mismas reglas** que "Actualizar km" (ni por debajo de la última
  lectura, ni antes de su día, ni después de hoy); si la lectura se rechaza,
  no se archiva nada. Igual a la última lectura también vale: marca el
  cierre. `archived_km` guarda el mismo valor como resumen para el banner y
  el chip. Sin km, no hay lectura.
- **Activo = vivo y no archivado.** Es el único filtro de los vehículos
  "actuales" (lista principal, y los recordatorios del paso 11); la ficha
  del propietario muestra también los archivados, en una sección plegable.
- **Solo lectura:** mientras está archivado, los repositorios rechazan
  cualquier escritura sobre el vehículo, sus entradas, sus lecturas y sus
  adjuntos (`VehicleArchivedException`); solo quedan **reactivar**, **mover a
  la papelera** y **restaurar**. Importar, restaurar desde Drive, eliminar
  definitivamente y la limpieza de los 30 días no pasan por esa puerta.
- **Reactivar** vacía las cuatro columnas y no toca ninguna lectura, tampoco
  la creada al archivar.
- **Papelera:** un vehículo archivado se puede mover a la papelera como
  cualquier otro; allí no aparece en la lista de archivados. Al restaurarlo
  vuelve a Archivados si tenía `archived_at`, a la lista principal si no.
- Historial de operaciones: `archive` y `reactivate` sobre el vehículo; la
  lectura del archivo tiene su propio `create`.
- La copia de seguridad, Drive y la importación llevan las columnas como
  cualquier otra del vehículo, sin trato especial; una copia v7 importa con
  todos los vehículos activos.

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
- Nacionalidad: se elige de la lista de países (ISO 3166-1) o se escribe a
  mano con "Otra…" (ver `03_features.md`)
- Foto
- Contactos: teléfono, email
- Notas libres

Todo es opcional salvo el nombre. La nacionalidad elegida de la lista se
guarda como **código ISO 3166-1 alfa-2** (`IT`, `CU`, …); la escrita a mano,
**tal como se escribe**. Se muestra con el nombre del país en el idioma de la
app cuando el valor es un código conocido, y tal cual en cualquier otro caso
(así siguen siendo legibles los valores de texto libre guardados antes de la
lista). Los nombres de los países vienen de Unicode CLDR, incluidos en la app.
Teléfono y email se guardan tal como se
escriben (sin espacios al principio ni al final), sin validar el formato.
La foto es una ruta opcional **relativa** a la carpeta de soporte de la app
(*application support*, la misma en la que vive la base de datos; ver
`05_sync_and_storage.md`). La foto de perfil todavía no se elige; los
documentos del propietario ya se pueden adjuntar (ver "Attachment").

Un Owner puede tener **varios vehículos**. Un vehículo tiene **un** Owner.

**Borrar un Owner** no se permite mientras tenga vehículos no borrados: la app
lo rechaza y no escribe nada. Primero hay que borrar o reasignar sus vehículos.
Tampoco se permite mientras tenga vehículos **en la papelera** (desde el
esquema v5): restaurarlos necesitaría al propietario. El mensaje lo dice
("Tiene vehículos en la papelera: restáuralos o vacía la papelera").

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

- **Tipo de vehículo** (**obligatorio**): coche, furgoneta, moto o ciclomotor
- **Marca** y **modelo** (**obligatorios** en el formulario; ver las reglas)
- Año del modelo (opcional)
- Versión / acabado (opcional, texto libre: motorización y acabado, p. ej.
  "1.2 69 CV Lounge")
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
- **Km actual**: obligatorio al crear el vehículo, número entero en la
  unidad elegida (ver `06_settings_and_i18n.md`, "Unidades de medida"),
  guardado en km, nunca negativo. **No se modifica desde el formulario del
  vehículo**: cambia solo
  con las lecturas del cuentakilómetros (`MileageReading`, ver abajo y
  `04_maintenance_logic.md`). Es una copia de trabajo: siempre igual a los km
  de la última lectura válida. Al crear el vehículo, el km escrito se guarda
  también como su **lectura inicial**, con la fecha de hoy.
- **Tipo de combustible**: obligatorio, uno de: gasolina, diésel,
  gasolina + GLP, gasolina + GNC (metano), híbrido, híbrido enchufable,
  eléctrico, otro. Los bifuel GLP / GNC son comunes en Italia.
- Aceite de motor recomendado y notas del fabricante: texto libre opcional.
- **Tipo de vehículo**: uno de coche, furgoneta, moto, ciclomotor (camiones y
  autobuses quedan fuera). Decide qué marcas y modelos ofrece el catálogo y,
  en el futuro, qué tipos de mantenimiento aplican (ver
  `04_maintenance_logic.md`). Los vehículos creados antes de existir este
  campo son coches.
- **Marca y modelo**: se guardan siempre como **nombre mostrado** (p. ej.
  "Fiat", "Punto") más un **identificador de catálogo opcional** (el *slug*
  de VehiclesDB, p. ej. `fiat`, `punto`), vacío cuando el valor se escribió a
  mano. El nombre guardado es lo que se muestra: si un catálogo futuro
  renombra una marca, lo que el usuario vio no cambia; el identificador solo
  sirve para emparejar con el catálogo. En la base de datos son opcionales,
  porque los vehículos creados antes no los tienen; el formulario los pide al
  crear **y** al editar.
- **Año del modelo**: número entero entre 1886 y 2100 en la base de datos; el
  formulario acepta como máximo el año siguiente al actual.
- **Nombre común**: opcional; en el formulario va al final.

### LogEntry (entrada del historial) — núcleo de la app

La "entrada base", igual para todo tipo de evento. Cada fila del historial es
una LogEntry. Los campos extra específicos de algunos tipos están en tablas
vinculadas (Attachment, Measurement) o en campos opcionales, para que esta
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

**Lo que existe hoy (esquema v3).** La tabla `log_entries` guarda los campos
técnicos comunes (`id`, `created_at`, `updated_at`, `deleted`), la referencia
al vehículo (`vehicle_id`, clave externa a `vehicles` con `ON DELETE
RESTRICT`), la **fecha** (fecha de calendario, texto `yyyy-MM-dd`, sin hora ni
zona horaria), los **km** (número en km, opcional, nunca negativo; `REAL`
desde la v9), el **tipo**
(texto con código estable), la **descripción** (texto, opcional) y el
**coste** (entero en **céntimos de euro**, opcional, nunca negativo). Un coste
vacío es distinto de un coste 0. Índices: `(vehicle_id, entry_date)` y
`(vehicle_id, type)`, para la lista y los filtros.

- **Tipos y sus códigos:** mantenimiento (`maintenance`), reparación
  (`repair`), vencimiento legal (`legalDue`), repostaje (`refuel`), gasto
  (`expense`), control con medición (`measuredCheck`), control genérico
  (`genericCheck`) y nota (`note`). El control con medición existe en el
  esquema pero **el formulario todavía no lo ofrece**: sin su medición sería
  un control genérico. Llegará con el paso de las mediciones.
- **Fechas futuras según el tipo:** solo el vencimiento legal, el gasto y la
  nota pueden tener una fecha posterior a hoy (algo que se planifica). El
  mantenimiento, la reparación, el repostaje y los controles se registran
  cuando ya han ocurrido: su fecha es hoy o anterior. Lo aplican el
  formulario y el repositorio; las filas que ya existían no se tocan.
- **Km obligatorio según el tipo:** obligatorio para mantenimiento,
  reparación, repostaje y control genérico (y el control con medición);
  opcional para vencimiento legal, gasto y nota. La regla la aplica el
  formulario y también el repositorio. Este km **nunca** alimenta
  `MileageReading` ni cambia el km actual del vehículo por sí solo: el único
  puente es la oferta explícita "¿Actualizar el cuentakilómetros?" después de
  guardar (ver `03_features.md`, E3).
- **Sin recordatorio todavía:** los campos del recordatorio se añadirán con su
  propia migración en el paso de los recordatorios. Guardar un recordatorio
  que nunca avisa engañaría al usuario.
- **Vehículo borrado:** sus entradas se quedan tal cual (no se borran en
  cascada) y simplemente no se ven, porque el vehículo ya no es accesible.
  Restaurar el vehículo las hace visibles de nuevo.
- **Deshacer el borrado de una entrada** la restaura; si mientras tanto se ha
  borrado su vehículo, el deshacer se rechaza con un mensaje y no cambia
  nada.
- Los campos extra del repostaje (litros, precio/litro), las partidas de
  gasto y las mediciones llegarán en pasos posteriores. Las fotos y los
  documentos de una entrada son **adjuntos** (ver "Attachment").

### Attachment (adjunto) — esquema v7

Sustituye a la antigua `EntryImage`. Un archivo (foto, PDF u otro) adjunto a
una **entrada** del historial, a un **vehículo** (sus documentos: permiso de
circulación, póliza, inspección…) o a un **propietario** (permiso de
conducir, documento de identidad…). Una entidad puede tener **varios**.

Tabla `attachments`: los campos técnicos comunes (`id`, `created_at`,
`updated_at`, `deleted`, `deleted_at`) y:

- `entity_type`: `logEntry`, `vehicle` u `owner` (los mismos códigos que el
  historial de operaciones) y `entity_id`. **Sin clave externa** (la tabla es
  polimórfica): el repositorio comprueba que la entidad existe y no está
  borrada (una entrada, además, de un vehículo no borrado).
- `kind`: `image`, `pdf` u `other`, según el tipo MIME o, si no lo hay, la
  extensión.
- `file_name`: el nombre original, el que ve el usuario y el que usan
  "Guardar en…" y "Compartir". Las fotos de la cámara y de la galería no
  tienen un nombre útil (el selector las llama `scaled_<uuid>….jpg`): se
  guardan como `IMG_aaaammdd_hhmmss.jpg`, con la hora local del momento de
  añadirlas, como la cámara de Android, y `_2`, `_3`… para las siguientes
  fotos elegidas a la vez. Los archivos del selector de archivos conservan
  su nombre.
- `mime_type`, `relative_path` (`attachments/<id>.<ext>`), `size_bytes`
  (`CHECK >= 0`).
- `caption`: descripción opcional, editable desde el visor o la lista.
- `sort_order`: orden entre los adjuntos de la misma entidad (los nuevos van
  al final).
- Índice `(entity_type, entity_id)`.

La migración v6 → v7 solo crea la tabla y el índice: no toca nada más.

**Archivos.** Cada fila tiene **un** archivo en
`<carpeta de soporte de la app>/attachments/`, con el id del adjunto y la
extensión del nombre original (en minúsculas; `bin` si es rara). Nunca en la
galería ni en el almacenamiento público.

- **Límite:** 25 MB por archivo; uno más grande se rechaza con un mensaje.
  Las fotos de la cámara y de la galería se reducen en el teléfono a 2000 ×
  2000 px como máximo y calidad JPEG 85 (`image_picker`); los archivos
  elegidos con el selector de archivos se guardan tal cual.
- **Borrar** un adjunto es lógico (con Deshacer): el archivo se queda.
  Varios adjuntos seleccionados se borran juntos en una sola transacción
  (una fila del historial de operaciones por adjunto) y un único Deshacer
  los restaura todos; si uno no se puede, no se toca ninguno.
- **Copias de los selectores:** la cámara, la galería y el selector de
  archivos dejan su propia copia en la caché de la app. En cuanto la app
  tiene la suya (o rechaza el archivo), esa copia se borra; al arrancar, antes
  de abrir la base de datos, se vacía la caché entera (también las copias
  hechas para "Compartir"), de modo que ninguna copia de una foto sobrevive
  a la sesión que la eligió.
- **Entidad borrada:** los adjuntos de un vehículo en la papelera (los suyos
  y los de sus entradas), de una entrada borrada o de un propietario borrado
  se quedan tal cual y se ocultan con ella.
- **Borrado físico** (fila y archivo), solo en tres casos: la **limpieza a
  los 30 días** (adjuntos borrados hace 30 días o más, y los de las entradas
  y propietarios que borra), **eliminar definitivamente un vehículo / vaciar
  la papelera** (todos los adjuntos del vehículo y de sus entradas, sea cual
  sea su indicador) y el **barrido al arrancar**: los archivos de
  `attachments/` que ninguna fila nombra se borran. Una fila cuyo archivo
  falta **se conserva** y se muestra con "Archivo no encontrado". Los
  archivos se borran después de confirmar la transacción; si uno no se puede
  borrar, lo recoge el barrido del siguiente arranque.
- **Staging:** el formulario de la entrada copia los archivos elegidos a
  `attachments_tmp/<sesión del formulario>/`. Al guardar, los archivos se
  mueven a `attachments/` y las filas se insertan junto con la entrada en una
  sola transacción; si la transacción falla, los archivos ya movidos se
  borran. Al cancelar el formulario se borra su carpeta, y al arrancar la app
  se vacía `attachments_tmp/` entera.
- **Historial de operaciones:** entidad `attachment`, con creación,
  modificación (descripción, orden), borrado y restauración.

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

**Lo que existe hoy (esquema v4).** La tabla `mileage_readings` guarda los
campos técnicos comunes (`id`, `created_at`, `updated_at`, `deleted`), la
referencia al vehículo (`vehicle_id`, clave externa a `vehicles` con `ON
DELETE RESTRICT`), la **fecha** (`reading_date`, fecha de calendario, texto
`yyyy-MM-dd`) y los **km** (número en km, nunca negativo). No hay campo de
nota. Índice: `(vehicle_id, reading_date)`.

**Esquema v9: distancias con decimales.** Las cuatro columnas de distancia
(`mileage_readings.km`, `log_entries.km`, `vehicles.current_odometer_km` y
`vehicles.archived_km`) pasaron de `INTEGER` a `REAL` en el paso 11
(unidades de medida), para guardar como km exactos un valor escrito en
millas (100 mi = 160,9344 km) y devolverlo tal cual. La migración v8 → v9
recrea las tres tablas copiando cada fila como está: 85000 pasa a 85000.0 y
sigue siendo km; ningún valor cambia. La base de datos sigue sin conocer
unidades: siempre km (ver `06_settings_and_i18n.md`).

- **Lectura inicial:** todo vehículo tiene siempre al menos una lectura
  válida. Al crear un vehículo se guarda en la misma transacción (hoy, con el
  km escrito). Para los vehículos que ya existían, la migración v3 → v4 creó
  una por vehículo — **también para los borrados**, para que una
  restauración futura sea coherente — con su km actual y la fecha del día en
  que se creó el vehículo. La lectura inicial es la más antigua; no hay
  columna que la marque.
- **Última lectura:** la lectura válida con la fecha más reciente y, en el
  mismo día, la creada más tarde.
- **Km actual como copia:** `vehicles.current_odometer_km` se mantiene y es
  siempre igual a los km de la última lectura válida. Cada escritura de
  lecturas (crear, borrar, deshacer, corregir) lo actualiza en la misma
  transacción.
- **Vehículo borrado:** sus lecturas se quedan tal cual y no se ven (sin
  borrado en cascada).
- **Historial de operaciones:** tipo de entidad `mileageReading`, con
  creación, modificación, borrado y restauración. Las lecturas creadas por
  la migración no tienen fila en el historial: no las escribió el usuario.

### AuditLog (historial de operaciones)

Registro ligero de todas las operaciones realizadas sobre las entradas,
consultable y útil también en el futuro. Existe **desde la primera versión
del esquema**: cada creación, modificación, borrado y restauración (deshacer
un borrado) de un Owner, un Vehicle, una LogEntry, una MileageReading o un
Attachment (desde la v7)
añade su fila en la misma transacción. El tipo de entidad es texto sin
restricción CHECK, así que añadir las entradas del historial (`logEntry`, en
la v3), las lecturas del cuentakilómetros (`mileageReading`, en la v4) y la
operación de borrado físico (`purge`, en la v5) no ha requerido tocar esta
tabla. Es solo de añadir: sus filas no se modifican ni se borran, tampoco
cuando la entidad a la que apuntan se borra físicamente.

- Qué: referencia a la entidad (qué entrada/vehículo)
- Operación: creación / modificación / eliminación / restauración /
  eliminación definitiva (`purge`: vehículos y propietarios, y entradas,
  lecturas y adjuntos que la limpieza elimina sueltos)
- Cuándo: fecha y hora

### Settings (ajustes)

Configuración de la app, no vinculada a un vehículo. Desde el esquema v6 es
la tabla clave / valor `settings`, descrita en `06_settings_and_i18n.md`.

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
- LogEntry 1 — N Attachment
- Vehicle 1 — N Attachment
- Owner 1 — N Attachment
- LogEntry 1 — 1 Measurement (solo para el tipo "control con medición")
- MaintenanceType 1 — N MaintenanceRule (el catálogo alimenta las reglas)
- AuditLog y Settings son transversales / globales
