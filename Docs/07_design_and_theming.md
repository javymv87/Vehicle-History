# 07 — Design e temi

Questo documento fissa le scelte di aspetto e di interazione dell'app, prima
del codice, coerentemente con gli altri documenti. Il principio guida resta
quello del concept: **velocità d'uso prima di tutto** (vedi
`01_concept_overview.md`).

## Design system: Material 3

L'app adotta **Material 3** (Material You), il design system nativo di Flutter.
Scelta motivata dal tipo di app — un registro con molte liste, form di
inserimento e dati — per cui Material 3 offre gratuitamente componenti coerenti
(liste, campi, date picker, dialog, evidenziazioni) e una gestione integrata e
ben studiata dei temi chiaro/scuro. Non si costruisce un design system da zero:
sarebbe lavoro sprecato per un'app utilitaria come questa.

## Tema chiaro / scuro

- Si definiscono due temi: **chiaro** e **scuro**.
- Il **default segue il sistema operativo** (modalità "Sistema").
- Nelle Impostazioni l'utente può scegliere tra tre opzioni: **Sistema**,
  **Chiaro**, **Scuro**. Anche se il default segue l'OS, la scelta manuale deve
  essere sempre disponibile.
- La preferenza si salva tra le impostazioni dell'app (vedi
  `06_settings_and_i18n.md`).

## Colore

- Si definisce **un solo colore "seme" (seed color)** e si lascia che Material
  3 generi da lì entrambe le palette (chiara e scura), automaticamente
  armoniose e con contrasti corretti. Non si scelgono decine di colori a mano.
- Il seme dà carattere senza essere invadente. Direzioni adatte al contesto
  "veicoli/officina": blu profondo, teal, oppure ambra/arancione come accento.
  È una scelta di gusto, facilmente modificabile perché tutto discende dal seme.

## Principi di design specifici dell'app

Contano più della scelta dei colori:

### Leggibilità prima di tutto

L'app è piena di numeri (km, litri, costi, date, scadenze). Serve una chiara
gerarchia tipografica e spaziatura adeguata. Nella lista delle voci, i dati
chiave (tipo, data, km, costo) devono saltare all'occhio **senza** dover aprire
il dettaglio.

### Colore con significato, non decorativo

Il colore è riservato agli **stati**, in particolare le scadenze:

- scadenza superata → rosso
- scadenza vicina → ambra
- tutto a posto → verde / neutro

Coerente con la logica di evidenziazione delle scadenze km descritta in
`03_features.md` e `04_maintenance_logic.md`.

**Mai affidarsi al solo colore:** accompagnare sempre con un'icona o un testo,
sia per accessibilità (daltonismo) sia perché in modalità scura la resa dei
colori cambia.

### Coerenza chiaro/scuro sulle immagini

L'app mostra foto (veicoli, documenti, voci). Le miniature devono avere uno
sfondo/contenitore che funzioni su entrambi i temi, e l'eventuale testo
sovrapposto deve restare leggibile in chiaro e in scuro.

### Azione "aggiungi" sempre a portata

Dato che il principio guida è la velocità d'inserimento, aggiungere una voce
deve essere immediato e sempre raggiungibile (bottone flottante di Material —
FAB — o equivalente sempre visibile nelle schermate pertinenti).

## Accessibilità (minimi da rispettare)

- Contrasti sufficienti in entrambi i temi (Material 3 aiuta, ma va verificato
  sui colori di stato).
- Informazione mai veicolata dal solo colore.
- Dimensioni dei tocchi adeguate e testo scalabile.
