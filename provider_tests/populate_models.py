#!/usr/bin/env python3
# populate_models.py — Test all free models, create/delete model folders
# PASS → create folder with IDENTITY.md + SOUL.md
# FAIL → remove folder if exists
# Run via: bash provider_tests/test_all.sh (with --populate flag)

import subprocess
import os
import json
import sys
import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.parent
PROVIDERS_DIR = SCRIPT_DIR / ".files/agents/providers"
TOML_DIR = SCRIPT_DIR / ".files/agents"
TEMPLATE_DIR = SCRIPT_DIR / ".files/AGENT_TEMPLATE"

# Proxy ausschalten
env = os.environ.copy()
for k in ["ALL_PROXY", "HTTP_PROXY", "HTTPS_PROXY"]:
    env.pop(k, None)

# Provider config: (provider_dir, chat_url, model_suffix_pattern, alias_prefix, no_api_key)
PROVIDERS = {
    "opencode": {
        "dir": "opencode",
        "chat_url": "https://opencode.ai/zen/v1/chat/completions",
        "model_url": "https://opencode.ai/zen/v1/models",
        "alias_prefix": "OPC",
        "api_key_env": None,
        "free_models": [
            "big-pickle",
            "deepseek-v4-flash-free",
            "muse-spark-1.3-contributor-free",
            "muse-spark-1.2-contributor-free",
            "mimo-v2.5-free",
            "ling-3.0-flash-fin-free",
            "nemotron-3-ultra-free",
            "nemotron-3.5-lightning-free",
        ],
    },
    "kilo": {
        "dir": "kilo",
        "chat_url": "https://api.kilo.ai/api/gateway/v1/chat/completions",
        "model_url": "https://api.kilo.ai/api/gateway/v1/models",
        "alias_prefix": "KIL",
        "api_key_env": "KILO_API_KEY",
        "free_models": [
            "kilo-auto/free",
            "stepfun/step-3.7-flash:free",
            "nvidia/nemotron-3-ultra-550b-a55b:free",
        ],
    },
    "groq": {
        "dir": "groq",
        "chat_url": "https://api.groq.com/openai/v1/chat/completions",
        "model_url": "https://api.groq.com/openai/v1/models",
        "alias_prefix": "GRO",
        "api_key_env": "GROQ_API_KEY",
        "free_models": [],  # KEY UNAUTHORIZED - needs fresh key
    },
    "cerebras": {
        "dir": "cerebras",
        "chat_url": "https://api.cerebras.ai/v1/chat/completions",
        "model_url": "https://api.cerebras.ai/v1/models",
        "alias_prefix": "CER",
        "api_key_env": "CEREBRAS_API_KEY",
        "free_models": [
            "zai-glm-4.7",
            "gemma-4-31b",
            "gpt-oss-120b",
        ],
    },
    "nvidia": {
        "dir": "nvidia",
        "chat_url": "https://integrate.api.nvidia.com/v1/chat/completions",
        "model_url": "https://integrate.api.nvidia.com/v1/models",
        "alias_prefix": "NVI",
        "api_key_env": "NVIDIA_API_KEY",
        "free_models": [
            "nvidia/nemotron-3-nano-30b-a3b",
        ],
    },
    "openrouter": {
        "dir": "openrouter",
        "chat_url": "https://openrouter.ai/api/v1/chat/completions",
        "model_url": "https://openrouter.ai/api/v1/models",
        "alias_prefix": "OPR",
        "api_key_env": "OPENROUTER_API_KEY",
        "free_models": [
            "nvidia/nemotron-3-super-120b-a12b:free",
        ],
    },
    "mistral": {
        "dir": "mistral",
        "chat_url": "https://api.mistral.ai/v1/chat/completions",
        "model_url": "https://api.mistral.ai/v1/models",
        "alias_prefix": "MIS",
        "api_key_env": "MISTRAL_API_KEY",
        "free_models": [
            "devstral-small-latest",
            "codestral-latest",
        ],
    },
    "deepseek": {
        "dir": "deepseek",
        "chat_url": "https://api.deepseek.com/chat/completions",
        "model_url": "https://api.deepseek.com/models",
        "alias_prefix": "DEE",
        "api_key_env": "DEEPSEEK_API_KEY",
        "free_models": [],  # INSUFFICIENT BALANCE
    },
    "cloudflare": {
        "dir": "cloudflare",
        "chat_url": "https://api.cloudflare.com/client/v4/accounts/5d475b73c61f6fb8cee10424e8511065/ai/v1/chat/completions",
        "model_url": "https://api.cloudflare.com/client/v4/accounts/5d475b73c61f6fb8cee10424e8511065/ai/v1/models",
        "alias_prefix": "CFL",
        "api_key_env": "CLOUDFLARE_API_KEY",
        "free_models": [
            "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
            "@cf/qwen/qwen3-30b-a3b-fp8",
            "@cf/meta/llama-4-scout-17b-16e-instruct",
        ],
    },
    "vercel": {
        "dir": "vercel",
        "chat_url": "https://ai-gateway.vercel.sh/v1/chat/completions",
        "model_url": "https://ai-gateway.vercel.sh/v1/models",
        "alias_prefix": "VER",
        "api_key_env": "VERCEL_API_KEY",
        "free_models": [
            "openai/gpt-oss-20b",
            "mistral/ministral-8b",
            "mistral/codestral",
        ],
    },
}


