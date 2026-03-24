---
name: code-analyzer
version: 1.5.0
description: Analizza in profondità qualsiasi file o snippet di codice. Usare questa skill quando l'utente vuole capire cosa fa un pezzo di codice, vuole una spiegazione delle funzioni/classi, vuole sapere quali librerie vengono usate e cosa fanno, oppure vuole verificare la correttezza del codice cercando su internet. Attivare anche se l'utente dice "spiegami questo codice", "analizza questo file", "cosa fa questa funzione", "che librerie usa", "è corretto questo codice".
author: "Aldo Forte"
email: "dev@aldoforte.it"
repository: ""
license: MIT
---

# Code Analyzer

> **Versione**: 1.5.0 | **Autore**: *(vedi frontmatter)* | **Licenza**: MIT

Skill per l'analisi dettagliata di codice sorgente in qualsiasi linguaggio.
Accetta sia snippet incollati nel prompt che path di file su disco.

> ⚙️ **Personalizzazione**: compila i campi `author`, `email`, `repository` e `created`
> nel frontmatter YAML. Il campo `updated` viene aggiornato automaticamente ad ogni analisi.

---

## Input accettati

- **Snippet inline**: codice incollato direttamente nel messaggio
- **Path file**: percorso assoluto o relativo a un file sorgente
- **Path directory**: analisi ricorsiva di tutti i file sorgente trovati

Se viene fornito un path, leggi il file prima di procedere.
Se viene fornita una directory, elenca i file sorgente rilevanti e chiedi all'utente quali
analizzare (o analizzali tutti se sono pochi, es. ≤ 5 file).

---

## Output — report dir timestampata

**Ogni analisi produce una sottodirectory con timestamp** dentro `code-analyzer/`,
nella root del progetto (o nella directory di lavoro corrente se non è un progetto).

### Formato del nome

```
YYYY-MM-DDTHH:MM:SS-Report
```

Esempio: `2026-03-23T14:32:06-Report`

Questa directory si chiama **`{report_dir}`** nel resto della skill.
Ogni occorrenza di `{report_dir}` va sostituita con il path reale generato dallo script.

### Creazione automatica — PRIMO ATTO di ogni analisi

In questa fase definisci anche `{data_corrente}` = la data odierna nel formato `YYYY-MM-DD` (es. `2026-03-24`), da usare nelle intestazioni dei file generati nei Passi 11 e 12.

**Prima ancora del Passo 1**, esegui lo script di inizializzazione:

```bash
REPORT_DIR=$(bash <skill_path>/scripts/init_report_dir.sh <project_dir>)
```

Lo script crea la directory e restituisce il path assoluto su stdout.
Salva il path in `REPORT_DIR` e usalo per tutti i file di output. Il path è **assoluto** (lo script chiama `cd && pwd` internamente).

Per gli snippet inline (nessun `<project_dir>`), usa la directory di lavoro corrente:

```bash
REPORT_DIR=$(bash <skill_path>/scripts/init_report_dir.sh .)
```

Struttura attesa per ogni esecuzione:
```
code-analyzer/
└── 2026-03-23T14:32:06-Report/     ← {report_dir}, unica per ogni analisi
    ├── analysis.md                  ← report completo e dettagliato
    ├── summary.md                   ← scheda sintetica: cosa fa, funzioni, input/output, esempi
    ├── uml-schema.md                ← diagramma UML Mermaid (solo se classi rilevate)
    ├── database-schema.md           ← schema ER Mermaid (solo se tabelle rilevate)
    ├── requirements_python.txt      ← (solo se Python + venv rilevato)
    └── requirements_typescript.txt  ← (solo se TypeScript/Node rilevato)
```

Il timestamp con secondi garantisce unicità: non c'è mai sovrascrittura tra analisi diverse.
Se due analisi vengono avviate nello stesso secondo (caso rarissimo), lo script aggiunge automaticamente un contatore (`-1`, `-2`, …).

