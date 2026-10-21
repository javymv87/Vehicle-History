# 05 — Almacenamiento y sincronización

## Dos planos distintos

1. **Almacenamiento local** — la base de datos propiamente dicha, en el
   teléfono, en SQLite (a través de Drift). Es aquí donde la app lee y escribe
   normalmente. Las fotos son archivos guardados localmente, referenciados por
   la base de datos.

   El archivo de la base de datos (`vehicle_history.sqlite`) y las fotos viven
   en la **carpeta de soporte de la aplicación** (*application support*), no
   en la carpeta de documentos: en iOS esta última es visible para el usuario
   en la app Archivos y se copia en iCloud, y la única copia de seguridad de
   estos datos debe ser la de la propia app. Las rutas de las fotos se guardan
   relativas a esa carpeta.
2. **Copia de seguridad en la nube** — una copia de toda la base de datos + las
   imágenes, empaquetada y subida a Google Drive, para poder recuperarlo todo en
   otro teléfono. NO es una sincronización continua: es una copia de seguridad
   (backup) / restauración manual con alguna protección.

No hay que confundir el esquema de la base de datos local (doc 02) con el
archivo de copia de seguridad: son cosas distintas.

## Google Drive

- La copia de seguridad está pensada como **un único archivo** (o paquete) en
  el Drive de la cuenta vinculada, que lo contiene todo: datos + ajustes +
  imágenes.
- Cambio de teléfono / reinstalación: se vincula la misma cuenta, se descarga
  la copia de seguridad y se recupera todo — incluidos los ajustes generales.

## Vinculación de la cuenta (dos modalidades)

La app admite **dos formas** de vincular la cuenta de Google usada para la
copia de seguridad. El usuario elige; ambas llevan al mismo resultado (un token
que autoriza el acceso a Drive), pero con flujos distintos.

### Modalidad 1 — Cuenta del teléfono (sencilla, predeterminada)

- Usa el **selector de cuentas del sistema** (`google_sign_in`).
- Android muestra la lista de cuentas de Google ya presentes en el teléfono
  (la principal **y** las cuentas añadidas en Ajustes → Cuentas): el usuario
  elige una. No está obligado a usar la principal.
- Es el camino cómodo para la mayoría de los casos.

### Modalidad 2 — Vincular una cuenta manualmente (avanzada)

Para usar una cuenta que **no es** (y no debe pasar a ser) una cuenta del
teléfono: la usa **solo la app**.

- Flujo **OAuth 2.0 Authorization Code + PKCE**, a través de `flutter_appauth`.
- El inicio de sesión tiene lugar en el **navegador del sistema** (Android
  Custom Tab), en la página real de Google: el usuario escribe allí el email y
  la contraseña. También la verificación en dos pasos la gestiona Google.
- **La app nunca ve la contraseña**: solo recibe, al final, los tokens de
  acceso/refresh.
- La cuenta **no** se añade a nivel de Android: permanece interna a la app.

### Reglas de seguridad (válidas para ambas modalidades)

- **Nunca una WebView interna** para el inicio de sesión de Google: solo
  navegador del sistema/Custom Tab. Una WebView es menos segura y, en
  cualquier caso, Google la bloquea.
- Los **tokens** se guardan en el **almacén cifrado del sistema** (Android
  Keystore, a través de `flutter_secure_storage`), nunca en archivos o
  preferencias en claro.
- La app muestra siempre con claridad **qué cuenta está vinculada** a la copia
  de seguridad (p. ej. "Copia de seguridad vinculada a: usuario@gmail.com") con
  un botón para **cambiar de cuenta**.

### Cambio de cuenta = copias de seguridad separadas

La copia de seguridad de una cuenta y la de otra son **archivos distintos en
Drives distintos**: no se comunican. El cambio de cuenta debe tratarse como una
operación consciente, con un aviso explícito: "Estás cambiando la cuenta de la
copia de seguridad; la copia de seguridad anterior se queda en la cuenta
antigua."

### Nota administrativa (Google Cloud Console)

