# Git Operations Companion

This branch extends the iOS-only MyApps app from the latest `master` with a separate Git operations area for iPhone.

## Implementation status

The scoped Git operations work is implemented on PR #2.

Development followed explicit phase gates: each phase was discussed, approved, implemented on the same PR, and stopped before continuing. CI was not set up or triggered as part of this work.

---

# Product boundary

MyApps becomes a top-level tab app.

The app has a five-tab product structure:

1. **Apps** — the existing custom app list and app details.
2. **Repos** — GitHub repositories and Git operations.
3. **App Store** — reserved for App Store Connect apps; implementation is deferred to later work.
4. **Notes** — the existing global Notes inbox.
5. **Settings** — the existing Settings screen.

There is **no link between `ManagedApp` and GitHub repositories**.

```text
MyApps
│
├── 1. Apps
│   └── existing ProjectsView
│       └── existing AppDetailView
│           └── leave app list/details behavior and design unchanged
│
├── 2. Repos
│   ├── connection guidance (PAT managed in Settings)
│   ├── all accessible GitHub repositories
│   └── tap repository
│       └── Git workspace
│           ├── Log
│           ├── Branches
│           ├── Tags
│           └── Releases
│
├── 3. App Store
│   └── reserved for future App Store Connect apps work
│
├── 4. Notes
│   └── existing global NotesInboxView
│
└── 5. Settings
    ├── GitHub PAT management (connect / replace / disconnect)
    └── existing SettingsView
```

## Core capabilities

1. **Beautified Git log / commit graph**
2. **Normal branch merge**
3. **True branch rebase**
4. **Create Git tag**
5. **Create GitHub release**

## Explicitly out of scope

- redesigning the existing app list UI
- changing `AppDetailView`
- implementing App Store Connect integration in this PR
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
┌─────────────────────────────────────────┐
│                                         │
│            Selected tab content         │
│                                         │
│                                         │
│                                         │
├─────────────────────────────────────────┤
│ Apps   Repos   App Store   Notes   ⚙︎  │
│  ▔▔▔                                    │
└─────────────────────────────────────────┘
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
├── Repos
│   └── NavigationStack
│       └── RepositoriesView
│
├── App Store
│   └── reserved for future App Store Connect implementation
│
├── Notes
│   └── NavigationStack
│       └── existing NotesInboxView
│
└── Settings
    └── NavigationStack
        └── existing SettingsView
