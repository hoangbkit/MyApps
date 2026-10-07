# GitHub Integration

This branch extends the iOS-only MyApps app from the latest `master` with a focused Git operations companion for iPhone.

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

# Product scope

MyApps should not duplicate GitHub Mobile.

GitHub Mobile is already good enough for:

- browsing files
- pull requests
- issues
- reviews
- notifications

MyApps should instead provide the Git operations that are awkward or missing on iPhone:

1. **Beautified Git log / commit graph**
2. **Branch merge**
3. **True branch rebase**
4. **Create Git tag**
5. **Create GitHub release**

This is a Git history + repository-operations layer attached to each `ManagedApp`.

## Explicitly out of scope

- file/repository tree browser
- source-code viewer
- editing files
- issue management
- PR review
- PR merge
- notifications
- discussions
- general GitHub replacement
- macOS target
- iCloud work from `develop`

---

# Product structure

```text
MyApps
  |
  +-- Spokio
  |    |
  |    +-- Notes
  |    |
  |    +-- Git
  |         |
  |         +-- Log
  |         +-- Branches
  |         +-- Tags
  |         +-- Releases
  |
  +-- BYOKchat
  |    +-- ...
  |
  +-- ReadAloud
       +-- ...
```

Git operations remain optional. An app without a linked repository continues behaving exactly as it does today.

---

# Core UX design

## App detail

```text
SPOKIO
────────────────────────────────────
‹ MyApps          [icon] Spokio    •••

Building · iOS/macOS
Live 1.12 · Dev 1.13

[ Notes ]                       [ Git ]
```

Git should feel like a capability of the app being managed, not a new global GitHub client.

---

# Git home / visual log

The visual Git log is the primary screen.

```text
SPOKIO · GIT
────────────────────────────────────
‹ Spokio                    develop ▾

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

## Log requirements

The graph should make these immediately visible:

- parent/child topology
- branch divergence
- merges
- current selected branch
- branch-head labels
- tag labels
- short SHA
- commit subject
- author
- relative/absolute time as appropriate

It should not try to become a desktop Git GUI.

The graph must prioritize readability on an iPhone-sized display.

---

# Commit details

Tap a commit:

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

Commit
e94fa51

────────────────────────────────────

[ Create Tag Here ]

Copy SHA
Open on GitHub
```

Commit details are intentionally lightweight.

No file diff viewer is required for v1 because GitHub Mobile/web can handle that.

---

# Branches

```text
BRANCHES
────────────────────────────────────
‹ Git

✓ develop
  e94fa51
  Fix model lifecycle

  ios-polish
  72ad510
  Paragraph sheet polish
  2 commits ahead · 1 behind

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

Relative to develop
2 ahead · 1 behind

Actions

[ View Log ]

[ Merge into… ]

[ Rebase onto… ]

[ Create Tag at HEAD ]
```

---

# Merge flow

This means normal Git branch merge, not PR merge.

```text
MERGE
────────────────────────────────────
Cancel

Source
ios-polish

        ↓

Destination
develop

2 commits ahead
1 commit behind

Commits introduced

● 72ad510  Paragraph sheet polish
● a8ff112  Voice gender labels

────────────────────────────────────

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

## Merge behavior

Use GitHub's normal branch merge capability when possible.

The UI must show:

- source branch
- destination branch
- ahead/behind relationship
- expected resulting operation
- merge conflicts/errors clearly

Never silently reverse source and destination.

---

# Rebase flow

This means **true branch rebase**, equivalent in intent to:

```text
git checkout ios-polish
git rebase develop
git push --force-with-lease
```

It is not GitHub's PR "Rebase and merge" feature.

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

────────────────────────────────────

⚠ History of ios-polish will change.

[ Rebase ios-polish onto develop ]
```

Confirmation:

```text
REWRITE BRANCH HISTORY?
────────────────────────────────────

ios-polish will be rebased onto develop.

Old head
72ad510

Base
e94fa51

The branch ref will move if the
rebase succeeds.

[ Cancel ]                [ Rebase ]
```