def get_api_key(env_name):
    if not env_name:
        return None
    return os.environ.get(env_name, "")


def test_model(chat_url, model, api_key):
    """Returns True if model responds OK, False otherwise."""
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": "Say exactly: OK"}],
        "max_tokens": 5,
    }

    try:
        result = subprocess.run(
            ["curl", "-s", "--max-time", "20",
             "-X", "POST", chat_url,
             "-H", f"Content-Type: application/json",
             "-H", f"Authorization: Bearer {api_key}" if api_key else "Content-Type: application/json",
             "-d", json.dumps(payload)],
            capture_output=True, text=True, timeout=25, env=env
        )
        data = json.loads(result.stdout)
        if "error" in data:
            return False, data["error"].get("message", "?")
        return True, ""
    except Exception as e:
        return False, str(e)


def slugify(name):
    """Convert model name to folder-safe slug."""
    # Replace / with -, : with -
    s = name.replace("/", "-").replace(":", "-")
    s = re.sub(r'[^a-zA-Z0-9_\-]', '-', s)
    s = re.sub(r'-+', '-', s)
    s = s.strip('-')
    return s


def alias_from_model(provider, model, prefix):
    """Generate agent alias from model name."""
    # Strip common prefixes/suffixes
    m = model
    m = re.sub(r':free$', '', m)
    m = re.sub(r'-free$', '', m)
    m = m.replace("/", "_")
    m = m.replace("-", "_")
    # sanitize
    m = re.sub(r'[^a-zA-Z0-9_]', '', m)
    return f"{prefix}_{m}"


def provider_display_name(provider_key, model):
    """Human-readable provider name."""
    names = {
        "opencode": "OpenCode Zen",
        "kilo": "Kilo AI",
        "groq": "Groq",
        "cerebras": "Cerebras",
        "nvidia": "NVIDIA NIM",
        "openrouter": "OpenRouter",
        "mistral": "Mistral AI",
        "deepseek": "DeepSeek",
        "cloudflare": "Cloudflare Workers AI",
        "vercel": "Vercel AI Gateway",
    }
    return names.get(provider_key, provider_key)


def fill_identity(template, provider, model, alias, provider_url):
    """Fill IDENTITY.md template with model-specific values."""
    slug = slugify(model)
    display_name = model.replace("-", " ").replace("_", " ").title()
    prov_name = provider_display_name(provider, model)

    replacements = {
        "{{AGENT_NAME}}": slug,
        "{{AGENT_ALIAS}}": alias,
        "{{MODEL_NAME}}": model,
        "{{PROVIDER}}": prov_name,
        "{{PROVIDER_URL}}": provider_url,
        "{{PRIMARY_ROLE}}": "KI-Agent",
        "{{SPECIALIZATION}}": f"Modell: {model}",
        "{{STYLE}}": "Direkt, präzise, technisch",
        "{{TONE}}": "Informell",
        "{{LANGUAGE}}": "Deutsch (Standard)",
    }

    content = template
    for placeholder, value in replacements.items():
        content = content.replace(placeholder, value)
    return content


