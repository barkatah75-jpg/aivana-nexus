"""
╔══════════════════════════════════════════════════════════════════════════════╗
║          AIVANA  NEXUS  v7.0  —  AUTONOMOUS  EDITION                       ║
║                                                                              ║
║  Multi-AI Brain (Ollama+Groq+Gemini+HuggingFace) · ReAct Agent Loop        ║
║  Whisper STT · edge-tts · Tool Registry · Auto-Chaining · Self-Healing     ║
║  Telegram Bot · Discord · WhatsApp · Email · Web Dashboard · Scheduler     ║
╚══════════════════════════════════════════════════════════════════════════════╝

FREE AI TOOLS INCLUDED:
  - Ollama       (local LLMs: llama3, mistral, codellama, phi3)
  - Groq         (free API: llama3-70b, mixtral - fastest inference)
  - Gemini       (Google free tier: gemini-1.5-flash)
  - HuggingFace  (free inference API)
  - Whisper      (local speech-to-text - openai-whisper)
  - edge-tts     (Microsoft TTS - free, 300+ voices)
  - DuckDuckGo   (free web search)
  - GitHub API   (free with token)
"""

# ══════════════════════════════════════════════════════════════════
#  STDLIB
# ══════════════════════════════════════════════════════════════════
import os, sys, json, time, asyncio, threading, logging, subprocess
import warnings
warnings.filterwarnings('ignore', category=FutureWarning)
import zipfile, shutil, smtplib, re, queue, traceback, inspect
import hashlib, signal
from pathlib import Path
from datetime import datetime, timedelta
from collections import deque, defaultdict
from typing import Optional, List, Dict, Any, Tuple, Callable
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import wraps

# ══════════════════════════════════════════════════════════════════
#  AUTO CHDIR — Always run from LAPPYHUB root
# ══════════════════════════════════════════════════════════════════
_SCRIPT_DIR = Path(__file__).resolve().parent
_ROOT = _SCRIPT_DIR.parent if _SCRIPT_DIR.name in ("AIVANA_Commander", "AIVANA_NEXUS") else _SCRIPT_DIR
os.chdir(_ROOT)

# ══════════════════════════════════════════════════════════════════
#  REQUIRED DEPS
# ══════════════════════════════════════════════════════════════════
def _try(name, pkg=None):
    try:
        import importlib
        return importlib.import_module(name)
    except ImportError:
        return None

try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table
    from rich.prompt import Prompt
    from rich import box
    from rich.progress import Progress, SpinnerColumn, TextColumn
    import uvicorn
    from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, BackgroundTasks
    from fastapi.responses import HTMLResponse, JSONResponse
    from fastapi.middleware.cors import CORSMiddleware
    from apscheduler.schedulers.background import BackgroundScheduler
    from apscheduler.triggers.cron import CronTrigger
    from apscheduler.triggers.interval import IntervalTrigger
    import requests
except ImportError as e:
    print(f"[MISSING] pip install rich fastapi 'uvicorn[standard]' apscheduler requests python-multipart")
    sys.exit(1)

# Optional AI providers
ollama       = _try("ollama")
groq_sdk     = _try("groq")
genai        = _try("google.generativeai", "google-generativeai") or _try("google.genai", "google-genai")
whisper_mod  = _try("whisper", "openai-whisper")
edge_tts_mod = _try("edge_tts")
sr_mod       = _try("speech_recognition")
docker_sdk   = _try("docker")
git_mod      = _try("git", "gitpython")

console = Console()

# ══════════════════════════════════════════════════════════════════
#  CONFIG
# ══════════════════════════════════════════════════════════════════
class Cfg:
    VERSION           = "7.0-NEXUS"
    # ── AI Providers ──────────────────────────────────────────────
    AI_PROVIDER       = os.getenv("AI_PROVIDER", "ollama")   # ollama|groq|gemini|huggingface
    OLLAMA_MODEL      = os.getenv("OLLAMA_MODEL", "llama3")
    GROQ_API_KEY      = os.getenv("GROQ_API_KEY", "")
    GROQ_MODEL        = os.getenv("GROQ_MODEL", "llama3-70b-8192")
    GEMINI_API_KEY    = os.getenv("GEMINI_API_KEY", "")
    GEMINI_MODEL      = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")
    HF_API_KEY        = os.getenv("HF_API_KEY", "")
    HF_MODEL          = os.getenv("HF_MODEL", "mistralai/Mistral-7B-Instruct-v0.2")
    GITHUB_TOKEN      = os.getenv("GITHUB_TOKEN", "")
    # ── Voice ─────────────────────────────────────────────────────
    VOICE_ENABLED     = os.getenv("VOICE", "0") == "1"
    TTS_VOICE         = os.getenv("TTS_VOICE", "en-IN-NeerjaNeural")   # Indian English
    WAKE_WORD         = os.getenv("WAKE_WORD", "aivana").lower()
    WHISPER_MODEL     = os.getenv("WHISPER_MODEL", "base")             # tiny/base/small
    # ── Server ────────────────────────────────────────────────────
    WEB_PORT          = int(os.getenv("WEB_PORT", "8765"))
    WEB_HOST          = "0.0.0.0"
    # ── Paths (relative to AIVANA_Commander/) ─────────────────────
    LOG_DIR           = _SCRIPT_DIR / "aivana_logs"
    BACKUP_DIR        = _SCRIPT_DIR / "aivana_backups"
    PLUGIN_DIR        = _SCRIPT_DIR / "plugins"
    MEMORY_FILE       = _SCRIPT_DIR / "aivana_memory.json"
    # ── Notifications ─────────────────────────────────────────────
    TELEGRAM_TOKEN    = os.getenv("TELEGRAM_TOKEN", "")
    TELEGRAM_CHAT     = os.getenv("TELEGRAM_CHAT_ID", "")
    DISCORD_WEBHOOK   = os.getenv("DISCORD_WEBHOOK", "")
    WHATSAPP_URL      = os.getenv("WHATSAPP_WEBHOOK", "http://localhost:3000/send")
    SMTP_HOST         = os.getenv("SMTP_HOST", "smtp.gmail.com")
    SMTP_PORT         = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USER         = os.getenv("SMTP_USER", "")
    SMTP_PASS         = os.getenv("SMTP_PASS", "")
    SMTP_TO           = os.getenv("SMTP_TO", "")
    # ── Agent ─────────────────────────────────────────────────────
    MAX_AGENT_STEPS   = 8     # max ReAct iterations
    AGENT_TIMEOUT     = 300   # seconds per agent run
    MAX_RETRIES       = 3
    RETRY_DELAY       = 5
    MONITOR_INTERVAL  = 300
    MAX_LOG_LINES     = 1000
    ROLLBACK_KEEP     = 10
    QUEUE_WORKERS     = 4
    WATCHER_ENABLED   = os.getenv("WATCHER", "0") == "1"

# Load config.json overrides
_cfg_file = _SCRIPT_DIR / "aivana_config.json"
if _cfg_file.exists():
    try:
        for k, v in json.loads(_cfg_file.read_text()).items():
            if hasattr(Cfg, k.upper()): setattr(Cfg, k.upper(), v)
    except: pass

for d in [Cfg.LOG_DIR, Cfg.BACKUP_DIR, Cfg.PLUGIN_DIR]:
    d.mkdir(exist_ok=True)

# ══════════════════════════════════════════════════════════════════
#  SCRIPT MAP + PIPELINES
# ══════════════════════════════════════════════════════════════════
BASE_SCRIPTS = {
    "deploy":     "AIVANA_FullAutoDeploy.ps1",
    "repair":     "AIVANA_AutoRepair.ps1",
    "autopilot":  "AIVANA_AutoPilot_v9.5_IntelliDeploy.ps1",
    "auto":       "AIVANA_AutoPilot_v9.5_IntelliDeploy.ps1",
    "heal":       "AIVANA_TODOLIST_AutoHeal_v10.9_ASCII_SAFE.ps1",
    "status":     "AIVANA_FTP_Diagnostic.ps1",
    "uploader":   "AIVANA_AutoUploader_v5.0_AutoPilot.ps1",
    "diag":       "AIVANA_FTP_Diagnostic.ps1",
    "diag105":    "AIVANA_FTPS_Diag_v10.5.ps1",
    "hostfix":    "AIVANA_Hostinger_Fix.ps1",
    "sftptest":   "Test_SFTP_Connect.ps1",
    "service":    "AIVANA_AutoPilot_ServiceSetup.ps1",
    "autostart":  "AIVANA_AutoStart.ps1",
    "github":     "setup_github.ps1",
}

PIPELINES = {
    "launch":    {"steps":["status","deploy","uploader"],                "on_fail":"repair",   "desc":"Production launch"},
    "hotfix":    {"steps":["repair","deploy","status"],                  "on_fail":"stop",     "desc":"Emergency hotfix"},
    "nightly":   {"steps":["heal","status","deploy"],                    "on_fail":"continue", "desc":"Nightly maintenance"},
    "full":      {"steps":["repair","heal","deploy","uploader","status"],"on_fail":"repair",   "desc":"Full 5-step cycle"},
    "recovery":  {"steps":["heal","repair","deploy"],                    "on_fail":"stop",     "desc":"Disaster recovery"},
    "diagnose":  {"steps":["status","diag","sftptest"],                  "on_fail":"continue", "desc":"Full diagnostic"},
    "fresh":     {"steps":["repair","heal","deploy","uploader"],         "on_fail":"repair",   "desc":"Fresh deploy"},
    "overnight": {"steps":["heal","repair","status","deploy","uploader"],"on_fail":"repair",   "desc":"Overnight maintenance"},
}

SCRIPT_MAP: Dict[str, str] = dict(BASE_SCRIPTS)

def reload_plugins():
    added = 0
    for f in Cfg.PLUGIN_DIR.glob("*.ps1"):
        if f.name.startswith("__"): continue
        key = f.stem.lower().replace(" ","_").replace("-","_")
        if key not in BASE_SCRIPTS:
            SCRIPT_MAP[key] = str(f); added += 1
    if added: broadcast(f"Loaded {added} plugins", "plugin", "plugins")
    return added

# ══════════════════════════════════════════════════════════════════
#  GLOBAL STATE
# ══════════════════════════════════════════════════════════════════
live_log = deque(maxlen=Cfg.MAX_LOG_LINES)
ws_clients: List[WebSocket] = []
scheduler = BackgroundScheduler()
convo: List[dict] = []
stats = {"total":0,"success":0,"failed":0,"pipelines":0,"agent_runs":0,"voice_commands":0}
active_jobs: Dict[str, dict] = {}
scheduled_jobs: Dict[str, dict] = {}
job_q: queue.Queue = queue.Queue()
asyncio_loop = None
perf_data: Dict[str, List[float]] = defaultdict(list)

