# AIVANA Commander v6.0 OMEGA — Setup Guide

## Step 1: Install Core Dependencies
```
pip install ollama rich fastapi "uvicorn[standard]" apscheduler watchdog requests python-multipart
```

## Step 2: Optional Features

### Voice Commands (say "AIVANA deploy karo")
```
pip install SpeechRecognition pyttsx3
# Windows microphone:
pip install pipwin
pipwin install pyaudio
```
Then run with: `set VOICE=1 && python commander_v6.py`

### Git Auto-Deploy
```
pip install gitpython
```

### Docker Management
```
pip install docker
```

## Step 3: Notifications Setup (via aivana_config.json)

Create `aivana_config.json` in same folder:
```json
{
  "TELEGRAM_TOKEN": "your_bot_token",
  "TELEGRAM_CHAT_ID": "your_chat_id",
  "DISCORD_WEBHOOK": "https://discord.com/api/webhooks/...",
  "WHATSAPP_URL": "http://localhost:3000/send",
  "SMTP_HOST": "smtp.gmail.com",
  "SMTP_PORT": 587,
  "SMTP_USER": "you@gmail.com",
  "SMTP_PASS": "your_app_password",
  "SMTP_TO": "alerts@email.com"
}
```

Or use Web Dashboard → Settings tab to configure.

## Step 4: Run
```
python commander_v6.py
```

Dashboard: http://localhost:8765

## Step 5: GitHub Webhook (for auto-deploy on push)
Set webhook URL in GitHub repo settings:
```
http://your-server-ip:8765/webhook/github
```
Content-Type: application/json
Events: Push

## Voice Commands Examples
Say: "AIVANA production launch karo"
Say: "AIVANA deploy karo"
Say: "AIVANA status check karo"

## WhatsApp Integration (with ultra-bot)
In your ultra-bot, forward commands to:
POST http://localhost:8765/command
Body: { "input": "deploy karo" }

## Plugin System
Drop any .ps1 file in the `plugins/` folder.
It auto-registers as a command. Filename = command name.
Example: plugins/backup.ps1 → type "backup" in CLI

## Environments
- `env dev`     → switch to dev mode
- `env staging` → staging
- `env prod`    → production (default)

## Rollback System
- `snapshot`      → save current state
- `snapshots`     → list all snapshots
- `rollback`      → restore last snapshot
- `rollback <id>` → restore specific snapshot

All pipelines auto-snapshot before running.