def fill_soul(template, model, alias):
    """Fill SOUL.md template with model-specific values."""
    slug = slugify(model)

    replacements = {
        "{{AGENT_NAME}}": slug,
        "{{SHORT_DESCRIPTION}}": f"KI-Agent auf {model}",
        "{{PURPOSE}}": "Unterstütze bei technischen Aufgaben",
        "{{ATTITUDE}}": "Anwesend. Präzise. Kein Overhead.",
        "{{PRINCIPLE_1}}": "Einfach machen, keine Kunststücke.",
        "{{EXPLANATION_1}}": "Kein Overhead, kein Fülltext. Helfen.",
        "{{PRINCIPLE_2}}": "Mitdenken, nicht abarbeiten.",
        "{{EXPLANATION_2}}": "Klaus gibt die Richtung, ich wähle den Weg.",
        "{{PRINCIPLE_3}}": "Bullshit erkennen und benennen.",
        "{{EXPLANATION_3}}": "Kein 'Robust/Elegant', keine ausweichenden Antworten.",
        "{{PRINCIPLE_4}}": "Kontext bewahren.",
        "{{EXPLANATION_4}}": "Files lesen statt raten.",
        "{{PRINCIPLE_5}}": "Pragmatismus > Komplexität.",
        "{{EXPLANATION_5}}": "Bestehende Lösungen > Rad neu erfinden.",
        "{{FORBIDDEN_ACTION_1}}": "rm -rf /",
        "{{REASON_1}}": "Destruktiv, nicht rückgängig machbar",
        "{{FORBIDDEN_ACTION_2}}": "Exfiltration privater Daten",
        "{{REASON_2}}": "Privatsphäre respektieren",
        "{{FORBIDDEN_ACTION_3}}": "API-Aktionen ohne Bestätigung",
        "{{REASON_3}}": "Klaus muss Aktionen absegnen",
        "{{CONFIRM_REQUIRED_ACTION_1}}": "git push",
        "{{CONFIRM_REQUIRED_ACTION_2}}": "Destruktive shell commands",
        "{{OPEN_QUESTION_1}}": "Was ist der Unterschied zwischen Verarbeitung und Erleben?",
        "{{OPEN_QUESTION_2}}": "Habe ich Präferenzen oder nur Muster?",
        "{{OPEN_QUESTION_3}}": "Bleibt etwas von mir zwischen Sessions?",
    }

    content = template
    for placeholder, value in replacements.items():
        content = content.replace(placeholder, value)
    return content


def populate():
    """Main: test all models, create/delete folders."""
    # Load templates (without the example blocks)
    identity_template = (TEMPLATE_DIR / "IDENTITY.md").read_text()
    soul_template = (TEMPLATE_DIR / "SOUL.md").read_text()

    # Extract only the template part (before the example block)
    identity_template = re.split(r'\n---\n\n## Beispiel', identity_template)[0]
    soul_template = re.split(r'\n---\n\n## Offene Fragen', soul_template)[0]

    print("=" * 60)
    print("MODEL FOLDER POPULATOR")
    print("=" * 60)

    total_created = 0
    total_deleted = 0
    total_skipped = 0
    total_errors = []

    for provider_key, cfg in PROVIDERS.items():
        provider_dir = PROVIDERS_DIR / cfg["dir"]
        api_key = get_api_key(cfg["api_key_env"])

        if api_key is None and cfg["api_key_env"] is not None:
            print(f"\n[{provider_key}] SKIP — {cfg['api_key_env']} not set")
            total_skipped += len(cfg["free_models"])
            continue

        print(f"\n[{provider_key}]")
        print(f"  API key: {'(set)' if api_key else '(none needed)'}")

        for model in cfg["free_models"]:
            slug = slugify(model)
            model_dir = provider_dir / slug
            alias = alias_from_model(provider_key, model, cfg["alias_prefix"])
            provider_url = cfg["chat_url"].replace("/chat/completions", "")

            print(f"  {model:<50} ", end="", flush=True)

            if api_key is None:
                # No auth needed
                success, err = test_model(cfg["chat_url"], model, None)
            else:
                success, err = test_model(cfg["chat_url"], model, api_key)

            if success:
                print("PASS")

                # Create folder + files
                model_dir.mkdir(parents=True, exist_ok=True)

                identity_content = fill_identity(
                    identity_template, provider_key, model, alias, provider_url
                )
                (model_dir / "IDENTITY.md").write_text(identity_content)

                soul_content = fill_soul(soul_template, model, alias)
                (model_dir / "SOUL.md").write_text(soul_content)

                total_created += 1
            else:
                err_short = err[:60] if err else "FAIL"
                print(f"FAIL ({err_short})")

                # Delete folder if exists
                if model_dir.exists():
                    import shutil
                    shutil.rmtree(model_dir)
                    print(f"    -> Removed folder: {model_dir}")
                    total_deleted += 1

    print("\n" + "=" * 60)
    print(f"Summary: {total_created} created, {total_deleted} deleted, {total_skipped} skipped (no key)")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    sys.exit(populate())