Ambas modalidades requieren que la app esté registrada en la **Google Cloud
Console** con la pantalla de consentimiento configurada para el ámbito (*scope*)
de Drive. La Modalidad 1 necesita además un ID de cliente OAuth para Android
(nombre del paquete + SHA-1 del certificado de firma); la Modalidad 2 utiliza,
además, el flujo a través del navegador con PKCE. El acceso a Drive conlleva un
proceso de **verificación de la app** por parte de Google. Mientras la app no
esté verificada funciona igual, pero muestra un aviso de "app no verificada" y
tiene un límite de usuarios de prueba — aceptable para uso personal / pocos
usuarios. La verificación solo se vuelve necesaria en caso de distribución
amplia. Es un paso administrativo, no de código, pero hay que planificarlo.

## Estrategia elegida: "Strada A" (vía A) — copia de seguridad/restauración con control de versión

Elección consciente de simplicidad (la app es monousuario). No hay fusión
automática de los datos: **una copia manda**. Para evitar que "fácil" se
convierta en "peligroso", se añade un control de versión (version guard)
ligero.

### Metadatos de versión

Tanto la base de datos local como la copia de seguridad en Drive llevan dos
datos ligeros:

- un **número de versión** que aumenta en 1 con cada modificación de la base de
  datos;
- la **fecha/hora de la última modificación**.

### Comprobación al abrir la app

Al arrancar, la app lee **solo estos dos metadatos** de la nube (no descarga
toda la base de datos) y los compara con los locales. Cuatro casos:

1. **Iguales** → sincronizado, ninguna acción.
2. **Nube más reciente que local** → mensaje: "En la nube hay una versión
   más reciente. ¿Quieres descargarla?" Si sí, la local se **sustituye**.
3. **Local más reciente que la nube** → mensaje: "Tienes cambios todavía no
   subidos. ¿Quieres subirlos?" Si sí, la nube se **sustituye**.
4. **Divergencia** (tanto la local como la nube modificadas respecto al último
   punto en común) → la app **avisa con honestidad**: "Atención: tanto este
   teléfono como la nube han cambiado. Si descargas pierdes los cambios
   locales; si subes sobrescribes los de la nube." Decide el usuario. Ninguna
   sobrescritura silenciosa, ninguna pérdida de datos a escondidas.

### Operaciones manuales

Además de la comprobación al arrancar, el usuario puede en cualquier momento:

- **Subir a la nube** (copia de seguridad)
- **Descargar de la nube** (restauración)

siempre con las mismas protecciones descritas arriba.

### Exportar / importar: el paquete de copia

Desde la pantalla **Copia de seguridad** (U20, `03_features.md`) el usuario
puede **exportar** todos sus datos a un archivo y **volver a importarlo**, con
la misma regla de "una copia manda": importar **sustituye** los datos locales,
y solo después de una confirmación explícita. Sirve antes de que exista la
copia en Google Drive y seguirá sirviendo después, como copia manual.

**Formato del paquete** (versión de formato 1):

- Un `.zip` llamado `vehicle-history-AAAAMMDD-HHmm.zip` (hora local del
  teléfono).
- Dentro: `manifest.json`, `vehicle_history.sqlite` y la carpeta
  `attachments/`, vacía por ahora; los adjuntos la llenarán sin cambiar el
  formato.
- `manifest.json` lleva `format_version` (1), `schema_version` (versión del
  esquema de la base de datos del paquete), `app_version` (versión de la app
  que lo exportó, como en `pubspec.yaml`), `exported_at` (instante UTC,
  ISO-8601), `counts` (propietarios, vehículos, entradas y lecturas **vivos**:
  no borrados, y las entradas y lecturas además de un vehículo no borrado) y
  `last_modified_at` (el `updated_at` más reciente de esas cuatro tablas,
  borrados incluidos, o `null` si están vacías).
- La base de datos es una copia **entera y coherente**, hecha con
  `VACUUM INTO` en un archivo temporal junto a la base de datos (sea cual sea
  el estado del WAL), con la papelera y el historial de operaciones dentro. El
  temporal se borra al terminar, también si algo falla.

**Exportar:** se construye el paquete y el diálogo del sistema pregunta dónde
guardarlo (Descargas, Drive, cualquier proveedor del selector de Android); la
app no necesita permisos de almacenamiento. Cancelar el diálogo no es un
error. Al guardarse: toast "Copia exportada" y la fecha queda anotada
(`last_export_at`, tabla `settings`, ver `06_settings_and_i18n.md`).

