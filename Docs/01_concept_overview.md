# 01 — Visión general

## Qué es

Aplicación móvil (Android en primer lugar, construida con Flutter y por tanto
preparada también para iOS en el futuro) para llevar el **historial completo de
uno o varios vehículos**: mantenimientos, reparaciones, repostajes, controles,
gastos, vencimientos legales y documentos.

No es una app "conectada al vehículo" (sin OBD, sin diagnóstico): es un
**registro digital** llevado a mano, pensado para sustituir el clásico
cuaderno de mantenimiento y la caja de recibos.

## A quién sirve

- A un **único usuario** (la app es monousuario) que usa la app desde su propio
  teléfono.
- Ese usuario puede gestionar **varios vehículos**, no solo el suyo: también
  coches de familiares o de personas cuyas cuentas lleva. Por eso cada vehículo
  está vinculado a un **propietario** (ficha propia).

## Qué problema resuelve

- Saber siempre **qué se ha hecho** en un vehículo y **cuándo** (fecha + km).
- Saber **qué hay que hacer** y **cuándo vence** (mantenimiento programado,
  impuesto de circulación, inspección técnica obligatoria, seguro, documentos
  personales).
- Saber **cuánto se ha gastado** (por vehículo, por tipo, por periodo).
- Poder **demostrar** el historial de mantenimiento del vehículo — útil para la
  reventa o el cambio de titularidad — mediante un informe completo
  exportable.
- Tenerlo todo **a salvo**: los datos viven en el teléfono y pueden copiarse
  en la nube (Google Drive) para recuperarlos en otro teléfono.

## Principio guía (el más importante)

**La rapidez de uso ante todo.** Las apps de este tipo se abandonan
rápidamente cuando la introducción de datos es lenta o engorrosa. Cada función
potente (consumos, vencimientos automáticos, controles con medición) debe
seguir siendo *opcional* y no hacer más pesada la introducción diaria de una
entrada. Registrar un repostaje o un mantenimiento debe requerir pocos toques;
los detalles avanzados están en secciones desplegables, nunca obligatorias
donde no tienen sentido.

## Límites de la versión 1 (lo que NO hacemos)

Para mantener la simplicidad y no depender de servicios externos, la primera
versión **excluye**:

- Llamadas a revisión de seguridad / recall del fabricante (requieren bases de
  datos comerciales, a menudo solo para el mercado de EE. UU.).
- Estimación de costes de reparación y búsqueda de talleres cercanos (servicios
  de terceros).
- Diagnóstico OBD / conexión a la centralita.
- Vehículos eléctricos (por ahora se razona sobre motores térmicos de
  gasolina/diésel; sin embargo, la estructura no debe hacerse tan rígida que lo
  impida en el futuro).

## Las secciones de la app

1. **Lista de vehículos** — con foto, nombre/matrícula.
2. **Ficha del vehículo** — datos generales, especificaciones de fábrica, km
   actual.
3. **Historial de entradas** — la lista desplazable de todo lo que ha sucedido.
4. **Documentos** — permiso de circulación, seguro, etc. (estado actual, no
   eventos).
5. **Vencimientos / recordatorios** — manuales y automáticos a partir de los
   datos de fábrica.
6. **Informes** — gastos, por tipo, consumos, general.
7. **Ajustes** — idioma, nube/copia de seguridad.
8. **Registro de propietarios** — personas y sus documentos personales.

El detalle de cada sección está en los documentos siguientes.
