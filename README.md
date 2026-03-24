# code-analyzer

**Versione**: 1.5.0 · **Licenza**: MIT · **Standard**: [Agent Skills](https://agentskills.io)

Skill per agenti AI di coding che analizza in profondità qualsiasi file sorgente o snippet di codice. Spiega cosa fa il codice, documenta ogni funzione, rileva bug, verifica le dipendenze su internet, genera diagrammi UML e schemi di database, e produce metriche di qualità — tutto salvato automaticamente in una directory con timestamp.

---

## Output prodotti

Ogni analisi crea una sottodirectory timestampata `code-analyzer/YYYY-MM-DDTHH:MM:SS-Report/` contenente:

| File | Contenuto |
|---|---|
| `analysis.md` | Report completo: panoramica, analisi componenti, verifica API, bug, pattern architetturali, metriche, fonti |
| `summary.md` | Scheda sintetica: cosa fa il codice, input/output di ogni funzione, esempi realistici con casi limite |
| `uml-schema.md` | Diagramma UML Mermaid `classDiagram` con classi, interfacce, relazioni e visibilità *(se rilevate)* |
| `database-schema.md` | Schema ER Mermaid `erDiagram` con tabelle, campi, PK, FK e relazioni *(se rilevate)* |
| `requirements_python.txt` | Dipendenze estratte dal virtual environment *(se presente)* |
| `requirements_typescript.txt` | Dipendenze da `package.json` e versioni installate *(se presente)* |

---

## Compatibilità

Segue lo **standard aperto [Agent Skills](https://agentskills.io)** — funziona su tutti i principali agenti AI:

| Agente | Istruzioni | Script bash |
|---|---|---|
| **OpenAI Codex CLI** | X | X |
| **Claude Code** | X | X |
| **GitHub Copilot** (VS Code) | X | X |
| **Cursor** | X | X |
| **Windsurf** | X | X |
| **Google Gemini CLI** | X | X |
| **OpenCode** | X | X |
| **Goose** (Block) | X | X |
| **Roo Code** | X | X |
| **Amp** | X | X |

Gli script bash (estrazione dipendenze da venv e node_modules) richiedono accesso alla shell locale. Su agenti senza shell, le versioni vengono verificate tramite ricerca internet.

---

## Installazione

### Metodo 1 — Manuale

```bash
# Estrai il pacchetto
tar -xzf code-analyzer.tar.gz

# Copia nella cartella skills del tuo agente
cp -r code-analyzer ~/.codex/skills/             # OpenAI Codex
cp -r code-analyzer ~/.claude/skills/            # Claude Code
cp -r code-analyzer ~/.config/opencode/skills/   # OpenCode
cp -r code-analyzer ~/.cursor/skills/            # Cursor
cp -r code-analyzer ~/.windsurf/skills/          # Windsurf

# Rendi eseguibili gli script (Linux/macOS)
chmod +x <skills_dir>/code-analyzer/scripts/*.sh

# Riavvia l'agente e verifica
/skills
```

### Metodo 2 — npx skills CLI

```bash
# Estrai prima il pacchetto
tar -xzf code-analyzer.tar.gz

# Installa su tutti gli agenti rilevati
npx skills add ./code-analyzer --all

# Oppure su agenti specifici
npx skills add ./code-analyzer -a claude-code -a cursor -a codex
```

>  La struttura installata deve essere `<skills_dir>/code-analyzer/SKILL.md` — non un livello annidato in più.

---

## Utilizzo

**Invocazione esplicita** (digita `$` seguito dal nome skill):
```
$code-analyzer analizza src/app.py
$code-analyzer analizza il progetto in /home/user/myapp
$code-analyzer cosa fa questo codice: <incolla snippet>
```

**Invocazione implicita** — l'agente attiva la skill automaticamente con frasi come:
- *"spiegami questo codice"*
- *"analizza questo file"*
- *"cosa fa questa funzione?"*
- *"che librerie usa?"*
- *"è corretto questo codice?"*
- *"ci sono bug qui?"*

---

## I 12 passi di analisi

| Passo | Cosa fa |
|---|---|
| **1** | Rileva il linguaggio — supporta progetti misti Python + TypeScript |
| **1b** | Estrae le dipendenze dal venv Python o da `node_modules` |
| **2** | Panoramica: scopo, pattern architetturale, dimensione, complessità |
| **3** | Tabella librerie: versione installata vs attuale (verificata online) con stato aggiornamento |
| **4** | Analisi dettagliata di ogni funzione/classe: input, output, logica interna |
| **5** | Verifica correttezza API e librerie esterne su internet |
| **6** | Bug rilevati con impatto e riproduzione + parti poco chiare |
| **7** | Suggerimenti architetturali consultivi: pattern applicabili e anti-pattern |
| **8** | Metriche di qualità: complessità ciclomatica, nesting, type hints, `any`, `var`… |
| **9** | Riepilogo in 3 frasi + tabella completa delle fonti consultate su internet |
| **10** | `summary.md` sintetico con esempi e casi limite per ogni funzione |
| **11** | `uml-schema.md` — diagramma Mermaid `classDiagram` *(se classi/interfacce rilevate)* |
| **12** | `database-schema.md` — schema Mermaid `erDiagram` con PK, FK e relazioni *(se tabelle rilevate)* |

---

## Linguaggi supportati

Qualsiasi linguaggio per l'analisi. Estrazione automatica delle dipendenze per:

- **Python** — virtual environment (`.venv`, `venv`, `env`, `.env`, `virtualenv`), fallback su `requirements.txt` / `pyproject.toml`
- **TypeScript / JavaScript** — `package.json` + `node_modules`, compatibile con **npm**, **Yarn v1**, **Yarn Berry (v2+)** e **pnpm**

---

## Struttura della skill

```
code-analyzer/
├── SKILL.md                                ← istruzioni per l'agente
├── scripts/
│   ├── init_report_dir.sh                  ← crea la report dir timestampata
│   ├── extract_requirements_python.sh      ← estrae dipendenze dal venv Python
│   └── extract_requirements_typescript.sh  ← estrae dipendenze da node_modules
└── references/
    ├── general.md                          ← pattern e anti-pattern multi-linguaggio
    ├── python.md                           ← PEP, convenzioni, librerie comuni
    └── javascript.md                       ← ES versioni, npm, TypeScript, checklist async
```

---

## Licenza

MIT