session_log = Cfg.LOG_DIR / f"nexus_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
_fh = logging.FileHandler(session_log, encoding="utf-8", errors="replace")
_fh.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(message)s"))
logging.basicConfig(level=logging.INFO, handlers=[_fh])
log = logging.getLogger("NEXUS")

# Windows stdout UTF-8 fix
if os.name == "nt":
    import io
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
    except: pass

# ══════════════════════════════════════════════════════════════════
#  BROADCAST
# ══════════════════════════════════════════════════════════════════
def broadcast(msg: str, level: str = "info", source: str = "system"):
    entry = {"time": datetime.now().strftime("%H:%M:%S"), "level": level, "source": source, "msg": msg}
    live_log.append(entry)
    safe = msg.encode("ascii", "replace").decode("ascii")
    try: log.info(f"[{source}] {safe}")
    except: pass
    if ws_clients and asyncio_loop:
        data = json.dumps(entry)
        dead = []
        for ws in ws_clients:
            try: asyncio.run_coroutine_threadsafe(ws.send_text(data), asyncio_loop)
            except: dead.append(ws)
        for d in dead:
            try: ws_clients.remove(d)
            except: pass

# ══════════════════════════════════════════════════════════════════
#  TOOL REGISTRY — @tool decorator
# ══════════════════════════════════════════════════════════════════
_tools: Dict[str, dict] = {}

def tool(name: str = None, desc: str = "", category: str = "general"):
    """Decorator to register a function as an AI-callable tool"""
    def decorator(fn: Callable):
        n = name or fn.__name__
        _tools[n] = {
            "fn": fn, "name": n, "desc": desc or fn.__doc__ or n,
            "category": category,
            "sig": str(inspect.signature(fn))
        }
        @wraps(fn)
        def wrapper(*a, **kw): return fn(*a, **kw)
        return wrapper
    return decorator

def get_tools_prompt() -> str:
    lines = ["Available tools (call with TOOL: name [args]):"]
    cats = defaultdict(list)
    for t in _tools.values(): cats[t["category"]].append(t)
    for cat, tools_list in cats.items():
        lines.append(f"\n[{cat.upper()}]")
        for t in tools_list:
            lines.append(f"  {t['name']}: {t['desc']}")
    return "\n".join(lines)

# ══════════════════════════════════════════════════════════════════
#  MEMORY SYSTEM
# ══════════════════════════════════════════════════════════════════
class Memory:
    def __init__(self):
        self.data = {"patterns":{}, "failures":{}, "successes":{}, "notes":{}, "schedules":{}}
        self.load()

    def load(self):
        if Cfg.MEMORY_FILE.exists():
            try: self.data = json.loads(Cfg.MEMORY_FILE.read_text())
            except: pass

    def save(self):
        try: Cfg.MEMORY_FILE.write_text(json.dumps(self.data, indent=2))
        except: pass

    def record(self, action: str, success: bool, duration: float = 0):
        k = "successes" if success else "failures"
        self.data[k][action] = self.data[k].get(action, 0) + 1
        if action in perf_data: perf_data[action].append(duration)
        self.save()

    def note(self, key: str, value: str):
        self.data["notes"][key] = value; self.save()

    def failure_rate(self, action: str) -> float:
        s = self.data["successes"].get(action, 0)
        f = self.data["failures"].get(action, 0)
        return f / (s + f) if (s + f) > 0 else 0.0

    def should_pre_heal(self, action: str) -> bool:
        return self.failure_rate(action) > 0.5

memory = Memory()

# ══════════════════════════════════════════════════════════════════
#  MULTI-AI PROVIDER
# ══════════════════════════════════════════════════════════════════
class AIBrain:
    """Routes to best available free AI provider"""

    def __init__(self):
        self.providers = []
        self._init_providers()

    def _init_providers(self):
        # 1. Groq (fastest free API)
        if Cfg.GROQ_API_KEY and groq_sdk:
            try:
                self._groq = groq_sdk.Groq(api_key=Cfg.GROQ_API_KEY)
                self.providers.append("groq")
                broadcast("Groq AI ready (llama3-70b)", "success", "ai")
            except: pass

        # 2. Gemini (Google free)
        if Cfg.GEMINI_API_KEY and genai:
            try:
                genai.configure(api_key=Cfg.GEMINI_API_KEY)
                self._gemini = genai.GenerativeModel(Cfg.GEMINI_MODEL)
                self.providers.append("gemini")
                broadcast(f"Gemini AI ready ({Cfg.GEMINI_MODEL})", "success", "ai")
            except: pass

        # 3. Ollama (local, always available if running)
        if ollama:
            try:
                ollama.list()
                self.providers.append("ollama")
                broadcast(f"Ollama ready ({Cfg.OLLAMA_MODEL})", "success", "ai")
            except: pass

        # 4. HuggingFace (free inference)
        if Cfg.HF_API_KEY:
            self.providers.append("huggingface")
            broadcast("HuggingFace ready", "success", "ai")

        if not self.providers:
            broadcast("WARNING: No AI provider available! Install ollama or set API keys.", "warn", "ai")

    def ask(self, prompt: str, system: str = "", provider: str = None) -> str:
        order = [provider] + [p for p in self.providers if p != provider] if provider else self.providers
        for p in order:
            if not p: continue
            try:
                result = self._call(p, prompt, system)
                if result: return result
            except Exception as e:
                broadcast(f"AI [{p}] error: {str(e)[:80]} — trying next", "warn", "ai")
        return "AI unavailable — check providers"

    def _call(self, provider: str, prompt: str, system: str) -> str:
        if provider == "groq":
            msgs = []
            if system: msgs.append({"role":"system","content":system})
            msgs.append({"role":"user","content":prompt})
            r = self._groq.chat.completions.create(model=Cfg.GROQ_MODEL, messages=msgs, max_tokens=1024)
            return r.choices[0].message.content.strip()

        elif provider == "gemini":
            full = f"{system}\n\n{prompt}" if system else prompt
            r = self._gemini.generate_content(full)
            return r.text.strip()

        elif provider == "ollama":
            full_prompt = f"{system}\n\nUser: {prompt}" if system else prompt
            r = ollama.generate(model=Cfg.OLLAMA_MODEL, prompt=full_prompt)
            return r["response"].strip()

        elif provider == "huggingface":
            headers = {"Authorization": f"Bearer {Cfg.HF_API_KEY}"}
            payload = {"inputs": f"{system}\n{prompt}" if system else prompt,
                       "parameters": {"max_new_tokens": 512, "return_full_text": False}}
            r = requests.post(
                f"https://api-inference.huggingface.co/models/{Cfg.HF_MODEL}",
                headers=headers, json=payload, timeout=30)
            data = r.json()
            if isinstance(data, list): return data[0].get("generated_text","").strip()
            return str(data)

        return ""

    def available_providers(self) -> List[str]:
        return self.providers

brain = AIBrain()

# ══════════════════════════════════════════════════════════════════
#  FREE WEB SEARCH (DuckDuckGo — no API key needed)
# ══════════════════════════════════════════════════════════════════
def web_search(query: str, max_results: int = 5) -> str:
    """Search the web using DuckDuckGo (free, no API key)"""
    try:
        url = "https://api.duckduckgo.com/"
        r = requests.get(url, params={"q": query, "format": "json", "no_html": 1}, timeout=10)
        data = r.json()
        results = []
        # Abstract
        if data.get("Abstract"):
            results.append(f"Summary: {data['Abstract']}")
        # Related topics
        for topic in data.get("RelatedTopics", [])[:max_results]:
            if isinstance(topic, dict) and topic.get("Text"):
                results.append(f"- {topic['Text'][:150]}")
        if results:
            return "\n".join(results)
        # Fallback: instant answer
        return data.get("Answer") or f"No results for: {query}"
    except Exception as e:
        return f"Search failed: {e}"

# ══════════════════════════════════════════════════════════════════
#  GITHUB INTEGRATION (free with token)
# ══════════════════════════════════════════════════════════════════
def github_api(endpoint: str, method: str = "GET", data: dict = None) -> dict:
    headers = {"Authorization": f"token {Cfg.GITHUB_TOKEN}", "Accept": "application/vnd.github.v3+json"}
    url = f"https://api.github.com/{endpoint.lstrip('/')}"
    try:
        r = requests.request(method, url, headers=headers, json=data, timeout=10)
        return r.json()
    except Exception as e:
        return {"error": str(e)}

# ══════════════════════════════════════════════════════════════════
#  NOTIFICATION HUB
# ══════════════════════════════════════════════════════════════════
class NotifyHub:
    @staticmethod
    def telegram(msg: str):
        if not Cfg.TELEGRAM_TOKEN: return
        try:
            requests.post(f"https://api.telegram.org/bot{Cfg.TELEGRAM_TOKEN}/sendMessage",
                json={"chat_id": Cfg.TELEGRAM_CHAT, "text": f"[AIVANA NEXUS]\n{msg}"}, timeout=5)
        except: pass

    @staticmethod
    def discord(msg: str, color: int = 0x00e5ff):
        if not Cfg.DISCORD_WEBHOOK: return
        try:
            requests.post(Cfg.DISCORD_WEBHOOK,
                json={"embeds":[{"description":msg,"color":color,"footer":{"text":"AIVANA NEXUS v7"}}]}, timeout=5)
        except: pass

    @staticmethod
    def whatsapp(msg: str):
        if not Cfg.WHATSAPP_URL: return
        try:
            requests.post(Cfg.WHATSAPP_URL, json={"message": f"AIVANA NEXUS: {msg}"}, timeout=5)
        except: pass

    @staticmethod
    def email(subject: str, body: str):
        if not Cfg.SMTP_USER: return
        try:
            mm = MIMEMultipart()
            mm["From"] = Cfg.SMTP_USER; mm["To"] = Cfg.SMTP_TO
            mm["Subject"] = f"[AIVANA] {subject}"
            mm.attach(MIMEText(body, "html"))
            s = smtplib.SMTP(Cfg.SMTP_HOST, Cfg.SMTP_PORT)
            s.starttls(); s.login(Cfg.SMTP_USER, Cfg.SMTP_PASS)
            s.sendmail(Cfg.SMTP_USER, Cfg.SMTP_TO, mm.as_string()); s.quit()
        except: pass

    @classmethod
    def alert(cls, msg: str, level: str = "info"):
        icon = "SUCCESS" if level=="success" else ("FAIL" if level=="error" else "INFO")
        full = f"[{icon}] {msg}"
        threading.Thread(target=cls.telegram, args=(full,), daemon=True).start()
        threading.Thread(target=cls.discord, args=(full,), daemon=True).start()
        if level == "error":
            threading.Thread(target=cls.whatsapp, args=(full,), daemon=True).start()

