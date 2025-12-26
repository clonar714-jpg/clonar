# Two-Repository Workflow Guide

## 🎯 Understanding Your Setup

You have **two separate repositories**:

### 1. **Private Repository (Main Project)**
- **Location:** `clonar_app - Copy/`
- **Contains:** Everything - your full app, agent-framework, and all other work
- **Status:** Private (stays on your computer or private GitHub repo)
- **Purpose:** Your main development workspace

### 2. **Public Repository (Agent Framework)**
- **Location:** `agent-framework/` (extracted folder)
- **Contains:** Only the agent-framework code (cleaned, no app-specific code)
- **Status:** Public on GitHub
- **Purpose:** Open-source version for the community

---

## 📊 Visual Structure

```
Your Computer:
├── clonar_app - Copy/              ← PRIVATE REPO (Main Project)
│   ├── node/
│   │   └── src/
│   │       ├── agent/              ← You work here
│   │       ├── services/
│   │       └── ... (all your code)
│   ├── lib/                        ← Flutter app
│   ├── agent-framework/            ← Extracted copy (for GitHub)
│   └── extract-agent-framework.js  ← Extraction script
│
└── GitHub:
    ├── your-username/clonar-app    ← PRIVATE (if you push main project)
    └── your-username/agent-framework ← PUBLIC (open source)
```

---

## 🔄 Workflow: How to Update Both Repos

### Scenario 1: You Make Changes to Agent Framework Code

**Step 1: Work in Your Main Project**
- Make changes in: `clonar_app - Copy/node/src/agent/` or other framework files
- Test and verify everything works

**Step 2: Extract Updated Framework**
```bash
cd "C:\Users\13127\clonar_app - Copy"
node extract-agent-framework.js
```
This updates the `agent-framework/` folder with your latest changes.

**Step 3: Update Public Repo (GitHub)**
```bash
cd agent-framework
git add .
git commit -m "Update: [describe your changes]"
git push origin main
```

**Step 4: Commit to Private Repo (Optional)**
```bash
cd "C:\Users\13127\clonar_app - Copy"
git add .
git commit -m "Update agent framework"
git push origin main  # Only if you have private repo set up
```

---

### Scenario 2: You Make Changes to App-Specific Code

**Step 1: Work in Your Main Project**
- Make changes to app-specific files (Flutter, personalization, etc.)
- These changes are NOT part of the framework

**Step 2: Commit to Private Repo Only**
```bash
cd "C:\Users\13127\clonar_app - Copy"
git add .
git commit -m "Update app features"
git push origin main  # Only to private repo
```

**Step 3: Do NOT Update Public Repo**
- These changes don't affect the public framework
- No extraction needed
- Public repo stays unchanged

---

## 📝 Detailed Workflow Examples

### Example 1: Adding a New Feature to Agent Framework

**1. Develop in Main Project:**
```bash
cd "C:\Users\13127\clonar_app - Copy"
# Make changes to node/src/agent/agent.handler.simple.ts
# Test your changes
npm run dev
```

**2. Extract to Framework:**
```bash
node extract-agent-framework.js
```

**3. Push to Public Repo:**
```bash
cd agent-framework
git status                    # Check what changed
git add .
git commit -m "Add: New feature to agent handler"
git push origin main
```

**4. Update Private Repo (if needed):**
```bash
cd "C:\Users\13127\clonar_app - Copy"
git add .
git commit -m "Update agent framework with new feature"
# Push to private repo if you have one
```

---

### Example 2: Fixing a Bug in Framework

**1. Fix in Main Project:**
```bash
cd "C:\Users\13127\clonar_app - Copy"
# Fix bug in node/src/services/perplexityAnswer.ts
# Test the fix
```

**2. Extract and Push:**
```bash
node extract-agent-framework.js
cd agent-framework
git add .
git commit -m "Fix: Bug in perplexityAnswer service"
git push origin main
```

---

### Example 3: Adding App-Specific Feature (NOT Framework)

**1. Develop in Main Project:**
```bash
cd "C:\Users\13127\clonar_app - Copy"
# Add new Flutter screen or personalization feature
# This is app-specific, not framework
```

**2. Commit to Private Repo Only:**
```bash
git add .
git commit -m "Add: New app feature"
git push origin main  # Only private repo
```

**3. Do NOT Extract:**
- These changes are not part of the framework
- Public repo stays unchanged

---

## 🔐 Repository Management

### Setting Up Private Repo (Main Project)

If you want to version control your main project:

**Option 1: Keep Local Only (No GitHub)**
- Just use git locally for version control
- Never push to GitHub
- Safest option

