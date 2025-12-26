# Guide: Pushing Agent Framework to GitHub

This guide shows you how to create a separate GitHub repository for just the agent-framework files, without disturbing your main project.

## 🎯 Goal

Create a clean, separate GitHub repository containing only the agent-framework files, while keeping your main project untouched.

## 📋 Method 1: Using the Extraction Script (Recommended)

This is the safest method - it creates a clean copy of only the framework files.

### Step 1: Run the Extraction Script

1. Open your terminal/command prompt
2. Navigate to your main project folder:
   ```bash
   cd "C:\Users\13127\clonar_app - Copy"
   ```
3. Run the extraction script:
   ```bash
   node extract-agent-framework.js
   ```
4. Wait for it to finish - it will create a folder called `agent-framework`

### Step 2: Navigate to the Agent Framework Folder

```bash
cd agent-framework
```

### Step 3: Initialize Git Repository

```bash
git init
```

This creates a new git repository (separate from your main project).

### Step 4: Create .gitignore File

Create a `.gitignore` file in the `agent-framework` folder with this content:

```
# Dependencies
node_modules/
package-lock.json

# Environment variables
.env
.env.local
.env.*.local

# Build outputs
dist/
build/
*.tsbuildinfo

# Logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# OS files
.DS_Store
Thumbs.db

# IDE files
.vscode/
.idea/
*.swp
*.swo
*~

# Testing
coverage/
.nyc_output/

# Temporary files
*.tmp
*.temp
```

### Step 5: Add Files to Git

```bash
git add .
```

This adds all files in the agent-framework folder to git.

### Step 6: Make Your First Commit

```bash
git commit -m "Initial commit: Agent Framework open source release"
```

### Step 7: Create GitHub Repository

1. Go to https://github.com
2. Click the "+" icon in the top right
3. Click "New repository"
4. Name it: `agent-framework` (or any name you like)
5. **DO NOT** initialize with README, .gitignore, or license (we already have these)
6. Click "Create repository"

### Step 8: Connect to GitHub

GitHub will show you commands - use these:

```bash
git remote add origin https://github.com/YOUR_USERNAME/agent-framework.git
```

Replace `YOUR_USERNAME` with your GitHub username.

### Step 9: Push to GitHub

```bash
git branch -M main
git push -u origin main
```

Enter your GitHub username and password (or use a personal access token).

### ✅ Done!

Your agent-framework is now on GitHub, completely separate from your main project!

---

## 📋 Method 2: Manual Setup (If Script Doesn't Work)

If the extraction script doesn't work, you can do it manually:

### Step 1: Create New Folder

Create a new folder somewhere else (NOT inside your main project):

```bash
mkdir C:\Users\13127\agent-framework-github
cd C:\Users\13127\agent-framework-github
```

### Step 2: Copy Only Framework Files

Copy these files/folders from your main project:

**From `agent-framework/` folder:**
- `README.md`
- `SIMPLE_GUIDE.md`
- `.env.example`
- `.gitignore`
- `node/` folder (entire folder)

**Structure should look like:**
```
agent-framework-github/
├── README.md
├── SIMPLE_GUIDE.md
├── .env.example
├── .gitignore
└── node/
    ├── package.json
    ├── tsconfig.json
    └── src/
        ├── index.ts
        ├── agent/
        ├── services/
        ├── embeddings/
        ├── utils/
        ├── stability/
        ├── memory/
        ├── middleware/
        └── routes/
```

### Step 3: Initialize Git

```bash
git init
```

### Step 4: Create .gitignore

Create `.gitignore` file (same content as Method 1, Step 4)

### Step 5: Add and Commit

```bash
git add .
git commit -m "Initial commit: Agent Framework open source release"
```

### Step 6: Push to GitHub

Follow Steps 7-9 from Method 1 above.

---

## 🔒 Important: Keep Your Main Project Safe

### What This Does:
- ✅ Creates a **completely separate** git repository
- ✅ Only includes agent-framework files
- ✅ Does NOT affect your main project's git history
- ✅ Your main project stays private

### What This Does NOT Do:
- ❌ Does NOT push your main project files
- ❌ Does NOT change your main project's git repository
- ❌ Does NOT expose any private code

### Double-Check Before Pushing:

1. **Verify you're in the right folder:**
   ```bash
   pwd  # On Mac/Linux
   cd   # On Windows
   ```
   Should show: `agent-framework` or `agent-framework-github`

