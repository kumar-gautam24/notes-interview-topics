# Git Cheatsheet — Developer Daily Use

---

## 1. Setup & Config

```bash
git config --global user.name "Your Name"          # set global username
git config --global user.email "you@email.com"      # set global email
git config --global init.defaultBranch main          # default branch name
git config --list                                    # show all config
git config user.email                                # check current email for this repo
git config --local user.email "work@company.com"     # per-repo email (overrides global)
```

---

## 2. Repo Init & Clone

```bash
git init                                # initialize new repo in current dir
git clone <url>                         # clone remote repo
git clone <url> my-folder               # clone into specific folder
git clone --depth 1 <url>               # shallow clone (latest commit only, faster)
```

---

## 3. Staging & Committing

```bash
git status                              # show working tree status
git add <file>                          # stage a specific file
git add .                               # stage all changes
git add -p                              # stage interactively (hunk by hunk)
git commit -m "msg"                     # commit with message
git commit -am "msg"                    # stage tracked files + commit (skips untracked)
git commit --amend -m "new msg"         # rewrite last commit message
git commit --amend --no-edit            # add staged changes to last commit silently
```

---

## 4. Viewing History & Diffs

```bash
git log                                 # full commit history
git log --oneline                       # compact one-line-per-commit view
git log --oneline -10                   # last 10 commits
git log --oneline --graph --all         # visual branch graph
git log --author="Gautam"               # filter by author
git log --since="2 weeks ago"           # filter by date
git show <commit-hash>                  # show full diff of a specific commit
git diff                                # unstaged changes vs last commit
git diff --staged                       # staged changes vs last commit
git diff main..feature-branch           # diff between two branches
```

---

## 5. Undoing Things

### Already pushed to remote (your current situation)

```bash
# OPTION A: Revert (safe, creates a NEW commit that undoes the last one)
git revert HEAD                         # undo last commit with a new reverse commit
git push                                # push the revert — clean history, no force push

# OPTION B: Reset + force push (rewrites history — use only on YOUR branch)
git reset --hard HEAD~1                 # delete last commit entirely (changes gone)
git reset --soft HEAD~1                 # undo commit but keep changes staged
git push --force-with-lease             # push rewritten history (safer than --force)
```

### Not yet pushed

```bash
git reset --soft HEAD~1                 # undo last commit, keep changes staged
git reset --mixed HEAD~1                # undo last commit, keep changes unstaged (default)
git reset --hard HEAD~1                 # undo last commit, discard all changes
git reset HEAD~3                        # undo last 3 commits
```

### Other undos

```bash
git checkout -- <file>                  # discard unstaged changes in a file
git restore <file>                      # same as above (modern syntax)
git restore --staged <file>             # unstage a file (keep changes)
git clean -fd                           # delete all untracked files + dirs
git stash                               # temporarily shelve all changes
git stash pop                           # re-apply stashed changes
git stash list                          # see all stashes
git stash drop                          # delete latest stash
```

---

## 6. Branches

```bash
git branch                              # list local branches
git branch -a                           # list all branches (local + remote)
git branch feature-x                    # create new branch
git checkout feature-x                  # switch to branch
git checkout -b feature-x               # create + switch in one step
git switch feature-x                    # modern switch syntax
git switch -c feature-x                 # modern create + switch
git branch -d feature-x                 # delete branch (safe, only if merged)
git branch -D feature-x                 # force delete branch
git branch -m old-name new-name         # rename a branch
git push origin --delete feature-x      # delete remote branch
```

---

## 7. Merging & Rebasing

```bash
git merge feature-x                     # merge feature-x into current branch
git merge --no-ff feature-x             # merge with a merge commit (no fast-forward)
git merge --abort                       # cancel a merge in progress

git rebase main                         # replay current branch on top of main
git rebase -i HEAD~3                    # interactive rebase last 3 commits (squash/edit/drop)
git rebase --abort                      # cancel rebase
git rebase --continue                   # continue after resolving conflicts
```

---

## 8. Remotes