**Tracciamento fonti**: dal Passo 1b in poi, tieni una lista interna di ogni URL consultato
su internet. Questa lista verrà usata per compilare la tabella Fonti nel Passo 9.
Non dimenticare nessun URL — anche quelli che non hanno confermato problemi vanno inclusi.
Includi anche ricerche fatte nel Passo 1b (es. compatibilità versioni Python/Node).

---

## Processo di analisi

Segui sempre questi passi nell'ordine indicato.

---

### Passo 1 — Rilevamento del linguaggio

Identifica il linguaggio dal contenuto o dall'estensione del file.
Se ambiguo, dichiaralo esplicitamente all'inizio dell'analisi.

**Progetto misto (es. monorepo con Python + TypeScript)**: se rilevi entrambi i linguaggi,
trattali entrambi — esegui il Passo 1b per ciascuno e analizza i componenti di entrambe
le parti nel Passo 4. Indica chiaramente a quale linguaggio appartiene ogni sezione.

---

### Passo 1b — Estrazione dipendenze da ambiente

> ⚠️ **Prerequisito**: `$REPORT_DIR` deve essere già stato catturato eseguendo `init_report_dir.sh` (vedi sezione "Creazione automatica — PRIMO ATTO"). Non eseguire questo passo senza aver prima inizializzato `$REPORT_DIR`.

**Esegui questo passo subito dopo aver identificato il linguaggio**, prima dell'analisi.

> ⚠️ **Snippet inline**: se l'utente ha incollato codice senza fornire un path di progetto,
> **salta interamente questo passo** e segnala all'utente:
> "Nessun ambiente rilevabile da snippet inline — le versioni delle librerie verranno
> verificate solo tramite ricerca internet (Passo 3)."

Per trovare il path corretto degli script, cerca `SKILL.md` in queste posizioni nell'ordine:
1. `.agents/skills/code-analyzer/` (installazione a livello di progetto — tutti gli agenti)
2. `~/.codex/skills/code-analyzer/` (OpenAI Codex — globale)
3. `~/.claude/skills/code-analyzer/` (Claude Code — globale)
4. `~/.config/opencode/skills/code-analyzer/` (OpenCode — globale)
5. `~/.cursor/skills/code-analyzer/` (Cursor — globale)
6. `~/.windsurf/skills/code-analyzer/` (Windsurf — globale)
7. Cerca ricorsivamente in `~/.agents/skills/` e nelle sottocartelle skills di qualsiasi agente installato

Usa il path trovato come base: `<skill_path>/scripts/<script>.sh`

#### Python — virtual environment

Se il linguaggio include Python e viene fornito un path:

**Prerequisito — determina la root del progetto**: se il path è un file, risali le directory fino a trovare un venv, `requirements.txt`, `pyproject.toml`, o la root del repo git (`.git/`). Usa quella directory come `<project_dir>`.

1. Cerca un venv in: `.venv/`, `venv/`, `env/`, `.env/`, `virtualenv/`
2. Verifica la presenza di `bin/pip` (Linux/macOS) o `Scripts/pip` / `Scripts/pip.exe` (Windows)
3. Se trovato → esegui:
   ```bash
   bash <skill_path>/scripts/extract_requirements_python.sh <project_dir> "$REPORT_DIR"
   ```
   Lo script salva i requirements in `{report_dir}/requirements_python.txt`.
   > Nota: i warning di pip (es. pacchetti corrotti o obsoleti) vengono silenziati dallo script. Se i requirements sembrano incompleti, segnalalo all'utente e suggerisci di eseguire `pip freeze` manualmente.
4. Se non trovato → leggi `requirements.txt` o `pyproject.toml` come fallback e segnalalo.
   **Non usare pip di sistema** — i pacchetti globali non sono rappresentativi del progetto.

#### TypeScript / Node — package.json

Se il linguaggio include TypeScript o JavaScript:

**Prerequisito — determina la root del progetto**: se il path è un file, risali le directory finché trovi `package.json` o la root git (`.git/`). Usa quella come `<project_dir>`.

