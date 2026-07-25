# 05 — Archiviazione e sincronizzazione

## Due piani distinti

1. **Archiviazione locale** — il database vero e proprio, sul telefono, in
   SQLite (tramite Drift). È qui che l'app legge e scrive normalmente. Le foto
   sono file salvati localmente, referenziati dal database.
2. **Backup su cloud** — una copia dell'intero database + le immagini,
   impacchettata e caricata su Google Drive, per poter recuperare tutto su un
   altro telefono. NON è una sincronizzazione continua: è un backup/restore
   manuale con qualche protezione.

Non confondere lo schema del database locale (doc 02) con il file di backup:
sono cose diverse.

## Google Drive

- Il backup è pensato come **un unico file** (o pacchetto) sul Drive
  dell'account collegato, che contiene tutto: dati + impostazioni + immagini.
- Cambio telefono / reinstallazione: ci si collega allo stesso account, si
  scarica il backup, e si recupera tutto — incluse le impostazioni generali.

## Collegamento dell'account (due modalità)

L'app supporta **due modi** per collegare l'account Google usato per il backup.
L'utente sceglie; entrambi portano allo stesso risultato (un token che autorizza
l'accesso a Drive), ma con flussi diversi.

### Modalità 1 — Account del telefono (semplice, predefinita)

- Usa il **selettore di account di sistema** (`google_sign_in`).
- Android mostra la lista degli account Google già presenti sul telefono
  (principale **e** account aggiunti in Impostazioni → Account): l'utente ne
  sceglie uno. Non è obbligato a usare il principale.
- È il percorso comodo per la maggior parte dei casi.

### Modalità 2 — Collega un account manualmente (avanzata)

Per usare un account che **non è** (e non deve diventare) un account del
telefono: resta usato **solo dall'app**.

- Flusso **OAuth 2.0 Authorization Code + PKCE**, tramite `flutter_appauth`.
- Il login avviene nel **browser di sistema** (Android Custom Tab), sulla vera
  pagina di Google: l'utente digita email e password lì. Anche la verifica in
  due passaggi è gestita da Google.
- **L'app non vede mai la password**: riceve solo, alla fine, i token di
  accesso/refresh.
- L'account **non** viene aggiunto a livello Android: rimane interno all'app.

### Regole di sicurezza (valide per entrambe le modalità)

- **Mai una WebView interna** per il login Google: solo browser di
  sistema/Custom Tab. Una WebView è meno sicura ed è comunque bloccata da
  Google.
- I **token** si conservano nell'**archivio cifrato del sistema** (Android
  Keystore, via `flutter_secure_storage`), mai in file o preferenze in chiaro.
- L'app mostra sempre chiaramente **quale account è collegato** al backup (es.
  "Backup collegato a: utente@gmail.com") con un pulsante per **cambiare
  account**.

### Cambio account = backup separati

Il backup di un account e quello di un altro sono **file distinti su Drive
diversi**: non si parlano. Il cambio account va trattato come operazione
consapevole, con avviso esplicito: "Stai cambiando l'account di backup; il
backup precedente resta sull'account vecchio."

### Nota amministrativa (Google Cloud Console)

Il flusso OAuth (Modalità 2, e in parte anche la 1) richiede che l'app sia
registrata nella **Google Cloud Console** con credenziali OAuth e schermata di
consenso. L'accesso a Drive comporta un processo di **verifica dell'app** da
parte di Google. Finché l'app non è verificata funziona lo stesso ma mostra un
avviso "app non verificata" e ha un limite di utenti di test — accettabile per
uso personale / pochi utenti. La verifica diventa necessaria solo in caso di
distribuzione ampia. È un passaggio amministrativo, non di codice, ma va
pianificato.

## Strategia scelta: "Strada A" — backup/restore con guardia di versione

Scelta consapevole di semplicità (l'app è mono-utente). Non c'è fusione
automatica dei dati: **una copia comanda**. Per evitare che "facile" diventi
"pericoloso", si aggiunge una guardia di versione leggera.

### Metadati di versione

Sia il database locale sia il backup su Drive portano due informazioni leggere:

- un **numero di versione** che cresce di 1 a ogni modifica del database;
- la **data/ora dell'ultima modifica**.

### Controllo all'apertura dell'app

All'avvio, l'app legge **solo questi due metadati** dal cloud (non scarica
l'intero database) e li confronta con quelli locali. Quattro casi:

1. **Uguali** → allineato, nessuna azione.
2. **Cloud più recente del locale** → messaggio: "Sul cloud c'è una versione
   più recente. Vuoi scaricarla?" Se sì, il locale viene **sostituito**.
3. **Locale più recente del cloud** → messaggio: "Hai modifiche non ancora
   caricate. Vuoi caricarle?" Se sì, il cloud viene **sostituito**.
4. **Divergenza** (sia locale sia cloud modificati rispetto all'ultimo punto in
   comune) → l'app **avvisa onestamente**: "Attenzione: sia questo telefono sia
   il cloud sono cambiati. Se scarichi perdi le modifiche locali; se carichi
   sovrascrivi quelle sul cloud." Decide l'utente. Nessuna sovrascrittura
   silenziosa, nessuna perdita di dati di nascosto.

### Operazioni manuali

Oltre al controllo all'avvio, l'utente può in qualsiasi momento:

- **Carica su cloud** (backup)
- **Scarica da cloud** (restore)

sempre con le stesse protezioni di cui sopra.

## Predisposizione per il futuro (senza implementarla ora)

Il modello dati è già predisposto per una futura sincronizzazione a fusione
(merge per singola voce), **anche se ora NON la implementiamo**:

- ogni record ha un `id` univoco (UUID) e `updated_at`;
- la cancellazione è **logica** (flag `deleted`), non fisica immediata — così
  una futura sync saprebbe distinguere "cancellato di proposito" da "mai
  esistito".

Questo costa pochissimo adesso e non chiude la porta a un'evoluzione, ma il
comportamento della versione 1 resta la Strada A.

## Cancellazione fisica / pulizia

Poiché la cancellazione è logica, servirà (in futuro, non urgente) una
strategia di pulizia periodica dei record marcati `deleted` da tempo, per non
far crescere il database all'infinito. Per la versione 1 è sufficiente tenerli.
