# 04 — Lógica de mantenimiento

Este es el documento más "de dominio": reúne todas las reglas de cálculo y de
comportamiento de la parte de mantenimiento. Las decisiones aquí derivan
también del análisis de los manuales reales del Fiat Grande Punto y del Toyota
Yaris Hybrid.

## Catálogo de tipos de mantenimiento (MaintenanceType)

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

Son dos cosas distintas y complementarias, ambas registrables:

- **Sustitución** — he cambiado un componente. Pone a cero el contador del
  criterio y reinicia el vencimiento.
- **Control** — he inspeccionado. No pone nada a cero. Puede ser:
  - **con medición** (ver abajo)
  - **genérico no clasificado** (solo nota libre)

## Control con medición

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

Cada repostaje es **autosuficiente**: contiene los datos para calcular el
consumo por sí solo, sin depender del repostaje anterior (método "por cada
lleno", no "rango entre dos llenos").

Campos:

- **Km recorridos** con ese lleno (del cuentakilómetros parcial/trip puesto a
  cero en cada lleno). NO es el cuentakilómetros total.
- **Litros**
- **Precio por litro** (introducido por el usuario)

Cálculos que hace la app:

- **Consumo** de cada repostaje = km recorridos ÷ litros. (Este cálculo lo
  hace la app; el total gastado NO se calcula automáticamente, por decisión.)
- Informe de **consumo medio** (total o por periodo).
- Informe de **gasto total en combustible** por periodo.

Atención a no confundir los dos tipos de km:

- **Km recorridos** (en el repostaje) → solo para el consumo. NO toca ni el
  cuentakilómetros total ni el historial de kilometraje.
- **Km total / cuentakilómetros total** (estado del vehículo) → para los
  vencimientos. Vive en `Vehicle.current_odometer_km` y en el historial
  `MileageReading`.

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

- Tipo de combustible
- Aceite de motor recomendado
- Intervalos de mantenimiento aconsejados (en km y/o tiempo), que alimentan las
  `MaintenanceRule`
