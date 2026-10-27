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
   relativas a esa carpeta. Desde el paso 8 los adjuntos viven en su
   subcarpeta `attachments/` (ver `02_data_model.md`, "Attachment").
2. **Copia de seguridad en la nube** — una copia de toda la base de datos + las
   imágenes, empaquetada (el mismo `.zip` de exportar / importar) y subida a
   Google Drive, para poder recuperarlo todo en otro teléfono. NO es una
   sincronización continua: es una copia de seguridad (backup) /
   restauración con control de versión. Desde el paso 9 conviven las dos
   vías: la exportación / importación manual a un archivo y la copia en
   Drive de la cuenta vinculada.

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

Implementada en el paso 9b. Sirve para usar una cuenta que **no es** (y no
debe pasar a ser) una cuenta del teléfono: la usa **solo la app**. Caso
típico: el teléfono de otra persona de la familia guarda la copia en la
cuenta del propietario sin que esa cuenta aparezca en Gmail, Play Store o
el selector de cuentas de Chrome de ese teléfono.

- Flujo **OAuth 2.0 Authorization Code + PKCE (S256)**, a través de
  `flutter_appauth` (AppAuth-Android). Cliente OAuth **Android** del
  proyecto (cliente público, **sin secreto**). El redirect es el ID de
  cliente invertido (`com.googleusercontent.apps.…:/oauth2redirect`). En
  Cloud Console ese cliente tiene activado "Enable custom URI scheme":
  Google lo desactiva por defecto en los clientes Android nuevos. Los
  endpoints salen del documento de descubrimiento de Google.
- El inicio de sesión tiene lugar en el **navegador del sistema** (Android
  Custom Tab), en la página real de Google, con `prompt=select_account`:
  siempre se puede elegir o escribir otra cuenta. El usuario escribe allí
  el email y la contraseña, y Google gestiona también la verificación en
  dos pasos.
- **La app nunca ve la contraseña**: al final solo recibe los tokens.
- Ámbitos: `openid email` (solo para mostrar qué cuenta está vinculada; el
  email se lee del ID token, sin otra llamada) y `drive.file`, el mismo de
  la Modalidad 1. Si en el consentimiento se desmarca Drive, la vinculación
  se rechaza y el token se revoca.
- La cuenta **no** se añade a nivel de Android: permanece interna a la app.
- **Dónde viven los tokens:**
  - el **refresh token**, y nada más, en `flutter_secure_storage`, cifrado
    con una clave del Android Keystore;
  - el token de acceso, solo en memoria; se renueva solo cuando está a
    punto de caducar (a la hora);
  - nunca en la tabla `settings`, en archivos ni en el registro, que solo
    anota nombres de evento.
  - Los archivos de `flutter_secure_storage` están excluidos de la copia de
    seguridad propia de Android y de la transferencia entre dispositivos:
    el token no sale nunca del teléfono, y su clave del Keystore tampoco
    viajaría.
- **Pestaña privada: no disponible en Android.** Ni `flutter_appauth` ni
  AppAuth-Android ofrecen una Custom Tab efímera, así que la sesión de
  Google puede quedar abierta en el navegador predeterminado (Chrome, Brave…)
  como sesión web, no como cuenta del teléfono. Tras vincular, la app lo
  avisa una vez: "La sesión de Google puede quedar abierta en el navegador
  del teléfono; cierra allí la sesión de Google si no quieres que quede
  guardada."
- **Afinidad de tarea.** `MainActivity` no lleva `android:taskAffinity=""`
  (la plantilla de Flutter lo pone): con él, la redirección de Google llega
  a una tarea nueva de Android, donde AppAuth no encuentra la solicitud en
  curso, y el navegador se queda abierto sin volver a la app.
- **Google rechaza el refresh token** (`invalid_grant`: acceso retirado,
  contraseña cambiada…): la app borra el token y conserva la cuenta y la
  modalidad, con la línea de estado "vuelve a vincular la cuenta", igual
  que en la Modalidad 1.
- **Desvincular** revoca el token en Google (`oauth2.googleapis.com/revoke`,
  que retira también el acceso de la app en la cuenta) y borra el almacén
  seguro y las claves de ajustes. Si no se puede revocar, por ejemplo sin
  conexión, la desvinculación se hace igual y la app explica cómo quitar el
  acceso a mano: cuenta de Google → Seguridad → Conexiones con terceros.
