# FreeLLMScanner

FreeLLMScanner ist ein kleiner Bash-basierter Scanner und Funktionstester für LLM-Provider mit OpenAI-kompatiblen APIs.

Das Ziel ist nicht nur, Modellnamen aus statischen Listen abzufragen. Der Scanner holt die aktuell angebotenen Modelle direkt über den jeweiligen `/models`-Endpoint, versucht daraus kostenlose Modelle zu erkennen und testet diese anschließend mit einer minimalen Chat-Completion.

> **Aktueller Stand:** Die Erkennung ist noch hybrid. Wo ein Provider keinen eindeutigen Free-Status über die API liefert, existieren derzeit noch provider-spezifische Fallback-Listen. Diese werden gegen die tatsächlich vom Provider gelieferten Modell-IDs gefiltert.

## Was der Scanner macht

Für jeden ausgewählten Provider läuft im Hauptscanner grundsätzlich folgende Kette:

1. `/models` abrufen
2. verfügbare Modell-IDs erfassen
3. Free-Status aus API-Metadaten ableiten
4. bekannte provider-spezifische Free-Modelle als Fallback ergänzen
5. alles gegen die aktuell verfügbaren Modelle filtern
6. die als Free eingestuften Modelle über `/chat/completions` testen
7. Ergebnisse nach `results.json` schreiben
8. im `--check`-Modus zusätzlich `check_state.json` aktualisieren

Ein Modell gilt im Hauptscanner aktuell als Free, wenn mindestens eine dieser Bedingungen zutrifft:

- `isFree == true`
- `pricing.prompt/input == 0` und `pricing.completion/output == 0`
- die Modell-ID auf `free` endet, z. B. `:free` oder `-free`
- Sonderfall `big-pickle`
- das Modell steht in der provider-spezifischen Fallback-Liste und wird aktuell vom `/models`-Endpoint angeboten

**Wichtig:** Die Ausgabe `PAID` bedeutet derzeit technisch nur: _von der aktuellen Logik nicht als Free erkannt_. Wenn der Provider keine Preis-Metadaten liefert (`?/?`), ist `PAID` nicht zwangsläufig ein bestätigter kostenpflichtiger Status. Eine saubere Trennung in `FREE / PAID / UNKNOWN` ist noch offen.

## Unterstützte Provider

| Provider | API-Key-Variable | Hinweis |
|---|---|---|
| OpenCode Zen | keiner | Free-Modelle ohne normalen API-Key |
| OpenRouter | `OPENROUTER_API_KEY` | |
| Kilo | `KILO_API_KEY` | |
| NVIDIA NIM | `NVIDIA_API_KEY` | |
| Groq | `GROQ_API_KEY` | |
| Cerebras | `CEREBRAS_API_KEY` | |
| Vercel AI Gateway | `VERCEL_API_KEY` | |
| DeepSeek | `DEEPSEEK_API_KEY` | Free-Status hängt auch vom Konto/Guthaben ab |
| Mistral | `MISTRAL_API_KEY` | Free Mode ist ein Sonderfall, siehe unten |
| Cloudflare Workers AI | `CLOUDFLARE_API_KEY` | Account-ID ist aktuell noch im Endpoint hinterlegt |

Die Zuordnung der API-Key-Variablen liegt in `agents/*.toml`.

## Voraussetzungen

Benötigt werden im Wesentlichen:

- Bash
- `curl`
- Python 3
- Standard-Unix-Tools wie `awk`, `grep`, `sed`, `date` und `mktemp`

Das Projekt ist für eine Linux-Shell ausgelegt.

## Installation

```bash
git clone https://github.com/kbarbel640-del/FreeLLMScanner.git
cd FreeLLMScanner
chmod +x fetch_free_models.sh provider_tests/*.sh
```

## API-Keys

Eine lokale `.env` kann zum Beispiel so aussehen:

```bash
OPENROUTER_API_KEY=...
KILO_API_KEY=...
NVIDIA_API_KEY=...
GROQ_API_KEY=...
CEREBRAS_API_KEY=...
VERCEL_API_KEY=...
DEEPSEEK_API_KEY=...
MISTRAL_API_KEY=...
CLOUDFLARE_API_KEY=...
```

`.env` ist über `.gitignore` ausgeschlossen und soll nicht committed werden.

Die Variablen müssen exportiert sein, bevor der Scanner gestartet wird:

```bash
set -a
source .env
set +a
```

Danach:

```bash
./fetch_free_models.sh
```

## Verwendung

### Interaktives Menü

```bash
./fetch_free_models.sh
```

Zeigt alle Provider und erlaubt die Auswahl eines einzelnen Providers oder aller Provider.

### Alle Provider scannen und testen

```bash
./fetch_free_models.sh --all
```

### Nur einzelne Provider

```bash
./fetch_free_models.sh --mistral
./fetch_free_models.sh --opencode --kilo
```

### Provider ausschließen

```bash
./fetch_free_models.sh --all --no-nvidia
```

### Nur Modelle auflisten

```bash
./fetch_free_models.sh --list
```

`--list` ruft die Modelllisten ab und klassifiziert sie, führt aber keine Chat-Completion-Tests aus.

