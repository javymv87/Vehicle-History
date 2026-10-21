# 03 — Funcionalidades

## Pantallas de vehículos y propietarios

Primera parte usable de la app (paso 3 de la hoja de ruta).

- **Inicio = lista de vehículos.** Una barra de navegación inferior con dos
  destinos: **Vehículos** y **Propietarios**.
- **Fila de la lista de vehículos:** icono del tipo de vehículo, marca +
  modelo como línea principal (p. ej. "Fiat Punto"), matrícula, nombre común
  (si lo hay), nombre del propietario, km actual (con el formato del idioma)
  y tipo de combustible. Un vehículo sin marca ni modelo (creado antes de
  existir esos campos) muestra la matrícula como línea principal. Ordenada
  por matrícula. Si no hay vehículos, solo un texto
  breve: para añadir se usa el botón flotante, que nunca se duplica.
- **Añadir siempre a mano:** un botón flotante (FAB) en las dos listas (ver
  `07_design_and_theming.md`).
- **Formulario del vehículo:** tipo de vehículo (primer campo), marca,
  modelo, año, versión / acabado, matrícula, propietario, tipo de
  combustible, km actual (**solo al crearlo**), aceite recomendado, notas del
  fabricante y, al final, el nombre común (opcional). El tipo es una
  elección segmentada con icono y texto (coche, furgoneta, moto,
  ciclomotor); al crear empieza en coche. Marca y modelo se eligen con los
  selectores descritos abajo. El propietario se elige entre los existentes **o con "Nuevo
  propietario"**, que abre el formulario del propietario y vuelve con el
  nuevo propietario ya elegido. Si todavía no existe ningún propietario, el
  campo ofrece directamente "Nuevo propietario".
- **Editar un vehículo:** el mismo formulario sin el km actual. Un vehículo
  creado antes de existir marca y modelo se abre y se ve normalmente, pero al
  guardarlo el formulario pide marca y modelo. La ficha del
  vehículo muestra el km en solo lectura, con una nota breve: se cambia solo
  desde la pestaña Kilometraje.
- **Formulario del propietario:** nombre (obligatorio), apellidos, fecha de
  nacimiento (selector de fecha de Material; fecha de calendario sin hora),
  nacionalidad (selector de países, abajo), teléfono, email y notas.
- **Ficha del propietario:** muestra sus vehículos; al tocar uno se abre su
  ficha.
- **Validación** en línea bajo cada campo y traducida: matrícula
  obligatoria; matrícula duplicada (otro vehículo no borrado ya la usa)
  señalada en el propio campo; km obligatorio, número entero ≥ 0; nombre del
  propietario obligatorio. También son obligatorios la marca, el modelo, el
  propietario y el tipo de combustible del vehículo. El año, si se escribe,
  va de 1886 al año siguiente al actual.
- **Mensajes** (reglas de abajo): toast breve al guardar; al borrar, toast
  **con Deshacer** durante unos segundos; errores explícitos y lo bastante
  persistentes para leerlos. Borrar un propietario que todavía tiene
  vehículos muestra un mensaje explícito y no borra nada.
- **Deshacer un borrado** devuelve el registro borrado lógicamente. En el
  historial de operaciones queda como **restauración**. Si mientras tanto
  otro vehículo ha tomado la matrícula, o el propietario del vehículo se ha
  borrado, el deshacer se rechaza con un mensaje y no cambia nada.
- **Confirmación** con un diálogo antes de borrar (además del Deshacer),
  porque un vehículo lleva consigo todo su historial. Para el vehículo, el
  diálogo dice qué se va con él (ver U16, en "Papelera").
- Los **tipos de combustible** y los **tipos de vehículo** se muestran
  traducidos en los tres idiomas.
- **Información:** el menú de la barra superior de las dos listas tiene
  "Información", con los créditos de los datos incluidos (VehiclesDB, Unicode
  CLDR) y la página de licencias. El de la lista de vehículos tiene además
  "Papelera" (ver U17).

### Selectores de marca, modelo y nacionalidad

Regla común: **la lista ayuda, nunca bloquea.** Siempre se puede escribir un
valor que no esté en la lista.

- **Primero el tipo:** cambiar el tipo de vehículo borra marca y modelo,
  porque las listas del catálogo son distintas para cada tipo.
