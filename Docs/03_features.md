# 03 — Funcionalidades

## Pantallas de vehículos y propietarios

Primera parte usable de la app (paso 3 de la hoja de ruta).

- **Inicio = lista de vehículos.** Una barra de navegación inferior con dos
  destinos: **Vehículos** y **Propietarios**.
- **Fila de la lista de vehículos:** matrícula, nombre común (si lo hay),
  nombre del propietario, km actual (con el formato del idioma) y tipo de
  combustible. Ordenada por matrícula. Si no hay vehículos, solo un texto
  breve: para añadir se usa el botón flotante, que nunca se duplica.
- **Añadir siempre a mano:** un botón flotante (FAB) en las dos listas (ver
  `07_design_and_theming.md`).
- **Formulario del vehículo:** matrícula, nombre común, propietario, tipo de
  combustible, km actual (**solo al crearlo**), aceite recomendado y notas del
  fabricante. El propietario se elige entre los existentes **o con "Nuevo
  propietario"**, que abre el formulario del propietario y vuelve con el
  nuevo propietario ya elegido. Si todavía no existe ningún propietario, el
  campo ofrece directamente "Nuevo propietario".
- **Editar un vehículo:** el mismo formulario sin el km actual. La ficha del
  vehículo muestra el km en solo lectura, con una nota breve: se cambia solo
  desde la función de cuentakilómetros (paso 5).
- **Formulario del propietario:** nombre (obligatorio), apellidos, fecha de
  nacimiento (selector de fecha de Material; fecha de calendario sin hora),
  nacionalidad, teléfono, email y notas.
- **Ficha del propietario:** muestra sus vehículos; al tocar uno se abre su
  ficha.
- **Validación** en línea bajo cada campo y traducida: matrícula
  obligatoria; matrícula duplicada (otro vehículo no borrado ya la usa)
  señalada en el propio campo; km obligatorio, número entero ≥ 0; nombre del
  propietario obligatorio. También son obligatorios el propietario y el tipo
  de combustible del vehículo.
- **Mensajes** (reglas de abajo): toast breve al guardar; al borrar, toast
  **con Deshacer** durante unos segundos; errores explícitos y lo bastante
  persistentes para leerlos. Borrar un propietario que todavía tiene
  vehículos muestra un mensaje explícito y no borra nada.
- **Deshacer un borrado** devuelve el registro borrado lógicamente. En el
  historial de operaciones queda como **restauración**. Si mientras tanto
  otro vehículo ha tomado la matrícula, o el propietario del vehículo se ha
  borrado, el deshacer se rechaza con un mensaje y no cambia nada.
- **Confirmación** con un diálogo antes de borrar (además del Deshacer),
  porque un vehículo lleva consigo todo su historial.
- Los **tipos de combustible** se muestran traducidos en los tres idiomas.

## Historial de entradas

Cada vehículo tiene una lista desplazable de LogEntry ordenadas por fecha (las
más recientes arriba). Cada fila muestra de un vistazo: tipo, fecha, km, un
extracto del texto, el coste (si lo hay) y un icono si hay fotos o un
recordatorio.

Al tocar una entrada se ve su detalle completo y se puede modificar o
borrar.

## Filtros y búsqueda

En el historial se puede filtrar por:

- **Fecha** (intervalo desde–hasta)
- **Tipo** de entrada (una o varias categorías)
- **Texto** (búsqueda libre en la descripción)

Los filtros son combinables. Deben poder activarse y restablecerse
rápidamente.

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