1. Verifica la presenza di `package.json` nella root del progetto
2. Verifica se `node_modules/` è presente
3. Esegui:
   ```bash
   bash <skill_path>/scripts/extract_requirements_typescript.sh <project_dir> "$REPORT_DIR"
   ```
   Lo script salva le dipendenze in `{report_dir}/requirements_typescript.txt`
4. Se `package.json` non esiste → segnalalo e prosegui
5. Controlla la presenza di `yarn.lock` o `pnpm-lock.yaml` per identificare il package manager

---

### Passo 2 — Panoramica generale

Produci questa struttura fissa (non prosa libera):

```
## Panoramica

**Scopo**: <una frase che descrive cosa fa il codice>
**Pattern architetturale**: <nome del pattern o "script procedurale" se non ne ha>
**Linguaggio/i**: <linguaggi rilevati>
**Dimensione**: <N righe totali (incluse vuote e commenti), M funzioni/classi>
**Complessità percepita**: Bassa / Media / Alta — <motivazione in una riga>
```

---

### Passo 3 — Librerie e dipendenze

Per ogni `import` / `require` / `use` / `include` trovato:
1. Nome della libreria
2. A cosa serve in questo codice specifico
3. Versione installata (da `{report_dir}/requirements_python.txt` o `{report_dir}/requirements_typescript.txt` se disponibile; altrimenti "—")
4. **Cerca su internet** la versione più recente → aggiungi l'URL alla lista fonti interne
5. Segnala deprecazioni o breaking change tra versione installata e attuale

**Formato tabella** (usalo sempre, anche per 1 sola libreria):

| Libreria | Versione installata | Versione attuale | Uso nel codice | Stato |
|---|---|---|---|---|
| nome | x.y.z oppure — | x.y.z | descrizione | 🟢 aggiornata / ⚠️ aggiornare / ❌ deprecata |

> Criteri stato: 🟢 = versione identica o solo patch diff; ⚠️ = minor o major version disponibile; ❌ = libreria ufficialmente deprecata o abbandonata (nessun commit da >2 anni).

> Se l'input è uno snippet inline, la colonna "Versione installata" sarà sempre "—":
> rimuovi la colonna e usa solo "Versione attuale (da web)".

---

### Passo 4 — Analisi dettagliata per componente

> ⚠️ **File lunghi (> 300 righe)**: analizza prima tutte le funzioni/classi pubbliche
> o esportate, poi quelle private. Per file molto grandi (> 800 righe) analizza solo
> i componenti pubblici e segnala all'utente che quelli privati sono stati omessi per brevità.
>
> ⚠️ **Directory con più file**: analizza ogni file separatamente seguendo i passi 4–8.
> Se i file sono molti (> 5), analizza prima i file principali (entry point, moduli pubblici)
> e segnala all'utente quali file sono stati omessi.

Per ogni funzione, classe, metodo o blocco logico significativo usa questa struttura fissa:

```
#### `nome_componente(parametri)` [TIPO]
- **Scopo**: cosa fa in una riga
- **Input**: elenco parametri con tipo atteso e valore di default se presente
- **Output**: tipo restituito e descrizione
- **Logica interna**: spiegazione passo-passo
- **Dipendenze interne**: altre funzioni/classi dello stesso file che usa (ometti se non ce ne sono)
- **Note**: edge case, side effect, comportamenti non ovvi (ometti se non ce ne sono)
```

Dove `[TIPO]` è uno tra: `funzione` / `classe` / `metodo` / `hook` / `middleware` / `decoratore` / `componente`.

---

### Passo 5 — Verifica correttezza API e librerie

Questo passo si concentra esclusivamente su **librerie e API esterne**.
I bug logici del codice vengono trattati nel Passo 6.

Per ogni chiamata a librerie esterne, framework o API HTTP:
1. **Cerca su internet** la documentazione ufficiale aggiornata → aggiungi URL alla lista fonti
2. Verifica che i metodi/parametri usati nel codice corrispondano alla versione installata
3. Segnala eventuali API deprecate, rename di metodi, o parametri rimossi

