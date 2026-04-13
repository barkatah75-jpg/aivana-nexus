"""
╔══════════════════════════════════════════════════════════════════════╗
║        AIVANA AI COMMANDER  v6.0  —  OMEGA  EDITION                ║
║  Voice · Git · Docker · Rollback · Plugins · Multi-Env · Queue      ║
║  Discord · Email · WhatsApp · Predict · Learn · Web Terminal        ║
╚══════════════════════════════════════════════════════════════════════╝
"""
# ═══════════════════════════════════════════════════════════════════
#  IMPORTS
# ═══════════════════════════════════════════════════════════════════
import os, sys, json, time, asyncio, threading, logging, subprocess
import zipfile, shutil, smtplib, hashlib, re, queue, traceback
from pathlib import Path
# Auto working directory — always run from LAPPYHUB root where PS1 files live
_THIS_DIR = Path(__file__).resolve().parent
_ROOT_DIR = _THIS_DIR.parent if _THIS_DIR.name == "AIVANA_Commander" else _THIS_DIR
os.chdir(_ROOT_DIR)

from datetime import datetime, timedelta
from collections import deque, defaultdict
from typing import Optional, List, Dict, Any, Tuple
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from concurrent.futures import ThreadPoolExecutor, as_completed

# ── Optional heavy deps (graceful fallback) ───────────────────
def try_import(name, pkg=None):
    try:
        import importlib
        return importlib.import_module(name)
    except ImportError:
        print(f"  [OPTIONAL] pip install {pkg or name}")
        return None

speech_recognition = try_import("speech_recognition")
pyttsx3_mod        = try_import("pyttsx3")
docker_sdk         = try_import("docker")
git_mod            = try_import("git", "gitpython")

# ── Required deps ─────────────────────────────────────────────
try:
    import ollama
    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table
    from rich.live import Live
    from rich.text import Text
    from rich.prompt import Prompt
    from rich import box
    from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TimeElapsedColumn
    from rich.layout import Layout
    import uvicorn
    from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, BackgroundTasks
    from fastapi.responses import HTMLResponse, JSONResponse
    from fastapi.middleware.cors import CORSMiddleware
    from apscheduler.schedulers.background import BackgroundScheduler
    from apscheduler.triggers.cron import CronTrigger
    from apscheduler.triggers.interval import IntervalTrigger
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
    import requests
except ImportError as e:
    print(f"[MISSING] pip install rich fastapi 'uvicorn[standard]' apscheduler watchdog requests python-multipart ollama")
    sys.exit(1)

console = Console()

# ═══════════════════════════════════════════════════════════════
#  CONFIG
# ═══════════════════════════════════════════════════════════════
class Cfg:
    VERSION          = "6.0-OMEGA"
    MODEL            = "llama3"
    WEB_PORT         = 8765
    WEB_HOST         = "0.0.0.0"
    LOG_DIR          = Path(__file__).resolve().parent / "aivana_logs"
    BACKUP_DIR       = Path(__file__).resolve().parent / "aivana_backups"
    PLUGIN_DIR       = Path(__file__).resolve().parent / "plugins"
    MEMORY_FILE      = Path(__file__).resolve().parent / "aivana_memory.json"
    MAX_RETRIES      = 3
    RETRY_DELAY      = 5
    MONITOR_INTERVAL = 180       # 3 min health monitor
    MAX_LOG_LINES    = 1000
    QUEUE_WORKERS    = 4
    ROLLBACK_KEEP    = 10        # keep last N backups
    # Notifications (set via env or config.json)
    TELEGRAM_TOKEN   = os.getenv("TELEGRAM_TOKEN", "")
    TELEGRAM_CHAT    = os.getenv("TELEGRAM_CHAT_ID", "")
    DISCORD_WEBHOOK  = os.getenv("DISCORD_WEBHOOK", "")
    WHATSAPP_URL     = os.getenv("WHATSAPP_WEBHOOK", "")  # ultra-bot endpoint
    SMTP_HOST        = os.getenv("SMTP_HOST", "smtp.gmail.com")
    SMTP_PORT        = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USER        = os.getenv("SMTP_USER", "")
    SMTP_PASS        = os.getenv("SMTP_PASS", "")
    SMTP_TO          = os.getenv("SMTP_TO", "")
    # Watcher is OFF by default. If enabled, only watches plugins/ folder
    WATCH_DIRS       = [str(Path(__file__).resolve().parent / "plugins")]
    WATCH_EXTS       = {".ps1"}
    VOICE_ENABLED    = os.getenv("VOICE", "0") == "1"

for d in [Cfg.LOG_DIR, Cfg.BACKUP_DIR, Cfg.PLUGIN_DIR]:
    d.mkdir(exist_ok=True)

# ── Load / save config.json override ─────────────────────────
cfg_file = Path("aivana_config.json")
if cfg_file.exists():
    try:
        overrides = json.loads(cfg_file.read_text())
        for k, v in overrides.items():
            if hasattr(Cfg, k.upper()):
                setattr(Cfg, k.upper(), v)
    except:
        pass

# ═══════════════════════════════════════════════════════════════
#  SCRIPT MAP  +  PIPELINES  +  ENVIRONMENTS
# ═══════════════════════════════════════════════════════════════
BASE_SCRIPTS = {
    "deploy":    "AIVANA_FullAutoDeploy.ps1",
    "repair":    "AIVANA_AutoRepair.ps1",
    "autopilot": "AIVANA_AutoPilot_v9.5_IntelliDeploy.ps1",
    "auto":      "AIVANA_AutoPilot_v9.5_IntelliDeploy.ps1",
    "heal":      "AIVANA_TODOLIST_AutoHeal_v10.8_FTPS_PORTABLE.ps1",
    "status":    "AIVANA_FTP_Diagnostic.ps1",
    "uploader":  "AIVANA_AutoUploader_v5.0_AutoPilot.ps1",
}

PIPELINES = {
    "launch":   {"steps":["status","deploy","uploader"],        "on_fail":"repair", "desc":"Production launch"},
    "hotfix":   {"steps":["repair","deploy","status"],          "on_fail":"stop",   "desc":"Emergency hotfix"},
    "nightly":  {"steps":["heal","status","deploy"],            "on_fail":"continue","desc":"Nightly maintenance"},
    "full":     {"steps":["repair","heal","deploy","uploader","status"], "on_fail":"repair","desc":"Full cycle"},
    "rollout":  {"steps":["status","repair","deploy","status"], "on_fail":"repair", "desc":"Safe rollout"},
    "recovery": {"steps":["heal","repair","deploy"],            "on_fail":"stop",   "desc":"Disaster recovery"},
}

# Environment-specific script overrides (optional)
ENVIRONMENTS = {
    "dev":     {"suffix": "_DEV",     "label": "🟡 DEV"},
    "staging": {"suffix": "_STAGING", "label": "🟠 STAGING"},
    "prod":    {"suffix": "",         "label": "🔴 PROD"},
}
current_env = "prod"

# Dynamic script map (includes plugins)
SCRIPT_MAP: Dict[str, str] = dict(BASE_SCRIPTS)

def reload_plugins():
    """Scan plugins/ folder and auto-register .ps1 files"""
    added = 0
    for f in Cfg.PLUGIN_DIR.glob("*.ps1"):
        key = f.stem.lower().replace(" ", "_").replace("-", "_")
        if key not in SCRIPT_MAP:
            SCRIPT_MAP[key] = str(f)
            added += 1
    if added:
        broadcast(f"Loaded {added} plugin(s) from {Cfg.PLUGIN_DIR}", "plugin", "plugins")

# ═══════════════════════════════════════════════════════════════
#  GLOBAL STATE
# ═══════════════════════════════════════════════════════════════
live_log_buffer  = deque(maxlen=Cfg.MAX_LOG_LINES)
ws_clients: List[WebSocket] = []
scheduler        = BackgroundScheduler()
conversation_history: List[dict] = []
execution_stats  = {"total":0,"success":0,"failed":0,"pipelines":0,"rollbacks":0,"predictions_correct":0}
active_jobs: Dict[str, dict] = {}
scheduled_jobs: Dict[str, dict] = {}
job_queue: queue.Queue = queue.Queue()
asyncio_loop     = None
voice_active     = False
tts_engine       = None
performance_data: Dict[str, List[float]] = defaultdict(list)  # action → [exec_times]

session_log = Cfg.LOG_DIR / f"session_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
# UTF-8 log file — never crashes on Windows cp1252
_log_handler = logging.FileHandler(session_log, encoding="utf-8", errors="replace")
_log_handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(message)s"))
logging.basicConfig(level=logging.INFO, handlers=[_log_handler])
log = logging.getLogger("AIVANA")

# ═══════════════════════════════════════════════════════════════
#  AI MEMORY  (persistent learning)
# ═══════════════════════════════════════════════════════════════
class AIMemory:
    def __init__(self):
        self.data = {"patterns": {}, "failures": {}, "successes": {}, "user_prefs": {}}
        self.load()

    def load(self):
        if Cfg.MEMORY_FILE.exists():
            try:
                self.data = json.loads(Cfg.MEMORY_FILE.read_text())
            except: pass

    def save(self):
        try:
            Cfg.MEMORY_FILE.write_text(json.dumps(self.data, indent=2))
        except: pass

    def record_result(self, action: str, success: bool, duration: float):
        key = action
        if success:
            self.data["successes"][key] = self.data["successes"].get(key, 0) + 1
        else:
            self.data["failures"][key] = self.data["failures"].get(key, 0) + 1
        self.save()

    def get_failure_rate(self, action: str) -> float:
        s = self.data["successes"].get(action, 0)
        f = self.data["failures"].get(action, 0)
        total = s + f
        return (f / total) if total > 0 else 0.0

    def should_pre_heal(self, action: str) -> bool:
        """Predict: if failure rate > 50%, run heal first"""
        return self.get_failure_rate(action) > 0.5

memory = AIMemory()

# ═══════════════════════════════════════════════════════════════
#  BROADCAST  (log → terminal + web + file + notifications)
# ═══════════════════════════════════════════════════════════════
def broadcast(msg: str, level: str = "info", source: str = "system"):
    entry = {"time": datetime.now().strftime("%H:%M:%S"), "level": level, "source": source, "msg": msg}
    live_log_buffer.append(entry)
    # ASCII-safe for log file (Windows cp1252 safe)
    safe = msg.replace("->", "->").encode("ascii", "replace").decode("ascii")
    try:
        log.info(f"[{source}] {safe}")
    except Exception:
        pass
    if ws_clients and asyncio_loop:
        data = json.dumps(entry)
        dead = []
        for ws in ws_clients:
            try:
                asyncio.run_coroutine_threadsafe(ws.send_text(data), asyncio_loop)
            except: dead.append(ws)
        for d in dead:
            try: ws_clients.remove(d)
            except: pass
    # speak important events
    if level in ("success", "error") and tts_engine:
        try: tts_engine.say(f"{source} {level}"); tts_engine.runAndWait()
        except: pass