## Rebase safety requirements

True rebase is the highest-risk feature in this scope.

GitHub does not provide the same simple high-level REST endpoint for arbitrary branch rebase that it provides for normal branch merge.

Implementation must therefore be designed carefully around Git commit/tree/ref operations, or another explicitly approved strategy.

Required safety properties:

- calculate the exact commit range to replay before writing
- refuse ambiguous or unsupported histories
- detect conflicts before moving the branch ref
- never partially move the branch on failed rebase
- use compare-and-swap / force-with-lease-style protection when updating the branch ref
- refuse the write if the remote branch moved since the operation was prepared
- show the old and proposed new head before confirmation
- do not offer rebase on protected/default branches unless explicitly allowed by the agreed requirements

Do not implement a fake rebase.

---

# Tags

```text
TAGS
────────────────────────────────────
‹ Git                            ＋

1.12
30bd728
Sep 29

1.11
19aa821
Sep 14

1.10
1f683cd
Sep 7
```

Create from a selected commit:

```text
CREATE TAG
────────────────────────────────────
Cancel                        Create

Tag
┌──────────────────────────────────┐
│ 1.13                             │
└──────────────────────────────────┘

Commit
e94fa51
Fix model lifecycle

Tag type
Lightweight / Annotated
(to be decided in Phase 0)

[ Create Tag ]
```

The app must resolve and show the exact target SHA before creation.

---

# Releases

```text
RELEASES
────────────────────────────────────
‹ Git                            ＋

1.12                         Latest
Sep 29

1.11
Sep 14

1.10
Sep 7

────────────────────────────────────

Build prereleases

mycli-build-37609478530-1
Today
```

Create release:

```text
CREATE RELEASE
────────────────────────────────────
Cancel                        Create

Tag
1.13                           ›

Title
Spokio 1.13

Release notes
┌──────────────────────────────────┐
│                                  │
│                                  │
└──────────────────────────────────┘

[ ] Prerelease
[ ] Draft

[ Create Release ]
```

Product releases and disposable `mycli-build-*` prereleases should be visually distinguishable.

Do not upload release assets in the initial implementation unless explicitly requested.

---

# Authentication and data rules

- GitHub credentials must live in Keychain only.
- Never put credentials in SwiftData, UserDefaults, backups, logs, analytics, or source control.
- Repository identity may be stored on `ManagedApp` once its exact representation is agreed.
- Git history is remote data and should be fetched on demand with only lightweight caching if needed.
- GitHub failure must never make local MyApps notes/business data unusable.
- All repository-writing operations need explicit confirmation and local error ownership.

---

# Requirements still to settle

Phase 0 must resolve these before implementation:

- authentication method for this personal app
- whether one GitHub account is enough
- how a `ManagedApp` links to a repository
- whether one app can link to more than one repository
- repository identity storage format
- where the Notes/Git switch should live in App Detail
- default selected branch
- how much Git history to load initially
- pagination/infinite-scroll behavior
- graph complexity limits on iPhone
- whether merge commits are always allowed or fast-forward should be preferred when possible
- exact merge commit-message behavior
- exact supported rebase cases
- protected/default branch restrictions for rebase
- lightweight vs annotated tag creation
- whether deleting tags is needed
- default release title/notes behavior
- whether `mycli-build-*` releases should be hidden, collapsed, or shown in a separate section

---

# Proposed architecture

```text
ManagedApp
   |
   +-- GitHub repository identity
   |
   v
GitWorkspaceView
   |
   +-- GitLogView
   +-- BranchesView
   +-- TagsView
   +-- ReleasesView
   |
   v
GitHubService
   |
   +-- Authentication
   +-- Commits / compare
   +-- Branch refs
   +-- Merge
   +-- Git objects / ref updates for rebase
   +-- Tags
   +-- Releases
   |
   v
Keychain
```

Keep the GitHub layer isolated from the existing MyApps local data layer.

