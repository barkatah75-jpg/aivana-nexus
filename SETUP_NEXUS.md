# AIVANA NEXUS v7.0 — Complete Setup Guide

## Step 1: Install Dependencies
```powershell
pip install rich fastapi "uvicorn[standard]" apscheduler requests python-multipart
pip install ollama groq google-generativeai huggingface_hub
pip install openai-whisper edge-tts SpeechRecognition sounddevice
```

## Step 2: FREE AI Provider Setup (choose any/all)

### Option A: Ollama (LOCAL — completely free, no internet)
```powershell
# Download from ollama.com
ollama pull llama3        # best general
ollama pull mistral       # fast
ollama pull codellama     # coding
ollama pull phi3          # small & fast
```

### Option B: Groq (FREE API — fastest in the world)
1. Go to: https://console.groq.com
2. Sign up free
3. Get API key
4. Set: GROQ_API_KEY=gsk_...

### Option C: Gemini (FREE — Google)
1. Go to: https://aistudio.google.com
2. Get API key (free)
3. Set: GEMINI_API_KEY=AIza...

### Option D: HuggingFace (FREE)
1. Go to: https://huggingface.co/settings/tokens
2. Get free token
3. Set: HF_API_KEY=hf_...

## Step 3: Configure (two ways)

### Way 1: aivana_config.json
```json
{
  "AI_PROVIDER": "groq",
  "GROQ_API_KEY": "gsk_your_key",
  "GEMINI_API_KEY": "AIza_your_key",
  "TELEGRAM_TOKEN": "your_bot_token",
  "TELEGRAM_CHAT_ID": "your_chat_id",
  "WHATSAPP_URL": "http://localhost:3000/send",
  "GITHUB_TOKEN": "ghp_your_token"
}
```

### Way 2: Environment Variables
```powershell
set GROQ_API_KEY=gsk_...
set GEMINI_API_KEY=AIza...
set TELEGRAM_TOKEN=...
set VOICE=1
python nexus_v7.py
```

## Step 4: Run
```powershell
cd C:\Users\LAPPYHUB
python AIVANA_Commander\nexus_v7.py
```

Dashboard: http://localhost:8765

## Step 5: Voice Commands
```powershell
# Enable voice
set VOICE=1
python AIVANA_Commander\nexus_v7.py

# Then say:
"AIVANA deploy karo"
"AIVANA status check karke heal karo"
"AIVANA production launch karo"
"AIVANA roj raat 2 baje deploy schedule karo"
```

## Step 6: Telegram Bot Control
1. Create bot via @BotFather
2. Set TELEGRAM_TOKEN
3. Set webhook:
```
https://api.telegram.org/bot{TOKEN}/setWebhook?url=http://YOUR_IP:8765/telegram/webhook
```
4. Now send messages to your bot and NEXUS will execute them!

## Step 7: GitHub Auto-Deploy
In GitHub repo settings -> Webhooks:
- URL: http://YOUR_IP:8765/webhook/github
- Content-Type: application/json
- Events: Push events

Now every git push auto-triggers deploy!

## Natural Language Examples
Just type anything naturally:
- "production deploy karo"
- "status fail hai toh repair karke restart karo"
- "roz midnight nightly pipeline chala"
- "github pe open issues dikhao"
- "docker containers ka status dikhao"
- "telegram pe message bhejo: deploy complete"
- "web search: Node.js deployment best practices"
- "AIVANA ka stats report dikhao"
- "backup snapshot le lo"

## Agent Chaining Example
Input: "check status, agar fail ho toh repair karke full pipeline chala"
Agent will:
1. THOUGHT: Need to check status first
2. ACTION: status
3. OBSERVATION: Status FAILED
4. THOUGHT: Status failed, need repair
5. ACTION: repair
6. OBSERVATION: Repair done
7. THOUGHT: Now run full pipeline
8. ACTION: full_pipeline
9. FINAL: Status was failing, repaired and ran full pipeline. All done!
