# 08 — Recordatorios

Desde el paso 13a (esquema v11). Este documento es la fuente de verdad de los
recordatorios: qué son, cómo se guardan, cómo se calcula su estado, qué
reglas aplica la app y cómo se cargan desde el manual del fabricante. Las
notificaciones del teléfono son el paso 13b y **no** están aquí.

## Qué es un recordatorio

Un recordatorio es el **criterio de un vehículo** sobre el que el usuario
quiere que se le avise: un mantenimiento periódico (aceite cada 15.000 km o
12 meses), un vencimiento legal periódico (revisión cada 24 meses) o una
**fecha única** (el seguro vence el 31 de marzo). Implementa lo que el doc 02
y el doc 04 describían como `MaintenanceRule` ("criterio configurado por
vehículo"), con una simplificación consciente: el catálogo de tipos es una
**lista fija** en el código (`ReminderKind`, abajo) en lugar de la tabla
`MaintenanceType` modificable, que sigue prevista para un paso posterior.

El recordatorio es **su propia fila**: no son campos de la entrada del
historial. Una entrada puede **cerrar** un recordatorio (ver "Cerrar"), y el
recordatorio guarda cuál fue la última, solo como información.

Tiene dos capas que nunca se mezclan:

- **Criterio de referencia** (`ref_*`): lo que dice el manual del fabricante,
  o lo que el usuario escribió. Se edita en el formulario del recordatorio.
- **Criterio aplicado** (`applied_*`, con `override_active`): el que la app
  usa cuando el usuario **ha decidido conscientemente** apartarse de la
  referencia, siempre con un motivo. La referencia **nunca se pierde** y se
  muestra siempre junto al aplicado.

Además, un **aplazamiento** (posponer solo esta vez, con un motivo) y un
**historial de cambios** de solo añadir (`reminder_changes`), para ver
siempre *por qué* se tomó cada decisión sobre el criterio.

El **estado** (vencido, próximo, al día) **nunca se guarda**: se calcula en
cada lectura con el ancla, el criterio aplicado, el aplazamiento, el aviso
anticipado y el km actual del vehículo.

## Tablas (esquema v11)

La migración v10 → v11 solo **crea** las dos tablas y sus índices: no toca
nada más ni escribe en el historial de operaciones.

### `reminders`

Los campos técnicos comunes (`id`, `created_at`, `updated_at`, `deleted`,
`deleted_at`, ver doc 02) y:

| Columna | Contenido |
| --- | --- |
| `vehicle_id` | El vehículo (clave externa, `ON DELETE RESTRICT`) |
| `kind` | Código del tipo (`ReminderKind`, abajo) |
| `title` | Título que se ve en todas partes; nunca vacío. El formulario lo rellena con el nombre del tipo |
| `note` | Nota libre (intervalos de uso severo, lo que dice el manual…) |
| `source` | `manual` (escrito en la app) o `generated` (cargado desde el manual, ver el procedimiento) |
| `manual_ref` | Dónde está en el manual ("p. 174, Piano di manutenzione") |
| `ref_interval_km` | Intervalo de referencia en km (SI), > 0 |
| `ref_interval_months` | Intervalo de referencia en meses, > 0 |
| `due_date` | Fecha de vencimiento (`yyyy-MM-dd`), **solo** en los de fecha única |
| `last_done_date` | **Ancla**: el día de la última intervención |
| `last_done_km` | **Ancla**: los km de la última intervención, ≥ 0 |
| `last_entry_id` | La entrada que lo cerró por última vez (clave externa `ON DELETE SET NULL`). Informativa: el ancla es una **copia**, no se deriva de ella |
| `override_active` | Si manda el criterio aplicado |
| `applied_interval_km`, `applied_interval_months` | El criterio aplicado (> 0). Con el override activo, `NULL` = **ese eje desactivado** |
| `override_reason`, `override_at` | El motivo (obligatorio) y el instante UTC del override |
| `lead_days`, `lead_km` | Aviso anticipado propio (≥ 0); vacío = el ajuste general |
| `snooze_until_date`, `snooze_until_km`, `snooze_reason` | El aplazamiento y su motivo (obligatorio) |
| `completed_at` | Instante UTC en que se cerró uno de fecha única |

Restricciones de la tabla (la app las comprueba antes que SQLite):

- **Periódico o fecha única, nunca los dos:** hay `due_date` si y solo si no
  hay intervalo de referencia.
- Un periódico tiene siempre **ancla de día**, y **ancla de km** en cuanto
  existe un eje de km, de referencia **o aplicado**.
- Un override **nunca desactiva los dos ejes**.
- Solo un recordatorio de fecha única puede estar **completado**.
- El título no puede quedar en blanco.

Índices: `(vehicle_id, deleted)`, `(vehicle_id, kind)` y un **índice único
parcial**: un solo recordatorio vivo y no completado de cada tipo por
vehículo, salvo los tipos `other` y `other_document`, que se pueden repetir.
Aplica el doc 04: "un tipo ya asignado a un vehículo no vuelve a aparecer".
La app comprueba la misma regla antes y lo explica con un mensaje ("Ya hay un
recordatorio de este tipo en este vehículo"); el índice es la red de
seguridad para quien escriba fuera de la app (el procedimiento de carga).

### `reminder_changes`

Historial de **solo añadir**, como el historial de operaciones: una fila por
cada cambio de un recordatorio, escrita **en la misma transacción**, con:
el recordatorio, el instante UTC, el tipo de cambio (`create`, `edit`,
`override`, `restoreReference`, `snooze`, `unsnooze`, `close`, `complete`),
el motivo del usuario (override, aplazamiento), la entrada (al cerrar) y una
**foto del estado después del cambio**: `due_date`, el ancla, los intervalos
de referencia, el override y sus intervalos y el aplazamiento. El estado de
antes es la fila anterior. La primera fila de todo recordatorio es su
`create`. Sin borrado lógico ni `updated_at`; se borra físicamente solo con
su recordatorio.

### Historial de operaciones

Entidad `reminder` con `create`, `update` (toda acción: editar, personalizar,
posponer, cerrar…), `delete`, `restore` y `purge`. Las filas de
`reminder_changes` no tienen fila propia en el historial de operaciones: ya
son un historial.

## El catálogo de tipos (`ReminderKind`)

85 tipos con código de texto estable, en 12 grupos para el selector: motor,
refrigeración, transmisión, frenos, suspensión y dirección, neumáticos y
ruedas, sistema eléctrico, combustible y escape, instalación de GLP / GNC,
alta tensión, vencimientos legales y general. La lista exacta (códigos y
nombres en los tres idiomas) está en el código y la comprueba un test.

- Los **frenos por eje** (CLAUDE.md §5) son tipos separados por componente y
  eje (pastillas, discos, zapatas y tambores, delanteros y traseros), cada
  uno con su vencimiento. La regla "el contenedor (disco / tambor) solo
  existe si existe el que se desgasta" del doc 04 **no** se aplica todavía:
  queda para el paso del catálogo.
- **Aplicabilidad:** cada tipo dice a qué tipos de vehículo y de combustible
  se aplica (p. ej. bujías: no diésel ni eléctrico; cadena: motos). Es **solo
  un filtro del selector**, con el interruptor "Mostrar todos": la lista
  ayuda, nunca bloquea, y el repositorio acepta cualquier tipo. Un vehículo
  de combustible "otro" entra en todo lo que es "no X" y en ningún grupo
  positivo; un híbrido puede ser diésel, así que ve las bujías y no las de
  precalentamiento (las encuentra con "Mostrar todos").
- **Qué entradas lo cierran:** mantenimiento o reparación para todo lo que
  no es legal; vencimiento legal o gasto para el grupo legal.
- **Únicos:** todos menos `other` y `other_document`.
- Los **documentos del propietario** (permiso de conducir, DNI) **no** son
  recordatorios en el 13a: llegarán con `OwnerDocument`.

## El estado

Se calcula, nunca se guarda, con: el recordatorio, **hoy** (el día local del
teléfono), el **km actual** del vehículo y el **aviso anticipado** general.

- Intervalos en uso: los aplicados si el override está activo, los de
  referencia si no.
- **Vencimiento por fecha:** la fecha única, o el ancla + los meses (el día se
  ajusta al último del mes: 31 de enero + 1 mes = 28 o 29 de febrero).
- **Vencimiento por km:** el ancla de km + el intervalo de km.
- El **aplazamiento** sustituye el vencimiento **de su eje**.
- **Vencido** si la fecha ya pasó o el cuentakilómetros llegó al km; **próximo**
  si faltan como mucho los días o los km del aviso; **al día** si no.
  **Vence el primero de los dos** (CLAUDE.md §5): cada eje decide solo.
- Un recordatorio de fecha única **completado** nunca aparece como activo.
- **Menos exigente que la referencia:** con el override activo, si en algún
  eje de la referencia el aplicado vence más tarde o está desactivado. Se
  avisa con un icono discreto y un texto; nunca se impide.
- **Color** solo para el estado y siempre con icono y texto (doc 07): rojo
  vencido, ámbar próximo, verde al día.

## Ajustes

Dos claves **compartidas** (viajan con el paquete, como el idioma):
`reminder_lead_days` (30 por defecto) y `reminder_lead_km` (1000 por
defecto, en km). En Ajustes, la sección **Recordatorios**: "Avisar N días
antes" y "Avisar N km antes" (la distancia en la unidad elegida, número
entero). Cada recordatorio puede tener su propio aviso.

## Reglas

Toda escritura comprueba que el vehículo esté **activo** (uno archivado es de
solo lectura), escribe su fila del historial de operaciones y su fila de
`reminder_changes`, todo en una transacción.

- **Crear / editar** (formulario): título, tipo, referencia, ancla o fecha
  única, aviso propio, nota y referencia del manual. El ancla de día nunca es
  posterior a hoy; la fecha única sí puede ser futura. Editar escribe un
  cambio `edit`. No se puede pasar a fecha única mientras haya override.
- **Personalizar criterio:** al menos un eje activo y motivo obligatorio. Si
  el override **añade el eje de km** a un recordatorio sin ancla de km, pide
  también **los km de la última vez** (obligatorios, sin valor por defecto: el
  ancla es un hecho, no se supone) y los guarda en la misma transacción.
  Editar un override activo es la misma acción. Solo en los periódicos.
- **Restaurar referencia:** quita el override y conserva el historial y el
  ancla, también `last_done_km`. Pide confirmación.
- **Posponer:** fecha y / o km, motivo obligatorio. Cada valor debe ser
  **posterior al vencimiento aplicado** de su eje (nunca al de referencia ni
  a un aplazamiento anterior) y ese eje debe tener vencimiento. Un nuevo
  aplazamiento sustituye al anterior. **Quitar aplazamiento** lo borra.
- **Cerrar** (la única forma de que un periódico avance): con una entrada
  viva del mismo vehículo, fechada **hoy o antes**, de un tipo que cierre ese
  recordatorio. Los km de la entrada son obligatorios si el recordatorio
  tiene intervalo de km, de referencia o aplicado, esté o no activo el
  override. Se rechaza una entrada **anterior al ancla** (fecha anterior, o
  menos km); el mismo día se acepta. Efecto: el ancla toma la fecha y los km
  de la entrada (una **copia**: editar la entrada después no la mueve; el
  ancla se corrige desde el formulario del recordatorio), `last_entry_id`
  apunta a la entrada, el aplazamiento se borra y el override se conserva.
  Uno de fecha única queda **completado**.
- **Marcar hecho:** atajo que crea la entrada que lo cierra (mantenimiento, o
  vencimiento legal en el grupo legal) y lo cierra con ella, todo en una
  transacción. Después, la oferta de actualizar el cuentakilómetros (E3)
  como tras cualquier entrada.
- **Completados:** de solo lectura; solo se pueden borrar.
- **Acciones sin efecto** (restaurar sin override, quitar un aplazamiento que
  no existe) se rechazan.
- **Borrar** es lógico, con Deshacer, y no borra nada más. Deshacer se rechaza
  si mientras tanto apareció otro del mismo tipo, o si el vehículo ya no está
  activo.

## Pantallas

- **Inicio:** tercer destino **Recordatorios**, entre Vehículos y
  Propietarios, con un **distintivo** = vencidos + próximos de los vehículos
  activos (sin distintivo con 0). Lista los recordatorios abiertos de todos
  los vehículos activos, agrupados en **Vencidos / Próximos / Al día** (los
  más urgentes primero: por días que faltan y luego por km). Cada fila: icono
  del tipo, título, vehículo, la línea de estado ("Vencido · Vencido hace 3
  días · en 850 km") y las etiquetas **Personalizado** (con el icono de aviso
  si es menos exigente) y **Pospuesto**. Sin botón de añadir: el texto vacío
  remite a la pestaña de cada vehículo.
- **Vehículo:** pestaña **Recordatorios** justo después de Historial
  (`?tab=reminders`), con las mismas filas sin la línea del vehículo y los
  completados plegados en "Completados (n)". Botón flotante **Nuevo
  recordatorio**; en un vehículo archivado todo se ve y no hay acciones.
- **Formulario:** selector de tipo a pantalla completa con búsqueda,
  agrupado, filtrado por el vehículo, con "Mostrar todos" y **"Otro…"** fijo
  abajo (tipo `other` con título libre); los tipos que el vehículo ya tiene
  no aparecen. Título (relleno con el nombre del tipo), **Periódico / Fecha
  única**, intervalos (al menos uno), ancla de día (hoy por defecto) y de km
  (la lectura actual por defecto, obligatoria con intervalo de km), aviso
  propio ("Usar el ajuste general" si vacío), nota y referencia del manual.
  Al editar, una línea dice que el criterio aplicado se cambia desde el
  detalle.
- **Detalle:** estado en color con icono; **Próximo vencimiento** por fecha y
  por km con lo que falta; con override, **Criterio aplicado** en grande,
  motivo y fecha, y **Criterio de referencia** debajo con "Según el
  fabricante vencería el … / a los …" y el aviso si es menos exigente; el
  aplazamiento con su motivo; **Última vez** con enlace a la entrada; aviso
  propio, nota, referencia del manual y origen ("Cargado desde el manual" /
  "Creado a mano"); **Historial del recordatorio** ("3 nov 2026 · Criterio
  personalizado · Cada 80.000 km · tiempo desactivado · «motivo»"). Acciones:
  Marcar hecho, Editar, Posponer / Quitar aplazamiento, Personalizar / Editar
  criterio, Restaurar referencia y Eliminar.
- **Entradas:** en mantenimiento, reparación, vencimiento legal y gasto, si
  el vehículo tiene recordatorios que ese tipo cierra, el campo opcional
  **Cierra el recordatorio** ("Ninguno" por defecto). Al guardar, la entrada
  y el cierre van juntos; si el recordatorio rechaza la entrada, el error sale
  bajo el campo y no se guarda nada. Una entrada que ya cerró uno muestra
  "Cerró: …" en solo lectura, sin forma de desvincularla. Sin oferta después
  de guardar: el campo es la vía explícita (CLAUDE.md, "keep it manual").
- **Historial:** un pequeño icono en la fila de la entrada que cerró por
  última vez un recordatorio vivo.

## Papelera, archivo y copia de seguridad

- Un recordatorio de un vehículo en la **papelera** se oculta con él y
  vuelve con él. El borrado del vehículo, su eliminación definitiva y la fila
  de la papelera dicen cuántos recordatorios se van con él.
- **Eliminar definitivamente** un vehículo borra antes los cambios y los
  recordatorios (las claves externas son `RESTRICT`).
- La **limpieza de los 30 días** borra los recordatorios borrados hace 30
  días o más de vehículos vivos, con su historial, y escribe una fila
  `purge` por cada uno. Si se borra físicamente la entrada que cerró un
  recordatorio, su `last_entry_id` se vacía; el ancla se queda.
- **Archivo:** los recordatorios de un vehículo archivado se ven, son de solo
  lectura y no cuentan para la lista de Inicio ni para el distintivo.
- **Fecha de última modificación** (`last_modified_at`, doc 05): incluye el
  `updated_at` de los recordatorios (también los borrados). Los cambios no
  cuentan aparte: cada cambio escribe también el `updated_at` de su
  recordatorio.
- **Paquete y Drive:** `counts.reminders` (recordatorios vivos y no
  completados de vehículos vivos) en el manifiesto y en las propiedades de la
  copia de Drive. Un paquete o una copia sin esa clave la lee como 0, como
  `counts.attachments`. El formato del paquete sigue siendo el 1. La
  confirmación de la importación añade "y R recordatorios" cuando hay alguno.

## Carga desde el manual (procedimiento)

Decisión del propietario: **ninguna IA dentro de la app y ninguna función de
importar recordatorios**. Los recordatorios de un vehículo los escribe Claude
Code **directamente en la base de datos de un paquete de copia exportado**, y
el propietario lo importa en el teléfono. Este procedimiento es la única
forma permitida; el comando `/load-reminders <manual.pdf> <paquete.zip>`
remite aquí. Se sigue **en este orden**, con su parada.

### 1. Condiciones previas

- El teléfono tiene una versión con **esquema ≥ 11** (0.13.0 o posterior).
- El propietario **exporta el paquete desde el teléfono que tiene los datos
  más recientes** (Copia de seguridad → Exportar) y el zip llega al PC (cable,
  o "Guardar como" en una carpeta de Drive que el PC sincroniza).
- La base de datos viva del teléfono **nunca** se edita a través de `adb`.
- Herramientas en el PC: **Python 3** con su módulo `sqlite3`, que se llama
  como **`py -3`** (`python3` es el alias de la Microsoft Store y no vale).
  La CLI `sqlite3` (en `platform-tools`) solo se usa como comprobación
  adicional de `PRAGMA integrity_check`. Python hace también el zip.
- Todo se trabaja en una carpeta nueva y vacía (el scratchpad de la sesión);
  el zip original no se modifica.

### 2. Propuesta (nada se escribe todavía)

- Claude Code lee el PDF del manual, localiza la tabla de mantenimiento
  programado y propone **una fila por elemento**: `kind` (del catálogo;
  `other` con título cuando nada encaja), título, `ref_interval_km`,
  `ref_interval_months` (la columna de **uso normal**; los valores de uso
  severo van a la nota), `manual_ref` y nota.
- **Pregunta al propietario** a qué vehículo (matrícula) van y **el ancla de
  cada fila** (fecha y km de la última vez que se hizo). Si no se sabe, el
  propietario elige la fecha de matriculación y la lectura inicial, y la nota
  lo dice.
- Los elementos "la primera vez a los X, después cada Y" se cargan con el
  intervalo que vale **ahora**, con una nota; tras el primer cierre el
  propietario edita el intervalo (el modelo tiene un intervalo por diseño).
- **PARADA:** la tabla completa se enseña al propietario y no se escribe nada
  hasta su aprobación. Nada se inventa.

### 3. Escritura en el paquete

1. Extraer `vehicle_history.sqlite` del zip a la carpeta de trabajo (sin
   cargarlo entero en memoria) y leer `manifest.json`.
2. Abrir la base de datos con `py -3` (`sqlite3`), `PRAGMA foreign_keys = ON`,
   y comprobar que `PRAGMA user_version` es **11** (el esquema del SQL de
   abajo). **Nunca** se edita un paquete de otra versión del esquema.
3. Buscar el vehículo por matrícula entre los vivos y no archivados
   (`deleted = 0 AND archived_at IS NULL`).
4. Tomar el **formato exacto de las marcas de tiempo de una fila existente**
   del mismo archivo (por ejemplo, el `updated_at` del vehículo): ISO-8601 en
   UTC. Se copia el formato; no se deduce de la documentación.
5. En **una transacción**, por cada fila aprobada, ejecutar las tres
   sentencias de [`tool/reminders/insert_reminder.sql`](../tool/reminders/insert_reminder.sql)
   (la fila de `reminders`, su cambio `create` en `reminder_changes` y su
   fila `create` en `audit_log`), separándolas por `;` y pasando los
   parámetros con nombre (`:id`, `:vehicle_id`, …) como diccionario:
   - UUID v4 en minúsculas para `:id`, `:change_id` y `:audit_id`;
   - `source = 'generated'` (lo pone el propio SQL);
   - km en **km** (SI), aunque el manual o el teléfono usen millas;
   - fechas de calendario como `yyyy-MM-dd`;
   - `:now` con el formato copiado en el paso 4, el mismo en las tres filas;
   - override, aplazamiento, aviso propio, `last_entry_id` y `completed_at`
     quedan vacíos (lo pone el propio SQL): son del propietario.
6. No se toca `user_version`, ninguna otra tabla ni ningún recordatorio que
   ya exista.
7. `PRAGMA integrity_check` (debe dar `ok`, también con la CLI `sqlite3`) y
   `PRAGMA foreign_key_check` (sin filas).
8. Si el **índice único parcial** rechaza un tipo repetido, se resuelve **con
   el propietario** (otro tipo, `other`, o dejar esa fila fuera); **nunca**
   borrando nada.
9. Leer de vuelta las filas recién escritas (`SELECT` por `id`) y enseñar al
   propietario una tabla con tipo, título, intervalos de referencia, ancla y
   nota, antes de hacer el zip.

### 4. Manifiesto y nuevo zip

1. **El zip no se hace hasta que el propietario da el visto bueno a la tabla
   del paso 9** de la sección 3. Con él, `manifest.json`: `last_modified_at`
   = el `:now` escrito (el `updated_at` más reciente del archivo) y
   `counts.reminders` = los recordatorios vivos y no completados de
   vehículos vivos tras la carga. Todo lo demás se deja igual.
2. Nuevo zip junto al original (nunca encima): cada entrada se copia **sin
   cambios y en streaming** (los adjuntos pueden ocupar cientos de MB), con
   su mismo método de compresión; solo cambian `vehicle_history.sqlite` y
   `manifest.json`. Los nombres de las entradas siguen planos:
   `manifest.json`, `vehicle_history.sqlite`, `attachments/<nombre>`.
3. Se comprueba el zip nuevo (abre, mismas entradas, la base de datos pasa
   `integrity_check`).

### 5. En el teléfono

- Copia de seguridad → **Importar** el zip nuevo → comprobar la pestaña
  Recordatorios del vehículo → **Subir a Drive** (después de una importación
  manual el control de versión dice "sin punto común": se confirma).
- Otros teléfonos: **primero actualizar la app** a 0.13.0 o posterior y
  después Restaurar desde Drive.

### Nunca

- Editar un paquete de otra versión del esquema.
- Escribir criterios aplicados (`applied_*`) o aplazamientos: son decisiones
  del propietario, desde la app.
- Cambiar la referencia de un recordatorio que ya existe sin el propietario:
  eso es un `edit` desde la app.
- Editar la base de datos viva del teléfono.

El test `test/unit/data/reminders_runbook_sql_test.dart` ejecuta el SQL de
`tool/reminders/insert_reminder.sql` sobre una base de datos v11 y comprueba
que lo escrito se lee bien, que el índice único rechaza un tipo repetido y
que la fecha de última modificación avanza: si el esquema cambia, el test
avisa de que el procedimiento también tiene que cambiar.
