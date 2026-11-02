# 04 — Lógica de mantenimiento

Este es el documento más "de dominio": reúne todas las reglas de cálculo y de
comportamiento de la parte de mantenimiento. Las decisiones aquí derivan
también del análisis de los manuales reales del Fiat Grande Punto y del Toyota
Yaris Hybrid.

**Qué está implementado.** Los repostajes y su consumo (paso 12) y el
historial de kilometraje (pasos 5 y 10). El catálogo de mantenimiento, los
criterios por vehículo, los frenos por eje, el control frente a sustitución,
los controles con medición y los intervalos de fábrica son **diseño previsto,
no implementado todavía** (paso 14 o posterior).

## Catálogo de tipos de mantenimiento (MaintenanceType)

*Previsto, no implementado todavía (paso 14 o posterior).*

Lista común, agrupada por familia para encontrarla fácilmente cuando crece.
Precargada con las entradas más comunes, y modificable por el usuario.

- **Fluidos**: aceite de motor, aceite de caja de cambios manual, aceite de
  caja de cambios automática, líquido de frenos, líquido refrigerante
- **Filtros**: filtro de aire, filtro antipolen/habitáculo, filtro de
  combustible
- **Neumáticos**: neumáticos, **rotación/permuta de neumáticos**,
  **alineación/convergencia**
- **Batería**: batería de 12V (control y sustitución)
- **Motor**: bujías, correa de distribución, correa de accesorios
- **Frenos**: frenos delanteros, frenos traseros (ver sección dedicada)
- **Otro**: entradas libres añadidas por el usuario

**Motos y ciclomotores tienen su propio camino.** El vehículo tiene un tipo
(coche, furgoneta, moto, ciclomotor; ver `02_data_model.md`), y el futuro
catálogo de mantenimiento marcará cada tipo de mantenimiento con los tipos de
vehículo a los que se aplica: por ejemplo la cadena de transmisión o el
reglaje de válvulas para las motos, y no para los coches. La lógica de frenos
por eje sigue valiendo en las motos como delantero / trasero. Esto aún no está
implementado: hoy el tipo de vehículo solo filtra el catálogo de marcas y
modelos.

Los dos manuales confirman la estructura: el Punto usa intervalos por km **y**
por tiempo con la regla "vence el primero de los dos" (p. ej. aceite de motor
en cada servicio de mantenimiento *o bien* cada 24 meses, 12 meses si pocos
km/ciudad; correa de distribución cada 4–5 años independientemente de los km);
el Yaris remite muchos intervalos a un libro de mantenimiento separado y a
veces proporciona un solo criterio (solo km o solo tiempo). Por tanto, la
estructura debe admitir: solo km, solo tiempo, o ambos.

## Criterio configurado por vehículo (MaintenanceRule)

*Previsto, no implementado todavía (paso 14 o posterior).*

Asignar un criterio a un vehículo significa tomar un tipo del catálogo y darle
los intervalos de *ese* vehículo:

- Vencimiento en km (opcional)
- Vencimiento en tiempo en meses (opcional)
- Si están presentes ambos → **vence el primero que se cumpla**
- Última intervención conocida (fecha + km) → base para calcular el próximo
  vencimiento

Un tipo ya asignado a un vehículo **no vuelve a aparecer** entre las opciones
para el mismo vehículo, así no se crean duplicados. Sigue disponible para los
demás vehículos.

### Cómo saltan los vencimientos

- **Por tiempo**: calculable en el tiempo → genera una notificación en la fecha
  prevista.
- **Por km**: la app no conoce los km en tiempo real, por lo que no puede
  notificar por sí sola. Las entradas con vencimiento por km se **resaltan** al
  abrir la app y al actualizar el cuentakilómetros total, comparando el umbral
  con el km actual del vehículo.

## Frenos (lógica por eje)

*Previsto, no implementado todavía (paso 14 o posterior).*

Modelo: **eje → tipo de sistema → componentes, cada uno con su propio
vencimiento.**

- Un freno pertenece a un **eje**: delantero o trasero. Se puede actuar sobre
  un solo eje o sobre ambos.