```

The Apps tab remains the existing custom app-management product. Do not redesign its rows, filtering, editing, app details, or per-app notes.

The current top-level entry points for global Notes and Settings should move to their dedicated tabs when the tab shell is implemented; their underlying screens and behavior should otherwise remain unchanged.

The App Store tab is a reserved product slot only in this PR. App Store Connect integration is explicitly deferred.

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
- GitHub account connection is managed from Settings, not the Repos tab.
- A single shared GitHubSession supplies both Settings and Repos; replacing or disconnecting resets repository navigation.
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
   |     +-- NavigationStack
   |           +-- RepositoriesView
   |                 +-- RepositoryWorkspaceView
   |                       +-- GitLogView
   |                       +-- BranchesView
   |                       +-- TagsView
   |                       +-- ReleasesView
   |
   +-- App Store tab
   |     +-- reserved / future App Store Connect work
   |
   +-- Notes tab
   |     +-- existing NotesInboxView
   |
   +-- Settings tab
         +-- existing SettingsView

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

# Implemented decisions

- GitHub authentication: one personal access token connection for now.
- Credentials: token stored only in Keychain with this-device-only accessibility.
- Token permissions: repository Contents read/write for private repositories and write operations.
- App structure: five visible tabs — Apps, Repos, App Store, Notes, Settings.
- App Store tab: placeholder only; App Store Connect work is deferred.
- Repository ordering: most recently updated first.
- Repository scope: owned, collaborator, and organization-member repositories; forks and archived repositories remain visible.
- Search: repository name, full name, and language.
- Default branch: repository default branch when opening a repository.
- Initial Git history: 40 commits.
- Pagination: explicit Load More.
- Git graph: compact iPhone-first selected-branch history with ref labels and merge topology indication.
- Merge: normal GitHub branch merge with explicit source/destination preview and refresh-before-write.
- Rebase: conservative linear replay only, maximum 100 commits each side; default/protected branches, merge commits, incomplete history, and overlapping changed paths are refused.
- Tags: both lightweight and annotated tags; no tag deletion.
- Releases: existing tags only; default title is `<Repository> <tag>`; notes are editable; draft and prerelease are supported.
- `mycli-build-*` releases: grouped separately as build prereleases.
- Release assets: not uploaded in this version.
- No GitHub data is persisted into `ManagedApp`.

---

# Multi-phase implementation plan

## Phase 0 — Requirements + UX lock

Discussion only. Finalize auth, root tabs, repository list, Git workspace navigation, graph behavior, merge semantics, rebase safety, tag type, and release defaults.

Deliverable: update this document only. No production implementation.

**STOP. Wait for explicit approval.**

## Phase 1 — Root tabs + GitHub foundation

**Status: implemented on PR #2.**

Phase 1 uses a GitHub personal access token (fine-grained or classic) as the initial connection mechanism. The token is validated against the authenticated-user endpoint and stored only in Keychain. Repository loading remains Phase 2.

- introduce the five-tab root architecture: Apps, Repos, App Store, Notes, Settings
- Apps hosts the existing app navigation without redesigning the app list/details
- Repos hosts the new GitHub feature area
- App Store is reserved for future App Store Connect work; no App Store Connect implementation in this PR
- Notes hosts the existing global `NotesInboxView`
- Settings hosts the existing `SettingsView`
- relocate the existing top-level Notes/Settings entry points into their dedicated tabs without redesigning those screens
- add GitHub client/auth abstraction
- store credentials in Keychain
- add connection/error/loading state

Acceptance: Apps, global Notes, and Settings retain their existing behavior; the future App Store slot is isolated; GitHub failures cannot break non-Git tabs.

**STOP. Wait for explicit approval.**

## Phase 2 — Repositories tab

**Status: implemented on PR #2.**

The implementation uses GitHub's authenticated-user repository endpoint, requests owned/collaborator/organization-member repositories, paginates at 100 repositories per request until exhausted, and sorts by most recently updated.

- list all accessible repositories
- private repos
- search/filter
- refresh
- loading/empty/error states
- navigate into repository workspace shell

No Git operations yet.

**STOP. Wait for explicit approval.**

## Git log graph and presentation refinement (PR #4)

- Compute graph lanes from actual parent SHAs, not a fabricated second line for each merge commit.
- Parent-child edges continue between rows at stable column positions, with lanes for additional parents and multiple children.
- Normalize loaded history to child-before-parent (topological) order while retaining the GitHub order when unconstrained.
- Track all visible lanes and keep unfinished parent edges through pagination; do not claim to show branches outside the loaded commits.
- Render lines in a row-height-aware SwiftUI Canvas, making multi-line subjects and reference badges safe.
- Keep history navigation, 40-commit paging, pull-to-refresh, and commit detail/actions unchanged.
- Improve text hierarchy: branch/tag refs, commit subject, author/date, and subdued monospaced SHA.

---

## Phase 3 — Beautified Git log

**Status: implemented on PR #2.**

The log uses GitHub's branches, tags, and paged commits endpoints. The selected branch is switchable from the repository toolbar; commits load 40 at a time. Branch/tag labels are attached by matching ref target SHAs, and merge commits render with a compact secondary graph lane so parent topology remains readable on iPhone.

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

**Status: implemented on PR #2.**

The Branches section now lists repository branches, shows default/protected status, previews ahead/behind state against the default branch, and supports an explicit source → destination merge flow. Before a merge write, MyApps re-fetches both branch heads and recomputes the SHA-based comparison; GitHub's normal branch-merge endpoint performs the actual merge.

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

**Status: implemented on PR #2.**

The first version is deliberately conservative: it handles linear replay ranges, declines merge-commit replay, and declines cases where both sides changed the same paths. It prepares replacement Git objects before updating the source branch, and the final ref update is guarded by GitHub GraphQL `beforeOid` checks for both selected branches.

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

**Status: implemented on PR #2.**

MyApps now lists repository tags and creates both lightweight and annotated tags from the Tags section, commit details, or branch HEADs. The exact target commit SHA is shown before confirmation, tag names are validated locally, duplicates are re-checked against GitHub immediately before creation, and refs/log labels refresh after success.

- tag list
- tag labels in Git log
- create tag from commit
- create tag at branch HEAD
- exact SHA preview
- lightweight/annotated behavior as agreed
- confirmation/errors/refresh

**STOP. Wait for explicit approval.**

## Phase 7 — Releases

**Status: implemented on PR #2.**

The Releases section loads GitHub releases independently from the Git log, separates product releases from `mycli-build-*` build releases, and creates releases only from tags that already exist. Creation supports title, notes, draft, and prerelease settings with duplicate-tag revalidation immediately before the write.

- release list
- product vs `mycli-build-*` grouping
- create release from existing tag
- title + notes
- draft/prerelease options
- confirmation/errors

No release-asset upload initially.

**STOP. Wait for explicit approval.**

## Phase 8 — Release-readiness polish

**Status: complete on PR #2.**

Final static review covered all changed Swift files and the XcodeGen source configuration. No TODO/FIXME/debug placeholders remain in the GitHub feature area. GitHub code remains isolated from `ManagedApp`; credentials remain Keychain-only; completed phase placeholder code was removed; write callbacks and permission guidance were clarified; product tags are preferred when creating releases.

No CI or tests were triggered during this work, per the project constraint.

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
Tab 1 · Apps      = existing custom app list/details
Tab 2 · Repos     = Git history + real repository operations
Tab 3 · App Store = reserved for future App Store Connect apps
Tab 4 · Notes     = existing global notes inbox
Tab 5 · Settings  = existing settings
```