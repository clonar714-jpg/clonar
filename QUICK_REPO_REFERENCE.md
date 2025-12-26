# Quick Reference: Two Repo Workflow

## 🎯 The Two Repos

| Repository | Location | Status | Contains |
|------------|----------|--------|----------|
| **Main Project** | `clonar_app - Copy/` | Private | Everything (app + framework) |
| **Agent Framework** | `agent-framework/` | Public | Only framework code |

---

## 🔄 Update Workflow

### When You Change Framework Code:

```bash
# 1. Extract
cd "C:\Users\13127\clonar_app - Copy"
node extract-agent-framework.js

# 2. Push to Public
cd agent-framework
git add .
git commit -m "Update: [description]"
git push origin main
```

### When You Change App-Specific Code:

```bash
# Only push to private repo
cd "C:\Users\13127\clonar_app - Copy"
git add .
git commit -m "Update: [description]"
git push origin main  # Private repo only
```

---

## ⚠️ Golden Rules

1. ✅ **Always extract before pushing to public repo**
2. ✅ **Test in main project first, then extract**
3. ✅ **Never push main project to public repo**
4. ✅ **Framework changes → Extract → Push public**
5. ✅ **App changes → Push private only**

---

## 📍 Quick Commands

### Check What Changed (Public Repo)
```bash
cd agent-framework
git status
```

### Check What Changed (Private Repo)
```bash
cd "C:\Users\13127\clonar_app - Copy"
git status
```

### Extract Latest Framework
```bash
cd "C:\Users\13127\clonar_app - Copy"
node extract-agent-framework.js
```

---

## 🎯 Decision Tree

```
Made changes?
│
├─ Framework code changed?
│  ├─ YES → Extract → Push to PUBLIC repo
│  └─ NO → Continue
│
└─ App-specific code changed?
   └─ YES → Push to PRIVATE repo only
```

---

**Full guide:** See `TWO_REPO_WORKFLOW.md` for detailed instructions.