- Para cada eje se indica el **tipo de sistema**:
  - de **disco** → componentes: **pastillas** (se desgastan) + **disco** (dura
    más)
  - de **tambor** → componentes: **zapatas** (se desgastan) + **tambor** (dura
    más)
- Cada componente tiene **su** vencimiento independiente, en km y/o tiempo. La
  pastilla se sustituye más a menudo que el disco; la zapata más a menudo que
  el tambor.
- El componente "contenedor" (disco/tambor) solo existe si existe el que se
  desgasta (no tiene sentido un disco sin pastilla).

En los manuales los frenos aparecen como **control de desgaste** en cada
servicio de mantenimiento, no como sustitución con vencimiento fijo: por eso la
distinción control frente a sustitución (abajo) se aplica también aquí.

## Control frente a sustitución

*Previsto, no implementado todavía (paso 14 o posterior).*

Son dos cosas distintas y complementarias, ambas registrables:

- **Sustitución** — he cambiado un componente. Pone a cero el contador del
  criterio y reinicia el vencimiento.
- **Control** — he inspeccionado. No pone nada a cero. Puede ser:
  - **con medición** (ver abajo)
  - **genérico no clasificado** (solo nota libre)

## Control con medición

*Previsto, no implementado todavía (paso de las mediciones).*

Registra un valor numérico inspeccionado en una fecha/km determinados,
construyendo un **historial de valores** en el que se ve la tendencia (p. ej.
dibujo del neumático 7 → 5 → 3 mm).

- Magnitud (dibujo del neumático, grosor de las pastillas, tensión de la
  batería, ...)
- Valor + unidad (mm, V, ...)
- **Umbral de alarma** opcional: si el último valor baja del umbral, la app
  avisa. Útil para anticipar una sustitución antes de que salte un
  vencimiento fijo.

## Repostajes y consumos

Desde el paso 12 (esquema v10). El consumo **se deriva, nunca se guarda**: se
calcula de nuevo con los repostajes cada vez que se muestra, así que corregir
un repostaje corrige al momento todo lo que depende de él.

### Campos de un repostaje

Además de la fecha, el km del cuentakilómetros (obligatorio en un repostaje),
el importe (el coste de siempre) y la descripción:

- **Carburante.** Lo decide el tipo de combustible del vehículo:

  | Combustible del vehículo | Cadenas | Elección en el formulario | Cantidad en |
  | --- | --- | --- | --- |
  | Gasolina, diésel, otro | una | no | volumen (L o galones según los ajustes) |
  | Híbrido, híbrido enchufable | una, de gasolina | no | volumen |
  | Gasolina + GLP | dos | gasolina / GLP | volumen |
  | Gasolina + GNC | dos | gasolina / GNC | gasolina en volumen; **GNC en kg** (sin conversión) |
  | Eléctrico | ninguna | — | — |

  En un eléctrico un repostaje es solo un gasto: el formulario no enseña
  ningún campo de carburante y no hay informe de consumo.
- **Cantidad** (opcional): litros, o kg con GNC. Sin cantidad, el repostaje
  cuenta como gasto y queda fuera de la cadena (no es un error).
- **Depósito lleno** (por defecto, sí). Sin cantidad se ignora para la
  cadena.
- **Me salté un repostaje antes de este** (por defecto, no): el usuario no
  registró el repostaje anterior, así que el tramo al que pertenece este no
  se puede calcular.
- **Precio por unidad**: solo en el formulario, **nunca se guarda**. Importe,
  cantidad y precio forman un triángulo: se escriben dos cualesquiera y el
  tercero se calcula al momento y sigue siendo editable. Al cambiar uno se
  recalcula el que no está entre los dos tocados más recientemente. El
  precio se muestra por la unidad que ve el usuario (€/L, €/gal, €/kg) y se
  calcula desde los valores en SI.

### La cadena de llenos

- Un **tramo** va de un repostaje con depósito lleno al siguiente repostaje
  con depósito lleno **del mismo carburante**, en orden cronológico (fecha y,
  en el mismo día, el creado antes). Solo un lleno **con cantidad** abre o
  cierra un tramo.