Se non trovi nessun problema, scrivi esplicitamente: "✅ Nessun problema API rilevato."

Formato per ogni problema trovato:
```
⚡ API-<N>: `libreria.metodo()`
- Problema: descrizione della discrepanza
- Versione affetta: introdotto in x.y.z / rimosso in x.y.z (indicare quale delle due si applica)
- Correzione: cosa usare al posto
- Fonte: <URL>
```

---

### Passo 6 — Bug e parti poco chiare

Questa sezione è **obbligatoria**. Se non trovi nulla, scrivi esplicitamente:
"✅ Nessun bug rilevato." e "✅ Nessuna ambiguità rilevata."

#### 6a — Bug rilevati

Verifica su internet se il comportamento è effettivamente un bug prima di segnalarlo.
Aggiungi ogni URL consultato alla lista fonti interna.

```
🐛 BUG-<N>
- Posizione: `nome_funzione` — riga indicativa
- Descrizione: cosa va storto e in quale condizione
- Impatto: 🔴 critico / 🟡 medio / 🟢 basso
- Riproduzione: esempio minimo che scatena il bug
- Correzione suggerita: come risolverlo
- Fonte: <URL che conferma il comportamento>
```

Tipologie da cercare attivamente:
- Off-by-one, condizioni al contorno non gestite
- Race condition o stato condiviso in contesti asincroni
- Eccezioni non catturate o catturate in modo troppo ampio (`except Exception` / `catch(e){}`)
- Mutazione accidentale di argomenti (liste/dict in Python, oggetti in JS)
- Promesse/async senza error handling
- Confronti errati (`==` vs `is` in Python, `==` vs `===` in JS)
- Memory leak (listener non rimossi, riferimenti circolari, interval non cancellati)
- Iniezioni (SQL injection, command injection, path traversal — nota: path traversal è difficile da rilevare staticamente senza contesto di esecuzione; segnala solo se il pattern è esplicito)
- Variabili non inizializzate o usate prima dell'assegnazione

#### 6b — Parti poco chiare o ambigue

```
⚠️ UNCLEAR-<N>
- Posizione: `nome_funzione` / blocco — riga indicativa
- Problema: perché è difficile da capire
- Suggerimento: come renderlo più leggibile (rinominare, estrarre, commentare)
```

---

### Passo 7 — Suggerimenti architetturali

**Consultivo**: proponi miglioramenti, non imporli. Suggerisci solo pattern pertinenti al
codice analizzato — non elencare tutti i pattern possibili.
Verifica ogni pattern su internet e aggiungi l'URL alla lista fonti.

#### 7a — Pattern applicabili

```
💡 PATTERN: <Nome del Pattern>
- Problema attuale: descrizione del problema architetturale che risolverebbe
- Soluzione proposta: come applicarlo a questo codebase specifico
- Beneficio atteso: leggibilità / testabilità / manutenibilità / performance
- Complessità di adozione: 🟢 bassa / 🟡 media / 🔴 alta
- Riferimento: <URL documentazione ufficiale o articolo autorevole>
```

Pattern da valutare per linguaggio (suggerisci solo quelli pertinenti):

**Python**: Dataclass/NamedTuple, Protocol/ABC, Context manager, Generator, Dependency injection
**TypeScript/JS**: Discriminated union, Builder, Repository, Custom hooks (React), Result type
**Generale**: Single Responsibility, Command/Query separation, Strategy, Observer, Factory

#### 7b — Anti-pattern rilevati

Elenca solo quelli effettivamente presenti:

```
🚫 ANTI-PATTERN: <Nome>
- Dove: `funzione` o file
- Descrizione: perché è problematico
- Alternativa: approccio consigliato
- Riferimento: <URL>
```

---

### Passo 8 — Metriche di qualità

