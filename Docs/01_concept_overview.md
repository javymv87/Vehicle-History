# 01 — Visione generale

## Cos'è

Applicazione mobile (Android in prima battuta, costruita con Flutter e quindi
predisposta anche per iOS in futuro) per tenere lo **storico completo di uno o
più veicoli**: manutenzioni, riparazioni, rifornimenti, controlli, spese,
scadenze legali e documenti.

Non è un'app "collegata al veicolo" (nessun OBD, nessuna diagnostica): è un
**registro digitale** curato a mano, pensato per sostituire il classico
quaderno delle manutenzioni e la scatola di ricevute.

## A chi serve

- Un **singolo utente** (l'app è mono-utente) che usa l'app dal proprio
  telefono.
- Quell'utente può gestire **più veicoli**, non solo il proprio: anche auto di
  familiari o di persone di cui tiene i conti. Per questo ogni veicolo è
  collegato a un **proprietario** (anagrafica dedicata).

## Che problema risolve

- Sapere sempre **cosa è stato fatto** su un veicolo e **quando** (data + km).
- Sapere **cosa va fatto** e **quando scade** (manutenzione programmata,
  bollo, revisione, assicurazione, documenti personali).
- Sapere **quanto si è speso** (per veicolo, per tipo, per periodo).
- Poter **dimostrare** la storia manutentiva del veicolo — utile per la
  rivendita o il passaggio di proprietà — tramite un report completo
  esportabile.
- Avere tutto **al sicuro**: i dati vivono sul telefono e possono essere
  copiati sul cloud (Google Drive) per recuperarli su un altro telefono.

## Principio guida (il più importante)

**Velocità d'uso prima di tutto.** Le app di questo tipo vengono abbandonate
in fretta quando l'inserimento è lento o macchinoso. Ogni funzione potente
(consumi, scadenze automatiche, controlli-misura) deve restare *opzionale* e
non appesantire l'inserimento quotidiano di una voce. Registrare un
rifornimento o una manutenzione deve richiedere pochi tocchi; i dettagli
avanzati stanno in sezioni espandibili, mai obbligatorie dove non hanno senso.

## Confini della versione 1 (cosa NON facciamo)

Per restare semplici e non dipendere da servizi esterni, la prima versione
**esclude**:

- Richiami di sicurezza / recall del costruttore (richiedono database
  commerciali, spesso solo per il mercato USA).
- Stima costi di riparazione e ricerca officine vicine (servizi di terzi).
- Diagnostica OBD / collegamento alla centralina.
- Veicoli elettrici (per ora si ragiona su motori termici benzina/diesel; la
  struttura non va però resa rigida al punto da impedirlo in futuro).

## Le sezioni dell'app

1. **Elenco veicoli** — con foto, nome/targa.
2. **Scheda veicolo** — anagrafica, specifiche di fabbrica, km attuale.
3. **Storico voci** — l'elenco scorrevole di tutto ciò che è successo.
4. **Documenti** — libretto, assicurazione, ecc. (stato attuale, non eventi).
5. **Scadenze / promemoria** — manuali e automatici dai dati di fabbrica.
6. **Report** — spese, per tipo, consumi, generale.
7. **Impostazioni** — lingua, cloud/backup.
8. **Anagrafica proprietari** — persone e loro documenti personali.

Il dettaglio di ciascuna sezione è nei documenti successivi.
