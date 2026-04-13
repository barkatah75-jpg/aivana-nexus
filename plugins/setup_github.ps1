<#
=========================================================
🤖 AIVANA Auto GitHub Setup Script
Author: Barkat Ahmad (Aivana Technologies)
Description:
  - Configures Git user info
  - Initializes repo if missing
  - Connects remote GitHub repo
  - Creates first commit + pushes main branch
=========================================================
#>

# === CONFIG ===
$projectPath = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$gitUser = "todolistaiautomation"             # 👉 यहाँ अपना GitHub username डालो
$gitEmail = "BARKATAH75@GMAIL.com"   # 👉 यहाँ अपना GitHub email डालो
$repoName = "TODOLISTAIAUTOMATION"    # 👉 GitHub पर repo का नाम
# ==================

Write-Host "`n🚀 Starting GitHub setup for AIVANA ToDoList..." -ForegroundColor Cyan

# Move to project folder
if (-not (Test-Path $projectPath)) {
    Write-Host "❌ Project folder not found: $projectPath" -ForegroundColor Red
    exit
}
Set-Location $projectPath

# Step 1: Git config
Write-Host "🧩 Configuring Git identity..." -ForegroundColor Yellow
git config --global user.name $gitUser
git config --global user.email $gitEmail

# Step 2: Init repo if not present
if (-not (Test-Path ".git")) {
    Write-Host "📦 Initializing new Git repository..." -ForegroundColor Yellow
    git init
}
else {
    Write-Host "✅ Existing Git repo detected." -ForegroundColor Green
}

# Step 3: Set main branch
git branch -M main

# Step 4: Add remote origin
$remoteUrl = "https://github.com/$gitUser/$repoName.git"
$existingRemote = git remote get-url origin 2>$null
if ($existingRemote) {
    Write-Host "🔄 Updating remote origin to $remoteUrl" -ForegroundColor Yellow
    git remote set-url origin $remoteUrl
} else {
    Write-Host "🔗 Adding remote origin $remoteUrl" -ForegroundColor Yellow
    git remote add origin $remoteUrl
}

# Step 5: Stage and Commit
Write-Host "🧠 Creating first commit..." -ForegroundColor Yellow
git add .
try {
    git commit -m "Initial AIVANA ToDoList setup" | Out-Null
} catch {
    Write-Host "ℹ️ No new changes to commit." -ForegroundColor Gray
}

# Step 6: Push to GitHub
Write-Host "🌍 Pushing project to GitHub..." -ForegroundColor Yellow
try {
    git push -u origin main
    Write-Host "✅ Successfully pushed to GitHub: $remoteUrl" -ForegroundColor Green
}
catch {
    Write-Host "⚠️ Push failed — might need authentication or token." -ForegroundColor Red
    Write-Host "👉 Run this to set token cache:" -ForegroundColor Gray
    Write-Host 'git config --global credential.helper store'
}

Write-Host "`n🎉 AIVANA GitHub setup complete! Repository ready at:" -ForegroundColor Cyan
Write-Host "🔗 $remoteUrl" -ForegroundColor Green
