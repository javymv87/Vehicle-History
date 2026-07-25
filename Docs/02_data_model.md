# 02 — Modello dati

Questo documento descrive le tabelle del database **locale** (SQLite tramite
Drift, sul telefono) e le loro relazioni. Il backup su Google Drive è un piano
separato, trattato in `05_sync_and_storage.md`: non confondere lo schema locale
con il file di backup.

Tutti i nomi di tabella e campo qui sono in italiano per chiarezza concettuale.
Nel **codice** i nomi reali saranno in inglese (vedi `CLAUDE.md`); accanto a
ogni tabella indico il nome inglese suggerito.

## Campi tecnici comuni a (quasi) tutte le tabelle

Per rendere possibile la sincronizzazione e lo storico delle operazioni, ogni
record principale porta con sé:

- `id` — identificativo univoco (UUID, non un semplice numero incrementale, per
  evitare collisioni tra dispositivi diversi).
- `created_at` — data/ora di creazione.
- `updated_at` — data/ora dell'ultima modifica.
- `deleted` — flag di **cancellazione logica**. Una voce cancellata non viene
  distrutta subito: viene marcata come cancellata. Serve a poter recuperare
  errori e a far sapere al backup che l'elemento è stato rimosso di proposito.

## Tabelle

### Owner (proprietario)

Anagrafica della persona proprietaria di uno o più veicoli.

- Nome, cognome
- Data di nascita
- Nazionalità
- Foto
- Contatti: telefono, email
- Note libere

Un Owner può avere **più veicoli**. Un veicolo ha **un** Owner.

### OwnerDocument (documento del proprietario)

Documenti personali legati a un Owner. Ognuno è un file (foto/scansione) con
i suoi dati e la sua scadenza, così può generare promemoria.

- Tipo: patente, carta d'identità, permesso di soggiorno, altro
- Numero documento
- Data di rilascio
- Data di scadenza
- Categorie (per la patente: B, A, C, ecc.)
- File/foto
- Note

Un Owner può avere più OwnerDocument.

### Vehicle (veicolo)

Il veicolo. È l'entità centrale: quasi tutto il resto vi è collegato.

