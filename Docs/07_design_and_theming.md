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

### Coherencia claro/oscuro en las imágenes

La app muestra fotos (vehículos, documentos, entradas). Las miniaturas deben
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
