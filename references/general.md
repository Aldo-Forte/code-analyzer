# Pattern comuni multi-linguaggio

## Pattern architetturali da riconoscere

- **Pipeline / Chain**: dati trasformati in sequenza attraverso funzioni
- **Observer / Event-driven**: callback, listener, subscribe/publish
- **Factory**: funzioni che creano e restituiscono altri oggetti/funzioni
- **Singleton**: una sola istanza condivisa (spesso moduli o config)
- **Middleware**: funzioni intermedie che intercettano richieste/risposte
- **DAO / Repository**: astrazione per accesso ai dati
- **Strategy**: comportamento intercambiabile tramite iniezione di funzioni

## Segnali di codice problematico

- Funzioni con più di 3-4 parametri non raggruppati → suggerisci oggetto config
- Nesting profondo (>3 livelli) → suggerisci early return o estrazione
- Variabili con nomi tipo `data`, `result`, `temp`, `x` → bassa leggibilità
- Commenti che spiegano il "cosa" invece del "perché" → codice non auto-esplicativo
- Duplicazione di logica in più punti → suggerisci astrazione
- Magic number o stringhe hardcoded → suggerisci costanti

## Sicurezza — da verificare sempre

- Input utente usato direttamente in query SQL → SQL injection
- Input utente renderizzato come HTML → XSS
- Credenziali o token hardcoded nel codice
- Uso di algoritmi crittografici custom o obsoleti (MD5, SHA1 per password)
- Deserializzazione di dati non fidati

## Performance — segnali da cercare

- Loop annidati su collezioni grandi → complessità O(n²) o peggio
- Query DB dentro un loop → N+1 problem (soluzione: eager loading, batch query, o join esplicito)
- Mancanza di caching per operazioni costose ripetute
- Caricamento sincrono di risorse che potrebbero essere lazy (pattern: lazy loading, dynamic `import()` in JS/TS, `importlib.import_module()` in Python, code splitting nei bundler)