Calcola o stima le metriche seguenti. Per la complessità ciclomatica usa questo metodo:
**CC = 1 + numero di (`if` + `elif` + `else if` + `for` + `while` + `case` + `except`/`catch` + `&&`/`and` + `||`/`or`)**
per funzione. Dichiara sempre che si tratta di una stima statica senza tool.

**Cerca su internet** i valori soglia e aggiungi gli URL alla lista fonti.

#### Metriche strutturali

| Metrica | Valore | Soglia consigliata | Stato |
|---|---|---|---|
| Righe totali del file | — | — | — |
| Numero funzioni/metodi | — | — | — |
| Lunghezza media funzioni (righe) | — | ≤ 20 | 🟢/🟡/🔴 |
| Funzione più lunga (righe + nome) | — | ≤ 50 | 🟢/🟡/🔴 |
| Complessità ciclomatica media (stima) | — | ≤ 10 | 🟢/🟡/🔴 |
| CC massima (funzione + nome) | — | ≤ 15 | 🟢/🟡/🔴 |
| Profondità massima di nesting | — | ≤ 3 livelli | 🟢/🟡/🔴 |
| Numero parametri medio per funzione | — | ≤ 4 | 🟢/🟡/🔴 |
| Rapporto commenti/righe codice | —% | 10–30% | 🟢/🟡/🔴 |

#### Metriche per linguaggio

**Python** (se applicabile):

| Metrica | Valore | Soglia | Stato |
|---|---|---|---|
| Copertura type hints (funzioni pubbliche) | —% | ≥ 80% | 🟢/🟡/🔴 |
| Uso f-string vs concatenazione `+` | — | 100% f-string | 🟢/🟡/🔴 |
| Bare `except` senza tipo | — | 0 | 🟢/🟡/🔴 |
| Argomenti mutabili come default | — | 0 | 🟢/🟡/🔴 |

**TypeScript / JavaScript** (se applicabile):

| Metrica | Valore | Soglia | Stato |
|---|---|---|---|
| Occorrenze di `any` | — | 0 in TS | 🟢/🟡/🔴 |
| Promise senza `.catch()` o try/catch | — | 0 | 🟢/🟡/🔴 |
| Uso di `var` | — | 0 | 🟢/🟡/🔴 |
| `console.log` non rimossi | — | 0 in produzione | 🟢/🟡/🔴 |
| Componenti React > 300 righe | — | 0 | 🟢/🟡/🔴 |

#### Score complessivo

| Dimensione | Score /10 | Motivazione |
|---|---|---|
| Leggibilità | —/10 | — |
| Manutenibilità | —/10 | — |
| Robustezza | —/10 | — |
| Sicurezza | —/10 | — |
| Aggiornamento dipendenze | —/10 | — |
| **Media** | **—/10** | — |

---

### Passo 9 — Riepilogo finale e fonti

#### Riepilogo

Tre frasi:
1. Cosa funziona bene nel codice
2. Cosa è urgente correggere (bug critici / dipendenze pericolose)
3. Il prossimo passo più importante consigliato

#### Fonti consultate

Elenca **tutti** gli URL raccolti durante i Passi 1b, 3, 5, 6, 7, 8, 11 e 12.
Se una fonte non era raggiungibile, scrivi "(non raggiungibile)" nella colonna URL.

| # | URL | Usata per |
|---|---|---|
| 1 | <sostituire con URL reale> | <passo e motivo> |
| 2 | <sostituire con URL reale> | <passo e motivo> |

> ⚠️ Non lasciare righe con `<sostituire con URL reale>` nel documento finale.
> Se non hai consultato fonti per un passo, ometti quelle righe.

---

Salva il report completo (Passi 2–9) in `{report_dir}/analysis.md`.
Il documento deve iniziare con il titolo: `# Analisi — {nome_file_o_progetto}`, dove `{nome_file_o_progetto}` è il nome del file o del progetto analizzato (es. `app.py`, `src/utils.ts`, `myproject`). Sostituire le graffe con il nome reale.
Seguono i contenuti dei Passi 2–9 nell'ordine.