- **Marca:** selector a pantalla completa con búsqueda, con las marcas **del
  tipo elegido**. La búsqueda no distingue mayúsculas ni acentos y encuentra
  el texto en cualquier parte del nombre. Primero las marcas más populares
  (las 20 primeras, con un encabezado), después todas las demás en orden
  alfabético. Última opción, **siempre visible** (fija abajo): **"Otra
  marca…"**, que abre un campo de texto libre (con lo que se había buscado
  como punto de partida).
- **Modelo:** tras elegir una marca del catálogo, selector con búsqueda de
  **los modelos de esa marca** (y de ese tipo), los más populares primero y
  luego en orden alfabético, con **"Otro modelo…"** siempre visible para
  escribirlo a mano. Con una marca escrita a mano, el modelo es directamente
  un campo de texto libre. Cambiar la marca borra el modelo. Sin marca, el
  modelo no se puede elegir ("Elige primero la marca").
- **Nacionalidad (propietario):** selector con búsqueda de todos los países
  ISO 3166-1, con el nombre en el idioma del teléfono (IT / ES / EN), más
  **"Otra…"** para escribirla a mano. Se guarda el código ISO del país (o el
  texto escrito); se muestra con el nombre del país en el idioma de la app,
  o tal cual si no es un código conocido. Se puede borrar con el botón de
  vaciar del campo, porque es opcional.
- **Origen de los datos:** el catálogo de marcas y modelos es de
  **VehiclesDB** (CC BY 4.0, elaborado a partir de registros públicos
  oficiales) y los nombres de países de **Unicode CLDR**. Los dos van
  incluidos en la app: no se consulta nada en internet.

## Historial de entradas

Cada vehículo tiene una lista desplazable de LogEntry ordenadas por fecha (las
más recientes arriba). Cada fila muestra de un vistazo: tipo, fecha, km, un
extracto del texto, el coste (si lo hay) y un icono si hay fotos o un
recordatorio.

Al tocar una entrada se ve su detalle completo y se puede modificar o
borrar.

Lo que hace hoy la app (paso 4 de la hoja de ruta):

- **U1 — El vehículo se abre en su historial.** La página del vehículo
  tenía dos pestañas: **Historial** (la primera, la que se ve al abrir) y
  **Ficha** (los datos del vehículo); desde el paso 5 tiene también
  **Kilometraje** (ver U11). Arriba, siempre visible, una cabecera
  compacta con el icono del tipo de vehículo, marca + modelo, matrícula y km
  actual.
- **U2 — Botón flotante "Nueva entrada"** en la página del vehículo (en las
  listas sigue el botón de añadir vehículo / propietario).
- **U3 — Formulario rápido, pocos toques.** Orden: tipo (chips con icono, un
  toque), fecha (**hoy por defecto**, selector de fecha de Material), km,
  coste y descripción. El botón Guardar está siempre en la barra superior.
- **U4 — Ayuda para el km:** bajo el campo, un chip de un toque "Usar km
  actual (123.456)" copia el km actual del vehículo. El campo **nunca** se
  rellena solo. La etiqueta indica si el km es obligatorio para el tipo
  elegido o opcional.
- **U5 — Coste en euros** con el separador decimal del idioma (`,` en
  italiano y español, `.` en inglés), con 2 decimales como máximo; se guarda
  en céntimos y se muestra con el formato de moneda del idioma. Como algunos
  teclados del teléfono solo muestran uno de los dos separadores, se acepta
  también el otro como separador decimal; no se aceptan separadores de miles
  (`1.234` se rechaza en vez de leerse como 1234 €).
