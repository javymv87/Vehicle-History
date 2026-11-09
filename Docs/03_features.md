# 03 — Funcionalidades

## Pantallas de vehículos y propietarios

Primera parte usable de la app (paso 3 de la hoja de ruta).

- **Inicio = lista de vehículos.** Una barra de navegación inferior con tres
  destinos: **Vehículos**, **Recordatorios** (desde el paso 13a, con su
  distintivo; ver "Recordatorios y notificaciones") y **Propietarios**.
- **Fila de la lista de vehículos:** icono del tipo de vehículo, marca +
  modelo como línea principal (p. ej. "Fiat Punto"), matrícula, nombre común
  (si lo hay), nombre del propietario, km actual (con el formato del idioma)
  y tipo de combustible. Un vehículo sin marca ni modelo (creado antes de
  existir esos campos) muestra la matrícula como línea principal. Ordenada
  por matrícula. Si no hay vehículos, solo un texto
  breve: para añadir se usa el botón flotante, que nunca se duplica.
- **Añadir siempre a mano:** un botón flotante (FAB) en las listas de
  vehículos y de propietarios (ver `07_design_and_theming.md`). La lista de
  recordatorios no tiene: un recordatorio se crea desde su vehículo.
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
  vehículo muestra el km en solo lectura, con el día de la última lectura;
  se cambia solo desde la pestaña Kilometraje (ver "Pantallas de
  detalle").
- **Formulario del propietario:** nombre (obligatorio), apellidos, fecha de
  nacimiento (selector de fecha de Material; fecha de calendario sin hora),
  nacionalidad (selector de países, abajo), teléfono, email y notas.
- **Ficha del propietario:** muestra sus vehículos; al tocar uno se abre su
  ficha (ver "Pantallas de detalle").
- **Validación** en línea bajo cada campo y traducida: matrícula
  obligatoria; matrícula duplicada (otro vehículo no borrado ya la usa)
  señalada en el propio campo; km actual obligatorio, número entero ≥ 0 en
  la unidad elegida (el campo lleva su símbolo); nombre del
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
- **Información:** el menú de la barra superior de las listas de inicio tiene
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

## Pantallas de detalle (paso 14b)

Desde la versión 0.14.0 la pestaña Ficha del vehículo, el detalle de una
entrada y la ficha del propietario siguen el arquetipo de detalle
(`07_design_and_theming.md`, "Una tarjeta por pregunta" y "Arquetipos"):
una tarjeta por pregunta, la más importante arriba, 20 dp a los lados y
entre bloques, y solo los campos rellenos. Muestran lo mismo que antes,
reordenado; las acciones siguen en la barra y en su menú ⋮.

- **Ficha del vehículo** (¿qué es y dónde está ahora?):
  1. **Tarjeta del cuentakilómetros:** el km actual como cifra grande y,
     debajo en gris, "Lectura del 3 nov 2026" (el día de la última
     lectura); desde 0.14.0 sin la nota "Solo se cambia desde la pestaña
     Kilometraje" (decisión del owner en la revisión). Sin tinte
     mientras está activo; archivado, en gris con el icono de archivo y
     "Archivado · 4 mar 2024" encima (el banner de arriba sigue con el
     motivo, la nota y Reactivar).
  2. **IDENTIFICACIÓN:** matrícula, marca, modelo, versión, año y nombre
     común, en filas de dos columnas (etiqueta gris a la izquierda, valor a
     la derecha).
  3. **MOTOR Y COMBUSTIBLE:** tipo de vehículo, combustible y aceite
     recomendado.
  4. **Propietario:** una fila con su nombre que abre su ficha.
  5. Las **notas del fabricante**, como párrafo gris.
- **Detalle de una entrada** (¿qué se hizo, cuándo y cuánto costó?). El
  tipo es el título de la barra.
  1. **Cabecera:** el icono del tipo en un círculo, el vehículo ("Fiat Punto
     · FS548KS") y, si la entrada cerró un recordatorio, "Cerró: Aceite de
     motor" en gris, que abre el recordatorio.
  2. **Tarjeta de estado,** sin tinte: la descripción (o el nombre del tipo
     si no la hay) como título y, debajo, los valores sin etiqueta (cada uno
     lleva su unidad): fecha, km y coste; en un repostaje, cantidad, precio
     por unidad e importe en la primera fila y fecha y km en la segunda. Con
     km, la nota gris "no cambia el km del vehículo".
  3. **CONSUMO** (solo repostajes): lo que el repostaje significa para el
     consumo en una línea con icono y color de estado (tramo válido en
     verde, sospechoso en ámbar con la frase "¿Faltó un repostaje?" y el
     enlace **Editar repostaje**, no calculable en gris con el motivo; un
     parcial o el primer lleno, en gris), y las filas carburante (en
     bifuel), depósito lleno y "me salté uno".
  4. **ADJUNTOS (n)** con el botón "Añadir adjunto" (un icono + de 40 dp
     al final de la etiqueta, que no hace más alta su fila): la cuadrícula de
     miniaturas y las filas de los demás archivos (U23).
- **Ficha del propietario** (¿quién es y cuáles son sus vehículos?). La
  barra no lleva título: el nombre está en la cabecera.
  1. **Cabecera:** icono de persona, nombre y apellidos, y teléfono · email
     en gris cuando los hay.
  2. **Vehículos:** una fila por vehículo activo (icono del tipo, marca y
     modelo, y "matrícula · km actual" en gris) y, al final, la sección
     plegada "Archivados (n)" con el icono de archivo, cada uno con su chip
     ("Vendido · mar 2024"). Sin vehículos, la vista vacía con el texto de
     siempre.
  3. **DATOS PERSONALES:** fecha de nacimiento y nacionalidad.
  4. Las **notas**, como párrafo gris.
  5. **DOCUMENTOS (n)** con el botón "Añadir documento", el mismo icono +
     (U26).

## Historial de entradas

Cada vehículo tiene una lista desplazable de LogEntry ordenadas por fecha (las
más recientes arriba). Cada fila muestra de un vistazo: tipo, fecha, km, un
extracto del texto, el coste (si lo hay) y un clip con el número de adjuntos
si los hay (U24) y, desde el paso 13a, un pequeño icono cuando la entrada es
la última que cerró un recordatorio vivo.

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
  Un repostaje añade sus campos (desde el paso 12, ver "Repostajes" abajo).
- **U4 — Ayuda para el km:** bajo el campo, un chip de un toque "Usar
  lectura actual (123.456 km)" copia el km actual del vehículo, en la
  unidad elegida. El campo **nunca** se rellena solo. La etiqueta indica si
  el km es obligatorio para el tipo elegido o opcional; el sufijo del campo
  es el símbolo de la unidad (`06_settings_and_i18n.md`, "Unidades de
  medida").
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
  en la entrada y no cambian el km del vehículo. Un repostaje enseña además
  sus campos y su consumo (ver "Repostajes"). Desde 0.14.0 sigue el
  arquetipo de detalle (ver "Pantallas de detalle").
- **U9 — Historial vacío:** un texto breve; para añadir, el botón flotante.
- **U10 — Validación** en línea y traducida: tipo obligatorio; fecha
  obligatoria; km entero ≥ 0 en la unidad elegida, obligatorio para los
  tipos que lo requieren (ver `02_data_model.md`); coste ≥ 0 con 2 decimales
  como máximo. En un repostaje: cantidad ≥ 0 (con decimales) y precio por
  unidad ≥ 0 con 3 decimales como máximo.

Reglas añadidas al formulario de entradas en el paso 5:

- **E1 — Fechas futuras** solo para vencimiento legal, gasto y nota. Para
  mantenimiento, reparación, repostaje y control la fecha debe ser hoy o
  anterior: el formulario lo señala bajo la fecha y el repositorio lo
  rechaza. Las entradas que ya existían no se tocan.
- **E2 — Entrada con km mayor que una lectura posterior:** si alguna
  lectura de un día posterior a la fecha de la entrada tiene menos km que la
  entrada, casi seguro es un error tipográfico (el cuentakilómetros no va
  hacia atrás). Se compara con la primera lectura posterior a esa fecha, no
  solo con la última. Un diálogo avisa ("Esta lectura es mayor que la
  lectura del 10 oct 2026 (111.000 km), fecha posterior a esta entrada.
  ¿Guardar igualmente?"). No bloquea.
- **E3 — Oferta de actualizar el cuentakilómetros.** Después de guardar una
  entrada (nueva o editada) cuando se cumplen las tres condiciones — km
  mayor que el km actual, fecha hoy o anterior, fecha no anterior a la
  última lectura — aparece durante unos 8 segundos "Entrada guardada.
  ¿Actualizar el cuentakilómetros a 123.456 km?" con la acción
  **"Actualizar"**. Al pulsarla se crea una lectura con la fecha y el km de
  la entrada (con la confirmación de los 50.000 km si procede) y la página
  del vehículo pasa a la pestaña Kilometraje. Si no se pulsa, no pasa nada:
  la entrada ya está guardada.

## Repostajes

Los campos del repostaje y su consumo (paso 12 de la hoja de ruta). Reglas de
cálculo en `04_maintenance_logic.md` ("Repostajes y consumos"); columnas en
`02_data_model.md` ("Repostaje (esquema v10)").

- **Formulario** (tipo repostaje, vehículo no eléctrico). Orden: fecha, km
  (obligatorio), **carburante** (solo en los bifuel: gasolina / GLP o
  gasolina / GNC, con la gasolina elegida al principio), **cantidad** (en la
  unidad de volumen de los ajustes, o en kg con GNC; con decimales; opcional,
  con la ayuda "Sin ella, el repostaje cuenta solo como gasto"), **precio por
  unidad** (€/L, €/gal o €/kg; no se guarda), **importe** (el coste de
  siempre), el interruptor **Depósito lleno** (encendido por defecto), la
  casilla **Me salté un repostaje antes de este** (apagada, con una línea de
  ayuda), descripción y adjuntos.
- **Triángulo importe / cantidad / precio:** se rellenan dos cualesquiera y
  el tercero se calcula al momento y sigue siendo editable; al cambiar uno se
  recalcula el que no está entre los dos tocados más recientemente.
- **Avisos que no bloquean:** un precio fuera de 0,5–3,5 € por litro (o por
  kg) o una cantidad de más de 200 L (o kg) piden "¿Guardar este repostaje?"
  con un "Guardar igualmente".
- Los repostajes anteriores al paso 12 se abren con la cantidad vacía y los
  valores por defecto, y se pueden completar.
- **Vehículo eléctrico:** el repostaje solo tiene los campos de siempre (es un
  gasto).
- **Al guardar**, un único aviso de unos 8 segundos: "Repostaje guardado." y
  lo que significa para el consumo (el consumo, km, días y coste del tramo
  que cierra; "A partir del siguiente lleno verás el consumo"; "Se contará en
  el tramo del siguiente lleno"; o por qué el tramo no se puede calcular).
  Si además procede la oferta de E3, el mismo aviso termina con "¿Actualizar
  el cuentakilómetros…?" y su botón **Actualizar**; si no, el botón es
  **Ver**, que abre el repostaje.
- **Detalle:** cantidad, precio por unidad (calculado) e importe en la
  tarjeta de estado; carburante (en bifuel), depósito lleno, "me salté uno" y
  lo mismo que el aviso en la tarjeta **Consumo** (ver "Pantallas de
  detalle"). Un tramo sospechoso añade la línea ámbar "Consumo muy distinto de la
  media. ¿Faltó un repostaje?" (con icono) y el enlace **Editar repostaje**;
  un parcial dice en qué tramo cuenta o que contará en el del siguiente
  lleno.
- **Ficha del vehículo:** cambiar el tipo de combustible se rechaza si deja
  repostajes con un carburante que el nuevo tipo no admite, con el número de
  repostajes en el mensaje.

## Kilometraje

El cuentakilómetros del vehículo (paso 5 de la hoja de ruta). Reglas en
`04_maintenance_logic.md`.

- **U11 — Pestañas** de la página del vehículo: en el paso 5 eran tres
  (**Historial**, la que se ve al abrir, **Kilometraje** y **Ficha**); el paso
  8 añadió **Documentos** (U25), el paso 12 **Informes** y el paso 13a
  **Recordatorios**. Hoy son seis: Historial, Recordatorios, Kilometraje,
  Informes, Documentos y Ficha. La cabecera compacta sigue mostrando el km
  actual.
- **U12 — Pestaña Kilometraje:** las lecturas de la más reciente a la más
  antigua; cada fila muestra la fecha, los km (con el formato del idioma) y
  la diferencia con la lectura anterior con los días entre las dos
  ("+1.250 km en 12 días"; desde el paso 12); la más antigua muestra
  "Lectura inicial" en lugar de la diferencia. Las estadísticas por periodo
  están en Informes.
- **U13 — Botón flotante "Actualizar cuentakilómetros"** en la pestaña
  Kilometraje (en Historial y en Ficha sigue "Nueva entrada", en
  Recordatorios es "Nuevo recordatorio", en Documentos es "Añadir documento" e
  Informes, que es de solo lectura, no tiene).
  Formulario:
  lectura (obligatoria, número entero en la unidad elegida, con su símbolo
  como sufijo y la ayuda "Última: 123.456 km el 3 oct 2026") y fecha (hoy
  por defecto; el selector solo permite días entre la última lectura y hoy).
  Mensajes para lectura inferior a la última y fecha fuera de rango; diálogo
  de confirmación si se superan en más de 50.000 km ("30.000 mi" cuando la
  unidad es la milla; ver `04_maintenance_logic.md`).
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
  lecturas **no borradas**, con singular y plural). Desde el paso 8, si el
  vehículo tiene adjuntos (los suyos más los de sus entradas no borradas),
  dice "…, sus M lecturas de km y K adjuntos"; lo mismo la fila de la
  papelera y la confirmación de eliminar definitivamente. Desde el paso 13a,
  si tiene recordatorios, los tres textos los nombran también ("…, sus M
  lecturas de km, K adjuntos y R recordatorios"). Al confirmar, el toast
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
    entradas y 7 lecturas; última modificación 18 oct 2026."), sus adjuntos
    ("3 adjuntos (12 MB)."), los archivos que faltan si falta alguno y, en
    negrita,
    "Importar sustituye todos los datos actuales.", con el botón en color de
    error. Al terminar, la app vuelve a la lista de vehículos con el toast
    "Copia importada"; si falla, "No se pudo importar; tus datos no han
    cambiado".
  - Diseño: Material 3, botones de al menos 48 dp, modo oscuro, texto grande
    y 360 dp de ancho.
  - **Sección Google Drive** (paso 9, ver `05_sync_and_storage.md`), debajo
    de exportar / importar:
    - Sin cuenta: una explicación y dos acciones, cada una con una línea que
      la explica (paso 9b):
      - **Vincular con cuenta del teléfono**: selector de cuentas del sistema
        y consentimiento de Google (Modalidad 1);
      - **Vincular cuenta manualmente**: inicio de sesión en el navegador,
        sin añadir la cuenta al teléfono (Modalidad 2). Si se cierra el
        navegador, no pasa nada. Sin conexión, "Sin conexión…". Después de
        vincular, un aviso que se cierra con Aceptar: la sesión de Google
        puede quedar abierta en el navegador.

      Al vincular una cuenta sin copia, la primera se sube al momento;
      toast "Vinculada a …".
    - Con cuenta: "Copia vinculada a: usuario@gmail.com" y debajo, con su
      icono, la modalidad ("Cuenta del teléfono" / "Vinculada manualmente
      (solo en esta app)"), "Última subida: …"
      / "Última restauración: …" (o "Todavía sin subidas ni
      restauraciones"), la **línea de estado** del guard ("Drive: al día",
      "cambios sin subir", "copia más reciente en Drive (de otro teléfono)",
      "han cambiado los dos", "copia sin comparar…", "versión más nueva…",
      "error en la última subida (se reintentará en el próximo arranque)",
      "sin conexión…", "vuelve a vincular la cuenta"), una nota de que la
      copia se sube sola al arrancar y Drive guarda las 3 últimas copias,
      y los botones **Subir a Drive** y **Restaurar desde Drive** (los dos
      desactivados con una copia de una versión más nueva; Restaurar, sin
      copia), con barra de progreso y porcentaje.
    - Subir a Drive sobre una copia que este teléfono no contiene (nube
      cambiada, ambos cambiados, sin punto común) pide confirmación con las
      fechas de los dos lados, en color de error. Toast "Copia subida a
      Drive".
    - Restaurar desde Drive: el diálogo de la importación con título
      "¿Restaurar desde Drive?", lo que contiene la copia, "Los datos de
      este teléfono (último cambio …) se sustituirán por la copia de Drive"
      (o "Este teléfono todavía no tiene datos." si está vacío) y, si hay cambios locales sin subir, "se perderán" en color de error.
      Al terminar, lista de vehículos y toast "Copia restaurada desde
      Drive".
    - Interruptor **Usar datos móviles para la copia automática**
      (desactivado por defecto).
    - **Cambiar de cuenta**, en la misma modalidad (aviso: "la copia de
      seguridad anterior se queda en la cuenta antigua"), y **Desvincular**
      (aviso: las copias se quedan en el Drive de esa cuenta; en la
      Modalidad 2, además, Google retira el acceso de la app). Si la
      revocación falla, la cuenta se desvincula igual y un mensaje largo
      explica dónde quitar el acceso a mano. Para cambiar de modalidad hay
      que desvincular primero.
    - La confirmación de una importación manual, con cuenta vinculada,
      añade: "La copia automática de Drive quedará en pausa hasta que elijas
      Subir a Drive o Restaurar desde Drive."
  - **Al abrir la app** (sin diálogos): si Drive tiene una copia más
    reciente o han cambiado los dos, un **banner discreto** arriba en la
    pantalla principal con la línea de estado ("Restaura antes de editar."
    en el primer caso) y el botón "Copia de seguridad"; se queda hasta que
    el estado cambia. Sin punto común, copia más nueva o cuenta por
    vincular: un mensaje breve una vez, con el mismo acceso.
- **U21 — Pantalla Ajustes** (ruta `/settings`), desde el menú de las listas
  de inicio, junto a Copia de seguridad, Papelera e Información. Idioma y
  tema, cada uno una fila con su valor actual que abre un diálogo con botones
  de opción, desde el paso 11 la sección **Unidades** (preajuste
  Internacional / Imperial y una fila por magnitud; ver
  `06_settings_and_i18n.md`, "Unidades de medida") y desde el paso 13a la
  sección **Recordatorios** ("Avisar N días antes", "Avisar N km antes"; ver
  `08_recordatorios.md`):
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

Los recordatorios dentro de la app están hechos (paso 13a); las
notificaciones del teléfono son el paso 13b. Modelo, reglas, pantallas y el
procedimiento de carga desde el manual: `08_recordatorios.md`.

- **Qué es:** un recordatorio por criterio y vehículo, en su propia tabla:
  periódico (cada X km y / o Y meses desde la última vez) o de fecha única
  (seguro, documento). Lo crea el usuario desde la pestaña Recordatorios del
  vehículo, o se carga desde el manual con el procedimiento del doc 08. No
  son campos de la entrada.
- **Inicio:** el destino **Recordatorios** es una agenda: solo los vencidos y
  los próximos de los vehículos activos, en Vencidos / Próximos, con un
  distintivo que cuenta esa misma lista. Sin nada pendiente dice "Nada
  pendiente" y cuántos están al día. Los vehículos archivados quedan fuera.
- **Vehículo:** pestaña **Recordatorios** (después de Historial) con el plan
  completo (Vencidos / Próximos / Al día), el botón "Nuevo recordatorio" y
  los completados plegados.
- **Estado:** vencido / próximo / al día, en color con icono y texto,
  calculado en cada lectura (nunca guardado): vence el primero de los dos, km
  o tiempo; el aviso anticipado es el de Ajustes o el propio del
  recordatorio.
- **Criterio aplicado:** el usuario puede apartarse de la referencia con un
  motivo; las dos se ven siempre, con la etiqueta **Menos exigente** si el
  aplicado lo es. **Posponer** solo esta vez, con motivo. Todo queda en el
  historial del recordatorio.
- **Cerrar:** solo con una entrada, de forma explícita: el campo **Cierra el
  recordatorio** del formulario de entradas (mantenimiento, reparación,
  vencimiento legal, gasto) o **Marcar hecho** en el detalle, que crea la
  entrada. El ancla es una copia de la fecha y los km de la entrada.
- **Previsto (13b):** los vencimientos **por tiempo** generarán una
  **notificación** del teléfono en la fecha prevista (incluso con la app
  cerrada), con un enlace directo al recordatorio. Los vencimientos **por km**
  no pueden "saltar" solos (la app no conoce los km en tiempo real): se
  señalan en la app, con el distintivo y los colores, al abrirla y al
  actualizar el cuentakilómetros.
- **Previsto (14+):** los documentos del propietario y del vehículo con
  vencimiento, y los controles con medición con **umbral**, que avisarán
  cuando el último valor baje del umbral.

## Informes

### Informes de la ficha del vehículo (paso 12)

Una pestaña **Informes** en la página del vehículo, entre Kilometraje y
Documentos (`?tab=reports`). Solo lectura, sin botón flotante; igual en un
vehículo archivado. Todo se calcula al momento con las entradas y lecturas:
nada se guarda.

- **Filtro común**, arriba, con dos modos excluyentes (control segmentado):
  - **Fechas**: Todo (por defecto), 12 meses, 90 días (los dos terminan hoy,
    incluido) o Personalizado, con dos selectores de fecha ("Desde",
    "Hasta"; uno vacío deja ese extremo abierto).
  - **Cuentakilómetros**: dos valores del cuentakilómetros en la unidad de
    distancia elegida, rellenados con la primera y la última lectura del
    vehículo.

  El filtro es estado de la pantalla: dura mientras la página del vehículo
  está abierta y no es un ajuste.
- Un **tramo de consumo pertenece al filtro** solo si sus dos repostajes, el
  que lo abre y el que lo cierra, caen dentro (por fecha o por km). Un tramo
  que cruza el borde queda fuera: no se reparte, porque sería suponer.
- **Consumo** (no en los vehículos eléctricos): resumen con el consumo medio,
  el coste medio por distancia, la cantidad total, el gasto total y el número
  de tramos válidos, más la **línea de cobertura** "Media calculada sobre X
  km (N días) de los Y km (M días) del tramo". X y N suman solo los tramos
  válidos del filtro. Y es el tramo real del filtro: en modo cuentakilómetros,
  exactamente el rango escrito, recortado a la primera y la última lectura
  del vehículo; en modo fechas, del primer al último repostaje de ese
  carburante dentro del filtro, tengan o no cantidad. M son los días entre
  el primer y el último repostaje de ese carburante dentro del filtro (en los
  dos modos). La diferencia Y − X es justo lo que no se pudo calcular: nada
  se estima ni se interpola. Debajo, la lista de tramos, el más reciente
  arriba: fechas de apertura → cierre, consumo, km, cantidad, importe y el
  estado (válido, no calculado con su motivo, o muy distinto de la media en
  ámbar), siempre con icono y texto. En un bifuel, unos chips cambian entre
  las dos cadenas. Tocar un tramo abre el repostaje que lo cierra.
- **Gasto en carburante**: gasto total, número de repostajes, precio medio
  por unidad (en un bifuel, uno por carburante: no se mezclan €/L y €/kg) y el
  gasto por mes en una tabla (sin gráfico), de todos los repostajes del
  filtro con importe, estén o no en una cadena. En un eléctrico, sin precio
  por unidad.
- **Distancia frente a tiempo**: con las lecturas del cuentakilómetros del
  filtro, la distancia, los días, la distancia por día y por mes, y la lista
  de lecturas con la distancia y los días desde la anterior. Varias lecturas
  del mismo día cuentan como una (la última); con un solo día no se divide
  entre cero (se muestra "—"). El nombre no dice "km" porque la distancia se
  muestra en la unidad elegida.
- Todo pasa por el formateador de unidades y los importes por el formato de
  moneda del idioma.

### Informes en PDF

*Previsto, no implementado todavía (paso 14 o posterior), sobre los informes
de la ficha.*

Todos los informes ofrecerán la opción **incluir / excluir imágenes** y, donde
corresponda, **incluir / excluir importes**. La exportación de referencia es
en **PDF** (adecuado para imprimir, enviar o entregar a un comprador).

Informes previstos:

- **Gastos** — por vehículo, por periodo, con totales. Incluye los gastos de
  los mantenimientos (ver abajo) y los gastos genéricos.
- **Entradas por tipo** — solo mantenimientos, solo repostajes, etc.; con la
  opción de incluir o no los importes.
- **Consumo de combustible** — el de la pestaña Informes (detalle del cálculo
  en `04_maintenance_logic.md`).
- **Km recorridos frente a tiempo** — basado en el historial de kilometraje
  (`MileageReading`), como la pestaña Informes.
- **General** — TODA la información de un vehículo en un único documento.
  Pensado como registro completo para la reventa / cambio de titularidad. Es
  un punto fuerte de la app.

Los informes en PDF podrán generarse para **un** vehículo o para **varios**
vehículos.

## Gastos dentro del mantenimiento

*Previsto, no implementado todavía.*

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

## Archivo

Vehículos vendidos, desguazados, robados… (paso 10 de la hoja de ruta).
Reglas de datos en `02_data_model.md` ("Archivo de vehículos").

- **Lista de vehículos:** solo los activos. Cuando hay al menos un vehículo
  archivado (y no en la papelera), una única fila discreta al final,
  "Archivados (n)", con el icono de archivo, abre la lista de archivados;
  sin archivados no hay fila. Como los "chats archivados" de una app de
  mensajería.
- **Lista de archivados** (ruta `/vehicles/archived`, sin botón de añadir):
  la misma fila que la lista principal más un chip con el motivo y el mes
  ("Vendido · mar 2026") y, si lo hay, los km finales. Tocar abre la ficha
  normal en solo lectura. Los más recientes primero.
- **Ficha archivada:** un banner gris fijo bajo la barra, con el icono de
  archivo: "Archivado el 12 mar 2026 · Vendido · 184.300 km" (sin km cuando
  no los hay; la nota en una segunda línea) y el botón **Reactivar**, sin
  confirmación. Todo se ve (entradas, lecturas, documentos, detalle), pero
  no hay ningún botón de añadir, editar ni borrar: ni el FAB, ni el lápiz,
  ni las acciones de las lecturas, ni la selección o el menú de borrar de
  los adjuntos (quedan Compartir y Guardar en…), ni editar / borrar en la
  entrada. El menú ⋮ conserva **Mover a la papelera**. Un enlace directo a
  un formulario de un vehículo archivado muestra "Este vehículo está
  archivado…".
- **Ficha activa:** el menú ⋮ ofrece **Archivar** (y Mover a la papelera,
  que sale del icono de la barra). El diálogo pide motivo (obligatorio,
  "Ninguno" por defecto), fecha (hoy por defecto, nunca futura), km finales
  (opcional, rellenado con la última lectura; vacío si no hay) y nota. Los
  km se validan como en "Actualizar km", con los mismos mensajes
  (`validationReadingKmBelowLast`, `validationReadingDateOutOfRange`) y la
  misma confirmación de salto grande; un rechazo del repositorio se muestra
  dentro del diálogo, que sigue abierto. Toast "Vehículo archivado" /
  "Vehículo reactivado".
- **Ficha del propietario:** sus vehículos activos y, si tiene archivados,
  una sección plegable "Archivados (n)" al final, cerrada por defecto, con
  el chip de cada uno. Un propietario con vehículos archivados sigue sin
  poder borrarse.
- Color solo para el estado, siempre con icono y texto; todo en los tres
  idiomas.

## Adjuntos

Fotos y documentos de las entradas, los vehículos y los propietarios (paso 8
de la hoja de ruta). Datos, límites y borrado en `02_data_model.md`
("Attachment").

- **Añadir:** siempre con una hoja inferior con **Cámara**, **Galería** y
  **Archivo**. Cámara y galería con `image_picker` (en Android 13+ el
  selector de fotos del sistema, sin permiso de almacenamiento; el permiso de
  cámara lo pide el sistema la primera vez y, si se deniega, un mensaje
  claro lo explica). Archivo con el selector de archivos del sistema. Más de
  25 MB → mensaje y no se añade.
- **Ver imágenes:** visor a pantalla completa con zoom con los dedos y
  deslizamiento entre las imágenes de la misma entrada, vehículo o
  propietario; "2 de 5" arriba; la descripción abajo (tocarla la edita, o
  "Añadir una descripción"); acciones **Compartir**, **Guardar en…** y
  **Eliminar** (con Deshacer). Las miniaturas se dibujan con `Image.file` al tamaño en que se
  ven (`cacheWidth`), sin archivos de miniatura.
- **PDF y otros:** se abren con la app del teléfono (`open_filex`); si no hay
  ninguna, un mensaje. Su fila tiene un menú con **Compartir**, **Guardar
  en…**, **Editar descripción** y **Eliminar**.
- **Guardar en…:** el diálogo "guardar como" del sistema con el nombre
  original del archivo; la copia es en streaming (ver `05_sync_and_storage.md`).
  Con varios adjuntos seleccionados, el usuario elige una **carpeta** (del
  teléfono o de un proveedor como Drive, si lo permite) y cada archivo se
  copia en ella con su nombre; si ya existe uno igual, Android añade " (1)"
  en lugar de sobrescribirlo. Después, "N archivos guardados".
- **Compartir:** la hoja de compartir del sistema (WhatsApp, correo…) con
  uno o varios adjuntos, con su nombre original. La app solo da acceso de
  lectura a una copia de esos archivos, nunca a la carpeta de adjuntos.
- **Archivo no encontrado:** un adjunto cuya fila existe pero cuyo archivo
  falta muestra ese texto en lugar de la miniatura o del tamaño.

Pantallas:

- **U22 — Formulario de la entrada** (crear y editar): sección "Adjuntos"
  con las miniaturas, una casilla para añadir y un botón para quitar cada
  uno. Al crear, lo elegido espera en el *staging* hasta guardar; al editar,
  lo añadido también espera y lo quitado se borra (lógicamente) al guardar.
  Cancelar descarta lo elegido. Mientras se copian los archivos se ve un
  indicador de progreso y Guardar espera.
- **U23 — Detalle de la entrada:** tarjeta "Adjuntos (n)" con el botón
  de icono "Añadir adjunto": miniaturas en cuadrícula para las imágenes y filas para
  los PDF / otros (icono, nombre, tamaño y día). Tocar abre.
- **U24 — Fila del historial:** un clip con el número de adjuntos cuando la
  entrada tiene alguno.
- **U25 — Página del vehículo:** pestaña nueva **Documentos** después de
  Kilometraje (Historial, Kilometraje, Documentos, Ficha; `?tab=documents`;
  desde el paso 12, Informes va entre Kilometraje y Documentos).
  En esa pestaña el botón flotante es "Añadir documento". Lista los adjuntos
  del propio vehículo (permiso de circulación, póliza, inspección…), con las
  mismas acciones. Las pestañas se desplazan si no caben (texto grande).
- **U26 — Ficha del propietario:** tarjeta "Documentos (n)" con la misma
  lista y el botón de icono "Añadir documento".
- **U27 — Copia de seguridad:** debajo de la fecha de la última exportación,
  "N adjuntos, 123 MB" (todos los archivos que llevará el paquete, también
  los de adjuntos borrados).
- **U28 — Diseño:** Material 3, zonas táctiles de al menos 48 dp, modo
  oscuro (el visor siempre sobre negro), texto grande y 360 dp de ancho;
  indicadores de progreso al elegir, guardar y exportar.
- **U29 — Selección múltiple**, igual en el detalle de la entrada, la
  pestaña Documentos del vehículo y los documentos del propietario (no en el
  formulario de la entrada, que tiene su propio botón para quitar):
  - Una **pulsación larga** sobre una miniatura o una fila activa la
    selección con ese adjunto marcado. Después, cada toque marca o desmarca
    (no abre); al desmarcar el último se sale. Las miniaturas marcadas se
    encogen un poco y llevan una marca; las filas muestran una casilla en
    lugar del menú.
  - La barra superior se convierte en barra contextual: **✕** (salir),
    "N seleccionados", **Seleccionar todo**, **Compartir**, **Guardar en…**
    y **Eliminar**. Atrás sale de la selección, no de la página. En la
    pestaña Documentos se oculta el botón flotante, y cambiar de pestaña
    sale de la selección.
  - **Eliminar** pide una sola confirmación ("¿Eliminar N adjuntos?"; con
    uno solo, con su nombre) y ofrece un único Deshacer. Compartir, guardar
    (si se guardó algo) y eliminar terminan la selección.

Pendiente: foto de perfil del vehículo y del propietario, y los datos propios
de los documentos (tipo, número, vencimiento) para los recordatorios.