- Targa (identificativo principale)
- Nome comune (opzionale)
- Foto profilo
- Riferimento all'Owner
- **Km attuale** (l'ultimo valore noto del totalizzatore)
- Specifiche di fabbrica: tipo di carburante, olio motore raccomandato, e
  qualsiasi nota utile del costruttore (vedi `04_maintenance_logic.md`)

### LogEntry (voce di storico) — cuore dell'app

La "voce base" uguale per ogni tipo di evento. Ogni riga dello storico è un
LogEntry. I campi extra specifici di alcuni tipi stanno in tabelle collegate
(EntryImage, Measurement) o in campi opzionali, così questa tabella resta
pulita.

Campi sempre presenti:

- Riferimento al Vehicle
- **Data**
- **Km** (chilometraggio al momento dell'evento; obbligatorio dove ha senso,
  omesso dove non ne ha — es. pagamento bollo). **Nota importante:** questo km
  resta *dentro la voce* e NON alimenta lo storico chilometraggio
  (`MileageReading`). I due registri sono indipendenti.
- **Tipo** di voce (vedi elenco sotto)
- **Testo** / descrizione libera
- **Costo** totale (opzionale)
- **Promemoria** opzionale (data futura + eventuale soglia km) che genera una
  notifica

Tipi di voce previsti:

- Manutenzione ordinaria
- Riparazione / straordinaria
- Scadenza legale (bollo, revisione, assicurazione)
- Rifornimento (campi extra: litri, prezzo/litro, km percorsi — vedi doc 04)
- Spesa generica (pedaggi, lavaggio, accessori...)
- Controllo con misura (campi extra in Measurement)
- Controllo generico non classificato (nota libera)
- Nota / evento (incidenti, multe, promemoria liberi)

### EntryImage (immagine di una voce)

Le foto allegate a una LogEntry. Una voce può avere **più** immagini.

- Riferimento alla LogEntry
- File immagine
- Didascalia opzionale

### Measurement (controllo con misura)

Campo extra per le voci di tipo "controllo con misura". Registra un valore
numerico ispezionato, alimentando lo storico dei valori nel tempo.

- Riferimento alla LogEntry
- Grandezza misurata (es. battistrada, spessore pastiglie, tensione batteria)
- Valore numerico
- Unità di misura (mm, V, ...)
- **Soglia di allarme** opzionale: se il valore scende sotto la soglia, l'app
  avvisa.

### Document (documento del veicolo)

Documenti del veicolo che rappresentano uno **stato attuale**, distinti dagli
eventi dello storico.

- Riferimento al Vehicle
- Tipo: libretto, assicurazione attiva, altro
- File/foto
- Data di scadenza (opzionale, per i promemoria)
- Note

### MaintenanceType (catalogo tipi di manutenzione)

Catalogo **comune** e modificabile dei tipi di manutenzione disponibili,
raggruppati per famiglia. È condiviso tra tutti i veicoli.

- Nome (es. "Olio motore", "Freni anteriori", "Rotazione gomme")
- Gruppo/famiglia: Fluidi, Filtri, Gomme, Batteria, Motore, Freni, Altro
- Natura dell'intervento: controllo / sostituzione (può valere entrambe)
- Precaricato dal sistema oppure creato dall'utente

### MaintenanceRule (criterio di manutenzione per veicolo)

Il criterio di manutenzione **configurato per uno specifico veicolo**,
pescando un tipo dal catalogo e assegnandogli gli intervalli di quel veicolo.
Un tipo già assegnato a un veicolo non ricompare tra le scelte per lo stesso
veicolo (ma resta disponibile per gli altri).

- Riferimento al Vehicle
- Riferimento al MaintenanceType
- **Scadenza in km** (opzionale)
- **Scadenza in tempo** (opzionale, in mesi)
- Regola "scatta il primo dei due" quando sono presenti entrambe
- Ultimo intervento noto (data + km) per calcolare la prossima scadenza
- Note

**Caso freni** (vedi dettaglio in `04_maintenance_logic.md`): per i tipi
"Freni anteriori" / "Freni posteriori" la regola porta con sé il tipo di
impianto (disco+pastiglie oppure tamburo+ganasce) e **due sotto-scadenze
indipendenti**: elemento che si consuma (pastiglia/ganascia) ed elemento che
lo contiene (disco/tamburo), ciascuno con la propria scadenza km e/o tempo.
Questo è modellato come struttura interna alla regola, non come nuova tabella.

### MileageReading (storico chilometraggio)

Registro **indipendente** delle letture del totalizzatore nel tempo. Serve al
report "km percorsi vs tempo".

- Riferimento al Vehicle
- Data
- Km (valore del totalizzatore)

Regole logiche (dettaglio in `04_maintenance_logic.md`):

- Una nuova lettura **non può essere inferiore** all'ultima valida.
- Un valore enormemente più alto (probabile refuso) chiede conferma, non viene
  vietato.
- Si può cancellare **solo l'ultima** lettura; poi la penultima diventa
  l'ultima e diventa a sua volta cancellabile (comportamento "annulla a
  ritroso"). Mai cancellare letture in mezzo alla serie.
- Si aggiorna **solo** quando l'utente aggiorna il totalizzatore in modo
  esplicito. Il km scritto sulle singole voci NON entra qui.

### AuditLog (storico delle operazioni)

Registro leggero di tutte le operazioni fatte sulle voci, consultabile e utile
anche in futuro.

- Cosa: riferimento all'entità (quale voce/veicolo)
- Operazione: creazione / modifica / eliminazione
- Quando: data e ora

### Settings (impostazioni)

Configurazione dell'app, non legata a un veicolo.

- Lingua (IT / ES / EN)
- Tema (Sistema / Chiaro / Scuro)
- Configurazione cloud / Google Drive (account, attivo sì/no)
- Metadati del backup: **numero di versione** del database e **data
  dell'ultima modifica**, usati per la guardia di versione all'apertura (vedi
  `05_sync_and_storage.md`).

## Riepilogo relazioni

- Owner 1 — N Vehicle
- Owner 1 — N OwnerDocument
- Vehicle 1 — N LogEntry
- Vehicle 1 — N Document
- Vehicle 1 — N MaintenanceRule
- Vehicle 1 — N MileageReading
- LogEntry 1 — N EntryImage
- LogEntry 1 — 1 Measurement (solo per il tipo "controllo con misura")
- MaintenanceType 1 — N MaintenanceRule (il catalogo alimenta le regole)
- AuditLog e Settings sono trasversali / globali