---

### Passo 10 — Scheda sintetica `summary.md`

Genera **`{report_dir}/summary.md`** pensato per essere letto rapidamente.
Salvalo subito dopo `{report_dir}/analysis.md`.

#### Struttura di `summary.md`

```markdown
# Sommario — {nome_file_o_progetto}

## Cosa fa questo codice
- <punto 1: scopo in linguaggio semplice>
- <punto 2>
- <punto 3>
<!-- istruzione: scrivere 3-5 bullet; questa riga non va nel file finale -->

---

## Funzioni / Componenti principali

<!-- ISTRUZIONI (rimuovere tutti i commenti HTML prima di salvare il file): -->
<!-- Per classi: aggiungere riga "**Stato interno**: attr1, attr2" prima dei metodi -->
<!-- {tipo}: sostituire con funzione / classe / metodo / hook / middleware / decoratore / componente -->
### `nome_funzione` — {tipo}
- **Scopo**: una riga
- **Input**: `param1` (`tipo`) — descrizione; `param2` (`tipo`, default: `val`) — descrizione
- **Output**: `tipo` — descrizione
- **Esempio** (codice indentato, non fence annidato):

        risultato = nome_funzione(valore_realistico)
        // → valore_atteso

  **Caso limite**:

        risultato = nome_funzione(valore_estremo)
        // → eccezione XYZ / None / []

---

> 📄 Analisi completa, metriche e fonti: vedere `analysis.md` nella stessa cartella
```

#### Caso speciale — script senza funzioni

Se il file è uno script top-level senza funzioni/classi, sostituisci la sezione componenti con:

```markdown
## Flusso di esecuzione

1. **<titolo blocco>**: descrizione
2. **<titolo blocco>**: descrizione
```

#### Regole

- Includi tutte le funzioni/classi **pubbliche o esportate**; quelle private solo se essenziali.
- Esempi **realistici**: mai `foo`/`bar`/`test` — usa valori del dominio reale.
- Ogni esempio mostra input + output atteso. Aggiungi sempre un caso limite se la funzione
  può fallire, sollevare eccezioni, o restituire un valore speciale (None, [], null, -1).
- Massimo **5 righe** di descrizione per funzione.
- Classi: aggiungi una riga "**Stato interno**" con gli attributi principali prima dei metodi.
- **Rimuovi tutti i commenti HTML** (`<!-- ... -->`) prima di salvare il file finale.

---

### Passo 11 — Diagramma UML `uml-schema.md`

Esegui questo passo **solo se** nel codice sono presenti almeno uno tra:
classi, interfacce, tipi strutturati, enumerazioni, protocolli, abstract class, dataclass, struct.

Se non ne trovi nessuno, **salta il passo** e segnala: "⏭ Passo 11 saltato — nessuna classe/interfaccia rilevata."

#### 11a — Elementi da includere

- **Classi** con attributi (nome e tipo) e metodi (nome, parametri, tipo di ritorno)
- **Interfacce / Protocol / ABC** con i metodi che definiscono
- **Enumerazioni** con i valori
- **Relazioni** tra classi:
  - Ereditarietà (`--|>`)
  - Implementazione di interfaccia (`..|>`)
  - Composizione (`*--`)
  - Aggregazione (`o--`)
  - Associazione (`-->`)
  - Dipendenza (`..>`)
- **Visibilità**: `+` pubblico, `-` privato, `#` protetto, `~` package (concetto Java — usa solo se il linguaggio lo supporta esplicitamente; ometti per Python e TypeScript)

#### 11b — Regole di precisione

- Usa solo relazioni **effettivamente presenti** nel codice — non inferire relazioni non esplicite.
- Per attributi e metodi, usa i **tipi reali** trovati nel codice, non tipi generici.
- Se un tipo è sconosciuto o non annotato: usa `Any` (Python — da `typing.Any`); per TypeScript preferisci `unknown` (più sicuro, richiede type-narrowing esplicito) e usa `any` solo come ultima risorsa; per JavaScript usa `any`.
- Se il codice ha molte classi (> 15), includi solo quelle pubbliche/esportate e le loro relazioni dirette; segnala le classi omesse.