2. **Check what files will be pushed:**
   ```bash
   git status
   ```
   Should only show agent-framework files, NOT your main project files

3. **Verify .gitignore is working:**
   ```bash
   git status
   ```
   Should NOT show:
   - `node_modules/`
   - `.env` (your actual API keys)
   - Any files from your main project

---

## 📁 Recommended Repository Structure

Your GitHub repository should look like this:

```
agent-framework/
├── README.md                 # Main documentation
├── SIMPLE_GUIDE.md          # Non-technical guide
├── LICENSE                   # License file (MIT recommended)
├── .gitignore               # Git ignore rules
├── .env.example             # Environment template
└── node/
    ├── package.json         # Dependencies
    ├── tsconfig.json        # TypeScript config
    └── src/
        ├── index.ts         # Example server
        ├── agent/           # Core agent files
        ├── services/         # Core services
        ├── embeddings/      # Embedding utilities
        ├── utils/           # Utilities
        ├── stability/       # Production features
        ├── memory/          # Memory management
        ├── middleware/      # Middleware
        └── routes/          # Routes
```

---

## 🚀 After Pushing to GitHub

### 1. Add a License File

Create a `LICENSE` file in your repository:

1. Go to your GitHub repository
2. Click "Add file" → "Create new file"
3. Name it: `LICENSE`
4. Choose a license (MIT is recommended for open source)
5. Copy the MIT license text
6. Commit the file

### 2. Add Repository Description

1. Go to your repository on GitHub
2. Click the gear icon (⚙️) next to "About"
3. Add description: "Production-ready agentic framework for AI-powered query processing"
4. Add topics: `agent`, `llm`, `ai`, `typescript`, `openai`, `query-processing`

### 3. Add Badges (Optional)

Add badges to your README.md to show:
- Build status
- License
- Version

Example:
```markdown
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![TypeScript](https://img.shields.io/badge/TypeScript-5.0-blue.svg)
```

---

## 🔍 Verification Checklist

Before pushing, verify:

- [ ] You're in the `agent-framework` folder (not main project)
- [ ] `.gitignore` file exists and includes `.env`
- [ ] No `.env` file with real API keys is included
- [ ] No `node_modules/` folder is included
- [ ] Only framework files are present
- [ ] README.md is included
- [ ] LICENSE file is included (or will be added)
- [ ] No files from main project are visible in `git status`

---

## 🛠️ Troubleshooting

### Problem: "Repository already exists"

**Solution:** You might be in your main project folder. Navigate to the agent-framework folder:
```bash
cd agent-framework
```

### Problem: "Permission denied"

**Solution:** 
- Make sure you're logged into GitHub
- Use a Personal Access Token instead of password
- Generate token: GitHub → Settings → Developer settings → Personal access tokens

### Problem: "Files from main project showing up"

**Solution:**
- Make sure you're in the agent-framework folder
- Check that you ran the extraction script correctly
- Verify `.gitignore` is in place

### Problem: "Can't find extract-agent-framework.js"

**Solution:**
- Make sure you're in the main project root folder
- The script should be in: `clonar_app - Copy/extract-agent-framework.js`

---

## 📝 Quick Reference Commands

```bash
# Navigate to main project
cd "C:\Users\13127\clonar_app - Copy"

# Run extraction script
node extract-agent-framework.js

# Navigate to extracted framework
cd agent-framework

# Initialize git
git init

# Add files
git add .

# Commit
git commit -m "Initial commit: Agent Framework"

# Add remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/agent-framework.git

# Push to GitHub
git branch -M main
git push -u origin main
```

---

## ✅ Success!

Once you've pushed, your agent-framework will be:
- ✅ Publicly available on GitHub
- ✅ Separate from your main project
- ✅ Ready for others to use and contribute
- ✅ Your main project remains private and untouched

---

## 🔐 Security Reminder

**Before pushing, make sure:**
1. ✅ No API keys in `.env` file (only `.env.example`)
2. ✅ No passwords or secrets in any files
3. ✅ `.gitignore` includes `.env`
4. ✅ No private business logic included

**If you accidentally pushed secrets:**
1. Remove them from the files
2. Generate new API keys (old ones are compromised)
3. Use `git commit --amend` and force push (if it's a new repo)
4. Or use GitHub's secret scanning to detect and remove them

---

**Need help?** Check the extraction script output or review the file structure to ensure everything is correct before pushing.

