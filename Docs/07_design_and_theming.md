# 07 — Diseño y temas

Este documento fija las decisiones de aspecto y de interacción de la app, antes
del código, de forma coherente con los demás documentos. El principio guía
sigue siendo el del concepto: **la rapidez de uso ante todo** (ver
`01_concept_overview.md`).

## Sistema de diseño: Material 3

La app adopta **Material 3** (Material You), el sistema de diseño nativo de
Flutter. Elección motivada por el tipo de app — un registro con muchas listas,
formularios de introducción de datos y datos — para el que Material 3 ofrece
gratuitamente componentes coherentes (listas, campos, selectores de fecha,
diálogos, resaltados) y una gestión integrada y bien estudiada de los temas
claro/oscuro. No se construye un sistema de diseño desde cero: sería trabajo
desperdiciado para una app utilitaria como esta.

## Tema claro / oscuro

- Se definen dos temas: **claro** y **oscuro**.
- El **predeterminado sigue al sistema operativo** (modo "Sistema").
- En los Ajustes el usuario puede elegir entre tres opciones: **Sistema**,
  **Claro**, **Oscuro**. Aunque el predeterminado siga al SO, la elección
  manual debe estar siempre disponible.
- La preferencia se guarda entre los ajustes de la app (ver
  `06_settings_and_i18n.md`).

## Color

- Se define **un único color "semilla" (seed color)** y se deja que Material 3
  genere a partir de él ambas paletas (clara y oscura), automáticamente
  armoniosas y con contrastes correctos. No se eligen decenas de colores a
  mano.
- La semilla aporta carácter sin ser invasiva. Elegida: **azul profundo**,
  valor inicial `#1F4E8C` (`Color(0xFF1F4E8C)`), definido una sola vez como
  constante documentada. Es fácilmente modificable porque todo deriva de la
  semilla.

## Principios de diseño específicos de la app

Importan más que la elección de los colores:

### La legibilidad ante todo

La app está llena de números (km, litros, costes, fechas, vencimientos). Hace
falta una jerarquía tipográfica clara y un espaciado adecuado. En la lista de
las entradas, los datos clave (tipo, fecha, km, coste) deben saltar a la vista
**sin** tener que abrir el detalle.

### Color con significado, no decorativo

El color se reserva para los **estados**, en particular los vencimientos:

- vencimiento vencido → rojo
- vencimiento próximo → ámbar
- todo en orden → verde

Coherente con la lógica de resaltado de los vencimientos por km descrita en
`03_features.md` y `04_maintenance_logic.md`.

**Nunca confiar solo en el color:** acompañarlo siempre de un icono o de un
texto, tanto por accesibilidad (daltonismo) como porque en el modo oscuro la
representación de los colores cambia.

**Patrón para un estado: la tarjeta teñida.** Cuando una pantalla responde
"¿cómo está esto?", la respuesta va en una tarjeta teñida del color del
estado (fondo y borde del color con poca opacidad, texto en el color del
estado, icono siempre) con la palabra del estado en la primera línea y el
dato decisivo como cifra grande debajo. Primer uso: la tarjeta de estado del
detalle de un recordatorio (`08_recordatorios.md`).

### Colores de acción

Regla para toda la app: **cada acción se pinta con el color de su
significado, no de su nombre**, allí donde se enumeran acciones (historial de
un recordatorio, filas de la papelera, sus botones).

| Significado | Color | Acciones |
| --- | --- | --- |
| Nace | primario | crear, cargado del manual |
| Se cumple | el verde de "al día" | cerrado, marcado hecho, completado, restaurado de la papelera |
| Se aplaza | el ámbar de "pronto" | pospuesto, aplazamiento quitado |
| Cambia la regla | terciario | personalizado, referencia restaurada, editado |
| Desaparece | error | eliminado, borrado definitivamente |

Siempre **icono + palabra de la acción en su color y peso medio + el resto de
la línea en el color normal** ("✓ **Hecho** · 3 nov 2026 · 200.000 km");
nunca el color solo. En el código, `ActionMeaning`, `actionColor` y
`ActionLabel` (`lib/shared/widgets/action_label.dart`).

### Una tarjeta por pregunta

Las pantallas de detalle se ordenan por las preguntas que se hace quien las
abre: **una tarjeta por pregunta, la más importante arriba**, y **sin
etiquetas que repitan lo que el valor ya dice** (una fecha no necesita la
etiqueta "Fecha" ni unos km la etiqueta "Cuentakilómetros"). Una etiqueta
pequeña en mayúsculas solo nombra la pregunta de la tarjeta ("ÚLTIMA VEZ").
Las tarjetas usan `surfaceContainer`, radio de 16 dp y 20 dp de separación;
lo secundario (como un historial) va plegado. Primer uso: el detalle y el
formulario de los recordatorios (versión 0.13.1).

### Arquetipos