**Option 2: Private GitHub Repo**
```bash
cd "C:\Users\13127\clonar_app - Copy"
git init
git add .
git commit -m "Initial commit"
# Create private repo on GitHub
git remote add origin https://github.com/YOUR_USERNAME/clonar-app.git
git push -u origin main
```

**Important:** Make sure the repo is set to **Private** on GitHub!

---

### Setting Up Public Repo (Agent Framework)

Already done (from previous guide):
```bash
cd agent-framework
git init
git remote add origin https://github.com/YOUR_USERNAME/agent-framework.git
```

---

## ⚠️ Important Rules

### ✅ DO:

1. **Always extract before pushing to public repo**
   - Run `extract-agent-framework.js` first
   - This ensures only framework files are included

2. **Test in main project first**
   - Make changes in main project
   - Test thoroughly
   - Then extract and push

3. **Use descriptive commit messages**
   - Public repo: "Add: Feature X"
   - Private repo: "Update: App feature Y"

4. **Keep main project private**
   - Never push main project to public repo
   - Only push extracted framework

### ❌ DON'T:

1. **Don't push main project to public repo**
   - Never do: `cd clonar_app - Copy && git push` to public repo
   - Always extract first

2. **Don't skip extraction step**
   - Don't manually copy files
   - Always use the extraction script

3. **Don't include app-specific code in public repo**
   - No Flutter code
   - No personalization
   - No domain-specific services

---

## 🔄 Sync Workflow Diagram

```
┌─────────────────────────────────────┐
│  Main Project (Private)             │
│  - All your code                    │
│  - Agent framework (source)         │
│  - App-specific features             │
└──────────────┬──────────────────────┘
               │
               │ You make changes
               │
               ▼
        ┌──────────────┐
        │   Extract    │
        │   Script     │
        └──────┬───────┘
               │
               ▼
    ┌──────────────────────┐
    │  agent-framework/    │
    │  (Extracted copy)    │
    └──────┬───────────────┘
           │
           │ git push
           │
           ▼
    ┌──────────────────────┐
    │  Public GitHub Repo  │
    │  (Open Source)      │
    └──────────────────────┘
```

---

## 📋 Quick Reference Commands

### Update Public Repo (Agent Framework)

```bash
# 1. Extract latest changes
cd "C:\Users\13127\clonar_app - Copy"
node extract-agent-framework.js

# 2. Go to framework folder
cd agent-framework

# 3. Check changes
git status

# 4. Commit and push
git add .
git commit -m "Update: [your message]"
git push origin main
```

### Update Private Repo (Main Project)

```bash
# 1. Go to main project
cd "C:\Users\13127\clonar_app - Copy"

# 2. Commit changes
git add .
git commit -m "Update: [your message]"

# 3. Push to private repo (if you have one)
git push origin main
```

---

## 🎯 Common Scenarios

### Q: I updated framework code, how do I push to both repos?

**A:**
1. Extract: `node extract-agent-framework.js`
2. Push to public: `cd agent-framework && git push`
3. Push to private: `cd .. && git push` (main project)

### Q: I updated app-specific code, what do I do?

**A:**
- Only push to private repo
- Don't extract (not framework code)
- Public repo stays unchanged

### Q: How do I know what changed in framework?

**A:**
```bash
cd agent-framework
git status
git diff
```

### Q: Can I work on both repos simultaneously?

**A:**
- Yes! They're separate git repositories
- Main project: `clonar_app - Copy/.git`
- Framework: `agent-framework/.git`
- They don't interfere with each other

---

## 🔍 Verification Checklist

Before pushing to public repo:

- [ ] Ran extraction script
- [ ] Checked `git status` in agent-framework folder
- [ ] No app-specific files showing
- [ ] No `.env` files (should be ignored)
- [ ] Commit message is clear
- [ ] Changes are tested in main project first

---

## 💡 Pro Tips

1. **Use branches for public repo:**
   ```bash
   cd agent-framework
   git checkout -b feature/new-feature
   # Make changes
   git push origin feature/new-feature
   # Create PR on GitHub
   ```

2. **Tag releases:**
   ```bash
   cd agent-framework
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

3. **Keep extraction script updated:**
   - If you add new framework files, update `extract-agent-framework.js`
   - This ensures they get included in extraction

---

## ✅ Summary

**Two Repos:**
- **Private:** Main project with all your work
- **Public:** Only agent-framework (extracted)

**Workflow:**
1. Work in main project
2. Extract when framework changes
3. Push to appropriate repo

**Key Rule:**
- Always extract before pushing to public repo
- Never push main project to public repo

---

**You're all set!** This workflow keeps your main project private while sharing only the framework code publicly.