# ═══════════════════════════════════════════════════════════════
#  NOTIFICATION HUB
# ═══════════════════════════════════════════════════════════════
class NotifyHub:
    @staticmethod
    def telegram(msg: str):
        if not Cfg.TELEGRAM_TOKEN: return
        try:
            requests.post(f"https://api.telegram.org/bot{Cfg.TELEGRAM_TOKEN}/sendMessage",
                json={"chat_id": Cfg.TELEGRAM_CHAT, "text": f"🤖 AIVANA\n{msg}"}, timeout=5)
        except: pass

    @staticmethod
    def discord(msg: str, color: int = 0x00e5ff):
        if not Cfg.DISCORD_WEBHOOK: return
        try:
            requests.post(Cfg.DISCORD_WEBHOOK,
                json={"embeds":[{"description": msg, "color": color, "footer":{"text":"AIVANA Commander"}}]}, timeout=5)
        except: pass

    @staticmethod
    def whatsapp(msg: str):
        if not Cfg.WHATSAPP_URL: return
        try:
            requests.post(Cfg.WHATSAPP_URL, json={"message": f"🤖 AIVANA: {msg}"}, timeout=5)
        except: pass

    @staticmethod
    def email(subject: str, body: str):
        if not Cfg.SMTP_USER: return
        try:
            mm = MIMEMultipart()
            mm["From"] = Cfg.SMTP_USER; mm["To"] = Cfg.SMTP_TO; mm["Subject"] = f"[AIVANA] {subject}"
            mm.attach(MIMEText(body, "html"))
            s = smtplib.SMTP(Cfg.SMTP_HOST, Cfg.SMTP_PORT)
            s.starttls(); s.login(Cfg.SMTP_USER, Cfg.SMTP_PASS)
            s.sendmail(Cfg.SMTP_USER, Cfg.SMTP_TO, mm.as_string()); s.quit()
        except: pass

    @classmethod
    def alert(cls, msg: str, level: str = "info"):
        """Send to ALL configured channels"""
        color = 0x00ff88 if level == "success" else (0xff3d5a if level == "error" else 0xffd600)
        icon  = "✅" if level == "success" else ("❌" if level == "error" else "⚠️")
        full  = f"{icon} {msg}"
        threading.Thread(target=cls.telegram, args=(full,), daemon=True).start()
        threading.Thread(target=cls.discord,  args=(full, color), daemon=True).start()
        threading.Thread(target=cls.whatsapp, args=(full,), daemon=True).start()
        if level == "error":
            threading.Thread(target=cls.email, args=(f"ERROR: {msg[:60]}", f"<pre>{msg}</pre>"), daemon=True).start()

notify = NotifyHub()

# ═══════════════════════════════════════════════════════════════
#  ROLLBACK ENGINE
# ═══════════════════════════════════════════════════════════════
class RollbackEngine:
    def __init__(self):
        self.snapshots: List[dict] = []
        self._load_index()

    def _load_index(self):
        idx = Cfg.BACKUP_DIR / "index.json"
        if idx.exists():
            try: self.snapshots = json.loads(idx.read_text())
            except: pass

    def _save_index(self):
        (Cfg.BACKUP_DIR / "index.json").write_text(json.dumps(self.snapshots, indent=2))

    def snapshot(self, label: str = "") -> str:
        """Zip all PS1 scripts into a timestamped backup"""
        ts   = datetime.now().strftime("%Y%m%d_%H%M%S")
        name = f"snap_{ts}.zip"
        path = Cfg.BACKUP_DIR / name
        try:
            with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
                for script in set(SCRIPT_MAP.values()):
                    if os.path.exists(script):
                        zf.write(script)
            info = {"id": ts, "file": name, "label": label or ts, "time": ts, "scripts": list(set(SCRIPT_MAP.values()))}
            self.snapshots.append(info)
            # keep only last N
            if len(self.snapshots) > Cfg.ROLLBACK_KEEP:
                old = self.snapshots.pop(0)
                try: (Cfg.BACKUP_DIR / old["file"]).unlink()
                except: pass
            self._save_index()
            broadcast(f"Snapshot created: {name} ({label})", "rollback", "rollback")
            return ts
        except Exception as e:
            broadcast(f"Snapshot failed: {e}", "error", "rollback")
            return ""

    def rollback(self, snap_id: str = None) -> bool:
        """Restore from last (or specified) snapshot"""
        if not self.snapshots:
            broadcast("No snapshots available", "error", "rollback")
            return False
        snap = next((s for s in reversed(self.snapshots) if s["id"] == snap_id), None) if snap_id else self.snapshots[-1]
        if not snap:
            broadcast(f"Snapshot {snap_id} not found", "error", "rollback")
            return False
        path = Cfg.BACKUP_DIR / snap["file"]
        if not path.exists():
            broadcast(f"Snapshot file missing: {snap['file']}", "error", "rollback")
            return False
        try:
            with zipfile.ZipFile(path, "r") as zf:
                zf.extractall(".")
            execution_stats["rollbacks"] += 1
            broadcast(f"Rolled back to: {snap['label']} ({snap['time']})", "success", "rollback")
            notify.alert(f"Rollback executed: {snap['label']}", "warn")
            return True
        except Exception as e:
            broadcast(f"Rollback failed: {e}", "error", "rollback")
            return False

    def list_snapshots(self):
        if not self.snapshots:
            console.print("[dim]  No snapshots.[/dim]"); return
        t = Table(title="Rollback Snapshots", box=box.ROUNDED, border_style="yellow")
        t.add_column("ID", style="yellow"); t.add_column("Label", style="white")
        t.add_column("Time", style="cyan"); t.add_column("File", style="dim")
        for s in reversed(self.snapshots):
            t.add_row(s["id"], s["label"], s["time"], s["file"])
        console.print(t)

rollback_engine = RollbackEngine()

# ═══════════════════════════════════════════════════════════════
#  GIT ENGINE
# ═══════════════════════════════════════════════════════════════
class GitEngine:
    def __init__(self):
        self.repo = None
        if git_mod:
            try:
                self.repo = git_mod.Repo(".", search_parent_directories=True)
            except: pass

    def pull(self) -> Tuple[bool, str]:
        if not self.repo:
            # fallback to subprocess
            try:
                r = subprocess.run(["git", "pull"], capture_output=True, text=True, timeout=30)
                if r.returncode == 0:
                    broadcast(f"Git pull: {r.stdout.strip()[:100]}", "success", "git")
                    return True, r.stdout
                return False, r.stderr
            except Exception as e:
                return False, str(e)
        try:
            origin = self.repo.remotes.origin
            result = origin.pull()
            msg = f"Pulled {len(result)} ref(s)"
            broadcast(msg, "success", "git")
            return True, msg
        except Exception as e:
            broadcast(f"Git pull failed: {e}", "error", "git")
            return False, str(e)

    def status(self) -> str:
        try:
            r = subprocess.run(["git", "status", "--short"], capture_output=True, text=True, timeout=10)
            return r.stdout or "Clean"
        except: return "Git unavailable"

    def current_branch(self) -> str:
        try:
            r = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True, timeout=5)
            return r.stdout.strip()
        except: return "unknown"

    def last_commit(self) -> str:
        try:
            r = subprocess.run(["git", "log", "-1", "--pretty=%h %s"], capture_output=True, text=True, timeout=5)
            return r.stdout.strip()
        except: return "unknown"

    def pull_and_deploy(self) -> bool:
        broadcast("Git pull + deploy triggered", "info", "git")
        ok, msg = self.pull()
        if ok:
            broadcast("Pull success → triggering deploy", "info", "git")
            threading.Thread(target=run_pipeline, args=("launch", None, "git-pull"), daemon=True).start()
            return True
        broadcast(f"Pull failed, aborting deploy: {msg}", "error", "git")
        return False

git_engine = GitEngine()

