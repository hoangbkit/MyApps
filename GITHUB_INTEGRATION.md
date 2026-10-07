# Git Operations Companion

This branch extends the iOS-only MyApps app from the latest `master` with a separate Git operations area for iPhone.

## Execution rule

This PR is **planning-only until explicitly approved**.

Before every implementation phase:

1. Discuss remaining requirements and UX choices with the user.
2. Wait for an explicit go-ahead.
3. Implement only that approved phase.
4. Stop after the phase and report what changed.
5. Do not continue to the next phase without another explicit go-ahead.

If a requirement is ambiguous or could materially change behavior, stop and ask before implementing it.

Do not set up or trigger CI for this integration unless explicitly requested.

---

# Product boundary

MyApps becomes a top-level tab app.

The existing app-management experience is the first tab and must be left alone. The second tab lists GitHub repositories. Tapping a repository opens Git operations.

There is **no link between `ManagedApp` and GitHub repositories**.

```text
MyApps
│
├── Apps tab
│   └── existing ProjectsView / AppDetailView / Notes
│       └── leave behavior and design unchanged
│
└── Repos tab
    ├── all accessible GitHub repositories
    └── tap repository
        └── Git workspace
            ├── Log
            ├── Branches
            ├── Tags
            └── Releases
```

## Core capabilities

1. **Beautified Git log / commit graph**
2. **Normal branch merge**
3. **True branch rebase**
4. **Create Git tag**
5. **Create GitHub release**

## Explicitly out of scope

- changing the existing app list UI
- changing `AppDetailView`
- linking a `ManagedApp` to a repository
- file/repository tree browsing
- source-code viewing/editing
- issue management
- PR review or PR merge
- notifications/discussions
- macOS target
- iCloud work from `develop`

---

# Top-level design

```text
┌────────────────────────────────────┐
│                                    │
│        Current Apps UI             │
│                                    │
│  Spokio                            │
│  BYOKchat                          │
│  ReadAloud                         │
│  ...                               │
│                                    │
├────────────────────────────────────┤
│                                    │
│      [ Apps ]        [ Repos ]     │
│        ▔▔▔                         │
└────────────────────────────────────┘
```

Conceptually:

```text
TabView
│
├── Apps
│   └── NavigationStack
│       └── ProjectsView
│           └── AppDetailView
│               └── existing behavior unchanged
│
└── Repos
    └── NavigationStack
        └── RepositoriesView
```

Do not redesign ProjectsView, AppDetailView, app editing, notes, backup, or current local data flows merely to support the new tab structure.

---

# Repos tab

```text
REPOS
────────────────────────────────────
Git Repositories                 ↻

Search repositories
┌──────────────────────────────────┐
│ 🔍 Search                        │
└──────────────────────────────────┘

Spokio
hoangbkit/Spokio
Private · Swift                       ›

BYOKchat
hoangbkit/BYOKchat
Private · Swift                       ›

ReadAloud
hoangbkit/ReadAloud
Private · Swift                       ›

analytics-server
hoangbkit/analytics-server
Private · TypeScript                  ›
```

Requirements:

- show all repositories the authenticated account can access
- support private repositories
- search/filter
- refresh
- lightweight metadata only
- clear loading/empty/error states
- no repository file browser

Pinned/recent repositories are optional and require explicit approval.

---

# Repository workspace

```text
SPOKIO
────────────────────────────────────
‹ Repos                    develop ▾

hoangbkit/Spokio

[ Log ]   [ Branches ]   [ Tags ]   [ Releases ]
 ─────
```

---

# Beautified Git log

```text
SPOKIO · LOG
────────────────────────────────────
‹ Repos                    develop ▾

[ Log ]   [ Branches ]   [ Tags ]   [ Releases ]
 ─────

●  e94fa51                         develop
│  Fix model lifecycle
│  Hoang · 18m
│
●  8136db2
│  Queue job-details polish
│  Hoang · 1h
│
├─● 72ad510                  ios-polish
│ │ Paragraph sheet polish
│ │ Hoang · 2h
│ │
│ ● a8ff112
│ │ Voice gender labels
│ │
●─┘ 71ac03f
│  Merge branch ios-polish
│
●  30bd728                         master
│  Release 1.12                    [1.12]
│  Sep 29
│
●  b8af203
│  Update AppFoundation
│
⋮
```