### Check-Modus

```bash
./fetch_free_models.sh --check
```

Der Check-Modus zeigt zunächst den bisherigen Zustand aus `check_state.json`, führt anschließend einen neuen Scan/Test aus und aktualisiert die Statusdatei.

Die Schwelle für einen "alten" Check beträgt standardmäßig 24 Stunden:

```bash
STALE_HOURS=6 ./fetch_free_models.sh --check
```

## Ergebnisdateien

### `results.json`

Wird nach jedem Lauf aktualisiert und enthält je Provider unter anderem:

- `last_check`
- `found` — vom Provider gemeldete Modelle
- `tested` — tatsächlich getestete Free-Kandidaten
- `status` — `ok`, `partial`, `fail` oder `no-models`

### `check_state.json`

Wird zusätzlich im `--check`-Modus gepflegt und dient zur Alters-/Statusanzeige beim nächsten Check.

## Provider-spezifische Tests

Unter `provider_tests/` liegen eigenständige Provider-Module:

```text
provider_tests/
├── 01_opencode.sh
├── 02_kilo.sh
├── 03_groq.sh
├── 04_cerebras.sh
├── 05_nvidia.sh
├── 06_openrouter.sh
├── 07_mistral.sh
├── 08_deepseek.sh
├── 09_cloudflare.sh
├── 10_vercel.sh
└── test_all.sh
```

Sie können einzeln gestartet werden:

```bash
bash provider_tests/07_mistral.sh
```

oder über das Testmenü:

```bash
bash provider_tests/test_all.sh
```

Diese Module enthalten teilweise provider-spezifischere Logik als der zentrale Scanner.

## Sonderfälle

### Mistral Free Mode

Mistral stellt nicht einfach eine separate Liste von Modell-IDs mit dem Label "free" bereit. Im Free Mode ist der Zugriff vielmehr über Konto-/Rate-/Volumenlimits geregelt.

`provider_tests/07_mistral.sh` behandelt das deshalb separat:

- `/v1/models` wird für den konkreten API-Key abgefragt
- nur Modelle mit `capabilities.completion_chat == true` werden verwendet
- diese Modelle werden anschließend über `/chat/completions` getestet

Der zentrale `fetch_free_models.sh` hat diese Logik noch nicht vollständig übernommen und besitzt für Mistral derzeit zusätzlich einen Snapshot-Fallback.

### OpenCode Zen

OpenCode Zen benötigt für die Free-Modelle besondere Request-Header. Das eigenständige Modul `provider_tests/01_opencode.sh` verwendet dafür die Funktionen in `_lib.sh` und kann bei Rate-Limits optional über konfigurierte PVPN-Hosts rotieren.

Der zentrale Scanner verwendet beim eigentlichen Modelltest aktuell noch den generischen `test_model()`-Pfad. Deshalb kann sich das Verhalten des Hauptscanners bei OpenCode vom Standalone-Test unterscheiden.

## Projektstruktur

```text
FreeLLMScanner/
├── fetch_free_models.sh      # Hauptscanner, Menü, Scan/Test, JSON-Merge
├── _lib.sh                   # gemeinsame Curl-/Test-/Provider-Helfer
├── agents/                   # API-Key-Zuordnung per TOML
├── provider_tests/           # eigenständige Provider-Tests
├── results.json              # laufende Scan-/Testergebnisse
├── check_state.json          # Zustand für --check
├── PLAN.md                   # Altbestand aus dem früheren Projektkontext
└── README.md
```

## Bekannte Baustellen

Der Scanner funktioniert, aber einige Dinge sollten als nächstes vereinheitlicht werden:

- `FREE / PAID / UNKNOWN` sauber unterscheiden
- statische Free-Snapshots möglichst vollständig entfernen
- provider-spezifische Erkennung aus `provider_tests/` in den Hauptscanner übernehmen
- OpenCode im Hauptscanner über `test_zencode()` statt über den generischen Tester führen
- Mistral im Hauptscanner dynamisch über seine Capabilities behandeln
- Cloudflare Account-ID aus dem Code in Konfiguration/Environment verschieben
- doppelte Erkennungslogik zwischen `fetch_free_models.sh`, `_lib.sh` und den Provider-Modulen reduzieren
- `PLAN.md` aufräumen oder durch projektbezogene Dokumentation ersetzen
- `provider_tests/populate_models.py` überarbeiten; die Datei enthält noch Pfade und Annahmen aus dem früheren AGENTS_Generator-Aufbau und gehört derzeit nicht zum normalen Scanner-Workflow

## Philosophie

Der Provider selbst soll möglichst die Source of Truth sein.

Statische Listen sind nur ein Fallback, kein Zielzustand. Der Scanner soll langfristig selbst herausfinden:

- welche Modelle **jetzt** angeboten werden
- welche davon **wirklich kostenlos nutzbar** sind
- welche nur unbekannte Preis-Metadaten haben
- und welche Modelle eine echte Completion erfolgreich beantworten

Damit bleibt nicht eine gepflegte Modellliste die Wahrheit, sondern der aktuelle Zustand der Provider-APIs.