#### 11c — Formato del file

Salva in **`{report_dir}/uml-schema.md`**.

> ⚠️ **Attenzione al rientro**: il template qui sotto usa 4 spazi di rientro per evitare conflitti con il parser del SKILL.md. Nel file generato **non usare rientri** — il blocco Mermaid — il rientro a 4 spazi è usato qui solo per mostrare il template senza rompere il SKILL.md. Nel file generato apri il blocco con tre backtick seguiti da `mermaid` a colonna 0, senza rientro.

    # UML Schema — <nome file o progetto>  ← sostituire con il nome reale

    > Generato da code-analyzer — <data_corrente>  ← sostituire con YYYY-MM-DD

    ```mermaid
    classDiagram
        class NomeClasse {
            +attributo1 Tipo
            -attributo2 Tipo
            +metodo1(Tipo param) TipoRitorno
            -metodo2() void
        }
        class Interfaccia {
            <<interface>>
            +metodoAstratto() void
        }
        class Enumerazione {
            <<enumeration>>
            VALORE1
            VALORE2
        }
        NomeClasse --|> ClasseBase
        NomeClasse ..|> Interfaccia
        NomeClasse *-- AltroComponente
    ```

    ## Note
    - <eventuali chiarimenti su relazioni ambigue o tipi non annotati>

---

### Passo 12 — Schema database `database-schema.md`

Esegui questo passo **solo se** nel codice sono presenti definizioni o utilizzi di tabelle di database o collection. Fonti da riconoscere:

- **SQL** puro: `CREATE TABLE`, `ALTER TABLE`, definizioni ORM (SQLAlchemy, TypeORM, Prisma, Hibernate, ActiveRecord, Django ORM, Sequelize, Drizzle…)
- **NoSQL document** (MongoDB, CosmosDB modalità document): definizioni di schema (Mongoose, MongoEngine, Spring Data MongoDB…)
- **Cloud table storage**: Azure Table Storage, AWS DynamoDB, Google Firestore/Bigtable — riconoscibili da SDK calls o definizioni di entità
- **In-memory / embedded**: SQLite, H2, embedded Redis con strutture definite

Se non trovi nessuna di queste fonti, **salta il passo** e segnala: "⏭ Passo 12 saltato — nessuna definizione di tabella/collection rilevata."

#### 12a — Elementi da includere

Per ogni tabella / collection / entità trovata:
- **Nome** della tabella o collection
- **Campi**: nome del campo e tipo dato. Usa il tipo nativo del DB quando possibile (`INT`, `BIGINT`, `BOOLEAN`, `TIMESTAMP`, `UUID`, `ObjectId`, `String`, `Number`…). Poiché Mermaid erDiagram non supporta parentesi nei nomi di tipo, sostituisci `()` con `_`: `VARCHAR(255)` → `VARCHAR_255`, `DECIMAL(10,2)` → `DECIMAL_10_2`.
- **Chiave primaria** (PK) — marcala con `PK`
- **Chiave esterna** (FK) — marcala con `FK` nel campo Mermaid. La tabella referenziata va indicata nella riga di relazione (`TABELLA ||--o{ ALTRA : "..."`) e nella sezione `## Relazioni`, NON inline nel campo (Mermaid erDiagram non supporta FK inline con target)
- **Vincoli notevoli**: `NOT NULL`, `UNIQUE`, `INDEX` — includili solo se esplicitamente presenti nel codice
- Per NoSQL: se lo schema non è esplicito, documenta la struttura dedotta dai dati usati nel codice e segnala che si tratta di una struttura inferita

#### 12b — Regole di precisione