The graph should clearly show parent topology, divergence, merges, selected branch, branch-head labels, tag labels, SHA, subject, author, and date while remaining readable on iPhone.

No file diff viewer is required for v1.

## Commit detail

```text
COMMIT
────────────────────────────────────
‹ Log

e94fa51

Fix model lifecycle

Hoang Nguyen
Today · 22:01

Refs
develop

────────────────────────────────────

Parents
8136db2

[ Create Tag Here ]

Copy SHA
Open on GitHub
```

---

# Branches

```text
BRANCHES
────────────────────────────────────
‹ Spokio

✓ develop
  e94fa51
  Fix model lifecycle

  ios-polish
  72ad510
  Paragraph sheet polish
  2 ahead · 1 behind vs develop

  master
  30bd728
  Release 1.12
```

Tap a branch:

```text
IOS-POLISH
────────────────────────────────────

Head
72ad510

Compare against
develop

2 ahead · 1 behind

[ View Log ]
[ Merge into… ]
[ Rebase onto… ]
[ Create Tag at HEAD ]
```

---

# Merge

This means normal Git branch merge, not PR merge.

```text
MERGE
────────────────────────────────────
Cancel

Source
ios-polish

        ↓ merge into

Destination
develop

2 commits ahead
1 commit behind

Commits introduced

● 72ad510  Paragraph sheet polish
● a8ff112  Voice gender labels

[ Merge ios-polish into develop ]
```

Confirmation:

```text
MERGE BRANCHES?
────────────────────────────────────

ios-polish
    ↓
develop

This updates develop.

[ Cancel ]                 [ Merge ]
```

Requirements: source/destination are always explicit, ahead/behind is shown before confirmation, merge direction is never reversed silently, and conflicts/errors are surfaced clearly.

---

# Rebase

This means true branch rebase, equivalent in intent to:

```text
git checkout ios-polish
git rebase develop
git push --force-with-lease
```

It is **not** PR "rebase and merge."

```text
REBASE
────────────────────────────────────
Cancel

Branch
ios-polish

        ↓ rebase onto

develop

Commits to replay

● 72ad510  Paragraph sheet polish
● a8ff112  Voice gender labels

⚠ History of ios-polish will change.

[ Rebase ios-polish onto develop ]
```

Rebase safety requirements:

- calculate the exact replay range before writing
- refuse unsupported or ambiguous histories
- detect conflicts before moving the branch ref
- never partially update the branch on failure
- use stale-head / force-with-lease-style protection
- refuse the write if the remote branch moved after preparation
- show old and proposed new head before confirmation
- do not fake rebase with PR operations

Protected/default-branch rules must be decided in Phase 0.

---

# Tags

```text
TAGS
────────────────────────────────────
‹ Spokio                         ＋

1.12
30bd728
Sep 29

1.11
19aa821
Sep 14
```

```text
CREATE TAG
────────────────────────────────────
Cancel                        Create

Tag
[ 1.13                         ]

Target
e94fa51
Fix model lifecycle

Tag type
Lightweight / Annotated
(decide in Phase 0)

[ Create Tag ]
```

The exact target SHA must be visible before creation.

---

# Releases

```text
RELEASES
────────────────────────────────────
‹ Spokio                         ＋

Product Releases
────────────────────────────────────

1.12                         Latest
Sep 29

1.11
Sep 14

Build Prereleases
────────────────────────────────────

mycli-build-37609478530-1
Today
```

```text
CREATE RELEASE
────────────────────────────────────
Cancel                        Create

Tag
1.13                           ›

Title
Spokio 1.13

Release notes
[                              ]
[                              ]

[ ] Prerelease
[ ] Draft

[ Create Release ]
```

Product releases and disposable `mycli-build-*` prereleases should be visually distinct. Release asset upload is out of scope initially.

---

# Data and architecture rules

- GitHub credentials live in Keychain only.
- Never store credentials in SwiftData, UserDefaults, backups, logs, analytics, or source control.
- Do not add Git-specific fields to `ManagedApp`.
- Repositories and Git history are remote data.
- GitHub failures must not affect the Apps tab or local MyApps data.
- All Git write operations require explicit confirmation and local error presentation.