### Basic remote ops

```bash
git remote -v                           # list all remotes with URLs
git remote add origin <url>             # add a remote named "origin"
git remote set-url origin <new-url>     # change existing remote URL
git remote rename origin old-origin     # rename a remote
git remote remove old-origin            # delete a remote
```

### Multiple remotes (e.g., company + personal fork)

```bash
git remote add origin git@github.com:company/repo.git      # primary
git remote add personal git@github.com:gautam/repo.git      # your fork

git push origin main                    # push to company
git push personal main                  # push to your fork
git pull origin main                    # pull from company
git fetch --all                         # fetch from ALL remotes
```

---

## 9. Multiple GitHub Accounts on One Machine

### Step 1: Generate separate SSH keys

```bash
ssh-keygen -t ed25519 -C "work@company.com" -f ~/.ssh/id_work
ssh-keygen -t ed25519 -C "personal@gmail.com" -f ~/.ssh/id_personal
```

### Step 2: Configure `~/.ssh/config`

```
# Work account
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_work

# Personal account
Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_personal
```

### Step 3: Clone using the host alias

```bash
git clone git@github-work:company/repo.git        # uses work key
git clone git@github-personal:gautam/repo.git      # uses personal key
```

### Step 4: Per-repo user config

```bash
cd ~/work/repo
git config user.name "Gautam (Work)"
git config user.email "work@company.com"

cd ~/personal/repo
git config user.name "Gautam"
git config user.email "personal@gmail.com"
```

---

## 10. Push & Pull

```bash
git push                                # push current branch to tracked remote
git push -u origin main                 # push + set upstream (first time)
git push --force-with-lease             # force push safely (fails if remote changed)
git push --force                        # force push (dangerous, overwrites remote)
git pull                                # fetch + merge
git pull --rebase                       # fetch + rebase (cleaner history)
git fetch                               # download remote changes without merging
git fetch --prune                       # fetch + remove deleted remote branches
```

---

## 11. Tags

```bash
git tag                                 # list all tags
git tag v1.0.0                          # create lightweight tag
git tag -a v1.0.0 -m "Release 1.0"     # create annotated tag
git push origin v1.0.0                  # push specific tag
git push origin --tags                  # push all tags
git tag -d v1.0.0                       # delete local tag
git push origin --delete v1.0.0         # delete remote tag
```

---

## 12. Cherry-pick & Bisect

```bash
git cherry-pick <commit-hash>           # apply a specific commit to current branch
git cherry-pick --no-commit <hash>      # apply changes without committing

git bisect start                        # start binary search for a bug
git bisect bad                          # current commit is broken
git bisect good <hash>                  # this older commit was fine
git bisect reset                        # end bisect session
```

---

## 13. Useful Shortcuts & Aliases

```bash
# Add to ~/.gitconfig under [alias]
git config --global alias.st "status"
git config --global alias.co "checkout"
git config --global alias.br "branch"
git config --global alias.lg "log --oneline --graph --all"
git config --global alias.last "log -1 --oneline"

# Then use:
git st                                  # = git status
git lg                                  # = pretty branch graph
git last                                # = show last commit
```

---

## Quick Reference: "I Need To..."

| I need to...                          | Command                                    |
|---------------------------------------|--------------------------------------------|
| See my last commit                    | `git log -1 --oneline`                     |
| Undo last commit (already pushed)     | `git revert HEAD` then `git push`          |
| Delete last commit (already pushed)   | `git reset --hard HEAD~1` then `git push --force-with-lease` |
| Undo last commit (not pushed)         | `git reset --soft HEAD~1`                  |
| Change remote URL                     | `git remote set-url origin <new-url>`      |
| Add second remote                     | `git remote add <name> <url>`              |
| Switch GitHub accounts                | SSH config with host aliases (Section 9)   |
| Discard all local changes             | `git checkout -- .` or `git restore .`     |
| See what changed in a file            | `git log --oneline -- <file>`              |
| Undo a pushed merge                   | `git revert -m 1 <merge-commit-hash>`     |
