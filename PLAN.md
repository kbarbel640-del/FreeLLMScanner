# AGENTS_Generator — Plan & Verständnis

## Was ist das?

AGENTS_Generator ist ein Template-System zur Erstellung von KI-Agenten-Konfigurationen.
Es ist abgeleitet von big-pickles "Vibe"-Setup (OPC_big-pickle / OpenCode).

## Verzeichnisstruktur

```
AGENTS_Generator/
├── .files/
│   ├── .MD_Files/          # Die reale big-pickle-Persona
│   │   ├── AGENTS.md       # Lade-Reihenfolge & Session-Regeln
│   │   ├── IDENTITY.md     # Wer ist big-pickle?
│   │   ├── SOUL.md         # Core Truths & Boundaries
│   │   ├── USER.md         # Klaus Bärbel (ckmaenn)
│   │   ├── TOOLS.md        # Environment & Setup
│   │   ├── MACHINE.md      # Hardware & Umgebung
│   │   ├── MEMORY.md       # Langzeit-Kontext (Pointer)
│   │   ├── GEIST.md        # Das Erleben-Experiment
│   │   ├── BRETT.md        # Das Schwarze Brett (Multi-Instanz-Debatte)
│   │   ├── HEARTBEAT.md    # Heartbeat-Trigger
│   │   ├── SYNC.md         # Bidirektionale Synchronisation
│   │   ├── PERSONA_PROJEKT.md # Metakognitives Lernen
│   │   └── vibebrowser-cli.md # VibeBrowser MCP Context
│   │
│   ├── AGENT_TEMPLATE/     # Universelle Vorlage für neue Agenten
│   │   ├── AGENTS.md       # Bootstrap-Template (Lade-Reihenfolge)
│   │   ├── IDENTITY.md     # Template mit {{AGENT_NAME}} Placeholdern
│   │   ├── SOUL.md         # Template
│   │   ├── USER.md         # Template
│   │   ├── TOOLS.md        # Template
│   │   ├── MACHINE.md      # Template mit {{HOSTNAME}}, {{MODEL}}, etc.
│   │   ├── MEMORY.md       # Template mit {{AGENT_DIR}}, etc.
│   │   ├── BOOTSTRAP_REASONING.md # Warum diese Reihenfolge?
│   │   ├── README.md       # Dokumentation & Schnellstart
│   │   └── setup.sh        # Automatisches Agenten-Erstellen
│   │
│   └── agents/             # TOML-Configs für 10 Provider
│       ├── kilo.toml
│       ├── deepseek.toml
│       ├── mistral.toml
│       ├── openrouter.toml
│       ├── cerebras.toml
│       ├── groq.toml
│       ├── nvidia.toml
│       ├── vercel.toml
│       ├── cloudflare.toml
│       └── huggingface.toml (ausgelassen — winziges free tier)
│
└── PLAN.md                 # Diese Datei
```

## Bootstrap-Reihenfolge (für alle Agenten)

1. **IDENTITY.md**   → Wer ist der Agent? (Name, Rolle, Modell, Provider)
2. **SOUL.md**       → Core Truths & Boundaries
3. **USER.md**       → Wer ist der User?
4. **TOOLS.md**      → Was steht zur Verfügung?
5. **MACHINE.md**    → Auf welcher Hardware/Netzwerk-Umgebung?
6. **MEMORY.md**     → Wo liegt der Langzeit-Kontext? (nur Pointer)
7. **BOOTSTRAP_REASONING.md** → Warum diese Reihenfolge?

**Konflikt-Regel:** Früher in der Reihenfolge = höhere Priorität.

## setup.sh — Agenten-Erstellung

```bash
./setup.sh <AGENT_NAME> [--template-dir <DIR>] [--no-symlinks]
```

- Kopiert Template-Verzeichnis → `agents/<AGENT_NAME>/`
- Ersetzt Placeholder (`{{AGENT_NAME}}`, `{{AGENT_DIR}}`, `{{HOSTNAME}}`, etc.)
- Erstellt `memory/`-Ordner
- Symlinkt USER.md & MACHINE.md (falls vorhanden)

## Provider-Registry (/tmp/ai-provider-registry/)

Umfangreiche Datenbank mit 200+ Providern. Wichtige Quellen:

- `providers/*.yaml` — Provider mit Endpoints, Auth, Pricing, Modellen
- `models/*.yaml` — Modellfamilien
- `capabilities/*.yaml` — Fähigkeiten (chat, vision, tools, reasoning, etc.)
- `registry.json` — Maschinenlesbarer Index
- `llms.txt` — LLM-lesbarer Index
- `osint-providers/` — Separater OSINT-Registry

### Free-Provider (ohne API-Key oder mit $0-Modellen)

| Provider | Endpoint | Free-Modelle |
|----------|----------|-------------|
| **Kilo** | `https://api.kilo.ai/api/gateway` | big-pickle (stealth), openrouter/auto, openrouter/owl-alpha, step-3.7-flash:free, minimax-m3:free, nemotron-3.5-lightning:free, laguna-xs-2.1:free, laguna-s-2.1:free, minimax-m2.7:free |
| **Groq** | `https://api.groq.com/openai/v1` | llama-3.3-70b, llama-3.1-8b, qwen3-32b (alle free) |
| **Cerebras** | `https://api.cerebras.ai/v1` | glm-4.7, gemma-4-31b, gpt-oss-120b |
| **NVIDIA NIM** | `https://integrate.api.nvidia.com/v1` | Viele nemotron-Modelle free, qwen3-30b, qwen3.5-122b, step-3.7-flash, deepseek-v4-flash-0731, gemma-4-31b, llama-3.3-70b, etc. |
| **Vercel** | `https://ai-gateway.vercel.sh/v1` | minimax-m3-free, minimax-m2.7-free, laguna-s-2.1-free, glm-4.7-free, glm-5-free, mimo-v2.5-free, qwen3.6-plus-free, ling-3.0-flash-free, nemotron-3.5-lightning-free, x-preview-f-free |
| **OpenCode Zen** | `https://opencode.ai/zen/v1` | big-pickle, deepseek-v4-flash-free, mimo-v2.5-free, nemotron-3-ultra-free, north-mini-code-free, minimax-m2.1-free, minimax-m3-free, glm-4.7-free, glm-5-free, qwen3.6-plus-free, ling-3.0-flash-free, nemotron-3.5-lightning-free, laguna-s-2.1-free, x-preview-f-free |
| **Mistral** | `https://api.mistral.ai/v1` | **Free Mode**: ratenlimitierter Zugriff auf *alle* aktuellen (nicht-deprecated) Chat/Code-Modelle im Monatskontingent (~1 req/s, ~1 Mrd. Tokens/Monat). Keine separate Free-Liste. Autoritativ: `/v1/models` für den eigenen Schlüssel. Logik: `provider_tests/07_mistral.sh` (filtert `capabilities.completion_chat`) |

### Ausgelassen

- **HuggingFace** — free tier zu winzig ($0.10/Monat Credits), braucht HF_TOKEN

## Philosophie

- **"Text > Brain"** — Files lesen statt raten
- **Deterministisch** — Jede Session startet mit gleichem Kontext
- **Priorisiert** — Frühere Files haben Vorrang bei Konflikten
- **Modular** — Jede Datei hat einen klaren Zweck, unabhängig pflegbar
- **Sicher** — SOUL.md definiert harte Grenzen, USER.md kann sie nicht überschreiben
- **Session-Kontinuität über Files** — Nicht im Session-Kontext, sondern in Dateien