```text
RootView
   |
   v
TabView
   |
   +-- Apps tab
   |     +-- existing NavigationStack
   |           +-- ProjectsView
   |                 +-- AppDetailView
   |
   +-- Repos tab
         +-- NavigationStack
               +-- RepositoriesView
                     +-- RepositoryWorkspaceView
                           +-- GitLogView
                           +-- BranchesView
                           +-- TagsView
                           +-- ReleasesView

GitHubService
   +-- Authentication
   +-- Repositories
   +-- Commits / refs / compare
   +-- Merge
   +-- Git objects / ref updates for rebase
   +-- Tags
   +-- Releases
   |
   v
Keychain
```

---

# Requirements still to settle

Phase 0 should settle:

- authentication method
- one account vs account switching
- repository ordering
- whether forks/archived repos appear by default
- search behavior
- whether recent/pinned repositories are needed
- default branch when opening a repo
- initial Git-history depth
- pagination/infinite-scroll behavior
- graph complexity limits
- merge strategy and commit-message behavior
- exact supported rebase cases
- protected/default branch rebase rules
- lightweight vs annotated tags
- whether tag deletion is needed
- release title/notes defaults
- grouping/filtering of `mycli-build-*` prereleases

---

# Multi-phase implementation plan

## Phase 0 — Requirements + UX lock

Discussion only. Finalize auth, root tabs, repository list, Git workspace navigation, graph behavior, merge semantics, rebase safety, tag type, and release defaults.

Deliverable: update this document only. No production implementation.

**STOP. Wait for explicit approval.**

## Phase 1 — Root tabs + GitHub foundation

- wrap the existing root navigation in a two-tab `TabView`
- first tab hosts the existing Apps navigation unchanged
- second tab hosts Repos
- add GitHub client/auth abstraction
- store credentials in Keychain
- add connection/error/loading state

Acceptance: Apps behaves unchanged and GitHub failures cannot break it.

**STOP. Wait for explicit approval.**

## Phase 2 — Repositories tab

- list all accessible repositories
- private repos
- search/filter
- refresh
- loading/empty/error states
- navigate into repository workspace shell

No Git operations yet.

**STOP. Wait for explicit approval.**

## Phase 3 — Beautified Git log

- commit history
- parent topology
- branch/tag metadata
- selected branch
- graph rendering
- pagination
- lightweight commit details
- Copy SHA / Open on GitHub

**STOP. Wait for explicit approval.**

## Phase 4 — Branch merge

- branch list
- ahead/behind comparison
- source/destination selection
- merge preview + confirmation
- normal GitHub branch merge
- conflicts/errors
- refresh after success

No PR operation.

**STOP. Wait for explicit approval.**

## Phase 5 — True branch rebase

- merge-base calculation
- replay-set determination
- topology validation
- safe rebased commit construction
- conflict/unsupported-case detection
- old/new-head preview
- guarded branch-ref update
- stale-head protection

Do not begin until supported cases and technical strategy are explicitly approved.

**STOP. Wait for explicit approval.**

## Phase 6 — Tags

- tag list
- tag labels in Git log
- create tag from commit
- create tag at branch HEAD
- exact SHA preview
- lightweight/annotated behavior as agreed
- confirmation/errors/refresh

**STOP. Wait for explicit approval.**

## Phase 7 — Releases

- release list
- product vs `mycli-build-*` grouping
- create release from existing tag
- title + notes
- draft/prerelease options
- confirmation/errors

No release-asset upload initially.

**STOP. Wait for explicit approval.**

## Phase 8 — Release-readiness polish

- accessibility
- repository-list performance
- graph performance/readability
- pagination/cache review
- destructive-action consistency
- credential/security review
- network/offline states
- documentation
- manual end-to-end validation

Do not redesign or expand the Apps tab during polish.

**STOP.**

---

# Core delivery path

```text
Phase 0   Requirements
    ↓
Phase 1   Tabs + Auth/Foundation
    ↓
Phase 2   Repositories
    ↓
Phase 3   Beautiful Git Log
    ↓
Phase 4   Merge
    ↓
Phase 5   Rebase
    ↓
Phase 6   Tags
    ↓
Phase 7   Releases
    ↓
Phase 8   Polish
```

Product boundary:

```text
Apps tab  = existing MyApps product, unchanged
Repos tab = Git history + real repository operations
```