notify = NotifyHub()

# ══════════════════════════════════════════════════════════════════
#  VOICE ENGINE (Whisper STT + edge-tts)
# ══════════════════════════════════════════════════════════════════
class VoiceEngine:
    def __init__(self):
        self.whisper_model = None
        self.active = False
        self._thread = None
        self._load_whisper()

    def _load_whisper(self):
        if whisper_mod:
            try:
                broadcast(f"Loading Whisper ({Cfg.WHISPER_MODEL})...", "info", "voice")
                self.whisper_model = whisper_mod.load_model(Cfg.WHISPER_MODEL)
                broadcast("Whisper STT ready", "success", "voice")
            except Exception as e:
                broadcast(f"Whisper load failed: {e}", "warn", "voice")

    def speak(self, text: str):
        """Text to speech using edge-tts (free Microsoft voices)"""
        if not edge_tts_mod:
            return
        async def _speak():
            try:
                communicate = edge_tts_mod.Communicate(text[:300], Cfg.TTS_VOICE)
                tmp = _SCRIPT_DIR / "tts_tmp.mp3"
                await communicate.save(str(tmp))
                # Play audio
                if os.name == "nt":
                    subprocess.Popen(["powershell.exe", "-c", f"(New-Object Media.SoundPlayer).PlaySync()"],
                        stdin=open(str(tmp),'rb'), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                else:
                    subprocess.Popen(["mpg123", "-q", str(tmp)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                broadcast(f"TTS error: {e}", "warn", "voice")
        threading.Thread(target=lambda: asyncio.run(_speak()), daemon=True).start()

    def start(self):
        if self.active: return
        self.active = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()
        broadcast(f"Voice listening — say '{Cfg.WAKE_WORD.upper()}' + command", "success", "voice")

    def stop(self):
        self.active = False
        broadcast("Voice stopped", "info", "voice")

    def _loop(self):
        """Listen continuously for wake word then transcribe command"""
        if self.whisper_model and sr_mod:
            self._whisper_loop()
        elif sr_mod:
            self._google_loop()
        else:
            broadcast("Voice: no STT available. pip install openai-whisper SpeechRecognition", "warn", "voice")
            self.active = False

    def _whisper_loop(self):
        """High quality local STT using Whisper"""
        import numpy as np
        try:
            import sounddevice as sd
            RATE, CHUNK = 16000, 16000 * 3  # 3 sec chunks
            broadcast("Whisper listening (sounddevice)...", "info", "voice")
            while self.active:
                try:
                    audio = sd.rec(CHUNK, samplerate=RATE, channels=1, dtype="float32")
                    sd.wait()
                    result = self.whisper_model.transcribe(audio.flatten(), language="en")
                    text = result.get("text","").strip().lower()
                    if Cfg.WAKE_WORD in text:
                        cmd = text.replace(Cfg.WAKE_WORD,"").strip()
                        if cmd and len(cmd) > 2:
                            stats["voice_commands"] += 1
                            broadcast(f"Voice: '{cmd}'", "voice", "voice")
                            console.print(f"\n[cyan]  Voice:[/cyan] [white]{cmd}[/white]")
                            self.speak("Processing")
                            threading.Thread(target=run_agent, args=(cmd, "voice"), daemon=True).start()
                except Exception as e:
                    if self.active: time.sleep(1)
        except ImportError:
            broadcast("pip install sounddevice for Whisper voice", "warn", "voice")
            self._google_loop()

    def _google_loop(self):
        """Fallback: Google Speech Recognition"""
        r = sr_mod.Recognizer()
        mic = sr_mod.Microphone()
        try:
            with mic as src: r.adjust_for_ambient_noise(src, duration=1)
        except Exception as e:
            broadcast(f"Mic init failed: {e}", "warn", "voice"); self.active = False; return
        while self.active:
            try:
                with mic as src:
                    audio = r.listen(src, timeout=5, phrase_time_limit=8)
                text = r.recognize_google(audio).lower()
                if Cfg.WAKE_WORD in text:
                    cmd = text.replace(Cfg.WAKE_WORD,"").strip()
                    if cmd:
                        stats["voice_commands"] += 1
                        broadcast(f"Voice: '{cmd}'", "voice", "voice")
                        self.speak("Processing")
                        threading.Thread(target=run_agent, args=(cmd, "voice"), daemon=True).start()
            except Exception: pass

voice = VoiceEngine()

# ══════════════════════════════════════════════════════════════════
#  SCRIPT EXECUTOR
# ══════════════════════════════════════════════════════════════════
def run_script(action: str, retry: int = 0) -> Tuple[bool, str]:
    if action not in SCRIPT_MAP:
        return False, f"Unknown: {action}"
    script = SCRIPT_MAP[action]
    if not os.path.exists(script):
        return False, f"Missing: {script}"
    stats["total"] += 1
    start = time.time()
    broadcast(f"[{action}] starting (attempt {retry+1})", "info", action)
    console.print(Panel(f"[cyan]{action}[/cyan] [dim]{script}[/dim]", border_style="cyan"))
    lines = []
    try:
        proc = subprocess.Popen(
            ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, shell=True,
            encoding="utf-8", errors="replace")
        for line in iter(proc.stdout.readline, ""):
            line = line.rstrip()
            if line: lines.append(line); broadcast(line, "output", action)
            console.print(f"  [dim]|[/dim] {line}")
        proc.stdout.close(); proc.wait()
        stderr = proc.stderr.read(); dur = time.time() - start
        if proc.returncode == 0:
            stats["success"] += 1; memory.record(action, True, dur)
            broadcast(f"[{action}] OK in {dur:.1f}s", "success", action)
            notify.alert(f"[{action}] succeeded in {dur:.1f}s", "success")
            return True, "\n".join(lines)
        else:
            stats["failed"] += 1; memory.record(action, False, dur)
            broadcast(f"[{action}] FAILED exit:{proc.returncode}", "error", action)
            notify.alert(f"[{action}] FAILED — {stderr[:120]}", "error")
            return False, stderr
    except Exception as e:
        stats["failed"] += 1; memory.record(action, False, 0)
        return False, str(e)

def run_script_with_retry(action: str) -> Tuple[bool, str]:
    if memory.should_pre_heal(action) and action not in ("heal","repair"):
        broadcast(f"Predictive heal for [{action}] (high fail rate)", "warn", "ai")
        run_script("heal")
    for attempt in range(Cfg.MAX_RETRIES):
        ok, out = run_script(action, attempt)
        if ok: return True, out
        if attempt < Cfg.MAX_RETRIES - 1:
            if action != "repair": run_script("repair")
            time.sleep(Cfg.RETRY_DELAY)
    return False, "All retries exhausted"

def run_pipeline(name: str, custom: List[str] = None, by: str = "manual") -> bool:
    steps = custom or PIPELINES.get(name, {}).get("steps", [])
    on_fail = PIPELINES.get(name, {}).get("on_fail", "repair")
    if not steps: broadcast(f"Unknown pipeline: {name}", "error"); return False
    stats["pipelines"] += 1
    broadcast(f"Pipeline [{name}] START: {' > '.join(steps)}", "pipeline", name)
    console.print(Panel(f"[magenta]PIPELINE: {name}[/magenta]\n[dim]{' -> '.join(steps)}[/dim]", border_style="magenta"))
    passed = 0
    for i, step in enumerate(steps):
        console.rule(f"[cyan]Step {i+1}/{len(steps)}: {step}[/cyan]")
        ok, out = run_script_with_retry(step)
        if ok: passed += 1
        elif on_fail == "stop":
            broadcast(f"Pipeline [{name}] stopped at [{step}]", "error", name); break
        elif on_fail == "repair":
            run_script("repair")
    status = "SUCCESS" if passed == len(steps) else ("PARTIAL" if passed > 0 else "FAILED")
    broadcast(f"Pipeline [{name}] {status} — {passed}/{len(steps)}", "pipeline" if status=="SUCCESS" else "error", name)
    notify.alert(f"Pipeline [{name}] {status} {passed}/{len(steps)} steps", "success" if status=="SUCCESS" else "error")
    return status == "SUCCESS"

# ══════════════════════════════════════════════════════════════════
#  REGISTERED TOOLS (AI can call these)
# ══════════════════════════════════════════════════════════════════

@tool("deploy", "Deploy AIVANA to production", "deploy")
def tool_deploy() -> str:
    ok, out = run_script_with_retry("deploy")
    return "Deploy SUCCESS" if ok else f"Deploy FAILED: {out[:200]}"

@tool("repair", "Auto-repair AIVANA services", "deploy")
def tool_repair() -> str:
    ok, out = run_script_with_retry("repair")
    return "Repair done" if ok else f"Repair failed: {out[:200]}"

@tool("heal", "Auto-heal TODO list and FTPS", "deploy")
def tool_heal() -> str:
    ok, out = run_script_with_retry("heal")
    return "Heal done" if ok else f"Heal failed: {out[:200]}"

@tool("status", "Check FTP/server status", "deploy")
def tool_status() -> str:
    ok, out = run_script_with_retry("status")
    return f"Status: {'OK' if ok else 'FAILED'} — {out[:300]}"

@tool("uploader", "Upload files to server", "deploy")
def tool_uploader() -> str:
    ok, out = run_script_with_retry("uploader")
    return "Upload done" if ok else f"Upload failed: {out[:200]}"

@tool("launch_pipeline", "Run full production launch: status->deploy->upload", "pipeline")
def tool_launch() -> str:
    ok = run_pipeline("launch", by="agent")
    return "Launch pipeline complete" if ok else "Launch pipeline failed"

@tool("full_pipeline", "Run complete 5-step cycle", "pipeline")
def tool_full() -> str:
    ok = run_pipeline("full", by="agent")
    return "Full pipeline complete" if ok else "Full pipeline failed"

@tool("hotfix_pipeline", "Emergency hotfix pipeline", "pipeline")
def tool_hotfix() -> str:
    ok = run_pipeline("hotfix", by="agent")
    return "Hotfix complete" if ok else "Hotfix failed"

@tool("recovery_pipeline", "Disaster recovery pipeline", "pipeline")
def tool_recovery() -> str:
    ok = run_pipeline("recovery", by="agent")
    return "Recovery complete" if ok else "Recovery failed"

@tool("git_pull", "Pull latest code from GitHub", "git")
def tool_git_pull() -> str:
    try:
        r = subprocess.run(["git","pull"], capture_output=True, text=True, timeout=30)
        return f"Git pull: {r.stdout.strip() or r.stderr.strip()}"
    except Exception as e:
        return f"Git pull failed: {e}"

@tool("git_status", "Check git repository status", "git")
def tool_git_status() -> str:
    try:
        r = subprocess.run(["git","status","--short"], capture_output=True, text=True, timeout=10)
        branch = subprocess.run(["git","branch","--show-current"], capture_output=True, text=True, timeout=5)
        return f"Branch: {branch.stdout.strip()} | {r.stdout.strip() or 'Clean'}"
    except Exception as e:
        return f"Git error: {e}"

@tool("git_deploy", "Pull latest code then deploy", "git")
def tool_git_deploy() -> str:
    pull = tool_git_pull()
    broadcast(f"Git: {pull}", "info", "git")
    if "error" in pull.lower(): return f"Deploy cancelled: {pull}"
    return tool_launch()

@tool("docker_ps", "List running Docker containers", "docker")
def tool_docker_ps() -> str:
    try:
        r = subprocess.run(["docker","ps","--format","table {{.Names}}\t{{.Status}}"],
            capture_output=True, text=True, timeout=15)
        return r.stdout.strip() or "No containers running"
    except Exception as e:
        return f"Docker error: {e}"

@tool("docker_up", "Start Docker compose services", "docker")
def tool_docker_up() -> str:
    try:
        r = subprocess.run(["docker","compose","up","-d","--build"],
            capture_output=True, text=True, timeout=120)
        return "Docker up: " + (r.stdout.strip() or r.stderr.strip())
    except Exception as e:
        return f"Docker up failed: {e}"

@tool("docker_down", "Stop Docker compose services", "docker")
def tool_docker_down() -> str:
    try:
        r = subprocess.run(["docker","compose","down"], capture_output=True, text=True, timeout=60)
        return "Docker down: " + (r.stdout.strip() or r.stderr.strip())
    except Exception as e:
        return f"Docker down failed: {e}"

@tool("web_search", "Search the web for information (free, no API key)", "info")
def tool_web_search(query: str = "") -> str:
    if not query: return "Provide a search query"
    return web_search(query)

@tool("system_info", "Get system information", "info")
def tool_system_info() -> str:
    try:
        cpu = subprocess.run(["wmic","cpu","get","name","/value"],capture_output=True,text=True,timeout=5)
        mem = subprocess.run(["wmic","computersystem","get","TotalPhysicalMemory","/value"],capture_output=True,text=True,timeout=5)
        return f"CPU: {cpu.stdout.strip()} | RAM: {mem.stdout.strip()}"
    except Exception as e:
        return f"System info: {e}"

@tool("list_scripts", "List all available PS1 scripts", "info")
def tool_list_scripts() -> str:
    lines = [f"  {k} -> {v} {'[OK]' if os.path.exists(v) else '[MISSING]'}"
             for k, v in SCRIPT_MAP.items()]
    return "\n".join(lines[:20])

@tool("stats_report", "Show execution statistics", "info")
def tool_stats_report() -> str:
    return (f"Total:{stats['total']} Success:{stats['success']} "
            f"Failed:{stats['failed']} Pipelines:{stats['pipelines']} "
            f"Agent runs:{stats['agent_runs']} Voice cmds:{stats['voice_commands']}")

@tool("send_telegram", "Send a Telegram notification", "notify")
def tool_send_telegram(message: str = "") -> str:
    if not message: return "Provide message"
    notify.telegram(message)
    return f"Telegram sent: {message[:50]}"

@tool("send_whatsapp", "Send a WhatsApp message via ultra-bot", "notify")
def tool_send_whatsapp(message: str = "") -> str:
    if not message: return "Provide message"
    notify.whatsapp(message)
    return f"WhatsApp sent: {message[:50]}"

@tool("write_file", "Write content to a file", "file")
def tool_write_file(filename: str = "", content: str = "") -> str:
    if not filename or not content: return "Provide filename and content"
    try:
        Path(filename).write_text(content, encoding="utf-8")
        return f"Written: {filename} ({len(content)} chars)"
    except Exception as e:
        return f"Write failed: {e}"

@tool("read_file", "Read content from a file", "file")
def tool_read_file(filename: str = "") -> str:
    if not filename: return "Provide filename"
    try:
        return Path(filename).read_text(encoding="utf-8", errors="replace")[:2000]
    except Exception as e:
        return f"Read failed: {e}"

@tool("run_command", "Run a PowerShell command", "system")
def tool_run_command(cmd: str = "") -> str:
    if not cmd: return "Provide command"
    try:
        r = subprocess.run(["powershell.exe","-Command",cmd],
            capture_output=True, text=True, timeout=30, encoding="utf-8", errors="replace")
        out = r.stdout.strip() or r.stderr.strip()
        return f"Output: {out[:500]}"
    except Exception as e:
        return f"Command failed: {e}"

@tool("github_repos", "List your GitHub repositories", "git")
def tool_github_repos() -> str:
    if not Cfg.GITHUB_TOKEN: return "Set GITHUB_TOKEN env var"
    data = github_api("user/repos?per_page=10&sort=updated")
    if isinstance(data, list):
        return "\n".join([f"  {r['name']}: {r.get('description','')[:50]}" for r in data[:10]])
    return str(data)[:300]

@tool("github_issues", "List open GitHub issues", "git")
def tool_github_issues(repo: str = "") -> str:
    if not Cfg.GITHUB_TOKEN: return "Set GITHUB_TOKEN env var"
    if not repo: return "Provide repo name (owner/repo)"
    data = github_api(f"repos/{repo}/issues?state=open&per_page=10")
    if isinstance(data, list):
        return "\n".join([f"  #{i['number']}: {i['title']}" for i in data[:10]])
    return str(data)[:300]

@tool("snapshot", "Save a backup snapshot of all scripts", "backup")
def tool_snapshot(label: str = "") -> str:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    name = f"snap_{ts}.zip"
    path = Cfg.BACKUP_DIR / name
    try:
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
            for s in set(SCRIPT_MAP.values()):
                if os.path.exists(s): zf.write(s)
        broadcast(f"Snapshot: {name}", "success", "backup")
        return f"Snapshot saved: {name}"
    except Exception as e:
        return f"Snapshot failed: {e}"

# ══════════════════════════════════════════════════════════════════
#  REACT AGENT LOOP (Think -> Act -> Observe -> Repeat)
# ══════════════════════════════════════════════════════════════════
AGENT_SYSTEM = f"""You are AIVANA NEXUS — an autonomous AI DevOps agent.

{get_tools_prompt()}

Your job: Given a task, autonomously select and call tools to complete it.

STRICT FORMAT for each step:
THOUGHT: [your reasoning about what to do next]
ACTION: tool_name [optional args]
OBSERVATION: [you will see result here]
... repeat ...
FINAL: [your conclusion/answer to user]

Rules:
- Always start with THOUGHT
- FINAL ends the agent loop
- Be decisive, don't ask for confirmation
- Chain tools when needed (e.g., git_deploy = git_pull + launch_pipeline)
- Hinglish commands are fine — understand and execute
- Max {Cfg.MAX_AGENT_STEPS} steps

Examples:
User: "production deploy karo"
THOUGHT: User wants production deploy. I'll run launch pipeline.
ACTION: launch_pipeline
OBSERVATION: Launch pipeline complete
FINAL: Production deploy complete!

User: "status check karke agar fail ho toh repair karo"
THOUGHT: Check status first
ACTION: status
OBSERVATION: Status: FAILED
THOUGHT: Status failed, need to repair
ACTION: repair
OBSERVATION: Repair done
FINAL: Status failed so I ran repair. System should be restored.
"""

def run_agent(task: str, source: str = "cli") -> str:
    stats["agent_runs"] += 1
    convo.append({"role":"user","content":task,"time":datetime.now().isoformat()})
    broadcast(f"Agent starting: '{task[:80]}'", "agent", source)

    history = f"Task: {task}\n"
    steps_done = 0
    final_answer = ""

    for step in range(Cfg.MAX_AGENT_STEPS):
        steps_done += 1
        prompt = history + "\nYour next step:"

        with Progress(SpinnerColumn(), TextColumn(f"[cyan]Agent thinking (step {step+1})..."), transient=True, console=console) as p:
            p.add_task("", total=None)
            response = brain.ask(prompt, AGENT_SYSTEM)

        broadcast(f"Agent step {step+1}: {response[:120]}", "agent", "agent")
        history += f"\n{response}\n"

        # Parse FINAL
        if "FINAL:" in response:
            final_answer = response.split("FINAL:")[-1].strip()
            break

        # Parse ACTION
        if "ACTION:" in response:
            action_line = ""
            for line in response.split("\n"):
                if line.strip().startswith("ACTION:"):
                    action_line = line.split("ACTION:")[1].strip()
                    break

            if action_line:
                parts = action_line.split(None, 1)
                tool_name = parts[0].lower().strip()
                tool_args = parts[1] if len(parts) > 1 else ""

                broadcast(f"Calling tool: {tool_name} ({tool_args[:50]})", "tool", "agent")
                console.print(f"  [yellow]-> Tool:[/yellow] [white]{tool_name}[/white] [dim]{tool_args}[/dim]")

                if tool_name in _tools:
                    fn = _tools[tool_name]["fn"]
                    try:
                        if tool_args:
                            obs = fn(tool_args)
                        else:
                            obs = fn()
                    except TypeError:
                        try: obs = fn()
                        except Exception as e: obs = f"Tool error: {e}"
                    except Exception as e:
                        obs = f"Tool error: {e}"
                else:
                    # Try as script name
                    if tool_name in SCRIPT_MAP:
                        ok, out = run_script_with_retry(tool_name)
                        obs = f"Script {'OK' if ok else 'FAILED'}: {out[:200]}"
                    else:
                        obs = f"Unknown tool: {tool_name}. Available: {', '.join(list(_tools.keys())[:15])}"

                obs_str = str(obs)[:500]
                history += f"OBSERVATION: {obs_str}\n"
                broadcast(f"Tool result: {obs_str[:100]}", "tool", "agent")

    if not final_answer:
        final_answer = brain.ask(
            f"Summarize what was accomplished:\n{history[-1000:]}\nGive a 1-2 sentence summary.",
            "Be brief and direct."
        )

    console.print(Panel(f"[green]{final_answer}[/green]", title="[bold]Agent Result[/bold]", border_style="green"))
    broadcast(f"Agent done: {final_answer[:120]}", "success", "agent")
    notify.alert(f"Task complete: {final_answer[:100]}", "success")
    voice.speak(final_answer[:150])
    convo.append({"role":"assistant","content":final_answer,"time":datetime.now().isoformat()})
    return final_answer

# ══════════════════════════════════════════════════════════════════
#  SCHEDULER
# ══════════════════════════════════════════════════════════════════
def add_schedule(cron: str, task: str, label: str = None):
    jid = label or f"{task}_{cron.replace(' ','_')}"
    try:
        fn = (lambda t=task: run_agent(t, "scheduler")) if task not in PIPELINES and task not in SCRIPT_MAP \
             else (lambda t=task: run_pipeline(t, by="scheduler")) if task in PIPELINES \
             else (lambda t=task: run_script_with_retry(t))
        job = scheduler.add_job(fn, CronTrigger.from_crontab(cron), id=jid, replace_existing=True)
        scheduled_jobs[jid] = {"cron": cron, "task": task, "next": str(job.next_run_time)}
        memory.data["schedules"][jid] = {"cron": cron, "task": task}
        memory.save()
        broadcast(f"Scheduled: '{task}' @ cron '{cron}'", "schedule")
        console.print(f"[green]  Scheduled:[/green] [white]{task}[/white] @ [cyan]{cron}[/cyan]")
    except Exception as e:
        broadcast(f"Schedule error: {e}", "error")

def remove_schedule(jid: str):
    try:
        scheduler.remove_job(jid)
        scheduled_jobs.pop(jid, None)
        memory.data["schedules"].pop(jid, None)
        memory.save()
        broadcast(f"Removed schedule: {jid}", "info")
    except Exception as e:
        broadcast(f"Remove schedule error: {e}", "error")

# Restore from memory
for k, v in memory.data.get("schedules", {}).items():
    try: add_schedule(v["cron"], v["task"], k)
    except: pass

# ══════════════════════════════════════════════════════════════════
#  HEALTH MONITOR
# ══════════════════════════════════════════════════════════════════
def health_monitor():
    broadcast("Health check cycle", "monitor")
    ok, _ = run_script("status")
    if not ok:
        broadcast("Health FAILED — running autonomous recovery", "warn", "monitor")
        threading.Thread(target=run_agent, args=("status fail hua hai - repair karke redeploy karo",), daemon=True).start()
    else:
        broadcast("Health: All OK", "success", "monitor")

# ══════════════════════════════════════════════════════════════════
#  WEB DASHBOARD v3 — Full UI
# ══════════════════════════════════════════════════════════════════
DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AIVANA NEXUS v7</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.0/chart.umd.min.js"></script>
<style>
@import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&family=Share+Tech+Mono&display=swap');
:root{
  --bg:#020507;--s1:#050d12;--s2:#091520;--b:#0d2030;
  --amber:#ffab00;--cyan:#00e5ff;--green:#00e676;--red:#ff1744;
  --mag:#e040fb;--yellow:#ffd600;--dim:#1a3545;--text:#90bfcf;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:var(--bg);color:var(--text);font-family:'Share Tech Mono',monospace;font-size:12px;overflow:hidden}
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:9999;
  background:repeating-linear-gradient(0deg,transparent,transparent 3px,rgba(0,229,255,.008) 3px,rgba(0,229,255,.008) 4px)}
.root{display:grid;grid-template-rows:52px 38px 1fr;height:100vh}
header{background:var(--s1);border-bottom:1px solid var(--b);display:flex;align-items:center;padding:0 24px;gap:16px}
.logo{font-family:'Orbitron',monospace;font-size:16px;font-weight:900;color:var(--amber);
  letter-spacing:4px;text-shadow:0 0 30px rgba(255,171,0,.5)}
.version{font-size:9px;color:var(--amber);opacity:.6;border:1px solid;padding:1px 5px;letter-spacing:2px}
.badge{font-size:9px;padding:2px 6px;border:1px solid;letter-spacing:1px;font-weight:700}
.blv{border-color:var(--green);color:var(--green);animation:pulse 1.5s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}
.spacer{flex:1}
.hstat{display:flex;gap:4px;align-items:center;background:var(--bg);border:1px solid var(--b);padding:3px 8px;font-size:11px}
.hstat .v{font-weight:700}
.va{color:var(--green)}.ve{color:var(--red)}.vp{color:var(--mag)}.vt{color:var(--amber)}.vc{color:var(--cyan)}
.tabs{background:var(--s1);border-bottom:1px solid var(--b);display:flex;padding:0 12px;gap:1px}
.tab{padding:0 16px;cursor:pointer;border-bottom:2px solid transparent;
  font-size:10px;color:var(--dim);letter-spacing:1.5px;height:100%;display:flex;align-items:center;gap:5px;transition:all .15s}
.tab:hover{color:var(--text)}
.tab.active{color:var(--amber);border-bottom-color:var(--amber)}
.pane{display:none;height:100%;overflow:hidden}
.pane.active{display:grid}
/* AGENT PANE */
#pane-agent{grid-template-columns:1fr 340px}
.chat-panel{display:flex;flex-direction:column;background:var(--bg)}
.chat-msgs{flex:1;overflow-y:auto;padding:16px;display:flex;flex-direction:column;gap:10px}
.chat-msgs::-webkit-scrollbar{width:3px}
.chat-msgs::-webkit-scrollbar-thumb{background:var(--b)}
.msg{max-width:80%;padding:10px 14px;border-radius:2px;font-size:12px;line-height:1.6}
.msg.user{background:#0d2535;border:1px solid #1a4060;align-self:flex-end;color:var(--cyan)}
.msg.ai{background:#0a1a08;border:1px solid #1a3515;align-self:flex-start;color:#7aba6a}
.msg.system{background:#1a0a00;border:1px solid #3a2000;align-self:center;color:var(--amber);font-size:10px;text-align:center}
.msg.tool{background:#0a0a1a;border:1px solid #1a1a3a;align-self:flex-start;color:#6a6aba;font-size:11px}
.input-area{padding:12px;border-top:1px solid var(--b);background:var(--s1);flex-shrink:0}
.input-row{display:flex;gap:8px;margin-bottom:6px}
.ai-inp{flex:1;background:var(--bg);border:1px solid var(--b);color:var(--amber);
  font-family:'Share Tech Mono',monospace;font-size:13px;padding:10px 12px;outline:none}
.ai-inp:focus{border-color:var(--amber);box-shadow:0 0 10px rgba(255,171,0,.1)}
.ai-inp::placeholder{color:var(--dim)}
.send-btn{background:var(--amber);color:var(--bg);border:none;padding:10px 20px;cursor:pointer;
  font-family:'Orbitron',monospace;font-size:11px;font-weight:700;letter-spacing:1px}
.send-btn:hover{background:#ffc107}
.voice-btn{background:none;border:1px solid var(--dim);color:var(--dim);padding:10px 14px;
  cursor:pointer;font-family:'Share Tech Mono',monospace;font-size:11px;transition:all .2s}
.voice-btn.listening{border-color:var(--red);color:var(--red);animation:pulse .8s infinite}
.voice-btn:hover{border-color:var(--amber);color:var(--amber)}
.quick-btns{display:flex;gap:6px;flex-wrap:wrap}
.qb{background:none;border:1px solid var(--b);color:var(--dim);padding:4px 10px;cursor:pointer;
  font-family:'Share Tech Mono',monospace;font-size:10px;transition:all .15s;letter-spacing:1px}
.qb:hover{border-color:var(--cyan);color:var(--cyan)}
.qb.pipe:hover{border-color:var(--mag);color:var(--mag)}
/* RIGHT PANEL */
.right-panel{background:var(--s1);border-left:1px solid var(--b);display:flex;flex-direction:column;overflow-y:auto}
.rp-section{padding:12px;border-bottom:1px solid var(--b)}
.rp-title{font-family:'Orbitron',monospace;font-size:9px;font-weight:700;color:var(--amber);
  letter-spacing:2px;margin-bottom:8px;text-transform:uppercase}
.ai-provider-row{display:flex;align-items:center;justify-content:space-between;margin-bottom:4px;font-size:11px}
.ai-dot{width:6px;height:6px;border-radius:50%;background:var(--dim)}
.ai-dot.ok{background:var(--green);box-shadow:0 0 6px var(--green)}
.script-row{display:flex;align-items:center;gap:6px;padding:4px 0;border-bottom:1px solid #091520;font-size:10px}
.sdot{width:5px;height:5px;border-radius:50%;flex-shrink:0}
.sdot.ok{background:var(--green)}.sdot.bad{background:var(--red)}
/* TERMINAL PANE */
#pane-terminal{grid-template-columns:220px 1fr}
.ctrl{background:var(--s1);border-right:1px solid var(--b);overflow-y:auto;padding:10px}
.ctrl::-webkit-scrollbar{width:3px}
.ctrl::-webkit-scrollbar-thumb{background:var(--b)}
.sec{font-size:9px;color:var(--dim);letter-spacing:2px;text-transform:uppercase;margin:10px 0 5px}
.sec:first-child{margin-top:0}
.cb{width:100%;padding:6px 8px;border:1px solid var(--b);background:none;color:var(--text);
  font-family:'Share Tech Mono',monospace;font-size:10px;cursor:pointer;text-align:left;
  margin-bottom:2px;transition:all .1s;display:flex;gap:6px;align-items:center}
.cb:hover{border-color:var(--amber);color:var(--amber);background:rgba(255,171,0,.03)}
.cb.p:hover{border-color:var(--mag);color:var(--mag)}
.cb.g:hover{border-color:var(--cyan);color:var(--cyan)}
.cb.d:hover{border-color:var(--green);color:var(--green)}
.term-wrap{display:flex;flex-direction:column;background:var(--bg)}
.term-hdr{background:var(--s1);border-bottom:1px solid var(--b);padding:6px 14px;
  display:flex;align-items:center;gap:10px;flex-shrink:0;font-size:10px;color:var(--dim)}
#log-out{flex:1;overflow-y:auto;padding:10px 14px;line-height:1.8;font-size:11px}
#log-out::-webkit-scrollbar{width:3px}
#log-out::-webkit-scrollbar-thumb{background:var(--b)}
.ll{display:flex;gap:8px}
.lt{color:var(--dim);flex-shrink:0;font-size:10px}.ls{color:var(--cyan);min-width:60px;flex-shrink:0;font-size:10px}
.ll.error .lm{color:var(--red)}.ll.success .lm{color:var(--green)}.ll.warn .lm{color:var(--yellow)}
.ll.pipeline .lm{color:var(--mag)}.ll.output .lm{color:#5a9ab0}.ll.agent .lm{color:var(--amber)}
.ll.tool .lm{color:#7070c0}.ll.voice .lm{color:#ff80ab}.ll.ai .lm{color:#ffd080}
/* ANALYTICS */
#pane-analytics{grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;padding:12px;gap:10px}
.cc{background:var(--s1);border:1px solid var(--b);padding:12px;display:flex;flex-direction:column}
.ct{font-family:'Orbitron',monospace;font-size:10px;font-weight:700;color:var(--amber);
  letter-spacing:2px;margin-bottom:8px;text-transform:uppercase}
.cc canvas{flex:1;min-height:0}
/* SETTINGS */
#pane-settings{padding:20px;overflow-y:auto;display:block}
.sg{display:grid;grid-template-columns:1fr 1fr;gap:14px;max-width:900px}
.sc{background:var(--s1);border:1px solid var(--b);padding:14px}
.st{font-family:'Orbitron',monospace;font-size:10px;font-weight:700;color:var(--amber);letter-spacing:2px;margin-bottom:10px;text-transform:uppercase}
.sr{margin-bottom:7px}
.sr label{font-size:9px;color:var(--dim);display:block;margin-bottom:3px;letter-spacing:1px}
.si{width:100%;background:var(--bg);border:1px solid var(--b);color:var(--text);
  font-family:'Share Tech Mono',monospace;font-size:11px;padding:5px 8px;outline:none}
.si:focus{border-color:var(--amber)}
.sb{background:var(--amber);color:var(--bg);border:none;padding:6px 14px;cursor:pointer;
  font-family:'Orbitron',monospace;font-weight:700;font-size:10px;margin-top:7px;letter-spacing:1px}
.sb:hover{background:#ffc107}
</style>
</head>
<body>
<div class="root">
<header>
  <div class="logo">AIVANA NEXUS</div>
  <span class="version">v7.0</span>
  <span class="badge blv" id="ws-badge">CONNECTING</span>
  <div class="spacer"></div>
  <div class="hstat">TOTAL <span class="v vt" id="st">0</span></div>
  <div class="hstat">OK <span class="v va" id="so">0</span></div>
  <div class="hstat">FAIL <span class="v ve" id="sf">0</span></div>
  <div class="hstat">PIPES <span class="v vp" id="sp">0</span></div>
  <div class="hstat">AGENT <span class="v vc" id="sa">0</span></div>
  <div class="hstat">VOICE <span class="v" style="color:var(--mag)" id="sv">0</span></div>
</header>
<div class="tabs">
  <div class="tab active" onclick="sw('agent')">AI AGENT</div>
  <div class="tab" onclick="sw('terminal')">TERMINAL</div>
  <div class="tab" onclick="sw('analytics')">ANALYTICS</div>
  <div class="tab" onclick="sw('settings')">SETTINGS</div>
</div>
<!-- AGENT TAB -->
<div class="pane active" id="pane-agent">
  <div class="chat-panel">
    <div class="chat-msgs" id="chat"></div>
    <div class="input-area">
      <div class="input-row">
        <input class="ai-inp" id="ai-inp" placeholder="Kuch bhi bolo... 'production deploy karo' 'status check karke heal karo'..."
          onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();send()}">
        <button class="voice-btn" id="vbtn" onclick="toggleVoice()">MIC</button>
        <button class="send-btn" onclick="send()">SEND</button>
      </div>
      <div class="quick-btns">
        <button class="qb" onclick="cmd('deploy karo')">deploy</button>
        <button class="qb" onclick="cmd('status check karo')">status</button>
        <button class="qb" onclick="cmd('repair karo')">repair</button>
        <button class="qb" onclick="cmd('heal karo')">heal</button>
        <button class="qb p" onclick="cmd('production launch pipeline chala')">launch</button>
        <button class="qb p" onclick="cmd('full cycle pipeline chala')">full cycle</button>
        <button class="qb p" onclick="cmd('hotfix pipeline chala')">hotfix</button>
        <button class="qb g" onclick="cmd('git pull karke deploy karo')">git deploy</button>
        <button class="qb d" onclick="cmd('docker containers dikhao')">docker ps</button>
        <button class="qb" onclick="cmd('system info dikhao')">sys info</button>
        <button class="qb" onclick="cmd('stats report dikhao')">stats</button>
        <button class="qb" onclick="cmd('web search: AIVANA Kids OS best practices')">web search</button>
      </div>
    </div>
  </div>
  <div class="right-panel">
    <div class="rp-section">
      <div class="rp-title">AI Providers</div>
      <div id="providers">Loading...</div>
    </div>
    <div class="rp-section">
      <div class="rp-title">Active Jobs</div>
      <div id="jobs" style="font-size:10px;color:var(--dim)">None</div>
    </div>
    <div class="rp-section">
      <div class="rp-title">Schedules</div>
      <div id="scheds" style="font-size:10px;color:var(--dim)">None</div>
    </div>
    <div class="rp-section">
      <div class="rp-title">Scripts</div>
      <div id="scripts" style="font-size:10px"></div>
    </div>
    <div class="rp-section">
      <div class="rp-title">Add Schedule</div>
      <input class="si" id="sc-cron" placeholder="0 2 * * *" style="margin-bottom:4px">
      <input class="si" id="sc-task" placeholder="deploy karo / nightly pipeline">
      <button class="sb" onclick="addSched()" style="width:100%;margin-top:6px">ADD SCHEDULE</button>
    </div>
  </div>
</div>
<!-- TERMINAL TAB -->
<div class="pane" id="pane-terminal">
  <div class="ctrl">
    <div class="sec">Scripts</div>
    <button class="cb" onclick="run('deploy')">deploy</button>
    <button class="cb" onclick="run('repair')">repair</button>
    <button class="cb" onclick="run('heal')">heal</button>
    <button class="cb" onclick="run('status')">status</button>
    <button class="cb" onclick="run('uploader')">uploader</button>
    <div class="sec">Pipelines</div>
    <button class="cb p" onclick="pipe('launch')">launch</button>
    <button class="cb p" onclick="pipe('hotfix')">hotfix</button>
    <button class="cb p" onclick="pipe('nightly')">nightly</button>
    <button class="cb p" onclick="pipe('full')">full cycle</button>
    <button class="cb p" onclick="pipe('recovery')">recovery</button>
    <div class="sec">Git</div>
    <button class="cb g" onclick="gtool('git_pull')">git pull</button>
    <button class="cb g" onclick="gtool('git_deploy')">git deploy</button>
    <button class="cb g" onclick="gtool('git_status')">git status</button>
    <div class="sec">Docker</div>
    <button class="cb d" onclick="gtool('docker_ps')">containers</button>
    <button class="cb d" onclick="gtool('docker_up')">compose up</button>
    <button class="cb d" onclick="gtool('docker_down')">compose down</button>
    <div class="sec">Backup</div>
    <button class="cb" onclick="gtool('snapshot')">snapshot</button>
  </div>
  <div class="term-wrap">
    <div class="term-hdr">
      <span>LIVE LOG</span>
      <label style="display:flex;gap:4px;align-items:center;cursor:pointer"><input type="checkbox" id="as" checked> AUTO-SCROLL</label>
      <button onclick="document.getElementById('log-out').innerHTML=''" style="margin-left:auto;background:none;border:1px solid var(--b);color:var(--dim);padding:2px 8px;cursor:pointer;font-family:inherit;font-size:10px">CLEAR</button>
    </div>
    <div id="log-out"></div>
  </div>
</div>
<!-- ANALYTICS TAB -->
<div class="pane" id="pane-analytics">
  <div class="cc"><div class="ct">Success vs Failed</div><canvas id="c1"></canvas></div>
  <div class="cc"><div class="ct">Agent Runs Timeline</div><canvas id="c2"></canvas></div>
  <div class="cc"><div class="ct">Avg Execution Time (s)</div><canvas id="c3"></canvas></div>
  <div class="cc"><div class="ct">Failure Rate %</div><canvas id="c4"></canvas></div>
</div>
<!-- SETTINGS TAB -->
<div class="pane" id="pane-settings">
  <div class="sg">
    <div class="sc">
      <div class="st">AI Providers</div>
      <div class="sr"><label>AI PROVIDER (ollama/groq/gemini)</label><input class="si" id="s-provider" placeholder="ollama"></div>
      <div class="sr"><label>GROQ API KEY (free: console.groq.com)</label><input class="si" id="s-groq" placeholder="gsk_..."></div>
      <div class="sr"><label>GEMINI API KEY (free: aistudio.google.com)</label><input class="si" id="s-gemini" placeholder="AIza..."></div>
      <div class="sr"><label>HUGGINGFACE API KEY (free: huggingface.co)</label><input class="si" id="s-hf" placeholder="hf_..."></div>
      <button class="sb" onclick="saveCfg()">SAVE & RESTART</button>
    </div>
    <div class="sc">
      <div class="st">Notifications</div>
      <div class="sr"><label>TELEGRAM TOKEN</label><input class="si" id="s-tg" placeholder="bot token..."></div>
      <div class="sr"><label>TELEGRAM CHAT ID</label><input class="si" id="s-tgc" placeholder="-100..."></div>
      <div class="sr"><label>DISCORD WEBHOOK</label><input class="si" id="s-disc" placeholder="https://discord.com/api/webhooks/..."></div>
      <div class="sr"><label>WHATSAPP WEBHOOK (ultra-bot)</label><input class="si" id="s-wa" placeholder="http://localhost:3000/send"></div>
      <button class="sb" onclick="saveCfg()">SAVE</button>
    </div>
    <div class="sc">
      <div class="st">Voice</div>
      <div class="sr"><label>TTS VOICE</label><input class="si" id="s-voice" value="en-IN-NeerjaNeural"></div>
      <div class="sr"><label>WAKE WORD</label><input class="si" id="s-wake" value="aivana"></div>
      <div class="sr"><label>WHISPER MODEL (tiny/base/small)</label><input class="si" id="s-whisper" value="base"></div>
      <div style="font-size:10px;color:var(--dim);margin-top:8px">Install: pip install openai-whisper edge-tts sounddevice</div>
      <button class="sb" onclick="toggleVoiceServer()">TOGGLE VOICE</button>
    </div>
    <div class="sc">
      <div class="st">GitHub Integration</div>
      <div class="sr"><label>GITHUB TOKEN (free: github.com/settings/tokens)</label><input class="si" id="s-gh" placeholder="ghp_..."></div>
      <div class="sr"><label>EMAIL (SMTP)</label><input class="si" id="s-smtp-u" placeholder="you@gmail.com"></div>
      <div class="sr"><label>EMAIL APP PASSWORD</label><input class="si" type="password" id="s-smtp-p" placeholder="app password"></div>
      <div class="sr"><label>ALERT EMAIL TO</label><input class="si" id="s-smtp-t" placeholder="alerts@email.com"></div>
      <button class="sb" onclick="saveCfg()">SAVE</button>
    </div>
  </div>
</div>
</div>
<script>
const term=document.getElementById('log-out');
const chat=document.getElementById('chat');
let ws,charts={},voiceOn=false;
Chart.defaults.color='#90bfcf';Chart.defaults.font.family='Share Tech Mono';Chart.defaults.font.size=10;
const g='#0d2030';

function connect(){
  ws=new WebSocket(`ws://${location.hostname}:${location.port}/ws`);
  ws.onopen=()=>{setb(true);fetch('/status').then(r=>r.json()).then(updateAll);}
  ws.onmessage=({data})=>{const d=JSON.parse(data);if(d.type==='stats'){updateStats(d);return;}appendLog(d);};
  ws.onclose=()=>{setb(false);setTimeout(connect,3000);}
}
function setb(ok){const b=document.getElementById('ws-badge');b.textContent=ok?'LIVE':'RECONNECTING';b.style.color=ok?'var(--green)':'var(--yellow)';b.style.borderColor=ok?'var(--green)':'var(--yellow)';}
function appendLog(d){
  const el=document.createElement('div');el.className=`ll ${d.level}`;
  el.innerHTML=`<span class="lt">${d.time}</span><span class="ls">[${(d.source||'').substring(0,8)}]</span><span class="lm">${esc(d.msg)}</span>`;
  term.appendChild(el);
  if(document.getElementById('as').checked) term.scrollTop=term.scrollHeight;
}
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function addChat(msg,cls,time){
  const el=document.createElement('div');el.className=`msg ${cls}`;
  el.textContent=msg;if(time)el.title=time;
  chat.appendChild(el);chat.scrollTop=chat.scrollHeight;
}
function send(){
  const v=document.getElementById('ai-inp').value.trim();if(!v)return;
  addChat(v,'user');
  document.getElementById('ai-inp').value='';
  addChat('Agent processing...','system');
  fetch('/agent',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({input:v})})
    .then(r=>r.json()).then(d=>{
      document.querySelector('.msg.system:last-child')?.remove();
      if(d.result) addChat(d.result,'ai');
    });
}
function cmd(c){document.getElementById('ai-inp').value=c;send();}
function run(a){fetch(`/run/${a}`,{method:'POST'}).then(()=>addChat(`Script '${a}' queued`,'system'));}
function pipe(n){fetch(`/pipeline/${n}`,{method:'POST'}).then(()=>addChat(`Pipeline '${n}' started`,'system'));}
function gtool(t){fetch('/tool',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:t})}).then(r=>r.json()).then(d=>addChat(d.result||'done','ai'));}
function addSched(){
  const cron=document.getElementById('sc-cron').value,task=document.getElementById('sc-task').value;
  if(!cron||!task)return;
  fetch('/schedule',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({cron,task})});
  addChat(`Scheduled: '${task}' @ ${cron}`,'system');
}
function toggleVoice(){
  voiceOn=!voiceOn;
  fetch('/voice',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({active:voiceOn})});
  const b=document.getElementById('vbtn');
  b.textContent=voiceOn?'MIC ON':'MIC';b.className=`voice-btn${voiceOn?' listening':''}`;
  addChat(voiceOn?`Voice ON — say '${('aivana').toUpperCase()}' + command`:'Voice OFF','system');
}
function toggleVoiceServer(){toggleVoice();}
function saveCfg(){
  const cfg={
    AI_PROVIDER:document.getElementById('s-provider').value||undefined,
    GROQ_API_KEY:document.getElementById('s-groq').value||undefined,
    GEMINI_API_KEY:document.getElementById('s-gemini').value||undefined,
    HF_API_KEY:document.getElementById('s-hf').value||undefined,
    TELEGRAM_TOKEN:document.getElementById('s-tg').value||undefined,
    TELEGRAM_CHAT:document.getElementById('s-tgc').value||undefined,
    DISCORD_WEBHOOK:document.getElementById('s-disc').value||undefined,
    WHATSAPP_URL:document.getElementById('s-wa').value||undefined,
    TTS_VOICE:document.getElementById('s-voice').value||undefined,
    WAKE_WORD:document.getElementById('s-wake').value||undefined,
    GITHUB_TOKEN:document.getElementById('s-gh').value||undefined,
    SMTP_USER:document.getElementById('s-smtp-u').value||undefined,
    SMTP_PASS:document.getElementById('s-smtp-p').value||undefined,
    SMTP_TO:document.getElementById('s-smtp-t').value||undefined,
  };
  Object.keys(cfg).forEach(k=>{if(!cfg[k])delete cfg[k];});
  fetch('/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(cfg)})
    .then(()=>addChat('Config saved!','system'));
}
function sw(name){
  document.querySelectorAll('.pane').forEach(p=>p.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
  document.getElementById(`pane-${name}`).classList.add('active');
  event.target.classList.add('active');
}
function updateStats(d){
  ['st','so','sf','sp','sa','sv'].forEach((id,i)=>{
    const vals=[d.total,d.success,d.failed,d.pipelines,d.agent_runs||0,d.voice_commands||0];
    document.getElementById(id).textContent=vals[i]||0;
  });
  if(charts.c1){
    charts.c1.data.datasets[0].data=[d.success||0,d.failed||0];charts.c1.update('none');
  }
  if(d.providers){
    document.getElementById('providers').innerHTML=d.providers.map(p=>
      `<div class="ai-provider-row"><div style="display:flex;gap:6px;align-items:center"><div class="ai-dot ok"></div><span>${p}</span></div><span style="color:var(--green);font-size:10px">READY</span></div>`
    ).join('');
  }
}
function updateAll(d){
  updateStats(d.stats||{});
  if(d.scripts){
    document.getElementById('scripts').innerHTML=d.scripts.slice(0,12).map(s=>
      `<div class="script-row"><div class="sdot ${s.found?'ok':'bad'}"></div><span>${s.name}</span></div>`
    ).join('');
  }
  if(d.schedules){
    const sl=d.schedules;
    document.getElementById('scheds').innerHTML=Object.entries(sl).length>0?
      Object.entries(sl).map(([k,v])=>`<div style="margin-bottom:3px;color:var(--text)">${v.task} <span style="color:var(--cyan)">${v.cron}</span></div>`).join(''):'None';
  }
}
function initCharts(){
  charts.c1=new Chart(document.getElementById('c1'),{type:'doughnut',
    data:{labels:['Success','Failed'],datasets:[{data:[0,0],backgroundColor:['#00e676','#ff1744'],borderWidth:0}]},
    options:{plugins:{legend:{labels:{color:'#90bfcf'}}},cutout:'60%'}});
  const line_data={labels:[],datasets:[{label:'agents',data:[],borderColor:'#ffab00',backgroundColor:'rgba(255,171,0,.1)',tension:.4,fill:true}]};
  charts.c2=new Chart(document.getElementById('c2'),{type:'line',data:line_data,
    options:{scales:{x:{grid:{color:g}},y:{grid:{color:g},beginAtZero:true}},plugins:{legend:{display:false}}}});
  charts.c3=new Chart(document.getElementById('c3'),{type:'bar',
    data:{labels:[],datasets:[{data:[],backgroundColor:'rgba(0,229,255,.6)',borderColor:'#00e5ff',borderWidth:1}]},
    options:{scales:{x:{grid:{color:g}},y:{grid:{color:g},beginAtZero:true}},plugins:{legend:{display:false}}}});
  charts.c4=new Chart(document.getElementById('c4'),{type:'bar',
    data:{labels:[],datasets:[{data:[],backgroundColor:'rgba(255,23,68,.5)',borderColor:'#ff1744',borderWidth:1}]},
    options:{scales:{x:{grid:{color:g}},y:{grid:{color:g},beginAtZero:true,max:100}},plugins:{legend:{display:false}}}});
}
let agentHistory=[];
setInterval(()=>{
  fetch('/status').then(r=>r.json()).then(d=>{
    updateAll(d);
    agentHistory.push(d.stats?.agent_runs||0);
    if(agentHistory.length>20) agentHistory.shift();
    if(charts.c2){charts.c2.data.labels=agentHistory.map((_,i)=>i+1);charts.c2.data.datasets[0].data=[...agentHistory];charts.c2.update('none');}
    if(d.perf&&charts.c3){
      const keys=Object.keys(d.perf),avgs=keys.map(k=>d.perf[k].avg),fails=keys.map(k=>d.perf[k].fail);
      charts.c3.data.labels=keys;charts.c3.data.datasets[0].data=avgs;charts.c3.update('none');
      charts.c4.data.labels=keys;charts.c4.data.datasets[0].data=fails;charts.c4.update('none');
    }
  });
},4000);
initCharts();connect();
addChat('AIVANA NEXUS v7.0 online. Kuch bhi bolo ya quick buttons use karo.','system');
</script>
</body>
</html>"""

# ══════════════════════════════════════════════════════════════════
#  FASTAPI
# ══════════════════════════════════════════════════════════════════
app = FastAPI(title="AIVANA NEXUS v7")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.get("/", response_class=HTMLResponse)
async def dashboard(): return DASHBOARD_HTML

@app.websocket("/ws")
async def ws_ep(ws: WebSocket):
    await ws.accept(); ws_clients.append(ws)
    for e in live_log: await ws.send_text(json.dumps(e))
    try:
        while True: await ws.receive_text()
    except WebSocketDisconnect:
        try: ws_clients.remove(ws)
        except: pass

@app.post("/agent")
async def api_agent(req: Request, bg: BackgroundTasks):
    body = await req.json()
    task = body.get("input","")
    # Run in thread, return immediately with queued status
    result_holder = {"result": None, "done": False}
    def _run():
        result_holder["result"] = run_agent(task, "web")
        result_holder["done"] = True
    t = threading.Thread(target=_run, daemon=True)
    t.start()
    t.join(timeout=Cfg.AGENT_TIMEOUT)
    return {"result": result_holder.get("result") or "Agent running in background..."}

@app.post("/run/{action}")
async def api_run(action: str, bg: BackgroundTasks):
    bg.add_task(run_script_with_retry, action)
    return {"queued": action}

@app.post("/pipeline/{name}")
async def api_pipe(name: str, bg: BackgroundTasks):
    bg.add_task(run_pipeline, name, None, "web")
    return {"queued": name}

@app.post("/tool")
async def api_tool(req: Request):
    body = await req.json()
    name = body.get("name",""); args = body.get("args","")
    if name not in _tools: return {"result": f"Unknown tool: {name}"}
    fn = _tools[name]["fn"]
    try:
        result = fn(args) if args else fn()
    except TypeError:
        result = fn()
    except Exception as e:
        result = str(e)
    return {"result": str(result)}

@app.post("/schedule")
async def api_schedule(req: Request):
    body = await req.json()
    add_schedule(body.get("cron",""), body.get("task",""))
    return {"ok": True}

@app.post("/voice")
async def api_voice(req: Request):
    body = await req.json()
    if body.get("active"): voice.start()
    else: voice.stop()
    return {"ok": True}

@app.post("/config")
async def api_config(req: Request):
    body = await req.json()
    _cfg_file.write_text(json.dumps(body, indent=2))
    broadcast("Config saved. Restart to apply some changes.", "info")
    return {"ok": True}

@app.post("/webhook/github")
async def github_hook(req: Request, bg: BackgroundTasks):
    payload = await req.json()
    ref = payload.get("ref","")
    if "main" in ref or "master" in ref:
        broadcast(f"GitHub push to {ref} -> auto deploy", "webhook", "github")
        bg.add_task(run_agent, "github pe push aaya hai, git pull karke production deploy karo", "github")
    return {"ok": True}

@app.post("/telegram/webhook")
async def telegram_hook(req: Request, bg: BackgroundTasks):
    """Telegram bot webhook — send commands via Telegram"""
    body = await req.json()
    msg = body.get("message",{})
    text = msg.get("text","").strip()
    if text and not text.startswith("/"):
        bg.add_task(run_agent, text, "telegram")
        notify.telegram(f"Processing: {text[:50]}")
    return {"ok": True}

@app.get("/status")
async def api_status():
    seen = set(); scripts_info = []; found = 0
    for k, v in SCRIPT_MAP.items():
        if v in seen: continue
        seen.add(v); f = os.path.exists(v)
        if f: found += 1
        scripts_info.append({"name": k, "file": v, "found": f})
    perf_report = {}
    for k, v in perf_data.items():
        if v:
            perf_report[k] = {"avg": round(sum(v)/len(v),1), "fail": round(memory.failure_rate(k)*100,0)}
    return {
        "found": found, "total": len(seen), "scripts": scripts_info,
        "providers": brain.available_providers(),
        "schedules": memory.data.get("schedules", {}),
        "perf": perf_report,
        "stats": {
            "type":"stats", "total":stats["total"], "success":stats["success"],
            "failed":stats["failed"], "pipelines":stats["pipelines"],
            "agent_runs":stats["agent_runs"], "voice_commands":stats["voice_commands"],
            "providers": brain.available_providers(),
        }
    }

# ══════════════════════════════════════════════════════════════════
#  QUEUE WORKERS
# ══════════════════════════════════════════════════════════════════
def _worker():
    while True:
        try:
            task = job_q.get(timeout=1)
            if task is None: break
            kind, payload = task
            if kind == "script": run_script_with_retry(payload)
            elif kind == "pipeline": run_pipeline(payload)
            elif kind == "agent": run_agent(payload)
            job_q.task_done()
        except queue.Empty: continue
        except Exception as e: log.error(f"Worker error: {e}")

for _ in range(Cfg.QUEUE_WORKERS):
    threading.Thread(target=_worker, daemon=True).start()

# ══════════════════════════════════════════════════════════════════
#  STARTUP BANNER + CLI
# ══════════════════════════════════════════════════════════════════
def banner():
    console.print(Panel(
        "[bold amber]AIVANA NEXUS v7.0 — AUTONOMOUS EDITION[/bold amber]\n"
        "[dim]Multi-AI: Ollama + Groq + Gemini + HuggingFace[/dim]\n"
        "[dim]ReAct Agent + Whisper STT + edge-tts + Tool Registry[/dim]\n"
        "[dim]Telegram Bot + Discord + WhatsApp + Web Dashboard[/dim]",
        border_style="yellow", box=box.DOUBLE))
    # Scripts
    t = Table(box=box.ROUNDED, border_style="yellow", show_header=False, padding=(0,1))
    t.add_column("",width=2); t.add_column("Script"); t.add_column("Key",style="yellow"); t.add_column("Status")
    seen = set()
    for k, v in list(BASE_SCRIPTS.items())[:10]:
        if v in seen:
            continue
        seen.add(v)
        script_found = os.path.exists(v)
        t.add_row("v" if script_found else "x", v, k,
                  "[green]OK[/green]" if script_found else "[red]MISSING[/red]")
    console.print(t)
    console.print(f"\n[dim]  Dashboard: http://localhost:{Cfg.WEB_PORT}[/dim]")
    console.print(f"[dim]  Log: {session_log}[/dim]")
    console.print(f"[dim]  AI: {', '.join(brain.available_providers()) or 'NONE — set API keys!'}[/dim]")
    console.print(f"[dim]  Voice: {'ON' if Cfg.VOICE_ENABLED else 'OFF'} (VOICE=1 to enable)[/dim]")
    console.print(f"[dim]  GitHub Webhook: POST http://localhost:{Cfg.WEB_PORT}/webhook/github[/dim]")
    console.print(f"[dim]  Telegram Bot: POST http://localhost:{Cfg.WEB_PORT}/telegram/webhook[/dim]\n")

def print_help():
    console.print(Panel(
        "[bold]DIRECT COMMANDS:[/bold]\n"
        "  [cyan]deploy repair heal status uploader auto[/cyan]  — run script\n"
        "  [magenta]launch hotfix nightly full recovery[/magenta]  — pipeline\n"
        "  [yellow]schedule[/yellow] [cyan]<cron> <task>[/cyan]         — e.g. schedule 0 2 * * * deploy karo\n"
        "  [yellow]voice on/off[/yellow]                      — toggle voice\n"
        "  [yellow]providers[/yellow]                         — AI provider status\n"
        "  [yellow]tools[/yellow]                             — list all agent tools\n"
        "  [yellow]stats[/yellow] [yellow]history[/yellow] [yellow]perf[/yellow] [yellow]clear[/yellow]\n\n"
        "[bold]NATURAL LANGUAGE (anything else):[/bold]\n"
        "  'production deploy karo'\n"
        "  'status check karke fail ho toh repair karo'\n"
        "  'roz raat 2 baje heal pipeline chala'\n"
        "  'github pe kya issues hain'\n"
        "  'web search: best FTP tools'\n"
        "  'telegram pe message bhejo: deploy ho gaya'",
        title="[bold yellow]AIVANA NEXUS HELP[/bold yellow]", border_style="yellow"))

def handle_builtin(cmd: str) -> bool:
    c = cmd.strip().lower(); parts = c.split()
    if c in ("help","?"): print_help(); return True
    if c == "clear": os.system("cls" if os.name=="nt" else "clear"); return True
    if c == "tools":
        t = Table(title="Registered Tools", box=box.ROUNDED, border_style="cyan")
        t.add_column("Name",style="yellow"); t.add_column("Category"); t.add_column("Description",style="dim")
        for n, info in _tools.items():
            t.add_row(n, info["category"], info["desc"][:60])
        console.print(t); return True
    if c == "providers":
        for p in brain.available_providers():
            console.print(f"  [green]OK[/green] {p}")
        if not brain.available_providers():
            console.print("[red]  No providers! Set GROQ_API_KEY or start Ollama[/red]")
        return True
    if c == "stats":
        t = Table(box=box.ROUNDED, border_style="cyan")
        t.add_column("Metric"); t.add_column("Value",style="cyan")
        for k,v in stats.items(): t.add_row(k,str(v))
        console.print(t); return True
    if c == "history":
        for m in convo[-8:]:
            console.print(f"  [{'blue' if m['role']=='user' else 'green'}]{m['role']}:[/] {m['content'][:120]}")
        return True
    if c == "perf":
        for k, v in perf_data.items():
            if v: console.print(f"  [yellow]{k}[/yellow]: avg={sum(v)/len(v):.1f}s fail={memory.failure_rate(k)*100:.0f}%")
        return True
    if c.startswith("voice"):
        if "on" in c: voice.start()
        else: voice.stop()
        return True
    if c.startswith("schedule "):
        p = c.split()[1:]
        if len(p) >= 6: add_schedule(" ".join(p[:5]), " ".join(p[5:]))
        else: console.print("[yellow]  schedule <min hr day mon wday> <task>[/yellow]")
        return True
    if c in SCRIPT_MAP:
        threading.Thread(target=run_script_with_retry, args=(c,), daemon=True).start(); return True
    if c in PIPELINES:
        threading.Thread(target=run_pipeline, args=(c, None, "cli"), daemon=True).start(); return True
    return False

def start_web():
    global asyncio_loop
    asyncio_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(asyncio_loop)
    uvicorn.run(app, host=Cfg.WEB_HOST, port=Cfg.WEB_PORT, log_level="error")

def main():
    if os.name == "nt": os.system("color")
    reload_plugins()
    banner()
    # Web server
    threading.Thread(target=start_web, daemon=True).start()
    time.sleep(1.5)
    broadcast("Web dashboard online", "success", "server")
    # Scheduler
    scheduler.start()
    scheduler.add_job(health_monitor, IntervalTrigger(seconds=Cfg.MONITOR_INTERVAL), id="health_monitor")
    broadcast(f"Health monitor every {Cfg.MONITOR_INTERVAL}s", "success", "scheduler")
    # Voice
    if Cfg.VOICE_ENABLED: voice.start()
    console.print(f"\n[bold green]  ALL SYSTEMS ONLINE — AUTONOMOUS MODE[/bold green]")
    console.print(f"  [dim]Dashboard: http://localhost:{Cfg.WEB_PORT} | Type [bold]help[/bold]\n[/dim]")

    while True:
        try:
            user_input = Prompt.ask("[bold yellow]  NEXUS>[/bold yellow]").strip()
        except (KeyboardInterrupt, EOFError): break
        if not user_input: continue
        if user_input.lower() in ("exit","quit"): break
        if not handle_builtin(user_input):
            # Send everything to autonomous agent
            threading.Thread(target=run_agent, args=(user_input, "cli"), daemon=True).start()

    console.print("\n[yellow]  NEXUS shutting down...[/yellow]")
    scheduler.shutdown(wait=False); memory.save()
    console.print("[yellow]  Goodbye.\n[/yellow]")

if __name__ == "__main__":
    main()
