# 04 — Logica di manutenzione

Questo è il documento più "di dominio": raccoglie tutte le regole di calcolo e
di comportamento della parte manutentiva. Le decisioni qui derivano anche
dall'analisi dei manuali reali di Fiat Grande Punto e Toyota Yaris Hybrid.

## Catalogo tipi di manutenzione (MaintenanceType)

Lista comune, raggruppata per famiglia per ritrovarla facilmente quando cresce.
Precaricata con le voci più comuni, e modificabile dall'utente.

- **Fluidi**: olio motore, olio cambio manuale, olio cambio automatico, liquido
  freni, liquido refrigerante
- **Filtri**: filtro aria, filtro antipolline/abitacolo, filtro carburante
- **Gomme**: pneumatici, **rotazione/permuta gomme**, **allineamento/convergenza**
- **Batteria**: batteria 12V (controllo e sostituzione)
- **Motore**: candele, cinghia distribuzione, cinghia accessori
- **Freni**: freni anteriori, freni posteriori (vedi sezione dedicata)
- **Altro**: voci libere aggiunte dall'utente

I due manuali confermano la struttura: il Punto usa intervalli a km **e** a
tempo con regola "scatta il primo dei due" (es. olio motore a ogni tagliando
*oppure* ogni 24 mesi, 12 mesi se pochi km/città; cinghia distribuzione ogni
4–5 anni a prescindere dai km); la Yaris rimanda molti intervalli a un libretto
separato e a volte fornisce solo un criterio (solo km o solo tempo). La
struttura deve quindi reggere: solo km, solo tempo, o entrambi.

## Criterio configurato per veicolo (MaintenanceRule)

Assegnare un criterio a un veicolo significa pescare un tipo dal catalogo e
dargli gli intervalli di *quel* veicolo:

- Scadenza in km (opzionale)
- Scadenza in tempo in mesi (opzionale)
- Se presenti entrambe → **scatta la prima che si verifica**
- Ultimo intervento noto (data + km) → base per calcolare la prossima scadenza

Un tipo già assegnato a un veicolo **non ricompare** tra le scelte per lo
stesso veicolo, così non si creano doppioni. Resta disponibile per gli altri
veicoli.

### Come scattano le scadenze

- **A tempo**: calcolabile nel tempo → genera una notifica alla data prevista.
- **A km**: l'app non conosce i km in tempo reale, quindi non può notificare da
  sola. Le voci in scadenza a km vengono **evidenziate** all'apertura dell'app
  e quando si aggiorna il totalizzatore, confrontando la soglia con il km
  attuale del veicolo.

## Freni (logica per asse)

Modello: **asse → tipo di impianto → componenti, ciascuno con scadenza
propria.**

- Un freno appartiene a un **asse**: anteriore o posteriore. Si può agire su un
  solo asse o su entrambi.
- Per ciascun asse si indica il **tipo di impianto**:
  - a **disco** → componenti: **pastiglie** (si consumano) + **disco** (dura di
    più)
  - a **tamburo** → componenti: **ganasce** (si consumano) + **tamburo** (dura
    di più)
- Ogni componente ha la **sua** scadenza indipendente, in km e/o tempo. La
  pastiglia si sostituisce più spesso del disco; la ganascia più spesso del
  tamburo.
- Il componente "contenitore" (disco/tamburo) esiste solo se c'è quello che si
  consuma (non ha senso un disco senza pastiglia).

Nei manuali i freni compaiono come **controllo usura** a ogni tagliando, non
come sostituzione a scadenza fissa: per questo la distinzione controllo vs
sostituzione (sotto) vale anche qui.

## Controllo vs sostituzione

Sono due cose diverse e complementari, entrambe registrabili:

- **Sostituzione** — ho cambiato un componente. Azzera il contatore del criterio
  e fa ripartire la scadenza.
- **Controllo** — ho ispezionato. Non azzera nulla. Può essere:
  - **con misura** (vedi sotto)
  - **generico non classificato** (solo nota libera)

## Controllo con misura

Registra un valore numerico ispezionato in una certa data/km, costruendo uno
**storico di valori** da cui si vede la tendenza (es. battistrada 7 → 5 → 3 mm).

- Grandezza (battistrada, spessore pastiglie, tensione batteria, ...)
- Valore + unità (mm, V, ...)
- **Soglia di allarme** opzionale: se l'ultimo valore scende sotto la soglia,
  l'app avvisa. Utile per anticipare una sostituzione prima che scatti una
  scadenza fissa.

## Rifornimenti e consumi

Ogni rifornimento è **autoconsistente**: contiene i dati per calcolare il
consumo da solo, senza dipendere dal rifornimento precedente (metodo "per
singolo pieno", non "range tra due pieni").

Campi:

- **Km percorsi** con quel pieno (dal contachilometri parziale/trip azzerato a
  ogni pieno). NON è il totalizzatore.
- **Litri**
- **Prezzo al litro** (inserito dall'utente)

Calcoli fatti dall'app:

- **Consumo** del singolo rifornimento = km percorsi ÷ litri. (Questo calcolo
  l'app lo fa; il totale speso NON viene calcolato in automatico, per scelta.)
- Report **consumo medio** (totale o per periodo).
- Report **spesa totale in carburante** per periodo.

Attenzione a non confondere i due tipi di km:

- **Km percorsi** (nel rifornimento) → solo per il consumo. NON tocca né il
  totalizzatore né lo storico chilometraggio.
- **Km totale / totalizzatore** (stato del veicolo) → per le scadenze. Vive in
  `Vehicle.km_attuale` e nello storico `MileageReading`.

## Chilometraggio

### Km attuale del veicolo

Il veicolo ha un "km attuale" (ultimo valore noto del totalizzatore), usato per
calcolare le scadenze a km. Si aggiorna **manualmente** dall'utente.

### Storico chilometraggio (MileageReading)

Registro indipendente delle letture del totalizzatore nel tempo, per il report
"km percorsi vs tempo". Regole:

- Si aggiorna **solo** quando l'utente aggiorna il totalizzatore in modo
  esplicito. Il km scritto sulle singole voci (manutenzioni, rifornimenti...)
  **non** entra qui: resta dentro la voce. Motivo: così un eventuale errore su
  una voce non finisce incastrato in mezzo alla serie, dove non sarebbe
  correggibile con la regola "cancella solo l'ultima".
- Una nuova lettura **non può essere inferiore** all'ultima valida (il
  contachilometri non torna indietro): l'app blocca e segnala.
- Un valore enormemente più alto (probabile refuso, es. 850.000 invece di
  85.000) **chiede conferma** prima di accettarlo — non lo vieta, perché
  potrebbe essere reale.
- Si può cancellare **solo l'ultima** lettura. Dopo la cancellazione la
  penultima diventa l'ultima e diventa a sua volta cancellabile
  (comportamento "annulla a ritroso"). Mai togliere letture intermedie: la
  serie resta sempre coerente e crescente.

## Specifiche di fabbrica del veicolo

Nella scheda veicolo si registrano i dati raccomandati dal costruttore, usati
come base per creare i criteri e per riferimento:

- Tipo di carburante
- Olio motore raccomandato
- Intervalli di manutenzione consigliati (in km e/o tempo), che alimentano le
  `MaintenanceRule`