- **Una modalidad a la vez.** Para pasar a la otra hay que desvincular
  primero. "Cambiar de cuenta" vincula otra cuenta en la misma modalidad
  (en la 2, el token anterior se revoca).
- **Las mismas copias.** `drive.file` es por proyecto de Cloud, y los dos
  clientes OAuth son del mismo proyecto: la misma cuenta ve las mismas
  copias en las dos modalidades, y el punto en común se guarda por email.

La modalidad activa se guarda en el ajuste `drive_auth_mode` (`system` /
`manual`, del teléfono; sin fila = `system`, como las vinculaciones de la
0.9.0).

### Reglas de seguridad (válidas para ambas modalidades)

- **Nunca una WebView interna** para el inicio de sesión de Google: solo
  navegador del sistema/Custom Tab. Una WebView es menos segura y, en
  cualquier caso, Google la bloquea.
- Los **tokens** se guardan en el **almacén cifrado del sistema** (Android
  Keystore, a través de `flutter_secure_storage`), nunca en la tabla
  `settings`, en archivos o en preferencias en claro. Con la Modalidad 1
  la app **no guarda ningún token**: cada vez que necesita uno se lo pide a
  Google Play Services para la cuenta vinculada (sin pantalla), lo usa solo
  en memoria para esa petición y, si Drive lo rechaza (caduca a la hora),
  pide otro y repite la petición. Con la Modalidad 2 solo se guarda el
  refresh token, en `flutter_secure_storage`. Ningún token ni código de
  autorización aparece nunca en el registro.
- La app muestra siempre con claridad **qué cuenta está vinculada** a la copia
  de seguridad (p. ej. "Copia de seguridad vinculada a: usuario@gmail.com") con
  un botón para **cambiar de cuenta**.

### Cambio de cuenta = copias de seguridad separadas

La copia de seguridad de una cuenta y la de otra son **archivos distintos en
Drives distintos**: no se comunican. El cambio de cuenta debe tratarse como una
operación consciente, con un aviso explícito: "Estás cambiando la cuenta de la
copia de seguridad; la copia de seguridad anterior se queda en la cuenta
antigua."

### Ámbito de Drive y carpeta

- La app pide solo el ámbito **`drive.file`**: ve y toca únicamente los
  archivos que ella misma creó. Es un ámbito **no sensible**: la pantalla
  de consentimiento no necesita verificación de Google.
- Las copias van a una carpeta **visible** "Vehicle History" en el Drive del
  usuario, que puede descargarlas a mano desde la web de Drive como red de
  seguridad adicional.
- La app encuentra sus copias por sus **propiedades** (`appProperties` de
  Drive, rol `backup`), nunca por el nombre de la carpeta ni del archivo:
  mover o renombrar la carpeta no hace creer a la app que no hay copia.
- **Sin cifrado propio** del paquete: la protección es la de la cuenta de
  Google (con verificación en dos pasos). Una contraseña olvidada sería una
  copia perdida. Decisión consciente, sabiendo que en Drive habrá fotos de
  documentos (DNI, carné); se puede revisar más adelante.

### Nota administrativa (Google Cloud Console)

Ambas modalidades requieren que la app esté registrada en la **Google Cloud
Console** con la pantalla de consentimiento configurada para el ámbito (*scope*)
de Drive. La Modalidad 1 necesita además un ID de cliente OAuth para Android
(nombre del paquete + SHA-1 del certificado de firma); la Modalidad 2 usa
ese mismo cliente Android para el flujo a través del navegador con PKCE,
con "Enable custom URI scheme" activado. El acceso a Drive conlleva un
proceso de **verificación de la app** por parte de Google. Mientras la app no
esté verificada funciona igual, pero muestra un aviso de "app no verificada" y
tiene un límite de usuarios de prueba — aceptable para uso personal / pocos
usuarios. La verificación solo se vuelve necesaria en caso de distribución
amplia. Es un paso administrativo, no de código, pero hay que planificarlo.