# ═══════════════════════════════════════════════════════════════
#  DOCKER ENGINE
# ═══════════════════════════════════════════════════════════════
class DockerEngine:
    def __init__(self):
        self.client = None
        if docker_sdk:
            try:
                self.client = docker_sdk.from_env()
            except: pass

    def _run(self, *args) -> Tuple[bool, str]:
        try:
            r = subprocess.run(["docker", *args], capture_output=True, text=True, timeout=30)
            return r.returncode == 0, (r.stdout or r.stderr).strip()
        except Exception as e:
            return False, str(e)

    def ps(self) -> str:
        ok, out = self._run("ps", "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
        return out if ok else "Docker unavailable"

    def restart(self, name: str) -> Tuple[bool, str]:
        ok, out = self._run("restart", name)
        broadcast(f"Docker restart {name}: {'OK' if ok else 'FAILED'}", "success" if ok else "error", "docker")
        return ok, out

    def logs(self, name: str, tail: int = 50) -> str:
        ok, out = self._run("logs", "--tail", str(tail), name)
        return out

    def up(self) -> Tuple[bool, str]:
        ok, out = self._run("compose", "up", "-d", "--build")
        broadcast(f"Docker compose up: {'OK' if ok else 'FAILED'}", "success" if ok else "error", "docker")
        return ok, out

    def down(self) -> Tuple[bool, str]:
        ok, out = self._run("compose", "down")
        broadcast(f"Docker compose down: {'OK' if ok else 'FAILED'}", "success" if ok else "error", "docker")
        return ok, out

docker_engine = DockerEngine()

# ═══════════════════════════════════════════════════════════════
#  VOICE ENGINE
# ═══════════════════════════════════════════════════════════════
class VoiceEngine:
    def __init__(self):
        self.recognizer = None
        self.active = False
        self._thread = None
        self._setup_tts()

    def _setup_tts(self):
        global tts_engine
        if pyttsx3_mod:
            try:
                tts_engine = pyttsx3_mod.init()
                tts_engine.setProperty("rate", 160)
                tts_engine.setProperty("volume", 0.85)
            except: pass

    def speak(self, text: str):
        if not tts_engine: return
        def _speak():
            try:
                tts_engine.say(text); tts_engine.runAndWait()
            except: pass
        threading.Thread(target=_speak, daemon=True).start()

    def start_listening(self):
        if not speech_recognition:
            console.print("[yellow]  ⚠ pip install SpeechRecognition pyaudio[/yellow]"); return
        self.active = True
        self._thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._thread.start()
        broadcast("Voice listening started", "voice", "voice")
        console.print("[green]  🎤 Voice active — say 'AIVANA' + command[/green]")

    def stop_listening(self):
        self.active = False
        broadcast("Voice stopped", "voice", "voice")

    def _listen_loop(self):
        r = speech_recognition.Recognizer()
        mic = speech_recognition.Microphone()
        with mic as source:
            r.adjust_for_ambient_noise(source, duration=1)
        while self.active:
            try:
                with mic as source:
                    audio = r.listen(source, timeout=5, phrase_time_limit=8)
                text = r.recognize_google(audio).lower()
                if "aivana" in text:
                    cmd = text.replace("aivana", "").strip()
                    broadcast(f"Voice command: {cmd}", "voice", "voice")
                    console.print(f"\n[cyan]  🎤 Voice:[/cyan] [white]{cmd}[/white]")
                    self.speak("Processing command")
                    threading.Thread(target=handle_command, args=(cmd,), daemon=True).start()
            except Exception:
                pass

voice_engine = VoiceEngine()

# ═══════════════════════════════════════════════════════════════
#  PERFORMANCE TRACKER
# ═══════════════════════════════════════════════════════════════
class PerfTracker:
    def record(self, action: str, duration: float, success: bool):
        performance_data[action].append(duration)
        if len(performance_data[action]) > 50:
            performance_data[action].pop(0)
        memory.record_result(action, success, duration)

    def avg(self, action: str) -> float:
        d = performance_data.get(action, [])
        return sum(d) / len(d) if d else 0.0

    def report(self) -> dict:
        return {k: {"avg": round(self.avg(k), 2), "runs": len(v),
                    "failure_rate": round(memory.get_failure_rate(k) * 100, 1)}
                for k, v in performance_data.items()}

perf = PerfTracker()

# ═══════════════════════════════════════════════════════════════
#  SCRIPT ENGINE  (with prediction + rollback + perf tracking)
# ═══════════════════════════════════════════════════════════════
def execute_script(action: str, retry: int = 0, env: str = None) -> Tuple[bool, str]:
    env = env or current_env
    if action not in SCRIPT_MAP:
        broadcast(f"Unknown action: {action}", "error"); return False, f"Unknown: {action}"

    script = SCRIPT_MAP[action]
    if not os.path.exists(script):
        broadcast(f"Script not found: {script}", "error", action); return False, f"Missing: {script}"

    execution_stats["total"] += 1
    start = time.time()
    broadcast(f"[{action}] starting (attempt {retry+1}, env={env})", "info", action)
    console.print(Panel(f"[cyan]⚙  [{action}][/cyan] [bold]{script}[/bold]  [dim]env:{env} attempt:{retry+1}[/dim]", border_style="cyan"))

    stdout_lines = []
    try:
        proc = subprocess.Popen(
            ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, shell=True)
        for line in iter(proc.stdout.readline, ""):
            line = line.rstrip()
            if line:
                stdout_lines.append(line)
                console.print(f"  [dim]│[/dim] {line}")
                broadcast(line, "output", action)
        proc.stdout.close(); proc.wait()
        stderr = proc.stderr.read(); duration = time.time() - start

        if proc.returncode == 0:
            execution_stats["success"] += 1
            perf.record(action, duration, True)
            broadcast(f"[{action}] ✓ SUCCESS in {duration:.1f}s", "success", action)
            notify.alert(f"[{action}] succeeded in {duration:.1f}s", "success")
            console.print(f"[green]  └─ ✓ Done ({duration:.1f}s)[/green]\n")
            return True, "\n".join(stdout_lines)
        else:
            execution_stats["failed"] += 1
            perf.record(action, duration, False)
            broadcast(f"[{action}] ✗ FAILED ({duration:.1f}s) exit:{proc.returncode}", "error", action)
            notify.alert(f"[{action}] FAILED after {duration:.1f}s — {stderr[:120]}", "error")
            console.print(f"[red]  └─ ✗ Failed ({duration:.1f}s)[/red]\n")
            return False, stderr
    except Exception as e:
        execution_stats["failed"] += 1
        broadcast(f"[{action}] EXCEPTION: {e}", "error", action)
        return False, str(e)


def execute_with_retry(action: str) -> Tuple[bool, str]:
    # Predictive pre-heal
    if memory.should_pre_heal(action) and action not in ("heal","repair"):
        broadcast(f"Predictive heal: {action} has high failure rate", "predict", "predictor")
        console.print(f"[yellow]  🔮 Predictive heal triggered for [{action}][/yellow]")
        execute_script("heal")

    for attempt in range(Cfg.MAX_RETRIES):
        ok, out = execute_script(action, retry=attempt)
        if ok: return True, out
        if attempt < Cfg.MAX_RETRIES - 1:
            if action != "repair":
                broadcast(f"Auto-repair before retry {attempt+2}", "warn", action)
                execute_script("repair")
            broadcast(f"Retrying [{action}] in {Cfg.RETRY_DELAY}s", "warn", action)
            time.sleep(Cfg.RETRY_DELAY)

    broadcast(f"[{action}] exhausted {Cfg.MAX_RETRIES} retries", "error", action)
    notify.alert(f"[{action}] EXHAUSTED ALL RETRIES", "error")
    return False, "Max retries exhausted"

# ═══════════════════════════════════════════════════════════════
#  PIPELINE ENGINE
# ═══════════════════════════════════════════════════════════════
def run_pipeline(name: str, custom_steps: List[str] = None, triggered_by: str = "manual", auto_snapshot: bool = True):
    steps   = custom_steps or PIPELINES.get(name, {}).get("steps", [])
    on_fail = PIPELINES.get(name, {}).get("on_fail", "repair")
    if not steps:
        broadcast(f"Unknown pipeline: {name}", "error"); return

    execution_stats["pipelines"] += 1
    job_id = f"{name}_{int(time.time())}"
    active_jobs[job_id] = {"pipeline": name, "steps": steps, "current": 0, "status": "running", "triggered_by": triggered_by}

    # Auto snapshot before pipeline
    if auto_snapshot:
        snap_id = rollback_engine.snapshot(label=f"pre_{name}")
    
    broadcast(f"Pipeline [{name}] START → {' → '.join(steps)} (by:{triggered_by})", "pipeline", name)
    console.print(Panel(
        f"[bold magenta]🚀 PIPELINE: {name}[/bold magenta]\n"
        f"[dim]{PIPELINES.get(name,{}).get('desc','Custom pipeline')}[/dim]\n"
        f"[cyan]Steps:[/cyan] {' [dim]→[/dim] '.join(steps)}\n"
        f"[dim]Triggered by: {triggered_by}[/dim]",
        border_style="magenta", title="[magenta]PIPELINE[/magenta]"))

    results = {}; start_time = time.time()
    for i, step in enumerate(steps):
        active_jobs[job_id]["current"] = i
        console.rule(f"[cyan]Step {i+1}/{len(steps)}: {step}[/cyan]")
        ok, out = execute_with_retry(step)
        results[step] = {"success": ok, "output": out[:300]}

        if not ok:
            if on_fail == "stop":
                broadcast(f"Pipeline [{name}] stopped at [{step}]", "error", name)
                # Auto-rollback on critical failure
                if auto_snapshot and snap_id:
                    console.print("[red]  ✗ Critical failure → auto-rollback[/red]")
                    rollback_engine.rollback(snap_id)
                active_jobs[job_id]["status"] = "failed"
                break
            elif on_fail == "repair":
                execute_script("repair"); continue

    elapsed = time.time() - start_time
    passed  = sum(1 for r in results.values() if r["success"])
    total   = len(results)
    status  = "success" if passed == total else ("partial" if passed > 0 else "failed")
    active_jobs[job_id]["status"] = status

    lv  = "success" if status == "success" else ("warn" if status == "partial" else "error")
    broadcast(f"Pipeline [{name}] {status.upper()} — {passed}/{total} in {elapsed:.1f}s", lv, name)
    notify.alert(f"Pipeline [{name}] {status.upper()} {passed}/{total} steps in {elapsed:.1f}s", lv)

    console.print(Panel(
        f"[bold]Pipeline:[/bold] {name}   [bold]Result:[/bold] {'[green]SUCCESS[/green]' if status=='success' else '[red]FAILED[/red]' if status=='failed' else '[yellow]PARTIAL[/yellow]'}\n"
        f"[bold]Steps:[/bold] {passed}/{total}   [bold]Time:[/bold] {elapsed:.1f}s",
        border_style="green" if status=="success" else "red"))

    del active_jobs[job_id]

# ═══════════════════════════════════════════════════════════════
#  COMMAND QUEUE WORKER
# ═══════════════════════════════════════════════════════════════
def queue_worker():
    """Background thread processing queued jobs"""
    while True:
        try:
            task = job_queue.get(timeout=1)
            if task is None: break
            kind, payload, kwargs = task
            if kind == "script":
                execute_with_retry(payload)
            elif kind == "pipeline":
                run_pipeline(payload, **kwargs)
            elif kind == "command":
                handle_command(payload)
            job_queue.task_done()
        except queue.Empty:
            continue
        except Exception as e:
            log.error(f"Queue worker error: {e}")

for _ in range(Cfg.QUEUE_WORKERS):
    threading.Thread(target=queue_worker, daemon=True).start()

def enqueue(kind: str, payload, **kwargs):
    job_queue.put((kind, payload, kwargs))
    broadcast(f"Queued: {kind}:{payload}", "queue", "queue")

# ═══════════════════════════════════════════════════════════════
#  AI BRAIN  (multi-agent for complex tasks)
# ═══════════════════════════════════════════════════════════════
SYSTEM_PROMPT = f"""You are AIVANA Commander v6 — elite DevOps AI for AIVANA Kids OS.

Actions: {', '.join(BASE_SCRIPTS.keys())}
Pipelines: {', '.join(PIPELINES.keys())}
Special: git_pull, git_deploy, docker_up, docker_down, docker_ps, docker_restart <name>, rollback, rollback <id>, snapshot, voice_on, voice_off, plugins, schedules, stats, queue

STRICT first-line format:
  ACTION: keyword
  PARALLEL: kw1,kw2,kw3
  PIPELINE: name
  CUSTOM_PIPELINE: s1,s2,s3
  SCHEDULE: cron_expr|action
  DOCKER: subcommand
  GIT: pull|deploy
  ROLLBACK: [snap_id]
  ANSWER: text
  CLARIFY: question

Examples:
  "sab kuch ek baar karo"          → PIPELINE: full
  "deploy aur status saath mein"   → PARALLEL: deploy,status
  "roz 2 baje heal karo"           → SCHEDULE: 0 2 * * *|heal
  "docker restart aivana-app"      → DOCKER: restart aivana-app
  "git pull aur deploy"            → GIT: deploy
  "pehle wali state pe wapas jao"  → ROLLBACK:
  "production launch karo"         → PIPELINE: launch
"""

def ask_ai(user_input: str) -> str:
    ctx = "\n".join(
        f"{'User' if m['role']=='user' else 'AI'}: {m['content']}"
        for m in conversation_history[-10:])
    perf_hint = f"\n[Perf hints: {json.dumps({k:f'{v:.0f}%fail' for k,v in {a: memory.get_failure_rate(a)*100 for a in BASE_SCRIPTS}.items() if v > 30})}]"
    prompt = f"{SYSTEM_PROMPT}{perf_hint}\n\nHistory:\n{ctx}\n\nUser: {user_input}"
    for attempt in range(3):
        try:
            with Progress(SpinnerColumn(), TextColumn("[cyan]AI..."), transient=True, console=console) as p:
                p.add_task("", total=None)
                r = ollama.generate(model=Cfg.MODEL, prompt=prompt)
            return r["response"].strip()
        except Exception as e:
            if attempt == 2: return f"ANSWER: AI error: {e}"
            time.sleep(1)

def ai_summarize(script: str, output: str, success: bool) -> str:
    try:
        r = ollama.generate(model=Cfg.MODEL,
            prompt=f"Script '{script}' {'succeeded' if success else 'FAILED'}. Output: {output[-400:]}. 1-sentence summary.")
        return r["response"].strip()
    except: return f"Script {'succeeded' if success else 'failed'}."

def parse_ai(text: str):
    line = text.split("\n")[0].strip()
    for prefix in ["ACTION","PARALLEL","PIPELINE","CUSTOM_PIPELINE","SCHEDULE","DOCKER","GIT","ROLLBACK","ANSWER","CLARIFY"]:
        if line.upper().startswith(prefix + ":"):
            val = line[len(prefix)+1:].strip()
            return prefix.lower(), val
    return "answer", text.replace("ANSWER:","").strip()

# ═══════════════════════════════════════════════════════════════
#  COMMAND HANDLER  (unified for CLI + Web + Voice + WhatsApp)
# ═══════════════════════════════════════════════════════════════
def handle_command(user_input: str, source: str = "cli"):
    conversation_history.append({"role":"user","content":user_input})
    broadcast(f"[{source}] {user_input}", "info", source)

    ai_text = ask_ai(user_input)
    kind, payload = parse_ai(ai_text)
    broadcast(f"AI → {kind}:{payload[:80]}", "ai", "ai")

    def reply(msg):
        console.print(f"\n[magenta]  🤖 {msg}[/magenta]\n")
        if tts_engine: voice_engine.speak(msg[:100])
        conversation_history.append({"role":"assistant","content":msg})
        memory.save()

    if kind == "action":
        action = payload.lower().split()[0]
        if action not in SCRIPT_MAP: reply(f"Unknown: {action}"); return
        ok, out = execute_with_retry(action)
        reply(ai_summarize(SCRIPT_MAP[action], out, ok))

    elif kind == "parallel":
        actions = [a.strip().lower() for a in payload.split(",")]
        console.print(f"[cyan bold]  ⚡ Parallel: {', '.join(actions)}[/cyan bold]")
        with ThreadPoolExecutor(max_workers=Cfg.QUEUE_WORKERS) as ex:
            futs = {ex.submit(execute_with_retry, a): a for a in actions if a in SCRIPT_MAP}
            for f in as_completed(futs):
                a = futs[f]; ok, out = f.result()
                s = ai_summarize(SCRIPT_MAP.get(a,a), out, ok)
                console.print(f"  [{'green' if ok else 'red'}]{'✓' if ok else '✗'}[/] [{a}]: {s}")

    elif kind == "pipeline":
        threading.Thread(target=run_pipeline, args=(payload, None, source), daemon=True).start()

    elif kind == "custom_pipeline":
        steps = [s.strip() for s in payload.split(",")]
        threading.Thread(target=run_pipeline, args=(f"custom", steps, source), daemon=True).start()

    elif kind == "schedule":
        parts = payload.split("|")
        if len(parts) >= 2: add_schedule(parts[0].strip(), parts[1].strip())
        else: reply("Format: SCHEDULE: cron|action")

    elif kind == "docker":
        parts = payload.split()
        sub = parts[0].lower() if parts else ""
        if sub == "ps":         reply(docker_engine.ps())
        elif sub == "up":       threading.Thread(target=docker_engine.up, daemon=True).start()
        elif sub == "down":     threading.Thread(target=docker_engine.down, daemon=True).start()
        elif sub == "restart":  name = parts[1] if len(parts)>1 else ""; threading.Thread(target=docker_engine.restart, args=(name,), daemon=True).start()
        elif sub == "logs":     name = parts[1] if len(parts)>1 else ""; reply(docker_engine.logs(name, 30))
        else: reply(f"Docker: {docker_engine.ps()}")

    elif kind == "git":
        sub = payload.lower().strip()
        if sub == "pull":       threading.Thread(target=git_engine.pull, daemon=True).start()
        elif sub == "deploy":   threading.Thread(target=git_engine.pull_and_deploy, daemon=True).start()
        else:                   reply(f"Branch: {git_engine.current_branch()}  Commit: {git_engine.last_commit()}")

    elif kind == "rollback":
        snap_id = payload.strip() or None
        threading.Thread(target=rollback_engine.rollback, args=(snap_id,), daemon=True).start()

    elif kind == "clarify":
        reply(payload)

    else:
        reply(payload)

# ═══════════════════════════════════════════════════════════════
#  SCHEDULER
# ═══════════════════════════════════════════════════════════════
def add_schedule(cron_expr: str, action: str, label: str = None):
    jid = label or f"{action}_{cron_expr.replace(' ','_')}"
    try:
        fn = (lambda a=action: run_pipeline(a, triggered_by="scheduler")) if action in PIPELINES \
             else (lambda a=action: execute_with_retry(a))
        job = scheduler.add_job(fn, CronTrigger.from_crontab(cron_expr), id=jid, replace_existing=True)
        scheduled_jobs[jid] = {"cron": cron_expr, "action": action, "job_id": job.id, "next": str(job.next_run_time)}
        broadcast(f"Scheduled: [{action}] @ '{cron_expr}'", "schedule", "scheduler")
        console.print(f"[green]  ✓ Scheduled[/green] [white]{action}[/white] @ [cyan]{cron_expr}[/cyan]")
        memory.data["user_prefs"][f"schedule_{jid}"] = {"cron": cron_expr, "action": action}
        memory.save()
    except Exception as e:
        broadcast(f"Schedule error: {e}", "error")

def list_schedules():
    if not scheduled_jobs: console.print("[dim]  No scheduled jobs.[/dim]"); return
    t = Table(title="Scheduled Jobs", box=box.ROUNDED, border_style="cyan")
    t.add_column("ID"); t.add_column("Action", style="yellow"); t.add_column("Cron", style="cyan"); t.add_column("Next Run", style="dim")
    for jid, info in scheduled_jobs.items():
        t.add_row(jid, info["action"], info["cron"], info.get("next","—"))
    console.print(t)

# Restore schedules from memory
for k, v in memory.data.get("user_prefs", {}).items():
    if k.startswith("schedule_"):
        try: add_schedule(v["cron"], v["action"], k.replace("schedule_",""))
        except: pass

# ═══════════════════════════════════════════════════════════════
#  FILE WATCHER
# ═══════════════════════════════════════════════════════════════
class AIVANAWatcher(FileSystemEventHandler):
    def __init__(self): self._cd = {}; self._lock = threading.Lock()
    def on_modified(self, event):
        if event.is_directory: return
        p = Path(event.src_path)
        if p.suffix not in Cfg.WATCH_EXTS: return
        now = time.time()
        with self._lock:
            if now - self._cd.get(str(p), 0) < 3: return
            self._cd[str(p)] = now
        broadcast(f"Changed: {p.name} → auto-trigger", "watch", "watcher")
        console.print(f"\n[yellow]  👁 {p.name}[/yellow] changed → auto-trigger")
        if p.suffix == ".ps1":
            reload_plugins()
            threading.Thread(target=execute_with_retry, args=("status",), daemon=True).start()
        elif p.name == ".env":
            threading.Thread(target=execute_with_retry, args=("repair",), daemon=True).start()
        elif p.suffix in (".json", ".py"):
            threading.Thread(target=run_pipeline, args=("nightly", None, f"file:{p.name}"), daemon=True).start()

file_observer = Observer()
def start_watcher():
    h = AIVANAWatcher()
    for d in Cfg.WATCH_DIRS:
        if os.path.exists(d):
            file_observer.schedule(h, d, recursive=True)
    file_observer.start()
    broadcast(f"File watcher active on {Cfg.WATCH_DIRS}", "info", "watcher")

# ═══════════════════════════════════════════════════════════════
#  HEALTH MONITOR
# ═══════════════════════════════════════════════════════════════
def health_monitor():
    broadcast("Health check cycle", "monitor", "monitor")
    ok, out = execute_script("status")
    if not ok:
        broadcast("Health: STATUS FAILED → heal + repair", "warn", "monitor")
        execute_with_retry("heal")
        execute_with_retry("repair")
        notify.alert("Health monitor: system needs attention!", "error")
    else:
        broadcast("Health: ✓ All systems OK", "success", "monitor")

# ═══════════════════════════════════════════════════════════════
#  WEB DASHBOARD  v2  (dark industrial + charts + multi-tab)
# ═══════════════════════════════════════════════════════════════
DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AIVANA OMEGA</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.0/chart.umd.min.js"></script>
<style>
@import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Rajdhani:wght@400;600;700&display=swap');
:root{
  --bg:#03070a;--s1:#080f14;--s2:#0c171e;--border:#162430;
  --amber:#ffab00;--cyan:#00e5ff;--green:#00e676;--red:#ff1744;
  --magenta:#e040fb;--yellow:#ffd600;--dim:#2a4050;--text:#b0cdd8;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;background:var(--bg);color:var(--text);
  font-family:'Share Tech Mono',monospace;font-size:12px}
/* scanline */
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:9999;
  background:repeating-linear-gradient(0deg,transparent,transparent 3px,rgba(0,229,255,.012) 3px,rgba(0,229,255,.012) 4px)}
