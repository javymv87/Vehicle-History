# 03 — Funzionalità

## Storico voci

Ogni veicolo ha un elenco scorrevole di LogEntry ordinate per data (le più
recenti in alto). Ogni riga mostra a colpo d'occhio: tipo, data, km, un
estratto del testo, il costo (se presente) e un'icona se ci sono foto o un
promemoria.

Toccando una voce se ne vede il dettaglio completo e la si può modificare o
cancellare.

## Filtri e ricerca

Sullo storico si può filtrare per:

- **Data** (intervallo da–a)
- **Tipo** di voce (una o più categorie)
- **Testo** (ricerca libera nella descrizione)

I filtri sono combinabili. Devono restare rapidi da attivare e da azzerare.

## Promemoria e notifiche

Due sorgenti di promemoria:

1. **Manuali** — impostati su una singola voce (una data futura e/o una soglia
   km).
2. **Automatici** — derivati dalle `MaintenanceRule` del veicolo e dalle
   scadenze dei documenti (bollo, revisione, assicurazione, patente,
   permesso...).

Comportamento degli avvisi:

- Le scadenze **a tempo** generano una **notifica** del telefono alla data
  prevista (anche ad app chiusa).
- Le scadenze **a km** non possono "scattare" da sole nel tempo (l'app non
  conosce i km in tempo reale): vengono **segnalate visivamente** — le voci di
  manutenzione vicine o oltre la soglia km sono evidenziate quando apri l'app e
  quando aggiorni il totalizzatore.
- I controlli-misura con **soglia** avvisano quando l'ultimo valore registrato
  scende sotto la soglia impostata.

## Report

Tutti i report offrono l'opzione **includi / escludi immagini** e, dove
pertinente, **includi / escludi importi**. L'esportazione di riferimento è in
**PDF** (adatto a stampa, invio, o consegna a un acquirente).

Report previsti:

- **Spese** — per veicolo, per periodo, con totali. Include le spese delle
  manutenzioni (vedi sotto) e le spese generiche.
- **Voci per tipo** — solo manutenzioni, solo rifornimenti, ecc.; con opzione
  di includere o meno gli importi.
- **Consumi carburante** — consumo medio (totale o per periodo) e spesa totale
  in carburante per periodo (dettaglio del calcolo in `04_maintenance_logic.md`).
- **Km percorsi vs tempo** — basato sullo storico chilometraggio
  (`MileageReading`).
- **Generale** — TUTTA l'informazione di un veicolo in un unico documento.
  Pensato come record completo per la rivendita / passaggio di proprietà. È un
  punto di forza dell'app.

I report possono essere generati per **un** veicolo o per **più** veicoli.

## Spese dentro la manutenzione

Il costo è già un campo della voce base (`LogEntry`). In più, dentro una voce
di manutenzione si possono elencare le **singole voci di spesa** (es.
"pastiglie — 45 €", "manodopera — 60 €"), la cui somma dà il costo totale
della manutenzione. Si inseriscono in una **sezione espandibile** all'interno
della voce, non in una schermata separata, e sono facoltative (coerente col
principio "velocità d'uso prima di tutto").

## Regole UX dei messaggi di esito (toast)

Gradazione da rispettare:

- **Salvataggio / modifica riusciti** — toast breve e discreto (es. "Voce
  salvata"). Se la schermata torna già indietro e la voce compare in lista, il
  toast può anche essere minimo per non risultare ridondante.
- **Eliminazione** — toast con **azione di annullo** ("Voce eliminata —
  Annulla"). È l'azione più rischiosa se involontaria, quindi l'annullo è
  importante. (Reso possibile dalla cancellazione logica: vedi `02_data_model.md`.)
- **Errore** (salvataggio fallito, spazio esaurito, sync non riuscita) —
  messaggio **esplicito e persistente** abbastanza da essere letto, non un
  lampo.

## Foto

- Foto profilo del veicolo (una).
- Foto del proprietario (una).
- Foto/scansioni dei documenti (veicolo e proprietario).
- Una o più immagini per ogni voce di storico.

Le immagini si acquisiscono da fotocamera o galleria e si salvano localmente;
rientrano nel backup su cloud.