Con solo `drive.file` (no sensible) la app se puede publicar "En producción"
sin verificación; en "Prueba" la autorización de los ámbitos caduca a los 7
días y habría que volver a vincular cada semana. Publicar exige en la
información de la marca una página principal y una política de privacidad
en el mismo dominio (dominio autorizado). El proyecto usa un cliente OAuth
**Android** (paquete + SHA-1 de la clave fija de firma, la misma en debug y
release) y un cliente **Web**, cuyo ID es el `serverClientId` que pide
`google_sign_in` en Android (público, en el código; su secreto no se usa ni
se guarda).

## Estrategia elegida: "Strada A" (vía A) — copia de seguridad/restauración con control de versión

Elección consciente de simplicidad (la app es monousuario). No hay fusión
automática de los datos: **una copia manda**. Para evitar que "fácil" se
convierta en "peligroso", se añade un control de versión (version guard)
ligero.

### Versión: sello local, propiedades de la copia y último punto en común

No hay un contador de versiones ni cambio de esquema.

- **Sello local**: `last_modified_at` (ver más abajo, "Formato del
  paquete"): el último cambio de lo que registra el usuario, purgas
  incluidas, ajustes e importaciones excluidos.
- **Propiedades de la copia en Drive** (se leen sin descargarla):
  `upload_id` (un UUID nuevo en cada subida), `last_modified_at`,
  `schema_version`, `app_version`, `device_id` (el teléfono que subió) y los
  recuentos (propietarios, vehículos, entradas, lecturas vivos y filas de
  adjuntos).
- **Último punto en común**, en la tabla `settings` del teléfono: la cuenta,
  el sello local y el `upload_id` de la copia en el momento de la última
  subida o restauración correcta, y cuándo y cómo (subida / restauración).
  Se anota **solo** cuando Drive ha confirmado la subida o la importación ha
  terminado bien; un fallo a medias deja el anterior. Tras restaurar, el
  sello local se lee después de reabrir (la limpieza puede haber purgado
  filas).
- Local cambiado = su sello no es el anotado. Nube cambiada = su `upload_id`
  no es el anotado. Se comparan como valores anotados, no como horas: un
  reloj mal puesto en otro teléfono no cambia nada.

### El control de versión (guard)

Lee solo los metadatos de la copia más reciente y decide uno de estos
estados, que la app muestra como **línea de estado** (nunca un diálogo):

| Estado | Cuándo | Línea de estado |
| --- | --- | --- |
| Sin cuenta | No hay cuenta vinculada | "Drive: sin cuenta" |
| Al día | Ni local ni nube han cambiado desde el punto en común | "Drive: al día" |
| Solo local cambiado | La nube sigue igual que en el punto en común | "Drive: cambios sin subir" — se sube sola al arrancar |
| Sin copia en la nube | La cuenta no tiene copia | "Drive: todavía no hay copia" — se sube sola al arrancar |
| Nube cambiada | Otro teléfono subió una copia | "Drive: copia más reciente en Drive (de otro teléfono)" |
| Ambos han cambiado | Local y nube cambiaron desde el punto en común | "Drive: han cambiado los dos, este teléfono y Drive" |
| Sin punto común | Hay copia pero ningún punto en común (primera vinculación, teléfono nuevo, otra cuenta, tras una importación manual) | "Drive: copia sin comparar con este teléfono; copia automática en pausa" |
| Copia más nueva | La copia es de un esquema más nuevo que la app | "Drive: la copia es de una versión más nueva de la app; actualiza la app" — ni descarga ni subida automática |

- **Mismos datos = al día.** Si no hay punto en común (o la nube cambió) pero
  los dos lados tienen el mismo sello no vacío **y** los mismos recuentos,
  es "al día" y ese estado se anota como nuevo punto en común.
- Un punto anotado con otra cuenta no cuenta.
- Si la última subida automática falló: "Drive: error en la última subida
  (se reintentará en el próximo arranque)" o "sin conexión"; si Google ya no
  autoriza la app: "vuelve a vincular la cuenta".

**Dónde se ve.** En la pantalla Copia de seguridad, siempre. Además, como
dos teléfonos pueden compartir la misma copia de Drive y hay que restaurar
antes de editar, **"copia más reciente en Drive"** y **"ambos han
cambiado"** aparecen al abrir la app como un **banner discreto** en la
pantalla principal (con "Restaura antes de editar." en el primer caso y un
acceso a Copia de seguridad), que se queda hasta que el estado cambia. Los
demás estados que piden algo al usuario (sin punto común, copia más nueva,
volver a vincular) se avisan una vez al arrancar con un mensaje breve
(snackbar) con el mismo acceso. Nunca un diálogo.

### La única acción automática: la subida al arrancar

Una vez por arranque, después de abrir la base de datos (nunca antes, y sin
bloquear el arranque ni las pantallas):

1. La app lee los metadatos de Drive y ejecuta el guard.
2. Solo si el estado es **solo local cambiado** o **sin copia en la nube**
   (lo que se sustituye ya está contenido en los datos locales, o no hay
   nada), sube una copia nueva en segundo plano, sin diálogo.
3. Justo antes de subir **vuelve a leer** los metadatos: si la copia cambió
   entretanto (otro teléfono subió), no sube nada y el estado pasa a
   "ambos han cambiado".
4. **Datos móviles**: el ajuste "Usar datos móviles para la copia
   automática" está **desactivado** por defecto; con una red de pago (datos
   móviles, punto de acceso) la subida espera ("cambios sin subir,
   esperando wifi"). Subir y Restaurar a mano funcionan siempre.
5. Si falla (sin conexión, error de Drive), la línea de estado lo dice y se
   intenta otra vez **en el siguiente arranque**. Sin reintentos, sin subida
   al pasar a segundo plano, sin tareas en segundo plano.

Además, justo después de **vincular** una cuenta que no tiene copia, la
primera copia se sube al momento (no se puede perder nada).

Nunca se descarga nada automáticamente y nunca hay fusión.

### Operaciones manuales (pantalla Copia de seguridad)

- **Subir a Drive**: sube una copia nueva. Si el estado es "nube cambiada",
  "ambos han cambiado" o "sin punto común", antes pide confirmación
  repitiendo el aviso, con las fechas de los dos lados. Si la copia de Drive
  cambió desde lo que se mostró, no sube nada.
- **Restaurar desde Drive**: descarga la copia **más reciente** junto a la
  base de datos y la pasa por la importación de siempre: la misma
  comprobación, el mismo diálogo de confirmación con fechas y recuentos
  (más "los datos de este teléfono, último cambio …, se sustituirán" y, si
  hay cambios locales que no están en Drive, el aviso de que se perderán) y
  la misma red de seguridad `pre_import`.
- **Historial**: Drive guarda en silencio las **3 últimas copias**; tras cada
  subida se borran las más antiguas. No hay pantalla de historial: una copia
  anterior se puede descargar a mano desde la carpeta de Drive e importar.
- **Cambiar de cuenta** (con el aviso de que la copia anterior se queda en
  la cuenta antigua) y **Desvincular**: los dos borran el último punto en
  común. Con otra cuenta que ya tiene copia, el estado es "sin punto común"
  y no se sube nada sobre ella hasta que el usuario elija.

### Subida y descarga en streaming

Como la exportación del paso 8, nada pasa entero por la memoria: el paquete
se escribe en un archivo temporal junto a la base de datos (sin tocar
`last_export_at`, que es la fecha de la última exportación manual), se sube
con la subida **reanudable** de Drive a trozos de 4 MB y se borra al
terminar; la descarga se escribe a disco a medida que llega. Si el token
caduca a mitad de una subida, el trozo rechazado se vuelve a enviar con un
token nuevo. Una barra de progreso muestra el avance (sin cancelar).

### Los ajustes y la importación

La tabla `settings` viaja dentro del paquete, pero lo que describe el
vínculo de **este teléfono** con Drive no debe llegar de otro:

- se conservan los del teléfono: la cuenta vinculada, el identificador del
  teléfono y el ajuste de datos móviles;
- el último punto en común se **borra** en toda importación (manual o
  desde Drive): los datos ya no son los de ese punto. La restauración desde
  Drive anota el nuevo al terminar; tras una importación manual el estado
  queda "sin punto común" y la copia automática en pausa hasta que el
  usuario suba o restaure, y la confirmación de la importación lo avisa.
- El idioma, el tema y `last_export_at` siguen viajando con los datos.

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
  `attachments/`, con el archivo de **cada** fila de adjuntos, viva o
  borrada (la papelera viaja con el paquete), con el mismo nombre que su
  `relative_path` (`attachments/<id>.<ext>`). El formato sigue siendo el 1:
  un paquete del paso 6 (con `attachments/` vacía) se sigue importando.
- `manifest.json` lleva `format_version` (1), `schema_version` (versión del
  esquema de la base de datos del paquete), `app_version` (versión de la app
  que lo exportó, como en `pubspec.yaml`), `exported_at` (instante UTC,
  ISO-8601), `counts` (propietarios, vehículos, entradas y lecturas **vivos**:
  no borrados, y las entradas y lecturas además de un vehículo no borrado;
  más `attachments`, el número de **archivos** de `attachments/`, borrados
  incluidos), `attachments_bytes` (lo que ocupan) y `last_modified_at`: el último
  instante en que cambió algo de lo que registra el usuario, es decir, el
  `updated_at` más reciente de propietarios, vehículos, entradas, lecturas
  y **adjuntos** (borrados incluidos) y la fecha de la última fila `purge`
  del historial (cada borrado físico); `null` si no hay datos. Quedan fuera
  a propósito los **ajustes** (idioma, tema, fecha de la última
  exportación: si no, cada exportación lo movería) y las filas `import`
  (tras importar, los datos son los del paquete y no deben parecer más
  recientes). Es la base del control de versión del paso 9; un paquete
  anterior a la 0.8.1 lleva el valor antiguo, solo de las cuatro tablas
  principales, y se sigue leyendo igual. En un paquete anterior al
  paso 8 faltan `counts.attachments` y `attachments_bytes`: se leen como 0.
- La base de datos es una copia **entera y coherente**, hecha con
  `VACUUM INTO` en un archivo temporal junto a la base de datos (sea cual sea
  el estado del WAL), con la papelera y el historial de operaciones dentro.

**Exportar, en streaming.** El paquete nunca está entero en memoria: el zip
se escribe en un **archivo temporal** junto a la base de datos con el
codificador de archivos de `archive`, que añade la copia de la base de datos
y los adjuntos uno a uno, leyéndolos del disco (los adjuntos sin
comprimir: fotos y PDF ya lo están). Un adjunto cuyo archivo falta en el
teléfono no entra en el zip (su fila sí, y la importación lo cuenta como
archivo que falta). Después el diálogo del sistema pregunta dónde guardarlo
(Descargas, Drive, cualquier proveedor del selector de Android) y el
archivo se copia allí. La copia de la base de datos y el zip temporal se
borran al terminar, también si algo falla o se cancela. La app no necesita
permisos de almacenamiento. Cancelar el diálogo no es un error. Al
guardarse: toast "Copia exportada" y la fecha queda anotada
(`last_export_at`, tabla `settings`, ver `06_settings_and_i18n.md`).

**"Guardar como" nativo.** Un pequeño canal de Android (Kotlin,
`vehicle_history/files`) con `saveFile(origen, nombre propuesto, tipo
MIME)`: abre `ACTION_CREATE_DOCUMENT` y, cuando el usuario elige el sitio,
copia el archivo al documento elegido a trozos de 64 KB, fuera del hilo
principal, y responde guardado / cancelado / error. Se usa para el paquete
y para "Guardar en…" de un adjunto (con su nombre original). Tiene también
`freeBytes`, el espacio libre del volumen, para la comprobación de la
importación. Solo Android; en iOS no existe todavía.

La fecha se escribe **antes** de la copia `VACUUM INTO`, así que el paquete
lleva dentro su propia fecha de exportación: tras importarlo, Copia de
seguridad muestra esa fecha y no "nunca". Si el usuario cancela el diálogo
de guardar o la exportación falla, se vuelve a poner el valor anterior: la
pantalla nunca muestra una exportación que no dejó ningún archivo.

**Importar** — el archivo elegido se copia (en streaming) junto a la base de
datos y, antes de tocar nada, se comprueba:

- que sea un zip válido;
- que `manifest.json` exista y tenga `format_version` 1 (uno mayor viene de
  una app más nueva);
- que `vehicle_history.sqlite` exista, sea un archivo SQLite y tenga la
  versión de esquema que dice el manifiesto;
- `PRAGMA integrity_check` = `ok` sobre una copia temporal;
- que estén las tablas que corresponden a esa versión del esquema;
- qué archivos de adjuntos nombran las filas del paquete y cuáles están en
  `attachments/`: los que faltan **se toleran** (las filas se importan y
  muestran "Archivo no encontrado") y el diálogo lo dice ("Faltan K
  archivos…"). Solo se aceptan entradas `attachments/<nombre>` sencillas: una
  entrada con subcarpetas o `..` se ignora;
- que haya **espacio libre** para los adjuntos del paquete y la copia
  `pre_import` de la base de datos actual (más un margen de 20 MB).

La comprobación lee solo el índice del zip y la base de datos: los adjuntos
se descomprimen una sola vez, al confirmar.

Cualquier fallo → mensaje claro ("no es una copia de Vehicle History", "está
dañado", "no hay espacio suficiente", …) y **nada cambia**.

**Regla de versión: un esquema más reciente se rechaza, uno anterior se
migra.** Un archivo de una versión del esquema **más reciente** que la de la
app se rechaza ("Este archivo viene de una versión más nueva de la app"); uno
de una versión **anterior** se importa y se migra con las protecciones de
siempre (incluida su copia `pre_v<n>`).

Si el archivo es válido, un diálogo con estilo destructivo muestra lo que
contiene: "Este archivo contiene 2 vehículos, 41 entradas y 7 lecturas;
última modificación 18 oct 2026." "3 adjuntos (12 MB)." y, en negrita,
"**Importar sustituye todos los datos actuales.**"

**Red de seguridad** al confirmar:

1. Los adjuntos del paquete se descomprimen en una carpeta temporal junto a
   `attachments/`; si falla, no ha cambiado nada.
2. El material `pre_import` de la importación anterior se aparta (no se
   borra todavía). Los datos actuales se copian (con `VACUUM INTO`) a
   `vehicle_history.pre_import.sqlite`; después se cierra la base de datos.
3. La carpeta `attachments/` actual pasa a llamarse
   `attachments.pre_import/` y la descomprimida ocupa su lugar; el archivo
   importado ocupa el lugar de la base de datos (los `-wal` / `-shm` del
   archivo anterior se borran).
4. Se reabre como en cualquier arranque: si el esquema es anterior se migra,
   y se ejecuta la limpieza de la papelera (30 días). Se añade una fila
   `import` (entidad `database`) al historial de operaciones de la base de
   datos importada.
5. Si todo va bien, se borra el material `pre_import` de la importación
   anterior (solo se guarda el último) y la app vuelve a la lista de
   vehículos con el toast "Copia importada".
6. Si algo falla después del punto 2, vuelven a su sitio **las dos cosas**:
   la base de datos (desde `pre_import`) y la carpeta `attachments/`; se
   reabre: "No se pudo importar; tus datos no han cambiado". La copia
   `pre_import` de la base de datos se conserva. Si ni siquiera eso funciona,
   el mensaje lo dice y el material `pre_import` se queda.

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
  cada vehículo y propietario borrados físicamente y por cada entrada,
  lectura o adjunto que la limpieza elimina sueltos (no por lo que se va
  con su padre).
- **Adjuntos:** se van con el vehículo, la entrada o el propietario que se
  borra físicamente, con sus archivos; la limpieza borra también los
  adjuntos borrados hace 30 días o más (salvo los que viajan con un vehículo
  de la papelera). Después de la limpieza, el arranque vacía
  `attachments_tmp/` y borra los archivos de `attachments/` sin fila
  (huérfanos). Ver `02_data_model.md`, "Attachment".
- **Vehículos archivados** (esquema v8): su paso por la papelera y su
  borrado físico son los de cualquier vehículo; el estado de archivo viaja
  con la fila. Ver `02_data_model.md`, "Archivo de vehículos".
- **La copia lleva la papelera dentro:** el archivo que se exporte o se suba
  a Drive es la base de datos entera, papelera incluida. Restaurar una copia
  devuelve también los vehículos que estaban en la papelera en ese momento,
  con su fecha de borrado; la siguiente limpieza al arrancar decide con esa
  fecha, no con la de la restauración.