La fecha se escribe **antes** de la copia `VACUUM INTO`, así que el paquete
lleva dentro su propia fecha de exportación: tras importarlo, Copia de
seguridad muestra esa fecha y no "nunca". Si el usuario cancela el diálogo
de guardar o la exportación falla, se vuelve a poner el valor anterior: la
pantalla nunca muestra una exportación que no dejó ningún archivo.

**Importar** — antes de tocar nada se comprueba el archivo:

- que sea un zip válido;
- que `manifest.json` exista y tenga `format_version` 1 (uno mayor viene de
  una app más nueva);
- que `vehicle_history.sqlite` exista, sea un archivo SQLite y tenga la
  versión de esquema que dice el manifiesto;
- `PRAGMA integrity_check` = `ok` sobre una copia temporal;
- que estén las tablas que corresponden a esa versión del esquema.

Cualquier fallo → mensaje claro ("no es una copia de Vehicle History", "está
dañado", …) y **nada cambia**.

**Regla de versión: un esquema más reciente se rechaza, uno anterior se
migra.** Un archivo de una versión del esquema **más reciente** que la de la
app se rechaza ("Este archivo viene de una versión más nueva de la app"); uno
de una versión **anterior** se importa y se migra con las protecciones de
siempre (incluida su copia `pre_v<n>`).

Si el archivo es válido, un diálogo con estilo destructivo muestra lo que
contiene: "Este archivo contiene 2 vehículos, 41 entradas y 7 lecturas;
última modificación 18 oct 2026. **Importar sustituye todos los datos
actuales.**"

**Red de seguridad** al confirmar:

1. Los datos actuales se copian (con `VACUUM INTO`) a
   `vehicle_history.pre_import.sqlite`, que sustituye a la de una importación
   anterior; después se cierra la base de datos.
2. El archivo importado ocupa el lugar de la base de datos; los `-wal` /
   `-shm` del archivo anterior se borran.
3. Se reabre como en cualquier arranque: si el esquema es anterior se migra,
   y se ejecuta la limpieza de la papelera (30 días). Se añade una fila
   `import` (entidad `database`) al historial de operaciones de la base de
   datos importada.
4. Si algo falla al reabrir o al migrar, la copia `pre_import` vuelve a su
   sitio y se reabre: "No se pudo importar; tus datos no han cambiado". La
   copia `pre_import` no se borra nunca automáticamente.
5. Si todo va bien, la app vuelve a la lista de vehículos con el toast "Copia
   importada".

## Preparación para el futuro (sin implementarla ahora)

El modelo de datos ya está preparado para una futura sincronización con fusión
(merge por entrada individual), **aunque ahora NO la implementamos**:

- cada registro tiene un `id` único (UUID) y `updated_at`;
- el borrado es **lógico** (indicador `deleted`), no físico inmediato — así
  una futura sincronización sabría distinguir "borrado a propósito" de "nunca
  existió".

Esto cuesta muy poco ahora y no cierra la puerta a una evolución, pero el
comportamiento de la versión 1 sigue siendo la Strada A.

## Papelera y limpieza

Desde el esquema v5 (paso 5b).

- **Lógico:** borrar un vehículo, una entrada, una lectura o un propietario
  solo lo marca (`deleted = 1` y `deleted_at` con el instante). Los
  vehículos borrados forman la **papelera** y se pueden restaurar con todas
  sus entradas y lecturas durante **30 días**.
- **Físico:** el registro desaparece del archivo, sin vuelta atrás. Ocurre
  solo al "Eliminar definitivamente" un vehículo o "Vaciar papelera" (por
  decisión del usuario, con confirmación) y en la **limpieza al arrancar la
  app**, que borra lo que lleva borrado 30 días o más: vehículos de la
  papelera (con todas sus entradas y lecturas), entradas y lecturas sueltas
  de vehículos vivos, y propietarios a los que ya no apunta ningún vehículo.
  La limpieza se ejecuta una vez por arranque, después de abrir y migrar la
  base de datos, en una sola transacción; si falla, no borra nada y la app
  arranca igual.
- El historial de operaciones conserva sus filas y añade una `purge` por
  cada vehículo y propietario borrados físicamente.
- **La copia lleva la papelera dentro:** el archivo que se exporte o se suba
  a Drive es la base de datos entera, papelera incluida. Restaurar una copia
  devuelve también los vehículos que estaban en la papelera en ese momento,
  con su fecha de borrado; la siguiente limpieza al arrancar decide con esa
  fecha, no con la de la restauración.
