# Steps to Commit Main Project to Private Repository

## 🔍 The Issue

You're seeing a warning because `agent-framework/` has its own `.git` folder (it's a separate git repository). We need to handle this before committing to your main private repo.

## ✅ Solution: Remove .git from agent-framework

Since `agent-framework` is just an extracted copy for the public repo, we'll remove its `.git` folder so it becomes a regular folder in your main project.

---

## 📋 Step-by-Step Instructions

### Step 1: Remove the Embedded Git Repository

**Option A: Using PowerShell (Recommended)**

```powershell
# Remove the .git folder from agent-framework
Remove-Item -Recurse -Force "agent-framework\.git"
```

**Option B: Using File Explorer**
1. Navigate to `agent-framework` folder
2. Show hidden files (View → Show → Hidden items)
3. Delete the `.git` folder inside `agent-framework`

**Option C: Using Command Line**
```bash
rmdir /s /q agent-framework\.git
```

### Step 2: Verify .gitignore is in Place

Make sure your `.gitignore` file is in the root directory and includes all sensitive files.

```powershell
# Check if .gitignore exists
Test-Path .gitignore
# Should return: True

# View .gitignore (optional)
Get-Content .gitignore
```

### Step 3: Check What Will Be Committed

```powershell
# Check git status
git status

# You should see files, but NOT:
# - .env files
# - config.json
# - node_modules/
# - agent-framework/.git (should be gone)
```

### Step 4: Remove agent-framework from Git Cache (if already added)

If you already ran `git add .`, remove agent-framework from the cache first:

```powershell
# Remove from git cache
git rm --cached -r agent-framework

# Now remove the .git folder from agent-framework
Remove-Item -Recurse -Force "agent-framework\.git"
```

### Step 5: Add All Files (Again)

```powershell
# Add all files
git add .

# Check status again
git status
```

**Expected:** No warning about embedded repository, and agent-framework should appear as regular files.

### Step 6: Verify Sensitive Files Are Ignored

```powershell
# Check if .env is ignored
git check-ignore .env
# Should return: .env

# Check if config.json is ignored
git check-ignore config.json
# Should return: config.json

# List what will be committed (should NOT show .env or config.json)
git status
```

### Step 7: Make Your First Commit

```powershell
# Commit all files
git commit -m "Initial commit: Main project with agent framework"

# Or with a more descriptive message
git commit -m "Initial commit: Complete application with agent framework, Flutter app, and backend services"
```

### Step 8: Create Private Repository on GitHub

1. Go to https://github.com/new
2. Repository name: `clonar-app` (or any name you prefer)
3. **IMPORTANT:** Select **"Private"** (not Public)
4. **DO NOT** initialize with README, .gitignore, or license
5. Click "Create repository"

### Step 9: Connect to GitHub

```powershell
# Add remote (replace YOUR_USERNAME with your GitHub username)
git remote add origin https://github.com/YOUR_USERNAME/clonar-app.git

# Verify remote was added
git remote -v
```

### Step 10: Push to GitHub

```powershell
# Rename branch to main (if needed)
git branch -M main

# Push to GitHub
git push -u origin main
```

You'll be prompted for your GitHub username and password (or personal access token).

---

## 🔄 Alternative: Keep agent-framework as Submodule (Advanced)

If you want to keep agent-framework as a separate git repository (for easier syncing with public repo), you can use git submodules:

```powershell
# Remove from cache first
git rm --cached -r agent-framework

# Add as submodule (after you've pushed agent-framework to GitHub)
git submodule add https://github.com/YOUR_USERNAME/agent-framework.git agent-framework
```

**Note:** This is more complex. For simplicity, just remove the `.git` folder (Step 1).

---

## ✅ Quick Reference (All Commands)

```powershell
# 1. Remove embedded git repository
Remove-Item -Recurse -Force "agent-framework\.git"

# 2. Remove from cache if already added
git rm --cached -r agent-framework

# 3. Add all files
git add .

# 4. Verify sensitive files are ignored
git check-ignore .env
git check-ignore config.json

# 5. Check status
git status

# 6. Commit
git commit -m "Initial commit: Main project"

# 7. Add remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/clonar-app.git

# 8. Push
git branch -M main
git push -u origin main
```

---

## 🛡️ Security Checklist Before Pushing

Before Step 10 (pushing), verify:

- [ ] `.env` files are NOT in `git status`
- [ ] `config.json` is NOT in `git status`
- [ ] `node_modules/` is NOT in `git status`
- [ ] `node/uploads/` is NOT in `git status`
- [ ] No `.log` files in `git status`
- [ ] `agent-framework/.git` is removed (no warning)
- [ ] Repository is set to **Private** on GitHub

---

## 🔍 Verification Commands

```powershell
# Check what will be committed
git status

# Verify .env is ignored
git check-ignore .env
# Expected: .env

# Verify config.json is ignored
git check-ignore config.json
# Expected: config.json

# Check for any .env files
Get-ChildItem -Recurse -Filter ".env*" -Force | Where-Object { $_.FullName -notlike "*node_modules*" }
# Should return nothing (or only .env.example)

# Verify no hardcoded API keys
Select-String -Path "*.ts","*.js","*.dart" -Pattern "sk-[a-zA-Z0-9]{20,}" -Recurse | Where-Object { $_.Path -notlike "*node_modules*" }
# Should return nothing
```

---

## ⚠️ Troubleshooting

### Problem: "agent-framework is still showing as embedded repo"

**Solution:**
```powershell
# Remove from cache
git rm --cached -r agent-framework

# Remove .git folder
Remove-Item -Recurse -Force "agent-framework\.git"

# Add again
git add agent-framework
```

### Problem: "Permission denied" when pushing

**Solution:**
- Use a Personal Access Token instead of password
- Generate token: GitHub → Settings → Developer settings → Personal access tokens → Generate new token
- Use token as password when prompted

### Problem: "Repository not found"

**Solution:**
- Make sure you created the repository on GitHub first
- Check the repository name matches
- Verify the repository is set to Private (if that's what you want)

### Problem: ".env file is showing in git status"

**Solution:**
```powershell
# Check if .gitignore is working
git check-ignore .env
# If returns nothing, .gitignore might not be in root

# Remove from cache
git rm --cached .env

# Verify .gitignore includes .env
Get-Content .gitignore | Select-String ".env"
```

---

## 📝 What Gets Committed

✅ **Will be committed:**
- All source code (`.ts`, `.dart`, `.py`)
- Configuration files (`package.json`, `pubspec.yaml`, `tsconfig.json`)
- Documentation (`.md` files)
- `agent-framework/` folder (as regular files, not git repo)
- `docker-compose.yml` (has default passwords, OK for private)
- Migration files (SQL structure)

❌ **Will NOT be committed (protected by .gitignore):**
- `.env` files
- `config.json`
- `node_modules/`
- `node/uploads/`
- `*.log` files
- Database files
- Android/iOS config files

---

## ✅ Success!

Once you've pushed, your main project will be:
- ✅ On GitHub as a private repository
- ✅ All code committed
- ✅ All secrets protected
- ✅ Ready for collaboration (if you add collaborators)

---

## 🔄 Future Updates

To update your private repo:

```powershell
# Make changes to your code
# ...

# Add changes
git add .

# Commit
git commit -m "Update: [description of changes]"

# Push
git push origin main
```

---

**You're all set!** Your main project is now safely stored in a private GitHub repository.

