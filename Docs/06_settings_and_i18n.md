# 06 — Impostazioni e lingue

## Schermata Impostazioni

Contiene le configurazioni generali dell'app (tabella `Settings`, doc 02):

- **Lingua** dell'interfaccia (vedi sotto)
- **Tema**: Sistema / Chiaro / Scuro (default: Sistema — vedi
  `07_design_and_theming.md`)
- **Cloud / Google Drive**:
  - collega / scollega account Google
  - stato dell'ultimo backup (versione + data)
  - azioni: Carica su cloud / Scarica da cloud
  - attiva/disattiva l'uso del cloud
- Eventuali preferenze future (unità di misura, formato data, ecc.)

**La valuta non è configurabile**: è sempre l'euro (vedi doc 02). Della lingua
scelta dipende solo il *formato* con cui l'importo viene mostrato.

## Lingue

L'app supporta tre lingue, selezionabili dall'utente:

- **Italiano** (it)
- **Spagnolo** (es)
- **Inglese** (en)

### Regole tecniche per la localizzazione

- Tutti i testi mostrati all'utente devono essere **esterni al codice**, in
  file di traduzione (approccio ARB + `flutter_localizations` / gen_l10n). Mai
  stringhe visibili "cablate" nel codice.
- Il codice, i nomi di variabili e i commenti restano in **inglese** (vedi
  `CLAUDE.md`); la localizzazione riguarda solo i testi rivolti all'utente.
- Attenzione a numeri, date, valute e unità: vanno formattati secondo la lingua
  scelta.

## Nota

La documentazione di progetto (questa cartella `Docs/`) è in **italiano**. I
testi dell'interfaccia sono tradotti nelle tre lingue. Il codice è in inglese.
Sono tre piani distinti e non vanno confusi.
