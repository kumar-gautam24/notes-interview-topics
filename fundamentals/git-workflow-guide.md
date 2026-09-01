# 🌳 Git Workflow Guide - Complete Reference

> **Author:** Gautam Kumar  
> **Last Updated:** October 14, 2025  
> **Audience:** Small to Large Development Teams

---

## 📚 Table of Contents

1. [Quick Reference](#quick-reference)
2. [Project Size Based Workflows](#project-size-based-workflows)
   - [Small Projects (1-3 Developers)](#small-projects-1-3-developers)
   - [Medium Projects (4-10 Developers)](#medium-projects-4-10-developers)
   - [Large Projects (10+ Developers)](#large-projects-10-developers)
3. [Scenario: Independent Features (No Branch Sharing)](#scenario-independent-features-no-branch-sharing)
4. [Scenario: Shared Feature Development](#scenario-shared-feature-development)
5. [Branch Strategies Explained](#branch-strategies-explained)
6. [Rebasing vs Merging](#rebasing-vs-merging)
7. [Commit Best Practices](#commit-best-practices)
8. [Pull Request Workflow](#pull-request-workflow)
9. [Emergency Fixes](#emergency-fixes)
10. [Common Mistakes](#common-mistakes)
11. [Git Commands Cheatsheet](#git-commands-cheatsheet)

---

## 🎯 Quick Reference

### When to Use What

| Situation | Strategy | Branch Type | Sync Method |
|-----------|----------|-------------|-------------|
| 2 devs, separate features | Feature Branch | Short-lived | Rebase |
| 2 devs, same feature | Shared Feature Branch | Medium-lived | Merge |
| Small team, simple project | GitHub Flow | Short-lived | Rebase |
| Medium team, release cycles | GitFlow | Mixed | Merge |
| Large team, microservices | Trunk-Based | Very short-lived | Rebase |

---

## 📊 Project Size Based Workflows

---

### Small Projects (1-3 Developers)

**Best Strategy:** GitHub Flow (Simplified)

#### Branch Structure
```
main (production)
  ├── feature/user-authentication
  ├── feature/payment-integration
  └── bugfix/login-crash
```

#### Workflow

##### Step 1: Start New Feature
```bash
# Always start from latest main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/user-authentication
```

##### Step 2: Work on Feature
```bash
# Make changes
git add .
git commit -m "feat: Add user authentication"

# More changes
git add .
git commit -m "feat: Add password validation"

# Push to remote
git push origin feature/user-authentication
```

##### Step 3: Keep Branch Updated (If main moves ahead)
```bash
# Fetch latest main
git fetch origin main

# Rebase your branch on main
git rebase origin/main

# If conflicts, resolve them
git add .
git rebase --continue

# Force push (safe because you're only one working on this branch)
git push --force-with-lease origin feature/user-authentication
```

##### Step 4: Create Pull Request
```bash
# On GitHub/GitLab
1. Create PR from feature/user-authentication → main
2. Request review
3. Wait for approval
4. Squash and merge (or rebase and merge)
```

##### Step 5: Clean Up
```bash
# After PR is merged
git checkout main
git pull origin main

# Delete local branch
git branch -d feature/user-authentication

# Delete remote branch
git push origin --delete feature/user-authentication
```

#### Rules for Small Projects

✅ **DO:**
- Create descriptive branch names (`feature/add-login`, not `dev-gautam`)
- Keep branches short-lived (max 1 week)
- Rebase on main before creating PR
- Squash commits if you have many WIP commits
- Delete branches after merge

❌ **DON'T:**
- Keep long-lived personal branches
- Merge main into feature branches (use rebase)
- Push directly to main
- Leave stale branches around

#### Example Timeline

```
Day 1:
------
Gautam: git checkout -b feature/authentication
Sourav: git checkout -b feature/dashboard

Day 2-3: (Both work independently)
------
Gautam: Multiple commits on authentication
Sourav: Multiple commits on dashboard

Day 4:
------
Gautam: git rebase origin/main
        Create PR → Review → Merge to main
        git branch -d feature/authentication

Day 5:
------
Sourav: git rebase origin/main (gets Gautam's auth code)
        Create PR → Review → Merge to main
        git branch -d feature/dashboard
```

---

### Medium Projects (4-10 Developers)

**Best Strategy:** GitFlow

#### Branch Structure
```
main (production releases only, tagged)
  |
  └── develop (integration branch)
       ├── feature/payment-gateway (Developer 1)
       ├── feature/notification-system (Developer 2)
       ├── feature/analytics (Developer 3)
       ├── release/v1.2.0 (preparing for release)
       └── hotfix/critical-security-patch (emergency)
```

#### Workflow

##### Permanent Branches
- **main:** Production-ready code, tagged with versions
- **develop:** Integration branch, latest development changes

##### Temporary Branches
- **feature/\*:** New features
- **release/\*:** Preparing for production release
- **hotfix/\*:** Emergency fixes for production

##### Step 1: Start New Feature
```bash
# Always branch from develop (not main)
git checkout develop
git pull origin develop

# Create feature branch
git checkout -b feature/payment-gateway
```

##### Step 2: Work on Feature
```bash
# Regular commits
git add .
git commit -m "feat: Add Stripe integration"

git add .
git commit -m "feat: Add payment validation"

# Push regularly
git push origin feature/payment-gateway
```

##### Step 3: Keep Updated with Develop
```bash
# Periodically sync with develop
git fetch origin develop
git rebase origin/develop

# Or merge if rebasing is complex
git merge origin/develop

# Push
git push --force-with-lease origin feature/payment-gateway
```

##### Step 4: Complete Feature
```bash
# Final sync
git checkout develop
git pull origin develop

git checkout feature/payment-gateway
git rebase origin/develop

# Create PR to develop (not main)
# After approval and merge:
git branch -d feature/payment-gateway
git push origin --delete feature/payment-gateway
```

##### Step 5: Release Process
```bash
# When develop is stable and ready for release
git checkout develop
git pull origin develop

# Create release branch
git checkout -b release/v1.2.0

# Bug fixes only on release branch
git commit -m "fix: Update version number"
git commit -m "fix: Minor UI tweaks"

# Merge to main
git checkout main
git merge release/v1.2.0
git tag -a v1.2.0 -m "Release version 1.2.0"
git push origin main --tags

# Merge back to develop
git checkout develop
git merge release/v1.2.0

# Delete release branch
git branch -d release/v1.2.0
git push origin --delete release/v1.2.0
```

##### Step 6: Hotfix (Emergency Production Fix)
```bash
# Branch from main (production)
git checkout main
git pull origin main
git checkout -b hotfix/security-patch

# Make fix
git add .
git commit -m "fix: Patch critical security vulnerability"

# Merge to main
git checkout main
git merge hotfix/security-patch
git tag -a v1.2.1 -m "Security hotfix"
git push origin main --tags

# Merge to develop too
git checkout develop
git merge hotfix/security-patch
git push origin develop

# Delete hotfix branch
git branch -d hotfix/security-patch
git push origin --delete hotfix/security-patch
```

#### Rules for Medium Projects

✅ **DO:**
- Use semantic branch names (feature/, bugfix/, hotfix/)
- Never merge directly to main (only from release/hotfix)
- Tag all production releases
- Keep develop stable (all tests pass)
- Code review mandatory for all PRs

❌ **DON'T:**
- Push directly to main or develop
- Create features from main (use develop)
- Keep feature branches longer than 2 weeks
- Mix multiple features in one branch

---

### Large Projects (10+ Developers)

**Best Strategy:** Trunk-Based Development + Feature Flags

#### Branch Structure
```
main (trunk - always deployable)
  ├── feature/user-service-refactor (1-2 days max)
  ├── feature/api-optimization (1-2 days max)
  └── release/v2024.10.14 (cut from main for deployment)
```

#### Workflow

##### Core Principles
1. **Main is always green** (all tests pass)
2. **Small, frequent commits** to main
3. **Feature flags** for incomplete features
4. **Very short-lived branches** (max 2 days)
5. **Continuous integration**

##### Step 1: Start Small Feature
```bash
# Feature must be small enough to complete in 1-2 days
git checkout main
git pull origin main --rebase

git checkout -b feature/add-user-avatar
```

##### Step 2: Work in Small Chunks
```bash
# Make minimal viable change
git add .
git commit -m "feat: Add avatar upload endpoint (behind feature flag)"

# Push immediately
git push origin feature/add-user-avatar
```

##### Step 3: Merge Fast
```bash
# Same day or next day
git checkout main
git pull origin main --rebase

git checkout feature/add-user-avatar
git rebase main

# Create PR → Fast review → Merge
# Delete branch immediately
```

##### Step 4: Use Feature Flags
```dart
// Code is in main but disabled by default
class UserProfile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(user.name),
        
        // Feature behind flag - safe to merge incomplete
        if (FeatureFlags.avatarUploadEnabled) 
          AvatarUploadWidget(),
      ],
    );
  }
}
```

##### Step 5: Release Branches
```bash
# Cut release branch from main
git checkout main
git pull origin main

git checkout -b release/2024.10.14

# Enable feature flags for this release
# Deploy to staging → testing → production

# Tag after successful deployment
git tag -a v2024.10.14 -m "Production release Oct 14"
git push origin --tags
```

#### Rules for Large Projects

✅ **DO:**
- Commit to main multiple times per day
- Keep branches alive for max 2 days
- Use feature flags for incomplete work
- Automate all tests (CI/CD)
- Pair programming for complex changes
- Deploy main to production frequently

❌ **DON'T:**
- Keep long-lived feature branches
- Merge large changes at once
- Disable tests to make CI pass
- Work in isolation for weeks

---

## 🤝 Scenario: Independent Features (No Branch Sharing)

**Best for:** You and teammate working on completely separate features

### Example: <AppName> Mobile App

**Gautam:** Working on chat localization  
**Sourav:** Working on health board UI

#### Recommended Approach: Feature Branches

##### Your Current Setup (2 Developers)

```
main (production)
  |
  └── dev (integration/testing)
       ├── feature/chat-localization (Gautam, 3-5 days)
       └── feature/health-board-ui (Sourav, 3-5 days)
```

#### Workflow for Gautam

##### Day 1: Start Feature
```bash
# Start from dev (your integration branch)
git checkout dev
git pull origin dev

# Create feature branch
git checkout -b feature/chat-localization

# Work and commit
git add .
git commit -m "feat: Add localization keys for chat screen"
git push origin feature/chat-localization
```

##### Day 2-3: Continue Work
```bash
# Morning: Check if dev moved ahead
git fetch origin dev

# If dev has new commits, rebase
git rebase origin/dev

# Continue work
git add .
git commit -m "feat: Implement language switcher"
git push --force-with-lease origin feature/chat-localization
```

##### Day 4: Complete Feature
```bash
# Final sync with dev
git checkout dev
git pull origin dev

git checkout feature/chat-localization
git rebase origin/dev

# Optional: Squash multiple commits
git rebase -i origin/dev
# Mark commits as 'squash' except first one

# Push
git push --force-with-lease origin feature/chat-localization

# Create PR on GitHub/GitLab
# feature/chat-localization → dev
```

##### Day 5: After Merge
```bash
# PR merged, clean up
git checkout dev
git pull origin dev

# Delete branches
git branch -d feature/chat-localization
git push origin --delete feature/chat-localization

# Start next feature
git checkout -b feature/voice-input
```

#### Workflow for Sourav (Same Pattern)

```bash
# Day 1
git checkout dev
git pull origin dev
git checkout -b feature/health-board-ui

# Day 2-4: Work independently
git add .
git commit -m "feat: Add health metrics widgets"
git push origin feature/health-board-ui

# Sync with dev when needed
git fetch origin dev
git rebase origin/dev

# Day 5: Create PR → Merge → Delete branch
```

#### Timeline Visualization

```
Day 1:
------
dev: ●───┐
         ├──● feature/chat-localization (Gautam starts)
         └──● feature/health-board-ui (Sourav starts)

Day 2-3:
--------
dev: ●───────●  (No changes, both work independently)
             |
    chat: ───┼──●──●──● (Gautam commits)
             |
   health: ──┴──●──●──● (Sourav commits)

Day 4:
------
dev: ●───────●◄────● (Gautam's PR merged)
             |
   health: ──┼──●──● (Sourav rebases to get Gautam's changes)
             |
             └──●──● (Sourav continues)

Day 5:
------
dev: ●───────●──────●◄────● (Sourav's PR merged)
         
Both branches deleted, both start new features
```

#### Key Rules for Independent Features

✅ **DO:**
1. **Always start from updated dev**
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/my-new-feature
   ```

2. **Use descriptive branch names**
   ```
   ✅ feature/add-payment-gateway
   ✅ feature/health-board-ui
   ✅ bugfix/login-crash-android
   ✅ refactor/chat-state-management
   
   ❌ dev-gautam
   ❌ my-branch
   ❌ test
   ❌ wip
   ```

3. **Rebase regularly (every 1-2 days)**
   ```bash
   git fetch origin dev
   git rebase origin/dev
   ```

4. **One feature = one branch**
   - Don't mix multiple unrelated features
   - Keep scope focused and small

5. **Delete after merge**
   ```bash
   git branch -d feature/my-feature
   git push origin --delete feature/my-feature
   ```

❌ **DON'T:**
1. **Merge dev into feature branches**
   ```bash
   # ❌ WRONG
   git merge origin/dev
   
   # ✅ RIGHT
   git rebase origin/dev
   ```

2. **Keep branches alive for weeks**
   - Max 1 week per feature branch
   - Break large features into smaller ones

3. **Push WIP commits to dev**
   - Squash before creating PR
   - Clean commit history in dev

4. **Work on multiple features in one branch**
   - One branch = one feature
   - Easier to review and rollback

#### Squashing Commits Before PR

If you have messy commits:

```bash
# View your commits
git log --oneline origin/dev..HEAD

# Output:
# a1b2c3d WIP: stuff
# d4e5f6g fix typo
# g7h8i9j WIP: more stuff
# j10k11l feat: Add localization

# Interactive rebase
git rebase -i origin/dev

# In editor, change to:
pick j10k11l feat: Add localization
squash g7h8i9j WIP: more stuff
squash d4e5f6g fix typo
squash a1b2c3d WIP: stuff

# Save, edit commit message, done!
```

---

## 👥 Scenario: Shared Feature Development

**Best for:** Multiple developers working on the same feature

### Example: Complex Payment Integration

**Gautam:** Frontend payment UI  
**Sourav:** Backend payment API  
**Both:** Working on same feature together

#### Recommended Approach: Shared Feature Branch

##### Branch Structure

```
dev (integration)
  |
  └── feature/payment-integration (shared by Gautam & Sourav)
       ├── (Gautam's commits for UI)
       └── (Sourav's commits for API)
```

#### Workflow

##### Step 1: One Person Creates Branch

**Gautam creates:**
```bash
git checkout dev
git pull origin dev
git checkout -b feature/payment-integration
git push origin feature/payment-integration
```

**Notify Sourav:** "Created feature/payment-integration branch"

##### Step 2: Both Developers Work on Same Branch

**Sourav starts working:**
```bash
git fetch origin
git checkout feature/payment-integration
git pull origin feature/payment-integration
```

##### Step 3: Daily Workflow (Both Developers)

**Morning routine:**
```bash
# Pull latest changes from shared branch
git checkout feature/payment-integration
git pull origin feature/payment-integration
```

**Work on your part:**
```bash
# Gautam works on UI
git add lib/features/payment/ui/
git commit -m "feat: Add payment form UI"
git push origin feature/payment-integration
```

```bash
# Sourav works on API (same branch, different files)
git add lib/features/payment/api/
git commit -m "feat: Add Stripe API integration"
git push origin feature/payment-integration
```

##### Step 4: Handling Conflicts

**If push fails (someone pushed before you):**
```bash
# Pull with rebase
git pull --rebase origin feature/payment-integration

# If conflicts:
# 1. VS Code will show conflicts
# 2. Resolve manually
# 3. Continue:
git add .
git rebase --continue

# Push
git push origin feature/payment-integration
```

##### Step 5: Communication Protocol

**Important:** Use git conventions for shared branches

```bash
# Before pushing large changes, communicate:
# Slack/Teams: "Hey, pushing payment validation logic now"

git push origin feature/payment-integration

# After push:
# Slack/Teams: "✅ Pushed, please pull latest"
```

##### Step 6: Complete Feature Together

```bash
# When both parts are done:
# 1. Final sync with dev
git fetch origin dev
git rebase origin/dev

# 2. Test together
# 3. Create PR: feature/payment-integration → dev
# 4. Both review
# 5. Merge
# 6. Both delete local branches
```

#### Sub-Branches Pattern (Advanced)

For complex shared features, use sub-branches:

```
dev
  |
  └── feature/payment-integration (shared base)
       ├── feature/payment-ui (Gautam's sub-branch)
       └── feature/payment-api (Sourav's sub-branch)
```

**Workflow:**

```bash
# Gautam creates UI sub-branch
git checkout feature/payment-integration
git checkout -b feature/payment-ui

# Works independently
git commit -m "feat: Add payment form"
git push origin feature/payment-ui

# When done, PR to base feature branch:
# feature/payment-ui → feature/payment-integration

# After both PRs merged to feature/payment-integration:
# Final PR: feature/payment-integration → dev
```

#### Rules for Shared Branches

✅ **DO:**
1. **Communicate before big pushes**
   - Let teammate know you're pushing
   - Coordinate merge conflict resolution

2. **Pull frequently (multiple times per day)**
   ```bash
   git pull --rebase origin feature/payment-integration
   ```

3. **Work on different files if possible**
   - Gautam: UI files
   - Sourav: API files
   - Minimizes conflicts

4. **Use descriptive commit messages**
   ```bash
   git commit -m "feat(payment-ui): Add credit card form"
   git commit -m "feat(payment-api): Add Stripe webhook"
   ```

5. **Test together before PR**
   - Ensure integration works
   - Run all tests

❌ **DON'T:**
1. **Force push to shared branches**
   ```bash
   # ❌ NEVER on shared branch
   git push --force origin feature/payment-integration
   
   # ✅ Only if teammate confirms they've pulled your changes
   git push --force-with-lease origin feature/payment-integration
   ```

2. **Work on same files without coordination**
   - Leads to constant conflicts
   - Plan who works on what

3. **Commit broken code**
   - At least make sure it compiles
   - Don't break teammate's work

4. **Rebase shared branch without agreement**
   - Can cause issues for teammate
   - Coordinate complex operations

#### Pair Programming Workflow

**Best approach for shared complex features:**

```bash
# 1. Screen share / live collaboration
# 2. One person drives (writes code)
# 3. Other person navigates (reviews, suggests)
# 4. Switch roles every 30-60 minutes

# Only driver commits:
git add .
git commit -m "feat: Add payment processing (pair: Gautam & Sourav)"
git push origin feature/payment-integration
```

---

## 🏗️ Branch Strategies Explained

### 1. GitHub Flow

**Structure:**
```
main
  ├── feature/a
  ├── feature/b
  └── hotfix/c
```

**When to use:**
- Small teams (1-5 developers)
- Continuous deployment
- Web apps with rolling releases
- Simple projects

**Pros:**
- Simple to understand
- Fast iteration
- Minimal overhead

**Cons:**
- Not suitable for versioned releases
- No staging environment support
- Hard to maintain multiple versions

---

### 2. GitFlow

**Structure:**
```
main (production)
  |
  └── develop
       ├── feature/a
       ├── feature/b
       ├── release/v1.0
       └── hotfix/c → merges to main & develop
```

**When to use:**
- Medium to large teams
- Scheduled releases
- Mobile apps (App Store/Play Store releases)
- Products with version numbers

**Pros:**
- Clear separation of concerns
- Supports versioned releases
- Easy to maintain multiple versions
- Good for scheduled sprints

**Cons:**
- Complex for beginners
- More merge commits
- Slower than trunk-based

---

### 3. Trunk-Based Development

**Structure:**
```
main (trunk)
  ├── feature/a (1-2 days max)
  └── feature/b (1-2 days max)
```

**When to use:**
- Large teams with strong CI/CD
- Microservices
- Fast-moving products
- Teams with high automation

**Pros:**
- Very fast integration
- Minimal merge conflicts
- Forces small, incremental changes
- Best for continuous deployment

**Cons:**
- Requires mature CI/CD
- Needs feature flags
- Requires discipline
- Not suitable for versioned releases

---

### 4. Release Branching

**Structure:**
```
main (latest)
  ├── release/v1.0 (supported)
  ├── release/v2.0 (supported)
  └── release/v3.0 (current)
```

**When to use:**
- Enterprise software
- On-premise deployments
- Products with LTS versions
- Multiple supported versions

**Pros:**
- Support multiple versions simultaneously
- Easy to backport fixes
- Clear version history

**Cons:**
- Complex maintenance
- Lots of branches to manage
- Potential for merge conflicts

---

## 🔄 Rebasing vs Merging

### Merge

**What it does:** Creates a merge commit that combines two branches

```bash
git checkout feature/my-feature
git merge dev

# Creates:
#   dev:     ●───●───●
#                     \
#   feature:  ●───●───●───● (merge commit)
```

**When to use:**
- Merging to main/dev (via PR)
- Shared branches
- Preserving full history

**Pros:**
- ✅ Preserves complete history
- ✅ Safe for shared branches
- ✅ Easy to understand

**Cons:**
- ❌ Creates merge commits (noisy history)
- ❌ Complex graph visualization
- ❌ Harder to bisect

**Command:**
```bash
git checkout feature-branch
git merge dev
```

---

### Rebase

**What it does:** Replays your commits on top of another branch

```bash
git checkout feature/my-feature
git rebase dev

# Creates:
#   dev:     ●───●───●
#                     \
#   feature:          ●───●───● (rebased, linear)
```

**When to use:**
- Updating feature branches
- Before creating PR
- Personal branches
- Cleaning up history

**Pros:**
- ✅ Clean, linear history
- ✅ Easier to understand what changed
- ✅ Better for git bisect
- ✅ No merge commits

**Cons:**
- ❌ Rewrites history (can't use on shared branches)
- ❌ Can cause confusion if used incorrectly
- ❌ Conflicts can be harder to resolve

**Command:**
```bash
git checkout feature-branch
git rebase dev
```

---

### Interactive Rebase (Clean Up Commits)

**Use case:** Squash multiple WIP commits into one clean commit

```bash
# Before PR, clean up commits
git rebase -i origin/dev

# Editor opens:
pick abc123 feat: Add user service
pick def456 WIP: fix typo
pick ghi789 WIP: more changes
pick jkl012 fix: validation

# Change to:
pick abc123 feat: Add user service
squash def456 WIP: fix typo
squash ghi789 WIP: more changes
squash jkl012 fix: validation

# Save and exit
# All commits combined into one
```

---

### Decision Matrix

| Situation | Use Rebase | Use Merge |
|-----------|-----------|-----------|
| Update feature branch from dev | ✅ | ❌ |
| Completing PR to dev/main | ❌ | ✅ |
| Clean up commit history | ✅ | ❌ |
| Shared branch (2+ developers) | ❌ | ✅ |
| Personal feature branch | ✅ | ❌ |
| Hotfix to production | ❌ | ✅ |

---

### Golden Rules

1. **Never rebase public/shared branches**
   ```bash
   # ❌ NEVER
   git checkout dev
   git rebase feature-branch  # DON'T!
   
   # ✅ CORRECT
   git checkout feature-branch
   git rebase dev
   ```

2. **Never rebase after pushing to shared branch**
   ```bash
   # If teammate already pulled your branch, DON'T rebase
   # Use merge instead
   ```

3. **Always rebase before creating PR**
   ```bash
   git fetch origin dev
   git rebase origin/dev
   # Now create PR
   ```

---

## ✍️ Commit Best Practices

### Conventional Commits Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

#### Types

- **feat:** New feature
- **fix:** Bug fix
- **docs:** Documentation changes
- **style:** Code style changes (formatting, no logic change)
- **refactor:** Code refactoring
- **test:** Adding tests
- **chore:** Maintenance tasks

#### Examples

```bash
# Good commits
git commit -m "feat(auth): Add user login functionality"
git commit -m "fix(chat): Resolve message ordering issue"
git commit -m "refactor(api): Extract payment service to separate class"
git commit -m "docs(readme): Add setup instructions"
git commit -m "chore(deps): Update flutter dependencies"

# Bad commits
git commit -m "fix stuff"
git commit -m "WIP"
git commit -m "changes"
git commit -m "update"
```

### Commit Message Template

**Short form (for small changes):**
```bash
git commit -m "feat(payments): Add Stripe integration"
```

**Long form (for complex changes):**
```bash
git commit -m "feat(payments): Add Stripe integration

- Add Stripe SDK dependency
- Implement payment form UI
- Add payment validation logic
- Connect to Stripe API

Related to issue #123"
```

### Commit Frequency

**How often to commit:**

✅ **DO commit:**
- After completing a logical unit of work
- Before switching tasks
- Before end of day
- After fixing a bug
- After adding a test

❌ **DON'T commit:**
- Broken code (unless explicitly WIP)
- Half-implemented features without context
- Just to "save" (use stash instead)

### Atomic Commits

**One commit = One logical change**

```bash
# ❌ BAD: Too many unrelated changes
git add .
git commit -m "Add login, fix typo, update readme, refactor utils"

# ✅ GOOD: Separate commits
git add lib/features/auth/
git commit -m "feat(auth): Add login functionality"

git add lib/core/utils/
git commit -m "refactor(utils): Extract validation helpers"

git add README.md
git commit -m "docs: Update setup instructions"
```

---

## 📬 Pull Request Workflow

### Before Creating PR

```bash
# 1. Update from base branch
git fetch origin dev
git rebase origin/dev

# 2. Run tests
flutter test

# 3. Check for linting errors
flutter analyze

# 4. Squash WIP commits (optional)
git rebase -i origin/dev

# 5. Push
git push --force-with-lease origin feature/my-feature
```

### PR Template

**Title:**
```
feat(chat): Add message editing functionality
```

**Description:**
```markdown
## Description
Implements message editing feature for chat screen

## Changes
- Add edit button to message long-press menu
- Implement edit mode in chat input
- Add edit API endpoint integration
- Update chat state management

## Screenshots
[Include before/after screenshots]

## Testing
- [ ] Tested on Android
- [ ] Tested on iOS
- [ ] Unit tests added
- [ ] Manual testing completed

## Related Issues
Closes #123
Related to #456

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] No console.log/print statements left
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
```

### PR Size Guidelines

| Size | Lines Changed | Review Time | Status |
|------|---------------|-------------|--------|
| XS | 0-50 | 5 min | ✅ Perfect |
| S | 50-200 | 15 min | ✅ Good |
| M | 200-500 | 30 min | ⚠️ Consider splitting |
| L | 500-1000 | 1 hour | ❌ Too large, split |
| XL | 1000+ | 2+ hours | ❌ Must split |

### Code Review Guidelines

**For Author:**
- Respond to all comments
- Don't take feedback personally
- Explain reasoning when needed
- Push fixes quickly

**For Reviewer:**
- Review within 24 hours
- Be constructive, not destructive
- Ask questions, don't demand
- Approve if no critical issues

---

## 🚨 Emergency Fixes

### Hotfix for Production

**Scenario:** Critical bug in production (main branch)

#### GitFlow Approach

```bash
# 1. Create hotfix from main
git checkout main
git pull origin main
git checkout -b hotfix/critical-login-bug

# 2. Fix the issue
git add .
git commit -m "fix: Resolve login crash on Android"

# 3. Merge to main
git checkout main
git merge hotfix/critical-login-bug
git tag -a v1.0.1 -m "Hotfix: Login crash"
git push origin main --tags

# 4. Merge to develop too (so fix isn't lost)
git checkout develop
git merge hotfix/critical-login-bug
git push origin develop

# 5. Delete hotfix branch
git branch -d hotfix/critical-login-bug
git push origin --delete hotfix/critical-login-bug

# 6. Deploy main to production
```

#### GitHub Flow Approach

```bash
# 1. Create hotfix from main
git checkout main
git pull origin main
git checkout -b hotfix/critical-bug

# 2. Fix quickly
git add .
git commit -m "fix: Resolve critical bug"

# 3. Create PR (expedited review)
# hotfix/critical-bug → main

# 4. Merge and deploy immediately
```

### Reverting Changes

**Undo last commit (not pushed):**
```bash
git reset --soft HEAD~1  # Keep changes
# or
git reset --hard HEAD~1  # Discard changes
```

**Undo pushed commit:**
```bash
# Create revert commit (safe for shared branches)
git revert <commit-hash>
git push origin branch-name
```

**Undo merge:**
```bash
# If merge was recent and not pushed
git reset --hard HEAD~1

# If merge was pushed
git revert -m 1 <merge-commit-hash>
git push origin branch-name
```

---

## ❌ Common Mistakes

### Mistake 1: Merging dev/main into feature branch

```bash
# ❌ WRONG
git checkout feature/my-feature
git merge dev

# ✅ CORRECT
git checkout feature/my-feature
git rebase dev
```

**Why:** Creates unnecessary merge commits and messy history

---

### Mistake 2: Force pushing to shared branches

```bash
# ❌ WRONG (if teammate is also working on this)
git push --force origin feature/shared-feature

# ✅ CORRECT
git push --force-with-lease origin feature/shared-feature
# or coordinate with teammate first
```

**Why:** Overwrites teammate's work

---

### Mistake 3: Not pulling before pushing

```bash
# ❌ WRONG
git add .
git commit -m "feat: Add feature"
git push origin feature-branch  # Fails!

# ✅ CORRECT
git pull --rebase origin feature-branch
git add .
git commit -m "feat: Add feature"
git push origin feature-branch
```

---

### Mistake 4: Too many WIP commits

```bash
# ❌ BAD HISTORY
abc123 WIP
def456 WIP: fix
ghi789 WIP: more fixes
jkl012 Finally working

# ✅ SQUASH BEFORE PR
git rebase -i origin/dev
# Squash all into one clean commit
```

---

### Mistake 5: Working directly on main/dev

```bash
# ❌ WRONG
git checkout dev
git add .
git commit -m "feat: Add feature"
git push origin dev

# ✅ CORRECT
git checkout -b feature/my-feature
git add .
git commit -m "feat: Add feature"
git push origin feature/my-feature
# Create PR
```

---

### Mistake 6: Keeping stale branches

```bash
# ❌ 50 branches in your repo, 90% merged

# ✅ Clean up regularly
git branch -d feature/old-merged-feature
git push origin --delete feature/old-merged-feature

# Delete all merged branches
git branch --merged dev | grep -v "dev" | xargs git branch -d
```

---

## 📝 Git Commands Cheatsheet

### Daily Commands

```bash
# Start day
git checkout dev
git pull origin dev --rebase
git checkout -b feature/new-feature

# Work
git add .
git commit -m "feat: Add something"
git push origin feature/new-feature

# Update branch
git fetch origin dev
git rebase origin/dev

# End day
git add .
git commit -m "WIP: Progress on feature"
git push origin feature/new-feature

# Next day, squash WIP
git rebase -i origin/dev
```

### Branch Management

```bash
# List branches
git branch                  # Local
git branch -a              # All (local + remote)

# Create branch
git checkout -b feature/name

# Switch branch
git checkout branch-name
git switch branch-name      # New Git

# Delete branch
git branch -d branch-name   # Local
git push origin --delete branch-name  # Remote

# Rename branch
git branch -m old-name new-name
```

### Syncing

```bash
# Fetch (download, don't apply)
git fetch origin

# Pull (fetch + merge)
git pull origin branch-name

# Pull with rebase (fetch + rebase)
git pull --rebase origin branch-name

# Push
git push origin branch-name

# Force push (careful!)
git push --force-with-lease origin branch-name
```

### Undoing Changes

```bash
# Discard local changes (not committed)
git restore file.dart       # Single file
git restore .              # All files

# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes)
git reset --hard HEAD~1

# Revert commit (safe for shared branches)
git revert <commit-hash>

# Stash changes
git stash                   # Save changes
git stash pop              # Restore changes
git stash list             # View stashes
git stash drop             # Delete stash
```

### Viewing History

```bash
# View commits
git log                     # Full log
git log --oneline          # Compact
git log --graph --all      # Visual graph

# View changes
git diff                    # Unstaged changes
git diff --staged          # Staged changes
git diff branch1..branch2  # Between branches

# View file history
git log --follow file.dart
git blame file.dart        # Line-by-line authorship
```

### Rebase Operations

```bash
# Rebase on branch
git rebase dev

# Interactive rebase (squash commits)
git rebase -i origin/dev

# Continue after resolving conflicts
git add .
git rebase --continue

# Abort rebase
git rebase --abort
```

### Conflict Resolution

```bash
# When conflicts occur:
# 1. Open conflicted files in VS Code
# 2. Choose "Accept Current" or "Accept Incoming" or edit manually
# 3. Stage resolved files
git add .

# 4. Continue
git rebase --continue  # If rebasing
git merge --continue   # If merging

# Or abort
git rebase --abort
git merge --abort
```

### Tags (Versioning)

```bash
# Create tag
git tag -a v1.0.0 -m "Release version 1.0.0"

# List tags
git tag

# Push tags
git push origin v1.0.0      # Single tag
git push origin --tags      # All tags

# Delete tag
git tag -d v1.0.0           # Local
git push origin --delete v1.0.0  # Remote

# Checkout tag
git checkout v1.0.0
```

### Advanced

```bash
# Cherry-pick (apply specific commit)
git cherry-pick <commit-hash>

# Find commit with specific change
git log -S "function name"

# Show commit details
git show <commit-hash>

# Search commit messages
git log --grep="keyword"

# Clean untracked files
git clean -fd              # Remove untracked files/folders

# Update remote URL
git remote set-url origin <new-url>

# View remote info
git remote -v
```

---

## 🎓 Conclusion

### For Your Team (2 Developers, Separate Features)

**Recommended Workflow:**

1. **Use Feature Branches (NOT personal branches)**
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/descriptive-name
   ```

2. **Keep branches short-lived (1 week max)**

3. **Rebase on dev, don't merge**
   ```bash
   git fetch origin dev
   git rebase origin/dev
   ```

4. **Delete after merge**
   ```bash
   git branch -d feature/name
   git push origin --delete feature/name
   ```

5. **For shared features, coordinate**
   - Use one shared branch
   - Pull frequently
   - Communicate before pushes

### Quick Decision Tree

```
Starting new work?
├─ Working alone? → Feature branch
├─ Working with teammate?
│  ├─ Same files? → Shared branch OR pair programming
│  └─ Different files? → Shared branch with coordination
└─ Emergency fix? → Hotfix branch

Updating branch?
├─ Personal branch? → Rebase
├─ Shared branch? → Merge
└─ Before PR? → Rebase + squash

Branch lifetime?
├─ Small project → 2-5 days
├─ Medium project → 1 week
└─ Large project → 1-2 days (trunk-based)
```

---

**Remember:**
- Keep history clean (rebase personal branches)
- Keep commits atomic (one logical change per commit)
- Keep branches short-lived (delete after merge)
- Keep communication open (coordinate on shared work)

**Happy Git-ing! 🎉**