---

# Multi-phase implementation plan

## Phase 0 — Requirements + UX lock

**Status: discussion only.**

Finalize:

- authentication
- repository linking
- Log / Branches / Tags / Releases navigation
- graph presentation
- merge semantics
- supported rebase semantics and safety rules
- tag type
- release defaults

Deliverable:

- update this document only
- no production implementation

**STOP. Wait for explicit approval.**

---

## Phase 1 — GitHub foundation + authentication

Goal: establish the safe API/auth layer.

Likely work:

- GitHub client
- authenticated request layer
- Keychain credential storage
- account connection/disconnection
- repository access validation
- shared error model
- request cancellation/loading state

No Git operation UI beyond what is required to validate the foundation.

**STOP. Wait for explicit approval.**

---

## Phase 2 — ManagedApp ↔ repository linking

Goal: associate each MyApps entry with its GitHub repository.

Likely work:

- minimal `ManagedApp` persistence change
- repository selection/linking
- unlink/change repository
- existing SwiftData migration
- Git entry point in App Detail
- unlinked empty state

Existing apps without GitHub links must continue working unchanged.

**STOP. Wait for explicit approval.**

---

## Phase 3 — Beautified Git log

Goal: deliver the main read-only value first.

Likely work:

- commit history retrieval
- branch/ref metadata
- tag metadata needed by the graph
- commit-parent topology
- iPhone-friendly graph layout
- branch/tag chips on commits
- branch selector
- pagination
- lightweight commit detail screen
- copy SHA / open on GitHub
- create-tag entry point may be visible but not active until the tag phase

Acceptance target:

The user can understand repository history and branch topology substantially faster than in GitHub Mobile.

**STOP. Wait for explicit approval.**

---

## Phase 4 — Branch merge

Goal: support normal Git branch merging safely.

Likely work:

- branches list
- ahead/behind comparison
- source/destination selector
- merge preview
- confirmation
- merge API operation
- conflict/error handling
- log/branch refresh after success

No PR is created or merged.

**STOP. Wait for explicit approval.**

---

## Phase 5 — True branch rebase

Goal: support real branch rebase, not PR "rebase and merge."

This phase must be treated independently because it rewrites history.

Likely work:

- determine merge base
- determine replay set
- validate topology
- construct rebased commits safely
- detect unsupported/conflicting cases
- preview old/new branch head
- guarded ref update with stale-head protection
- refuse update if remote branch changed
- clear failure/recovery presentation

This phase must not start until its technical strategy and supported cases are explicitly approved.

**STOP. Wait for explicit approval.**

---

## Phase 6 — Tags

Goal: create Git tags from known commits.

Likely work:

- tag list
- tag labels in the Git log
- create tag from commit
- create tag from branch HEAD
- exact SHA preview
- lightweight/annotated behavior as agreed
- confirmation and error handling
- refresh log/tag state after success

Tag deletion remains out of scope unless explicitly added.

**STOP. Wait for explicit approval.**

---

## Phase 7 — Releases

Goal: make product release creation practical from iPhone.

Likely work:

- release list
- visually separate product releases from `mycli-build-*` prereleases
- create release from existing tag
- title
- release notes
- draft/prerelease options
- release creation confirmation/error handling

No release-asset upload initially.

**STOP. Wait for explicit approval.**

---

## Phase 8 — Release-readiness polish

After approved functionality is complete:

- accessibility
- graph rendering/performance
- pagination/cache review
- destructive-action consistency
- credential/security review
- migration review
- backup/restore review
- offline/network-state review
- documentation
- end-to-end manual validation

Do not expand product scope during polish.

**STOP.**

---

# Core delivery path

```text
Phase 0   Requirements
    ↓
Phase 1   GitHub/Auth foundation
    ↓
Phase 2   App ↔ Repo
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

The defining features of this integration are the **visual Git log** and the ability to perform **real Git repository operations from iPhone** without duplicating GitHub Mobile.
