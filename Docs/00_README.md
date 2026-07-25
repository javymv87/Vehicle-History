# Documentazione — App gestione storico veicoli

Documento generale di concept, redatto **prima** di scrivere codice. È la
fonte di verità condivisa. La documentazione è in **italiano**; il codice sarà
in **inglese** (vedi `../CLAUDE.md`).

## Indice

1. [`01_concept_overview.md`](01_concept_overview.md) — Visione generale, a chi
   serve, principio guida, confini della versione 1, sezioni dell'app.
2. [`02_data_model.md`](02_data_model.md) — Tabelle del database locale, campi,
   relazioni, campi tecnici per sync e storico operazioni.
3. [`03_features.md`](03_features.md) — Storico, filtri, promemoria/notifiche,
   report, spese nella manutenzione, regole UX dei messaggi, foto.
4. [`04_maintenance_logic.md`](04_maintenance_logic.md) — Catalogo tipi,
   criteri per veicolo, scadenze km/tempo, freni per asse, controllo vs
   sostituzione, controlli-misura, rifornimenti/consumi, storico km.
5. [`05_sync_and_storage.md`](05_sync_and_storage.md) — Archiviazione locale e
   backup su Google Drive (Strada A con guardia di versione), predisposizione
   futura.
6. [`06_settings_and_i18n.md`](06_settings_and_i18n.md) — Impostazioni e
   lingue IT/ES/EN.
7. [`07_design_and_theming.md`](07_design_and_theming.md) — Design system
   Material 3, temi chiaro/scuro, principi di leggibilità e colore.

## Sintesi in una frase

App mobile mono-utente (Flutter, Android prima, iOS possibile poi) per tenere
lo storico completo di uno o più veicoli — manutenzioni, rifornimenti, spese,
controlli, scadenze e documenti — offline, con backup manuale su Google Drive
e report esportabili in PDF.

## Stato

Concept completo. Prossimo passo: impostazione del progetto Flutter secondo la
struttura descritta in `../CLAUDE.md`.