Desde la versión 0.13.2 las piezas con las que se construyeron las pantallas
de recordatorios viven en `lib/shared/widgets/` y son el canon de **toda
pantalla nueva o rehecha**. Hay cuatro tipos de pantalla:

- **Detalle.** Un `ListView` con 20 dp a los lados y entre bloques: una
  cabecera (icono en círculo, dos líneas), la **tarjeta de estado**
  (`StatusCard`, una `AppCard` teñida con la palabra del estado y su icono
  en `StateLine.heading`, la cifra decisiva grande y una línea gris, o dos
  columnas con `StatusCard.twoAxes`), una `AppCard` por pregunta con su
  `SectionLabel` (y un `AppChip` al final de la etiqueta si hace falta), lo
  secundario plegado, y el historial en filas `HistoryLine` (un
  `ActionLabel` con el resto de la línea y un paréntesis opcional).
- **Formulario.** `SingleChildScrollView` + `Column` con 20 dp a los lados y
  entre secciones; cada sección es una `FormSection` (una `AppCard` con su
  `SectionLabel` y los campos uno bajo otro, 16 dp entre ellos). Guardar va
  en la barra.
- **Lista.** `ListSections`: una cabecera de sección (`SectionHeader`) y
  sus filas `ListRow` (icono en círculo de 40 dp, título, segunda línea
  —normalmente una `StateLine`—, tercera línea gris, etiquetas `AppChip`
  apiladas a la derecha; alto mínimo 72 dp, 16 dp a los lados, sin
  separadores, 4 dp entre filas), con una sección plegada al final si la
  hay. Sin nada que listar, un `EmptyState` (icono, frase y una segunda
  línea gris opcional).
- **Diálogo.** `ActionDialog`: el título es el verbo; arriba una frase gris
  de contexto; los campos; el motivo siempre el último; debajo, si hace
  falta, una línea gris que dice qué cambia, y el error del rechazo; botón
  principal con el verbo y "Cancelar".

| Widget | Qué es |
| --- | --- |
| `AppCard` | Tarjeta de 16 dp de radio y 16 dp de relleno sobre `surfaceContainer`; con tinte (`AppCardTint.ok / dueSoon / overdue / neutral`), fondo al 10 % y borde al 35 % del color del estado, texto e iconos en el color |
| `SectionLabel` | Etiqueta pequeña en mayúsculas (`labelSmall`, espaciado 0,8, `onSurfaceVariant`), con un widget opcional al final |
| `StatusCard` | La tarjeta teñida de "¿cómo está esto?": palabra del estado con icono, cifra grande (`headlineMedium` 600) y línea gris; o dos ejes (`twoAxes`) |
| `StateLine` | Icono de 16 dp + texto en el color del estado (fila); `heading` = icono de 20 dp + `titleSmall` 600 (tarjeta) |
| `AppChip` | Etiqueta pequeña con icono opcional; variantes `neutral`, `warning` (ámbar de "pronto" al 14 %), `info` (primario al 14 %) |
| `ListRow` | Fila de lista: círculo de 40 dp, título, segunda y tercera línea, etiquetas a la derecha; mínimo 72 dp |
| `ListSections` | Lista por secciones con cabeceras y una sección plegada opcional con su recuento |
| `EmptyState` | Vista vacía: icono, frase, segunda línea gris y botón opcionales (también la de error y la de "no existe") |
| `ActionLabel` | Icono + palabra de la acción en el color de su significado + el resto en color normal |
| `HistoryLine` | Una fila de historial: `ActionLabel` + resto + paréntesis opcional |
| `ActionDialog` | Diálogo de una acción: verbo, contexto, campos, motivo, nota, error, botones |
| `FormSection` | Sección de formulario: `AppCard` con `SectionLabel` y campos a 16 dp |

Reglas:

- Un widget recibe **roles del tema**, nunca colores literales: todo color
  sale de `ColorScheme` o de los tres colores de estado (`StatusColors`, la
  extensión de tema de `lib/app/theme/status_colors.dart`).
- **Una pantalla nueva o rehecha usa estos widgets; si uno no sirve, se
  amplía el widget, no se copia.**
- Los valores de este documento son los del código: donde difieran, manda
  el código y se corrige el documento.

### Coherencia claro/oscuro en las imágenes

La app muestra fotos (documentos y entradas; las fotos de perfil de los
vehículos y propietarios están pendientes). Las miniaturas deben
tener un fondo/contenedor que funcione en ambos temas, y el posible texto
superpuesto debe seguir siendo legible en claro y en oscuro.

### Acción "añadir" siempre a mano

Dado que el principio guía es la rapidez de introducción, añadir una entrada
debe ser inmediato y estar siempre accesible (botón flotante de Material —
FAB — o equivalente siempre visible en las pantallas pertinentes).

## Accesibilidad (mínimos que respetar)

- Contrastes suficientes en ambos temas (Material 3 ayuda, pero hay que
  verificarlo en los colores de estado).
- Información nunca transmitida solo mediante el color.
- Tamaños de toque adecuados y texto escalable.