- **Km del tramo** = km del cuentakilómetros del repostaje que lo cierra − km
  del que lo abre. Son los km que ya pide cada repostaje: no hay km parciales
  ni cuentakilómetros parcial.
- **Cantidad del tramo** = la del repostaje que lo cierra **más la de todos
  los repostajes parciales** de ese carburante entre los dos. La cantidad del
  repostaje que lo abre pertenece al tramo anterior.
- **Días del tramo** = días entre las dos fechas.
- **Consumo** = cantidad ÷ km (L/100 km por dentro), mostrado con el ajuste de
  consumo: L/100 km, km/L, mpg EE. UU. o mpg imperial; el GNC en kg/100 km o
  km/kg según la forma del ajuste (con mpg, km/kg).
- **Coste por distancia** = suma de los importes de esos mismos repostajes ÷
  km, en € por 100 km (o € por milla con la distancia en millas). Si a alguno
  le falta el importe, el coste del tramo no se calcula (una suma parcial lo
  subestimaría).
- **Tramo no calculable** (se lista, nunca entra en las medias): algún
  repostaje del tramo (sin contar el que lo abre) tiene marcado "me salté
  uno"; un repostaje entre los dos no tiene cantidad; a alguno le falta el
  km; los km no aumentan; la cantidad es 0. La app dice el motivo en una
  línea.
- **Tramo sospechoso** (en ámbar, sigue contando): cuando la cadena tiene al
  menos 3 tramos calculables y este se aleja más de un 40 % de la media de
  su cadena (todos sus tramos calculables, sin filtro). Nunca se excluye solo:
  la app sugiere revisar si faltó un repostaje.
- **Media del vehículo** = cantidad total ÷ km totales de los tramos
  calculables, no la media de los consumos de cada tramo.
- El primer lleno no tiene tramo: la app dice "A partir del siguiente lleno
  verás el consumo".
- Los repostajes registrados antes del paso 12 recibieron el carburante
  principal del vehículo y "depósito lleno", pero no tienen cantidad: no
  forman tramos hasta que el usuario los completa.

### Qué enseña la app

- **Al guardar un repostaje**, un único aviso (con la oferta de actualizar el
  cuentakilómetros si procede, o "Ver" para abrir el repostaje): el consumo,
  km, días y coste del tramo que cierra; o "A partir del siguiente lleno
  verás el consumo"; o, para un parcial, que se contará en el tramo del
  siguiente lleno; o por qué el tramo no se puede calcular.
- **En el detalle del repostaje**, lo mismo, y para un tramo sospechoso la
  línea ámbar "Consumo muy distinto de la media. ¿Faltó un repostaje?" con un
  enlace al formulario, donde se marca "me salté uno". Los informes nunca
  escriben.
- **En Informes** (ver `03_features.md`), el consumo, el gasto en carburante y
  la distancia frente al tiempo. El gasto total en carburante **sí** se
  calcula ahí: es una suma de importes que el usuario ya escribió, no un dato
  inventado.

### Los km de un repostaje y el historial de kilometraje

El km de un repostaje es el del cuentakilómetros total, como el de cualquier
entrada, y **no** alimenta el historial de kilometraje (`MileageReading`) ni el
km actual del vehículo: sigue valiendo la oferta explícita "¿Actualizar el
cuentakilómetros?" después de guardar. La cadena usa los km de las entradas;
el informe de distancia usa solo las lecturas.

## Kilometraje

### Km actual del vehículo

El vehículo tiene un "km actual" (último valor conocido del cuentakilómetros
total), usado para calcular los vencimientos por km. Lo actualiza
**manualmente** el usuario.

### Historial de kilometraje (MileageReading)

Registro independiente de las lecturas del cuentakilómetros total a lo largo
del tiempo, para el informe "km recorridos frente a tiempo". Reglas:

- Se actualiza **solo** cuando el usuario actualiza el cuentakilómetros total
  de forma explícita. El km escrito en cada entrada (mantenimientos,
  repostajes...) **no** entra aquí: se queda dentro de la entrada. Motivo: así
  un posible error en una entrada no queda encajado en medio de la serie, donde
  no podría corregirse con la regla "borrar solo la última".
- Una nueva lectura **no puede ser inferior** a la última válida (el
  cuentakilómetros no va hacia atrás): la app bloquea y lo señala.
- Un valor enormemente más alto (probable error tipográfico, p. ej. 850.000 en
  lugar de 85.000) **pide confirmación** antes de aceptarlo — no lo prohíbe,
  porque podría ser real.
- Solo se puede borrar **la última** lectura. Después del borrado la
  penúltima pasa a ser la última y a su vez se puede borrar
  (comportamiento "deshacer hacia atrás"). Nunca quitar lecturas intermedias:
  la serie se mantiene siempre coherente y creciente.

### Cómo funciona hoy (paso 5)

- **Lectura inicial:** cada vehículo empieza su serie con una lectura: el km
  escrito al crearlo, con la fecha de ese día (los vehículos anteriores al
  paso 5 la recibieron en la migración). Es la más antigua y **nunca se
  borra**: un vehículo siempre tiene al menos una lectura.
- **Nueva lectura:** fecha entre la de la última lectura y hoy (ambas
  incluidas); km igual o mayor que el de la última (igual se acepta). Lo
  aplica el formulario y también el repositorio.
- **Umbral de confirmación: 50.000 km.** Si la nueva lectura supera la
  última en más de 50.000 km, la app pregunta "¿Seguro? Son X km más que la
  última lectura, por encima del control de 50.000 km" antes de guardar.
  Nunca se prohíbe. La comparación es siempre en km; con la unidad en
  millas el diálogo enseña la cifra amigable "30.000 mi"
  (`06_settings_and_i18n.md`, "Unidades de medida").
- **Borrar:** solo la última, y nunca la inicial. El km actual vuelve a la
  lectura anterior. Se puede **deshacer** durante unos segundos, siempre que
  la lectura borrada vuelva a ser la última (si mientras tanto se ha añadido
  otra más reciente, se rechaza: "Ya hay una lectura más reciente") y el
  vehículo no se haya borrado.
- **Corregir:** solo mientras el vehículo tiene **una única lectura** (la
  inicial): se pueden corregir sus km y su fecha (no posterior a hoy). Las
  demás lecturas no se editan: se borran (de la última hacia atrás) y se
  vuelven a escribir.
- **Oferta desde las entradas:** el km de una entrada nunca entra solo en
  la serie. Después de guardar una entrada cuyo km supera el km actual,
  fechada hoy o antes y no antes de la última lectura, la app **ofrece**
  actualizar el cuentakilómetros con ese km y esa fecha; solo si el usuario
  pulsa "Actualizar" se crea la lectura (con la misma confirmación de los
  50.000 km).
- **Entradas con km demasiado alto para su fecha:** si alguna lectura de
  un día posterior a la fecha de la entrada tiene menos km que la entrada,
  es casi seguro un error (el cuentakilómetros no va hacia atrás): la app
  avisa y deja guardar igualmente. Basta con mirar la primera lectura
  posterior a esa fecha, que es la de menos km entre las posteriores; así
  también se detecta el error frente a lecturas intermedias, no solo frente
  a la última.
- **Fechas futuras por tipo:** solo vencimientos legales, gastos y notas
  pueden tener fecha futura; mantenimientos, reparaciones, repostajes y
  controles no (ver `02_data_model.md`).

## Especificaciones de fábrica del vehículo

En la ficha del vehículo se registran los datos recomendados por el
fabricante, usados como base para crear los criterios y como referencia:

- Tipo de combustible (implementado; decide los carburantes de sus
  repostajes)
- Aceite de motor recomendado (implementado, texto libre)
- Notas del fabricante (implementado, texto libre)
- Intervalos de mantenimiento aconsejados (en km y/o tiempo), que alimentarán
  las `MaintenanceRule` — *previsto, no implementado todavía*