/* grid */
.root{display:grid;grid-template-rows:48px 36px 1fr;height:100vh}
/* header */
header{background:var(--s1);border-bottom:1px solid var(--border);
  display:flex;align-items:center;padding:0 20px;gap:16px}
.logo{font-family:'Rajdhani',sans-serif;font-size:20px;font-weight:700;
  color:var(--amber);letter-spacing:3px;text-shadow:0 0 20px rgba(255,171,0,.4)}
.badge{font-size:9px;padding:2px 6px;border:1px solid;letter-spacing:1px;font-weight:700}
.b-ver{border-color:var(--amber);color:var(--amber)}
.b-live{border-color:var(--green);color:var(--green);animation:blink 1.5s infinite}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.3}}
.hdr-stat{display:flex;gap:4px;align-items:center;background:#060e13;
  border:1px solid var(--border);padding:3px 8px;font-size:11px}
.hdr-stat .v{font-weight:700}
.v-ok{color:var(--green)}.v-err{color:var(--red)}.v-pipe{color:var(--magenta)}.v-total{color:var(--amber)}
.spacer{flex:1}
#voice-btn{background:none;border:1px solid var(--dim);color:var(--dim);
  padding:4px 12px;cursor:pointer;font-family:'Share Tech Mono',monospace;font-size:11px;
  transition:all .2s;letter-spacing:1px}