- Usa solo campi **effettivamente definiti** nel codice — non aggiungere campi presunti.
- Se un tipo non è specificato, usa `unknown` come placeholder testuale (Mermaid lo renderà come testo, non è un tipo SQL standard — aggiungi una nota in `## Note` se necessario).
- Se una FK è implicita (join senza constraint esplicito), marcala comunque come `FK` nel campo Mermaid e aggiungi una nota nella sezione "## Note" del documento: "Campo `nome_campo` in `tabella`: FK implicita verso `tabella_referenziata` — non presente come constraint nel codice."
- Se il database è multitenancy o sharding, segnalalo nelle Note.

#### 12c — Formato del file

Salva in **`{report_dir}/database-schema.md`**.
`{nome ORM/SDK/tipo DB rilevato}`: sostituisci con il nome effettivo rilevato nel codice, es. `Prisma`, `SQLAlchemy`, `Mongoose`, `AWS DynamoDB SDK`, `Azure Table Storage SDK`, ecc.

> ⚠️ **Attenzione al rientro**: il template qui sotto usa 4 spazi di rientro per evitare conflitti con il parser del SKILL.md. Nel file generato **non usare rientri** — il blocco Mermaid — il rientro a 4 spazi è usato qui solo per il template. Nel file generato apri il blocco con tre backtick seguiti da `mermaid` a colonna 0, senza rientro.

    # Database Schema — <nome file o progetto>  ← sostituire con il nome reale

    > Generato da code-analyzer — <data_corrente>  ← sostituire con YYYY-MM-DD
    > Fonte: <nome ORM/SDK>  ← sostituire con es. Prisma, SQLAlchemy, Mongoose

    ```mermaid
    erDiagram
        NOME_TABELLA {
            UUID id PK
            VARCHAR_255 nome
            INT eta
            TIMESTAMP created_at
        }
        ALTRA_TABELLA {
            INT id PK
            INT utente_id FK
            TEXT contenuto
            BOOLEAN attivo
        }
        NOME_TABELLA ||--o{ ALTRA_TABELLA : "ha molti"
    ```

    ## Relazioni
    | Tabella | Campo FK | Referenzia | Cardinalità |
    |---|---|---|---|
    | ALTRA_TABELLA | utente_id | NOME_TABELLA.id | many-to-one |

    ## Note
    - <chiarimenti su tipi inferiti, FK implicite, strutture NoSQL dedotte, ecc.>

---

Al termine comunica all'utente il path della report dir e i file prodotti:
- `{report_dir}/analysis.md` — report completo (analisi, bug, pattern, metriche, fonti)
- `{report_dir}/summary.md` — scheda sintetica con funzioni, input, output ed esempi
- `{report_dir}/uml-schema.md` — diagramma UML classDiagram Mermaid (se classi rilevate)
- `{report_dir}/database-schema.md` — schema ER erDiagram Mermaid (se tabelle rilevate)
- `{report_dir}/requirements_python.txt` — (se estratto)
- `{report_dir}/requirements_typescript.txt` — (se estratto)

---

## Regole generali

- **Cerca sempre su internet** prima di affermare che una libreria, funzione o pattern è
  corretto/deprecato. Non fidarti della sola conoscenza interna.
- Usa sempre il linguaggio dell'utente (italiano se scrive in italiano).
- Nomi di funzioni, variabili e librerie sempre in `backtick`.
- Se qualcosa è ambiguo o poco chiaro, dillo esplicitamente — non inventare spiegazioni.
- Aggiorna il campo `updated` nel frontmatter di questo `SKILL.md` con la data corrente al termine di ogni analisi. Il formato è `"YYYY-MM-DD"` (es. `"2026-03-24"`). Modifica la riga `updated: ""` sostituendo il valore tra le virgolette.

---

## Riferimenti aggiuntivi

Per linguaggi specifici, leggi il file corrispondente in `references/` quando disponibile:
- `references/python.md` — convenzioni Python, PEP, librerie comuni
- `references/javascript.md` — ecosistema JS/TS, Node, browser API
- `references/general.md` — pattern comuni multi-linguaggio