- **U6 — Fila de la lista:** icono y nombre del tipo, fecha, km (si los
  hay), la primera línea de la descripción y el coste (si lo hay). Las más
  recientes arriba (por fecha y, en el mismo día, la creada más tarde
  primero), agrupadas por mes con un pequeño encabezado ("Octubre de
  2026").
- **U7 — Detalle:** todos los campos; editar y borrar (confirmación +
  toast con Deshacer). Bajo los km, una nota recuerda que solo se registran
  en la entrada y no cambian el km del vehículo.
- **U9 — Historial vacío:** un texto breve; para añadir, el botón flotante.
- **U10 — Validación** en línea y traducida: tipo obligatorio; fecha
  obligatoria; km entero ≥ 0, obligatorio para los tipos que lo requieren
  (ver `02_data_model.md`); coste ≥ 0 con 2 decimales como máximo.

Reglas añadidas al formulario de entradas en el paso 5:

- **E1 — Fechas futuras** solo para vencimiento legal, gasto y nota. Para
  mantenimiento, reparación, repostaje y control la fecha debe ser hoy o
  anterior: el formulario lo señala bajo la fecha y el repositorio lo
  rechaza. Las entradas que ya existían no se tocan.
- **E2 — Entrada con km mayor que una lectura posterior:** si alguna
  lectura de un día posterior a la fecha de la entrada tiene menos km que la
  entrada, casi seguro es un error tipográfico (el cuentakilómetros no va
  hacia atrás). Se compara con la primera lectura posterior a esa fecha, no
  solo con la última. Un diálogo avisa ("Este km es mayor que la lectura del
  10 oct 2026 (111.000 km), fecha posterior a esta entrada. ¿Guardar
  igualmente?"). No
  bloquea.
- **E3 — Oferta de actualizar el cuentakilómetros.** Después de guardar una
  entrada (nueva o editada) cuando se cumplen las tres condiciones — km
  mayor que el km actual, fecha hoy o anterior, fecha no anterior a la
  última lectura — aparece durante unos 8 segundos "Entrada guardada.
  ¿Actualizar el cuentakilómetros a 123.456 km?" con la acción
  **"Actualizar"**. Al pulsarla se crea una lectura con la fecha y el km de
  la entrada (con la confirmación de los 50.000 km si procede) y la página
  del vehículo pasa a la pestaña Kilometraje. Si no se pulsa, no pasa nada:
  la entrada ya está guardada.

## Kilometraje

El cuentakilómetros del vehículo (paso 5 de la hoja de ruta). Reglas en
`04_maintenance_logic.md`.

- **U11 — Tres pestañas** en la página del vehículo: **Historial** (la que
  se ve al abrir), **Kilometraje** y **Ficha**. La cabecera compacta sigue
  mostrando el km actual.
- **U12 — Pestaña Kilometraje:** las lecturas de la más reciente a la más
  antigua; cada fila muestra la fecha, los km (con el formato del idioma) y
  la diferencia con la lectura anterior ("+1.250 km"); la más antigua
  muestra "Lectura inicial" en lugar de la diferencia.
- **U13 — Botón flotante "Actualizar km"** en la pestaña Kilometraje (en
  Historial y en Ficha sigue "Nueva entrada"). Formulario: km (obligatorio,
  entero, con la ayuda "Última: 123.456 km el 3 oct 2026") y fecha (hoy por
  defecto; el selector solo permite días entre la última lectura y hoy).
  Mensajes para km inferior a la última lectura y fecha fuera de rango;
  diálogo de confirmación si se superan en más de 50.000 km.
- **U14 — Acciones de una fila** (al tocarla, una pequeña hoja inferior): la
  última lectura, si no es la inicial, ofrece **"Eliminar"** (confirmación +
  toast con Deshacer); la única lectura (la inicial) ofrece **"Corregir"**
  (el mismo formulario, ya relleno). Las demás muestran la lectura y una
  explicación breve: solo se puede borrar la última.
- **U15 — Abrir en una pestaña:** la página del vehículo acepta el
  parámetro `tab` (`?tab=mileage`), para que la acción "Actualizar" y los
  futuros enlaces directos lleguen a la pestaña correcta.

## Papelera

Los vehículos borrados (paso 5b de la hoja de ruta). Reglas de datos en
`02_data_model.md` ("Borrado lógico, papelera y borrado físico") y en
`05_sync_and_storage.md` ("Papelera y limpieza").

- **U16 — Confirmación al borrar un vehículo:** el título lleva el nombre y
  la matrícula ("¿Eliminar Fiat Punto (AB123CD)?"; solo la matrícula si el
  vehículo no tiene marca ni modelo) y el texto dice qué se va con él: "Se
  borrarán el vehículo, sus N entradas y sus M lecturas de km. Podrás
  recuperarlo desde la papelera durante 30 días." (cuenta las entradas y
  lecturas **no borradas**, con singular y plural). Al confirmar, el toast
  con Deshacer de siempre.
- **U17 — Pantalla Papelera** (ruta `/trash`), desde el menú de la lista de
  vehículos: "Papelera", con el número de vehículos cuando hay alguno
  ("Papelera (2)"). Cada fila: icono del tipo, marca + modelo, matrícula,
  propietario, "Borrado el 3 oct 2026", "Se eliminará en 27 días" (días que
  faltan para los 30, redondeados hacia arriba: recién borrado dice 30) y
  cuántas entradas y lecturas lleva. Acciones de cada fila: **Restaurar** y
  **Eliminar definitivamente** (diálogo de confirmación con lo que se borra,
  en color de error, sin Deshacer). En la barra superior, **Vaciar
  papelera** (icono con su nombre como descripción; confirmación con el
  número de vehículos). Sin vehículos: "La papelera está vacía", y no hay
  botón de vaciar.
- **U18 — Restaurar:** toast "Vehículo restaurado" y el vehículo vuelve a la
  lista con sus entradas y lecturas. Si otro vehículo ha tomado la matrícula
  o el propietario ya no existe, se rechaza con los mensajes de siempre y
  sigue en la papelera.
- **U19 — Diseño:** Material 3, zonas táctiles de al menos 48 dp, modo
  oscuro, texto grande y 360 dp de ancho; las acciones destructivas
  (eliminar, eliminar definitivamente, vaciar) usan el color de error. Los
  diálogos se pueden desplazar cuando el texto grande no cabe.

## Copia de seguridad

Exportar e importar todos los datos como un paquete (paso 6 de la hoja de
ruta). Formato del paquete, validación y red de seguridad en
`05_sync_and_storage.md` ("Exportar / importar: el paquete de copia").

- **U20 — Pantalla Copia de seguridad** (ruta `/backup`), desde el menú de
  las listas de inicio: "Última exportación: 20 oct 2026, 18:30" (o
  "Última exportación: nunca"), una explicación breve de lo que contiene el
  paquete y de que importar sustituye todos los datos, y los botones
  **Exportar** e **Importar**. Mientras trabaja, un indicador de progreso con
  "Exportando…" / "Importando…" y los botones desactivados.
  - Exportar: el diálogo del sistema para elegir dónde guardar; cancelar no
    es un error; al guardar, toast "Copia exportada" y la fecha se
    actualiza.
  - Importar: el selector de archivos (zip); un archivo que no vale se
    rechaza con un mensaje claro y no cambia nada; si vale, diálogo de
    confirmación con lo que contiene ("Este archivo contiene 2 vehículos, 41
    entradas y 7 lecturas; última modificación 18 oct 2026.") y, en negrita,
    "Importar sustituye todos los datos actuales.", con el botón en color de
    error. Al terminar, la app vuelve a la lista de vehículos con el toast
    "Copia importada"; si falla, "No se pudo importar; tus datos no han
    cambiado".
  - Diseño: Material 3, botones de al menos 48 dp, modo oscuro, texto grande
    y 360 dp de ancho.
- **U21 — Pantalla Ajustes** (ruta `/settings`), desde el menú de las listas
  de inicio, junto a Copia de seguridad, Papelera y Acerca de. Dos ajustes,
  cada uno una fila con su valor actual que abre un diálogo con botones de
  opción:
  - **Idioma**: Sistema, Italiano, Español, English. Cada idioma se escribe
    en su propio idioma, sea cual sea el de la app.
  - **Tema**: Sistema, Claro, Oscuro.
  - Tocar una opción cierra el diálogo y la app cambia al momento (ver
    `06_settings_and_i18n.md`); Cancelar no cambia nada. Sin toast: el
    cambio ya se ve.
  - Diseño: Material 3, opciones de al menos 48 dp, modo oscuro, texto
    grande y 360 dp de ancho.

## Filtros y búsqueda

En el historial se puede filtrar por:

- **Fecha** (intervalo desde–hasta)
- **Tipo** de entrada (una o varias categorías)
- **Texto** (búsqueda libre en la descripción)

Los filtros son combinables. Deben poder activarse y restablecerse
rápidamente.

Cómo funciona (U8):

- Un botón de filtro en la barra superior (solo en la pestaña Historial, con
  un punto cuando hay filtros activos) abre una hoja inferior con el
  intervalo de fechas (selector de intervalo de Material), los tipos (chips
  de selección múltiple) y el texto. Se aplican con "Aplicar".
- Los filtros activos aparecen como chips encima de la lista, cada uno con su
  botón para quitarlo, más **"Quitar filtros"** para quitarlos todos.
- El texto se busca en la descripción, en cualquier parte, sin distinguir
  mayúsculas ni acentos ("malaga" encuentra "Málaga").
- El intervalo de fechas incluye los dos extremos. Los criterios se combinan
  (todos deben cumplirse).
- Si no hay resultados: "Ninguna entrada con estos filtros" y un botón para
  quitarlos.
- Los filtros duran mientras la página del vehículo está abierta.

## Recordatorios y notificaciones

Dos orígenes de recordatorios:

1. **Manuales** — configurados en una sola entrada (una fecha futura y/o un
   umbral de km).
2. **Automáticos** — derivados de las `MaintenanceRule` del vehículo y de los
   vencimientos de los documentos (impuesto de circulación, inspección técnica
   obligatoria, seguro y los documentos del propietario: permiso de conducir,
   documento de identidad, permiso de residencia).

Comportamiento de los avisos:

- Los vencimientos **por tiempo** generan una **notificación** del teléfono en
  la fecha prevista (incluso con la app cerrada).
- Los vencimientos **por km** no pueden "saltar" por sí solos en el tiempo (la
  app no conoce los km en tiempo real): se **señalan visualmente** — las
  entradas de mantenimiento próximas al umbral de km o que lo superan se
  resaltan cuando abres la app y cuando actualizas el cuentakilómetros total.
- Los controles con medición con **umbral** avisan cuando el último valor
  registrado baja del umbral configurado.

## Informes

Todos los informes ofrecen la opción **incluir / excluir imágenes** y, donde
corresponda, **incluir / excluir importes**. La exportación de referencia es
en **PDF** (adecuado para imprimir, enviar o entregar a un comprador).

Informes previstos:

- **Gastos** — por vehículo, por periodo, con totales. Incluye los gastos de
  los mantenimientos (ver abajo) y los gastos genéricos.
- **Entradas por tipo** — solo mantenimientos, solo repostajes, etc.; con la
  opción de incluir o no los importes.
- **Consumo de combustible** — consumo medio (total o por periodo) y gasto
  total en combustible por periodo (detalle del cálculo en
  `04_maintenance_logic.md`).
- **Km recorridos frente a tiempo** — basado en el historial de kilometraje
  (`MileageReading`).
- **General** — TODA la información de un vehículo en un único documento.
  Pensado como registro completo para la reventa / cambio de titularidad. Es
  un punto fuerte de la app.

Los informes pueden generarse para **un** vehículo o para **varios**
vehículos.

## Gastos dentro del mantenimiento

El coste ya es un campo de la entrada base (`LogEntry`). Además, dentro de una
entrada de mantenimiento se pueden enumerar las **partidas de gasto
individuales** (p. ej. "pastillas — 45 €", "mano de obra — 60 €"), cuya suma da
el coste total del mantenimiento. Se introducen en una **sección desplegable**
dentro de la entrada, no en una pantalla separada, y son opcionales (coherente
con el principio "la rapidez de uso ante todo").

## Reglas UX de los mensajes de resultado (toast)

Gradación que se debe respetar:

- **Guardado / modificación correctos** — toast breve y discreto (p. ej.
  "Entrada guardada"). Si la pantalla ya vuelve atrás y la entrada aparece en
  la lista, el toast puede ser incluso mínimo para no resultar redundante.
- **Eliminación** — toast con **acción de deshacer** ("Entrada eliminada —
  Deshacer"). Es la acción más arriesgada si es involuntaria, por lo que el
  deshacer es importante. (Posible gracias al borrado lógico: ver
  `02_data_model.md`.)
- **Error** (guardado fallido, espacio agotado, sincronización fallida) —
  mensaje **explícito y lo bastante persistente** para poder leerlo, no un
  destello.

## Fotos

- Foto de perfil del vehículo (una).
- Foto del propietario (una).
- Fotos/escaneos de los documentos (vehículo y propietario).
- Una o varias imágenes por cada entrada del historial.

Las imágenes se obtienen de la cámara o de la galería y se guardan localmente;
se incluyen en la copia de seguridad en la nube.