#voice-btn.active{border-color:var(--red);color:var(--red);animation:blink 1s infinite}
#voice-btn:hover{border-color:var(--amber);color:var(--amber)}
/* env selector */
.env-sel{display:flex;gap:1px}
.env-btn{background:none;border:1px solid var(--border);color:var(--dim);
  padding:3px 10px;cursor:pointer;font-family:'Share Tech Mono',monospace;font-size:10px;
  transition:all .15s;letter-spacing:1px}
.env-btn.active{background:#1a0a00;border-color:var(--amber);color:var(--amber)}
/* tabs */
.tabs{background:var(--s1);border-bottom:1px solid var(--border);
  display:flex;align-items:stretch;padding:0 12px;gap:2px}
.tab{padding:0 16px;cursor:pointer;border-bottom:2px solid transparent;
  display:flex;align-items:center;gap:6px;font-size:11px;color:var(--dim);
  letter-spacing:1px;transition:all .15s;height:100%}
.tab:hover{color:var(--text)}
.tab.active{color:var(--amber);border-bottom-color:var(--amber)}
.tab .dot{width:6px;height:6px;border-radius:50%;background:currentColor;opacity:.5}
/* panels */
.pane{display:none;height:100%;overflow:hidden}
.pane.active{display:grid}
/* ── TERMINAL PANE ── */
#pane-terminal{grid-template-columns:240px 1fr 220px}
.ctrl-panel{background:var(--s1);border-right:1px solid var(--border);
  display:flex;flex-direction:column;overflow:hidden}
.ctrl-scroll{flex:1;overflow-y:auto;padding:10px}
.ctrl-scroll::-webkit-scrollbar{width:3px}
.ctrl-scroll::-webkit-scrollbar-thumb{background:var(--border)}
.sec-lbl{font-size:9px;color:var(--dim);letter-spacing:2px;text-transform:uppercase;
  margin:12px 0 6px;padding-left:2px}
.sec-lbl:first-child{margin-top:0}
.cmd-btn{width:100%;padding:7px 10px;border:1px solid var(--border);background:transparent;
  color:var(--text);font-family:'Share Tech Mono',monospace;font-size:11px;cursor:pointer;
  text-align:left;display:flex;align-items:center;gap:6px;transition:all .12s;margin-bottom:3px}
.cmd-btn:hover{border-color:var(--amber);color:var(--amber);background:rgba(255,171,0,.04)}
.cmd-btn.pipe:hover{border-color:var(--magenta);color:var(--magenta);background:rgba(224,64,251,.04)}
.cmd-btn.git:hover{border-color:var(--cyan);color:var(--cyan)}
.cmd-btn.docker:hover{border-color:var(--green);color:var(--green)}
.cmd-btn.danger:hover{border-color:var(--red);color:var(--red)}
.btn-desc{font-size:9px;color:var(--dim);display:block;margin-top:2px}
/* terminal log */
.terminal-wrap{display:flex;flex-direction:column;background:var(--bg)}
.term-header{background:var(--s1);border-bottom:1px solid var(--border);
  padding:6px 14px;display:flex;align-items:center;gap:10px;flex-shrink:0}
.term-header span{font-size:10px;color:var(--dim);letter-spacing:1px}
.clr-btn{margin-left:auto;background:none;border:1px solid var(--border);color:var(--dim);
  padding:2px 8px;cursor:pointer;font-family:'Share Tech Mono',monospace;font-size:10px}
.clr-btn:hover{border-color:var(--red);color:var(--red)}
#log-out{flex:1;overflow-y:auto;padding:10px 14px;line-height:1.8}
#log-out::-webkit-scrollbar{width:3px}
#log-out::-webkit-scrollbar-thumb{background:var(--border)}
.ll{display:flex;gap:10px}
.lt{color:var(--dim);flex-shrink:0;font-size:10px}
.ls{color:var(--cyan);min-width:70px;flex-shrink:0;font-size:10px}
.lm{word-break:break-word}
.ll.error .lm{color:var(--red)}
.ll.success .lm{color:var(--green)}
.ll.warn .lm{color:var(--yellow)}
.ll.pipeline .lm{color:var(--magenta)}
.ll.output .lm{color:#6ab0c8}
.ll.ai .lm{color:var(--amber)}
.ll.voice .lm{color:#ff80ab}
.ll.rollback .lm{color:var(--yellow)}
/* cmd input */
.ai-input-area{padding:10px;border-top:1px solid var(--border);background:var(--s1);flex-shrink:0}
.ai-row{display:flex;gap:6px}
.ai-inp{flex:1;background:var(--bg);border:1px solid var(--border);color:var(--amber);
  font-family:'Share Tech Mono',monospace;font-size:12px;padding:7px 10px;outline:none}
.ai-inp:focus{border-color:var(--amber)}
.ai-inp::placeholder{color:var(--dim)}
.ai-send{background:var(--amber);color:var(--bg);border:none;padding:7px 14px;
  cursor:pointer;font-family:'Rajdhani',sans-serif;font-weight:700;font-size:12px;letter-spacing:1px}
.ai-send:hover{background:#ffc107}
/* right info */
.info-bar{background:var(--s1);border-left:1px solid var(--border);display:flex;flex-direction:column;overflow-y:auto}
.info-block{padding:10px 12px;border-bottom:1px solid var(--border)}
.i-lbl{font-size:9px;color:var(--dim);letter-spacing:1.5px;text-transform:uppercase;margin-bottom:5px}
.i-val{font-family:'Rajdhani',sans-serif;font-size:22px;font-weight:700}
.script-row{display:flex;align-items:center;gap:6px;padding:5px 0;border-bottom:1px solid #0a1822;font-size:10px}
.sdot{width:6px;height:6px;border-radius:50%;flex-shrink:0}
.sdot.ok{background:var(--green);box-shadow:0 0 6px var(--green)}
.sdot.bad{background:var(--red)}
/* ── ANALYTICS PANE ── */
#pane-analytics{grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;padding:16px;gap:12px}
.chart-card{background:var(--s1);border:1px solid var(--border);padding:14px;display:flex;flex-direction:column}
.chart-title{font-family:'Rajdhani',sans-serif;font-size:13px;font-weight:600;
  color:var(--amber);letter-spacing:2px;margin-bottom:10px;text-transform:uppercase}
.chart-card canvas{flex:1;min-height:0}
/* ── QUEUE PANE ── */
#pane-queue{grid-template-columns:1fr 1fr;padding:16px;gap:12px;align-content:start}
.q-card{background:var(--s1);border:1px solid var(--border);padding:14px}
/* ── SETTINGS PANE ── */
#pane-settings{padding:20px;overflow-y:auto;display:block}
.settings-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;max-width:900px}
.setting-card{background:var(--s1);border:1px solid var(--border);padding:16px}
.setting-title{font-family:'Rajdhani',sans-serif;font-size:13px;font-weight:700;
  color:var(--amber);letter-spacing:2px;margin-bottom:12px;text-transform:uppercase}
.setting-row{margin-bottom:8px}
.setting-row label{font-size:10px;color:var(--dim);display:block;margin-bottom:3px;letter-spacing:1px}
.setting-inp{width:100%;background:var(--bg);border:1px solid var(--border);
  color:var(--text);font-family:'Share Tech Mono',monospace;font-size:11px;
  padding:6px 8px;outline:none}
.setting-inp:focus{border-color:var(--amber)}
.save-btn{background:var(--amber);color:var(--bg);border:none;padding:6px 16px;
  cursor:pointer;font-family:'Rajdhani',sans-serif;font-weight:700;margin-top:8px}
</style>
</head>
<body>
<div class="root">
<header>
  <div class="logo">⚡ AIVANA OMEGA</div>
  <span class="badge b-ver">v6.0</span>
  <span class="badge b-live" id="ws-badge">● CONNECTING</span>
  <div class="env-sel">
    <button class="env-btn" onclick="setEnv('dev')">DEV</button>
    <button class="env-btn active" onclick="setEnv('prod')" id="env-prod">PROD</button>
    <button class="env-btn" onclick="setEnv('staging')">STAGING</button>
  </div>
  <div class="spacer"></div>
  <div class="hdr-stat">EXEC <span class="v v-total" id="s-total">0</span></div>
  <div class="hdr-stat">OK <span class="v v-ok" id="s-ok">0</span></div>
  <div class="hdr-stat">FAIL <span class="v v-err" id="s-fail">0</span></div>
  <div class="hdr-stat">PIPES <span class="v v-pipe" id="s-pipe">0</span></div>
  <div class="hdr-stat">Q <span class="v v-total" id="s-queue">0</span></div>
  <button id="voice-btn" onclick="toggleVoice()">🎤 VOICE OFF</button>
</header>
<div class="tabs">
  <div class="tab active" onclick="switchTab('terminal')"><span class="dot"></span>TERMINAL</div>
  <div class="tab" onclick="switchTab('analytics')"><span class="dot"></span>ANALYTICS</div>
  <div class="tab" onclick="switchTab('queue')"><span class="dot"></span>JOBS / ROLLBACK</div>
  <div class="tab" onclick="switchTab('settings')"><span class="dot"></span>SETTINGS</div>
</div>
<!-- ── TERMINAL ── -->
<div class="pane active" id="pane-terminal">
  <div class="ctrl-panel">
    <div class="ctrl-scroll">
      <div class="sec-lbl">⚡ Scripts</div>
      <button class="cmd-btn" onclick="run('deploy')">🚀 deploy<span class="btn-desc">Full deployment</span></button>
      <button class="cmd-btn" onclick="run('auto')">🤖 autopilot<span class="btn-desc">Intelligent v9.5</span></button>
      <button class="cmd-btn" onclick="run('heal')">🩺 heal<span class="btn-desc">Auto-heal</span></button>
      <button class="cmd-btn" onclick="run('repair')">🔧 repair<span class="btn-desc">Fix services</span></button>
      <button class="cmd-btn" onclick="run('status')">📡 status<span class="btn-desc">FTP diagnostic</span></button>
      <button class="cmd-btn" onclick="run('uploader')">📤 uploader<span class="btn-desc">AutoUpload v5</span></button>
      <div class="sec-lbl">🔗 Pipelines</div>
      <button class="cmd-btn pipe" onclick="pipe('launch')">🌟 launch<span class="btn-desc">status→deploy→upload</span></button>
      <button class="cmd-btn pipe" onclick="pipe('hotfix')">🚨 hotfix<span class="btn-desc">repair→deploy→verify</span></button>
      <button class="cmd-btn pipe" onclick="pipe('nightly')">🌙 nightly<span class="btn-desc">heal→status→deploy</span></button>
      <button class="cmd-btn pipe" onclick="pipe('full')">⚡ full cycle<span class="btn-desc">5-step complete</span></button>
      <button class="cmd-btn pipe" onclick="pipe('recovery')">🆘 recovery<span class="btn-desc">Disaster recovery</span></button>
      <div class="sec-lbl">🐳 Docker</div>
      <button class="cmd-btn docker" onclick="docker('ps')">📋 containers<span class="btn-desc">List running</span></button>
      <button class="cmd-btn docker" onclick="docker('up')">▶️ compose up<span class="btn-desc">Start all</span></button>
      <button class="cmd-btn docker" onclick="docker('down')">⏹ compose down<span class="btn-desc">Stop all</span></button>
      <div class="sec-lbl">🔀 Git</div>
      <button class="cmd-btn git" onclick="gitOp('pull')">⬇ git pull<span class="btn-desc">Pull latest</span></button>
      <button class="cmd-btn git" onclick="gitOp('deploy')">🚀 pull + deploy<span class="btn-desc">Auto deploy</span></button>
      <div class="sec-lbl">🔄 Rollback</div>
      <button class="cmd-btn danger" onclick="doRollback()">↩ rollback last<span class="btn-desc">Restore snapshot</span></button>
      <button class="cmd-btn" onclick="snapshot()">📸 snapshot now<span class="btn-desc">Save current state</span></button>
    </div>
    <div class="ai-input-area">
      <div style="font-size:9px;color:var(--dim);margin-bottom:5px;letter-spacing:2px">AI COMMAND (Hinglish OK)</div>
      <div class="ai-row">
        <input class="ai-inp" id="ai-inp" placeholder="production launch karo..." onkeydown="if(event.key==='Enter')sendCmd()">
        <button class="ai-send" onclick="sendCmd()">SEND</button>
      </div>
    </div>
  </div>
  <div class="terminal-wrap">
    <div class="term-header">
      <span>LIVE TERMINAL</span>
      <label style="color:var(--dim);display:flex;gap:5px;align-items:center;cursor:pointer;font-size:10px">
        <input type="checkbox" id="autoscroll" checked> AUTOSCROLL</label>
      <button class="clr-btn" onclick="clearLog()">CLEAR</button>
    </div>
    <div id="log-out"></div>
  </div>
  <div class="info-bar">
    <div class="info-block"><div class="i-lbl">Scripts Found</div><div class="i-val" id="i-found" style="color:var(--green)">—</div></div>
    <div class="info-block"><div class="i-lbl">Active Jobs</div><div class="i-val" id="i-jobs" style="color:var(--cyan)">0</div></div>
    <div class="info-block"><div class="i-lbl">Schedules</div><div class="i-val" id="i-sched" style="color:var(--magenta)">0</div></div>
    <div class="info-block"><div class="i-lbl">Snapshots</div><div class="i-val" id="i-snaps" style="color:var(--yellow)">0</div></div>
    <div class="info-block"><div class="i-lbl">Git Branch</div><div id="i-branch" style="color:var(--cyan);font-size:11px;margin-top:4px">—</div></div>
    <div class="info-block">
      <div class="i-lbl">Scripts</div>
      <div id="script-list"></div>
    </div>
  </div>
</div>
<!-- ── ANALYTICS ── -->
<div class="pane" id="pane-analytics">
  <div class="chart-card"><div class="chart-title">Executions — Success vs Fail</div><canvas id="chart-pie"></canvas></div>
  <div class="chart-card"><div class="chart-title">Pipeline Runs Over Time</div><canvas id="chart-line"></canvas></div>
  <div class="chart-card"><div class="chart-title">Avg Execution Time (s)</div><canvas id="chart-bar"></canvas></div>
  <div class="chart-card"><div class="chart-title">Failure Rate by Script</div><canvas id="chart-fail"></canvas></div>
</div>
<!-- ── QUEUE / ROLLBACK ── -->
<div class="pane" id="pane-queue">
  <div class="q-card">
    <div class="chart-title">Active Jobs</div>
    <div id="active-jobs-list" style="font-size:11px;color:var(--dim)">No active jobs</div>
  </div>
  <div class="q-card">
    <div class="chart-title">Rollback Snapshots</div>
    <div id="snapshot-list" style="font-size:11px;color:var(--dim)">Loading...</div>
  </div>
</div>
<!-- ── SETTINGS ── -->
<div class="pane" id="pane-settings">
  <div class="settings-grid">
    <div class="setting-card">
      <div class="setting-title">Notifications</div>
      <div class="setting-row"><label>TELEGRAM TOKEN</label><input class="setting-inp" id="cfg-tg-token" placeholder="bot token..."></div>
      <div class="setting-row"><label>TELEGRAM CHAT ID</label><input class="setting-inp" id="cfg-tg-chat" placeholder="-100..."></div>
      <div class="setting-row"><label>DISCORD WEBHOOK</label><input class="setting-inp" id="cfg-discord" placeholder="https://discord.com/api/webhooks/..."></div>
      <div class="setting-row"><label>WHATSAPP WEBHOOK URL</label><input class="setting-inp" id="cfg-wa" placeholder="http://localhost:3000/send"></div>
      <button class="save-btn" onclick="saveConfig()">SAVE CONFIG</button>
    </div>
    <div class="setting-card">
      <div class="setting-title">Email Alerts</div>
      <div class="setting-row"><label>SMTP HOST</label><input class="setting-inp" id="cfg-smtp-host" value="smtp.gmail.com"></div>
      <div class="setting-row"><label>SMTP USER</label><input class="setting-inp" id="cfg-smtp-user" placeholder="you@gmail.com"></div>
      <div class="setting-row"><label>SMTP PASS</label><input class="setting-inp" type="password" id="cfg-smtp-pass" placeholder="app password"></div>
      <div class="setting-row"><label>ALERT TO</label><input class="setting-inp" id="cfg-smtp-to" placeholder="alerts@email.com"></div>
      <button class="save-btn" onclick="saveConfig()">SAVE CONFIG</button>
    </div>
    <div class="setting-card">
      <div class="setting-title">Scheduler</div>
      <div class="setting-row"><label>CRON EXPRESSION</label><input class="setting-inp" id="s-cron" placeholder="0 2 * * *"></div>
      <div class="setting-row"><label>ACTION / PIPELINE</label><input class="setting-inp" id="s-action" placeholder="deploy"></div>
      <button class="save-btn" onclick="addSchedule()">ADD SCHEDULE</button>
      <div id="sched-list" style="margin-top:10px;font-size:10px;color:var(--dim)"></div>
    </div>
    <div class="setting-card">
      <div class="setting-title">System Info</div>
      <div id="sysinfo" style="font-size:11px;line-height:2;color:var(--text)">Loading...</div>
    </div>
  </div>
</div>
</div><!-- root -->
<script>
const term=document.getElementById('log-out');
let ws, charts={}, voiceOn=false;
const chartCfg={color:'white',grid:'#162430',font:'Share Tech Mono'};
Chart.defaults.color=chartCfg.color; Chart.defaults.font.family=chartCfg.font; Chart.defaults.font.size=10;

function connect(){
  ws=new WebSocket(`ws://${location.hostname}:${location.port}/ws`);
  ws.onopen=()=>{setWsBadge(true); fetchAll();}
  ws.onmessage=({data})=>{ const d=JSON.parse(data); if(d.type==='stats'){updateStats(d);return;} appendLog(d); };
  ws.onclose=()=>{ setWsBadge(false); setTimeout(connect,3000); };
}
function setWsBadge(ok){
  const b=document.getElementById('ws-badge');
  b.textContent=ok?'● LIVE':'● RECONNECTING';
  b.style.borderColor=ok?'var(--green)':'var(--yellow)';
  b.style.color=ok?'var(--green)':'var(--yellow)';
}
function appendLog(d){
  const el=document.createElement('div'); el.className=`ll ${d.level}`;
  el.innerHTML=`<span class="lt">${d.time}</span><span class="ls">[${(d.source||'').substring(0,8)}]</span><span class="lm">${esc(d.msg)}</span>`;
  term.appendChild(el);
  if(document.getElementById('autoscroll').checked) term.scrollTop=term.scrollHeight;
}
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function clearLog(){term.innerHTML='';}

function run(a)    {fetch(`/run/${a}`,{method:'POST'});}
function pipe(n)   {fetch(`/pipeline/${n}`,{method:'POST'});}
function docker(s) {fetch('/docker',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({cmd:s})});}
function gitOp(s)  {fetch('/git',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({op:s})});}
function doRollback(){if(confirm('Rollback to last snapshot?')) fetch('/rollback',{method:'POST',body:JSON.stringify({})});}
function snapshot() {fetch('/snapshot',{method:'POST'});}
function sendCmd(){
  const v=document.getElementById('ai-inp').value.trim(); if(!v)return;
  fetch('/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({input:v})});
  document.getElementById('ai-inp').value='';
}
function setEnv(e){
  document.querySelectorAll('.env-btn').forEach(b=>b.classList.remove('active'));
  event.target.classList.add('active');
  fetch('/env',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({env:e})});
}
function toggleVoice(){
  voiceOn=!voiceOn;
  const b=document.getElementById('voice-btn');
  b.textContent=voiceOn?'🎤 VOICE ON':'🎤 VOICE OFF';
  b.className=voiceOn?'active':'';
  fetch('/voice',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({active:voiceOn})});
}
function addSchedule(){
  const cron=document.getElementById('s-cron').value, action=document.getElementById('s-action').value;
  if(!cron||!action)return;
  fetch('/schedule',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({cron,action})});
}
function saveConfig(){
  const cfg={
    TELEGRAM_TOKEN:document.getElementById('cfg-tg-token').value,
    TELEGRAM_CHAT:document.getElementById('cfg-tg-chat').value,
    DISCORD_WEBHOOK:document.getElementById('cfg-discord').value,
    WHATSAPP_URL:document.getElementById('cfg-wa').value,
    SMTP_HOST:document.getElementById('cfg-smtp-host').value,
    SMTP_USER:document.getElementById('cfg-smtp-user').value,
    SMTP_PASS:document.getElementById('cfg-smtp-pass').value,
    SMTP_TO:document.getElementById('cfg-smtp-to').value,
  };
  fetch('/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(cfg)})
    .then(()=>alert('Config saved! Restart to apply.'));
}

function updateStats(d){
  document.getElementById('s-total').textContent=d.total;
  document.getElementById('s-ok').textContent=d.success;
  document.getElementById('s-fail').textContent=d.failed;
  document.getElementById('s-pipe').textContent=d.pipelines;
  document.getElementById('s-queue').textContent=d.queue_size||0;
  document.getElementById('i-jobs').textContent=d.active_jobs||0;
  document.getElementById('i-sched').textContent=d.schedules||0;
  if(d.snapshots!=null) document.getElementById('i-snaps').textContent=d.snapshots;
  if(d.branch) document.getElementById('i-branch').textContent=d.branch;
  updateCharts(d);
  updateActiveJobs(d.jobs||[]);
  updateSnapshots(d.snapshot_list||[]);
  updateSchedList(d.schedule_list||[]);
  updateSysInfo(d);
}

function fetchAll(){
  fetch('/status').then(r=>r.json()).then(d=>{
    const found=d.scripts.filter(s=>s.found).length;
    document.getElementById('i-found').textContent=`${found}/${d.scripts.length}`;
    const sl=document.getElementById('script-list');
    sl.innerHTML=d.scripts.map(s=>`<div class="script-row"><div class="sdot ${s.found?'ok':'bad'}"></div><div style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${s.name}</div></div>`).join('');
    updateStats(d.stats);
    for(const e of d.logs||[]) appendLog(e);
  });
}

// Charts
function initCharts(){
  const g='#162430',t='rgba(0,0,0,0)';
  charts.pie=new Chart(document.getElementById('chart-pie'),{type:'doughnut',
    data:{labels:['Success','Failed'],datasets:[{data:[0,0],backgroundColor:['#00e676','#ff1744'],borderColor:t,borderWidth:0}]},
    options:{plugins:{legend:{labels:{color:'#b0cdd8'}}},cutout:'65%'}});
  charts.line=new Chart(document.getElementById('chart-line'),{type:'line',
    data:{labels:[],datasets:[{label:'Pipelines',data:[],borderColor:'#e040fb',backgroundColor:'rgba(224,64,251,.1)',tension:.4,fill:true,pointRadius:3}]},
    options:{scales:{x:{grid:{color:g}},y:{grid:{color:g},beginAtZero:true}},plugins:{legend:{display:false}}}});
  charts.bar=new Chart(document.getElementById('chart-bar'),{type:'bar',
    data:{labels:[],datasets:[{label:'avg (s)',data:[],backgroundColor:'rgba(255,171,0,.7)',borderColor:'#ffab00',borderWidth:1}]},
    options:{scales:{x:{grid:{color:g}},y:{grid:{color:g},beginAtZero:true}},plugins:{legend:{display:false}}}});
  charts.fail=new Chart(document.getElementById('chart-fail'),{type:'bar',
    data:{labels:[],datasets:[{label:'fail %',data:[],backgroundColor:'rgba(255,23,68,.6)',borderColor:'#ff1744',borderWidth:1}]},
    options:{scales:{x:{grid:{color:g}},y:{grid:{color:g},beginAtZero:true,max:100}},plugins:{legend:{display:false}}}});
}

let lineHistory=[];
function updateCharts(d){
  if(!charts.pie) return;
  charts.pie.data.datasets[0].data=[d.success||0,d.failed||0]; charts.pie.update('none');
  lineHistory.push(d.pipelines||0); if(lineHistory.length>20) lineHistory.shift();
  charts.line.data.labels=lineHistory.map((_,i)=>i+1);
  charts.line.data.datasets[0].data=[...lineHistory]; charts.line.update('none');
  if(d.perf){
    const keys=Object.keys(d.perf), avgs=keys.map(k=>d.perf[k].avg), fails=keys.map(k=>d.perf[k].failure_rate);
    charts.bar.data.labels=keys; charts.bar.data.datasets[0].data=avgs; charts.bar.update('none');
    charts.fail.data.labels=keys; charts.fail.data.datasets[0].data=fails; charts.fail.update('none');
  }
}
function updateActiveJobs(jobs){
  const el=document.getElementById('active-jobs-list');
  if(!jobs.length){el.textContent='No active jobs';return;}
  el.innerHTML=jobs.map(j=>`<div style="padding:4px 0;border-bottom:1px solid var(--border);color:var(--text)">${j.pipeline||j.name} [${j.status}] — step ${j.current||0}</div>`).join('');
}
function updateSnapshots(snaps){
  const el=document.getElementById('snapshot-list');
  if(!snaps.length){el.textContent='No snapshots';return;}
  el.innerHTML=snaps.slice(-8).reverse().map(s=>
    `<div style="padding:4px 0;border-bottom:1px solid var(--border);display:flex;justify-content:space-between">
      <span style="color:var(--text)">${s.label}</span>
      <button onclick="rollbackTo('${s.id}')" style="background:none;border:1px solid var(--red);color:var(--red);padding:1px 6px;cursor:pointer;font-family:inherit;font-size:9px">↩</button>
    </div>`).join('');
}
function rollbackTo(id){
  if(confirm(`Rollback to ${id}?`)) fetch('/rollback',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})});
}
function updateSchedList(scheds){
  const el=document.getElementById('sched-list'); if(!el)return;
  el.innerHTML=scheds.map(s=>`<div style="padding:3px 0;color:var(--text)">${s.action} @ <span style="color:var(--cyan)">${s.cron}</span></div>`).join('') || '<span style="color:var(--dim)">None</span>';
}
function updateSysInfo(d){
  const el=document.getElementById('sysinfo'); if(!el)return;
  el.innerHTML=`<div>Branch: <span style="color:var(--cyan)">${d.branch||'—'}</span></div>
    <div>Commit: <span style="color:var(--dim)">${d.commit||'—'}</span></div>
    <div>Env: <span style="color:var(--amber)">${d.env||'prod'}</span></div>
    <div>Voice: <span style="color:${d.voice?'var(--red)':'var(--dim)'}">${d.voice?'ON':'OFF'}</span></div>
    <div>Log: <span style="color:var(--dim);font-size:10px">${d.log_file||'—'}</span></div>`;
}
function switchTab(name){
  document.querySelectorAll('.pane').forEach(p=>p.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
  document.getElementById('pane-'+name).classList.add('active');
  event.target.closest('.tab').classList.add('active');
}
initCharts();
setInterval(fetchAll,3000);
connect();
</script>
</body>
</html>"""

# ═══════════════════════════════════════════════════════════════
#  FASTAPI
# ═══════════════════════════════════════════════════════════════
app = FastAPI(title="AIVANA Omega")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.get("/", response_class=HTMLResponse)
async def dashboard(): return DASHBOARD_HTML

@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept(); ws_clients.append(ws)
    for e in live_log_buffer: await ws.send_text(json.dumps(e))
    try:
        while True: await ws.receive_text()
    except WebSocketDisconnect:
        try: ws_clients.remove(ws)
        except: pass

@app.post("/run/{action}")
async def api_run(action: str, bg: BackgroundTasks):
    bg.add_task(execute_with_retry, action); return {"queued": action}

@app.post("/pipeline/{name}")
async def api_pipeline(name: str, bg: BackgroundTasks):
    bg.add_task(run_pipeline, name, None, "web"); return {"queued": name}

@app.post("/command")
async def api_command(req: Request, bg: BackgroundTasks):
    body = await req.json(); bg.add_task(handle_command, body.get("input",""), "web"); return {"ok": True}

@app.post("/docker")
async def api_docker(req: Request, bg: BackgroundTasks):
    body = await req.json(); cmd = body.get("cmd",""); parts = cmd.split()
    sub = parts[0] if parts else ""
    if sub == "ps":      return {"output": docker_engine.ps()}
    elif sub == "up":    bg.add_task(docker_engine.up)
    elif sub == "down":  bg.add_task(docker_engine.down)
    elif sub == "restart": bg.add_task(docker_engine.restart, parts[1] if len(parts)>1 else "")
    return {"ok": True}

@app.post("/git")
async def api_git(req: Request, bg: BackgroundTasks):
    body = await req.json(); op = body.get("op","")
    if op == "pull":   bg.add_task(git_engine.pull)
    elif op == "deploy": bg.add_task(git_engine.pull_and_deploy)
    return {"ok": True}

@app.post("/rollback")
async def api_rollback(req: Request, bg: BackgroundTasks):
    body = await req.json(); snap_id = body.get("id", None)
    bg.add_task(rollback_engine.rollback, snap_id); return {"ok": True}

@app.post("/snapshot")
async def api_snapshot(bg: BackgroundTasks):
    bg.add_task(rollback_engine.snapshot, "manual"); return {"ok": True}

@app.post("/schedule")
async def api_schedule(req: Request):
    body = await req.json(); add_schedule(body.get("cron",""), body.get("action",""))
    return {"ok": True}

@app.post("/env")
async def api_env(req: Request):
    global current_env; body = await req.json()
    current_env = body.get("env", "prod")
    broadcast(f"Environment switched to: {current_env}", "info", "env")
    return {"env": current_env}

@app.post("/voice")
async def api_voice(req: Request):
    body = await req.json(); active = body.get("active", False)
    if active: voice_engine.start_listening()
    else:       voice_engine.stop_listening()
    return {"ok": True}

@app.post("/config")
async def api_config(req: Request):
    body = await req.json()
    cfg_file.write_text(json.dumps(body, indent=2))
    broadcast("Config saved (restart to apply)", "info", "settings")
    return {"ok": True}

@app.post("/webhook/github")
async def github_hook(req: Request, bg: BackgroundTasks):
    payload = await req.json()
    ref = payload.get("ref","")
    if "main" in ref or "master" in ref:
        broadcast(f"GitHub push → {ref} → launch pipeline", "webhook", "github")
        bg.add_task(git_engine.pull_and_deploy)
    return {"ok": True}

@app.get("/status")
async def api_status():
    seen = set(); scripts_info = []; found = 0
    for k, v in SCRIPT_MAP.items():
        if v not in seen:
            seen.add(v); f = os.path.exists(v)
            if f: found += 1
            scripts_info.append({"name": k, "file": v, "found": f})
    return {
        "found": found, "total": len(seen), "scripts": scripts_info,
        "logs": list(live_log_buffer)[-50:],
        "stats": {
            "type": "stats",
            "total": execution_stats["total"],
            "success": execution_stats["success"],
            "failed": execution_stats["failed"],
            "pipelines": execution_stats["pipelines"],
            "rollbacks": execution_stats["rollbacks"],
            "queue_size": job_queue.qsize(),
            "active_jobs": len(active_jobs),
            "schedules": len(scheduled_jobs),
            "snapshots": len(rollback_engine.snapshots),
            "snapshot_list": rollback_engine.snapshots,
            "schedule_list": list(scheduled_jobs.values()),
            "jobs": list(active_jobs.values()),
            "branch": git_engine.current_branch(),
            "commit": git_engine.last_commit(),
            "env": current_env,
            "voice": voice_active,
            "log_file": str(session_log),
            "perf": perf.report(),
        }
    }

# ═══════════════════════════════════════════════════════════════
#  STARTUP + CLI
# ═══════════════════════════════════════════════════════════════
def startup_banner():
    console.print(Panel(
        "[bold amber]⚡ AIVANA AI COMMANDER  v6.0  —  OMEGA EDITION[/bold amber]\n"
        "[dim]Voice · Git · Docker · Rollback · Plugins · Multi-Env · Predict · Learn[/dim]\n"
        "[dim]Scheduler · File Watcher · Queue · Notifications · Web Dashboard v2[/dim]",
        border_style="yellow", box=box.DOUBLE))
    t = Table(box=box.ROUNDED, border_style="yellow", show_header=False, padding=(0,1))
    t.add_column("", width=3); t.add_column("Script"); t.add_column("Key", style="yellow"); t.add_column("Status")
    seen = set()
    for k, v in SCRIPT_MAP.items():
        if v in seen: continue; seen.add(v)
        ok = os.path.exists(v)
        t.add_row("✓" if ok else "✗", v, k, "[green]FOUND[/green]" if ok else "[red]MISSING[/red]")
    console.print(t)
    console.print(f"\n  [dim]📄 Log: {session_log}[/dim]")
    console.print(f"  [dim]🌐 Dashboard: http://localhost:{Cfg.WEB_PORT}[/dim]")
    console.print(f"  [dim]🔗 GitHub Webhook: POST /webhook/github[/dim]")
    console.print(f"  [dim]🎤 Voice: set env VOICE=1 or use web dashboard[/dim]\n")

def start_webserver():
    global asyncio_loop
    asyncio_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(asyncio_loop)
    uvicorn.run(app, host=Cfg.WEB_HOST, port=Cfg.WEB_PORT, log_level="error")

def print_help():
    console.print(Panel(
        "[bold]SCRIPTS:[/bold]  deploy repair heal status uploader auto\n"
        "[bold]PIPELINES:[/bold] launch hotfix nightly full rollout recovery\n"
        "[bold]GIT:[/bold]      git pull  |  git deploy\n"
        "[bold]DOCKER:[/bold]   docker ps | up | down | restart <name> | logs <name>\n"
        "[bold]ROLLBACK:[/bold] rollback [snap_id]  |  snapshot  |  snapshots\n"
        "[bold]PLUGINS:[/bold]  plugins reload  |  plugins list\n"
        "[bold]QUEUE:[/bold]    queue  |  queue clear\n"
        "[bold]SCHED:[/bold]    schedule <min hr day mon wday> <action>  |  schedules\n"
        "[bold]VOICE:[/bold]    voice on  |  voice off\n"
        "[bold]INFO:[/bold]     stats  |  history  |  perf  |  env <dev|staging|prod>\n"
        "[bold]OTHER:[/bold]    clear  |  help  |  exit\n\n"
        "[dim]Or just type naturally in Hinglish — AI samjhega![/dim]",
        title="[bold yellow]AIVANA v6.0 HELP[/bold yellow]", border_style="yellow"))

def handle_builtin(cmd: str) -> bool:
    c = cmd.strip().lower()
    parts = c.split()
    if c in ("exit","quit"):           return False  # let main handle
    if c in ("help","?"):              print_help(); return True
    if c == "clear":                   os.system("cls" if os.name=="nt" else "clear"); return True
    if c == "stats":
        t = Table(title="Stats", box=box.ROUNDED, border_style="yellow")
        t.add_column("Metric"); t.add_column("Value",style="yellow")
        for k,v in execution_stats.items(): t.add_row(k,str(v))
        console.print(t); return True
    if c == "perf":
        r = perf.report()
        t = Table(title="Performance", box=box.ROUNDED, border_style="cyan")
        t.add_column("Action"); t.add_column("Avg (s)",style="cyan"); t.add_column("Runs"); t.add_column("Fail%",style="red")
        for k,v in r.items(): t.add_row(k,str(v["avg"]),str(v["runs"]),str(v["failure_rate"])+"%")
        console.print(t); return True
    if c == "history":
        for m in conversation_history[-12:]:
            console.print(f"  [{'blue' if m['role']=='user' else 'magenta'}]{m['role']}:[/] {m['content'][:120]}")
        return True
    if c == "schedules":               list_schedules(); return True
    if c in ("snapshots","rollbacks"): rollback_engine.list_snapshots(); return True
    if c == "snapshot":                rollback_engine.snapshot("manual"); return True
    if c.startswith("rollback"):
        sid = parts[1] if len(parts)>1 else None
        rollback_engine.rollback(sid); return True
    if c.startswith("voice"):
        if "on" in c: voice_engine.start_listening()
        else:          voice_engine.stop_listening()
        return True
    if c.startswith("docker"):
        sub = parts[1] if len(parts)>1 else "ps"
        if sub == "ps":      console.print(docker_engine.ps())
        elif sub == "up":    threading.Thread(target=docker_engine.up, daemon=True).start()
        elif sub == "down":  threading.Thread(target=docker_engine.down, daemon=True).start()
        elif sub == "restart": threading.Thread(target=docker_engine.restart, args=(parts[2] if len(parts)>2 else "",), daemon=True).start()
        elif sub == "logs":  console.print(docker_engine.logs(parts[2] if len(parts)>2 else "", 30))
        return True
    if c.startswith("git"):
        sub = parts[1] if len(parts)>1 else "status"
        if sub == "pull":    threading.Thread(target=git_engine.pull, daemon=True).start()
        elif sub == "deploy": threading.Thread(target=git_engine.pull_and_deploy, daemon=True).start()
        else: console.print(f"Branch: {git_engine.current_branch()}  Commit: {git_engine.last_commit()}")
        return True
    if c.startswith("env "):
        global current_env; current_env = parts[1] if len(parts)>1 else "prod"
        broadcast(f"Env → {current_env}", "info", "env"); console.print(f"[yellow]  Env: {current_env}[/yellow]")
        return True
    if c.startswith("plugins"):
        reload_plugins()
        t = Table(title="Plugins", box=box.ROUNDED, border_style="cyan")
        t.add_column("Key",style="yellow"); t.add_column("File")
        for k,v in SCRIPT_MAP.items():
            if k not in BASE_SCRIPTS: t.add_row(k,v)
        console.print(t); return True
    if c.startswith("schedule "):
        p = c.split()[1:]
        if len(p) >= 6: add_schedule(" ".join(p[:5]), p[5])
        else: console.print("[yellow]  schedule <min hr day mon wday> <action>[/yellow]")
        return True
    if c == "queue":
        console.print(f"[cyan]  Queue size: {job_queue.qsize()}[/cyan]")
        for jid, info in active_jobs.items():
            console.print(f"  [magenta]{jid}[/magenta] {info}")
        return True
    if c in SCRIPT_MAP:
        threading.Thread(target=execute_with_retry, args=(c,), daemon=True).start(); return True
    if c in PIPELINES:
        threading.Thread(target=run_pipeline, args=(c, None, "cli"), daemon=True).start(); return True
    return False  # not a builtin → send to AI

def main():
    global asyncio_loop
    if os.name == "nt": os.system("color")
    reload_plugins()
    startup_banner()
    threading.Thread(target=start_webserver, daemon=True).start()
    time.sleep(1.5)
    broadcast("Web dashboard online", "success", "server")
    # File watcher OFF by default — PS1 temp files cause infinite loops
    # Enable: set env WATCHER=1 before running, or type 'watcher on' in CLI
    if os.getenv("WATCHER", "0") == "1":
        start_watcher()
    else:
        broadcast("File watcher disabled. Type 'watcher on' to enable.", "info", "watcher")
        console.print("  [dim]File watcher disabled (prevents PS1 temp file loops)[/dim]")
    scheduler.start()
    scheduler.add_job(health_monitor, IntervalTrigger(seconds=Cfg.MONITOR_INTERVAL), id="health_monitor")
    broadcast(f"Health monitor every {Cfg.MONITOR_INTERVAL}s", "success", "scheduler")
    if Cfg.VOICE_ENABLED: voice_engine.start_listening()
    console.print(f"\n[bold green]  ✓ ALL SYSTEMS ONLINE — OMEGA EDITION[/bold green]")
    console.print(f"  [dim]Type [bold]help[/bold] for commands  |  [bold]http://localhost:{Cfg.WEB_PORT}[/bold] for dashboard\n[/dim]")

    while True:
        try:
            user_input = Prompt.ask("[bold yellow]  ❯[/bold yellow]").strip()
        except (KeyboardInterrupt, EOFError): break
        if not user_input: continue
        if user_input.lower() in ("exit","quit"): break
        if not handle_builtin(user_input):
            threading.Thread(target=handle_command, args=(user_input,"cli"), daemon=True).start()

    console.print("\n[yellow]  Shutting down OMEGA...[/yellow]")
    scheduler.shutdown(wait=False); file_observer.stop(); memory.save()
    console.print("[yellow]  👋 AIVANA OMEGA offline.\n[/yellow]")

if __name__ == "__main__":
    main()