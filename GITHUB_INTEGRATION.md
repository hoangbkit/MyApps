# GitHub Integration

This branch extends the iOS-only MyApps app from the latest `master` with focused GitHub repository tooling.

## Execution rule

This PR is **planning-only until explicitly approved**.

Do not start implementation merely because a phase is documented here. Before every phase:

1. Discuss any remaining product/UX/API requirements with the user.
2. Wait for an explicit go-ahead for that phase.
3. Implement only the approved phase.
4. Stop again after that phase is complete and report what changed.
5. Do not continue to the next phase without another explicit go-ahead.

If a requirement is ambiguous or a choice could materially change the product, stop and ask before implementing it.

Do not set up or trigger CI as part of this GitHub-integration work unless explicitly requested.

## Product direction

MyApps should remain the personal dashboard for apps the user builds. GitHub functionality belongs to each `ManagedApp`; this should not become a generic replacement for GitHub Mobile.

The primary motivation is to make important repository-management workflows usable from iPhone where GitHub Mobile is currently weak, especially:

- browsing the actual repository tree
- changing branch/tag context while browsing
- viewing source/text files
- inspecting branches and tags
- creating tags without needing a desktop terminal

Later phases may extend this into releases and GitHub Actions if those workflows prove useful inside MyApps.

## Constraints

- Base all work on the latest `master`.
- Do not merge in the experimental macOS/iCloud work from `develop`.
- iOS only.
- Preserve the current MyApps navigation and SwiftData architecture unless a narrowly scoped change is required.
- Existing MyApps data remains local-first and usable without GitHub.
- GitHub credentials must never be stored in SwiftData, UserDefaults, backups, logs, or source control.
- GitHub repository contents remain remote/on-demand; do not mirror repositories into SwiftData.
- Prefer native SwiftUI and Foundation APIs.
- Avoid duplicating GitHub Mobile functionality unless it directly helps the intended developer workflow.
- Destructive or repository-writing actions need clear confirmation and error presentation.

## Requirements to settle before implementation

These are intentionally unresolved until discussed:

- authentication method for this personal app
- whether repository linking stores `owner/name`, repository ID, URL, or a combination
- how repositories are selected/linked to a `ManagedApp`
- whether one ManagedApp may link to more than one GitHub repository
- default branch behavior and remembered branch/tag selection
- tree browsing behavior for large repositories and binary files
- source viewer feature level
- lightweight vs annotated tag creation
- exact tag target-selection UX
- whether tag deletion belongs in the first release
- whether Releases and Actions belong in the initial product scope
- how much PR/issue functionality, if any, belongs in MyApps

## Proposed architecture

```text
ManagedApp
   |
   +-- GitHub repository link
   |
   v
GitHubRepositoryView
   |
   +-- Code
   +-- Branches
   +-- Tags
   +-- Releases       later / if approved
   +-- Actions        later / if approved
   |
   v
GitHubClient
   |
   +-- REST API
   +-- authentication provider
   +-- Keychain credential storage
```

The GitHub layer should be isolated from the existing notes/business-data features so GitHub integration can fail or be disconnected without affecting the local MyApps library.

---

# Multi-phase implementation plan

## Phase 0 — Requirements and UX lock

**Status:** discussion only.

Goal: settle the product decisions that affect architecture before code is written.

Discuss and decide:

- authentication approach
- account/repository access expectations
- how a ManagedApp links to its repository
- where GitHub appears in App Detail
- initial navigation structure for Code / Branches / Tags
- write-operation confirmation rules
- exact first-release feature boundary

Deliverable:

- update this document with agreed requirements
- no production implementation

**Stop after Phase 0 and wait for explicit approval.**

## Phase 1 — GitHub foundation

Goal: add the smallest reusable GitHub infrastructure without changing the main product flow.

Likely work:

- GitHub API client
- request/response models required by the approved first-release scope
- authentication abstraction
- secure credential storage in Keychain
- connection/account state
- consistent loading and error handling
- no repository UI beyond what is necessary to validate the foundation

Acceptance direction:

- connection can be established and revoked safely
- credentials never enter SwiftData/backups
- failed/offline GitHub requests do not affect local MyApps data

**Stop after Phase 1 and wait for explicit approval.**

## Phase 2 — Link ManagedApp to GitHub repository

Goal: make GitHub context app-specific.

Likely work:

- minimally extend `ManagedApp` with the agreed repository identity
- repository picker/search/manual-link UX as agreed in Phase 0
- link/unlink/change repository
- surface repository identity in App Detail
- preserve backward migration for existing SwiftData records
- ensure MyApps backup behavior does not accidentally include secrets

Acceptance direction:

- existing ManagedApp records migrate cleanly
- unlinked apps behave exactly as before
- linking is optional
- incorrect/inaccessible repositories have clear recoverable errors

**Stop after Phase 2 and wait for explicit approval.**

## Phase 3 — Repository tree and source viewing

Goal: solve the biggest GitHub Mobile gap first.

Likely work:

- repository root browser
- directory traversal
- branch/tag/ref selector
- file metadata sufficient for navigation
- text/source-file viewer
- explicit handling for unsupported/binary/oversized files
- loading, empty, offline, permission, and not-found states

Avoid turning this into an IDE. Editing repository files is out of scope unless explicitly added later.

Acceptance direction:

- user can open an app, enter GitHub, navigate the real repository tree, switch refs, and inspect source/text files comfortably on iPhone

**Stop after Phase 3 and wait for explicit approval.**

## Phase 4 — Branches and tags

Goal: make refs genuinely useful from iPhone.

Likely work:

- branch list
- tag list
- ref details needed to understand targets
- create-tag flow
- target selection from approved branch/tag/commit sources
- confirmation before creating the tag
- success/failure feedback
- refresh affected views after creation

Tag type and deletion behavior remain dependent on Phase 0 requirements.

Acceptance direction:

- user can reliably create the intended Git tag against the intended commit without using a desktop terminal

**Stop after Phase 4 and wait for explicit approval.**

## Phase 5 — Releases

**Only implement if explicitly approved after the earlier phases.**

Possible scope:

- release list
- release details
- distinguish product releases from `mycli-build-*` prereleases where useful
- create release from an existing tag
- draft/prerelease controls
- release notes input
- optional asset visibility/download metadata

Do not add complex release-asset uploading unless there is a concrete requirement.

**Stop after Phase 5 and wait for explicit approval.**

## Phase 6 — GitHub Actions

**Only implement if explicitly approved.**

Possible scope:

- workflow list
- recent workflow runs
- run status/details
- manual `workflow_dispatch`
- workflow inputs where supported
- rerun/cancel only if clearly useful and approved

This should complement the existing manual release workflow rather than introducing new CI architecture.

**Stop after Phase 6 and wait for explicit approval.**

## Phase 7 — Optional PR/issues integration

**Deferred by default.**

Only add features that materially improve the MyApps developer workflow beyond what GitHub Mobile already does well.

Possible candidates:

- compact open-PR status for the linked repository
- compact open-issue status
- deep links into GitHub Mobile/web for full review

Full PR review, issue management, discussions, notifications, and social GitHub features are explicitly not goals unless later requested.

**Stop after Phase 7.**

## Phase 8 — Release-readiness polish

Only after the approved functional scope is complete:

- accessibility
- loading/error/empty-state consistency
- caching review
- data-migration review
- credential/security review
- backup/restore interaction review
- documentation update
- manual end-to-end validation of approved workflows

Do not expand scope during polish.

---

## Initial priority

Unless requirements discussion changes it, the highest-value path is:

```text
Requirements
    ↓
Secure GitHub connection
    ↓
ManagedApp ↔ repository
    ↓
Repository tree + source viewer
    ↓
Branches + tags
    ↓
Create tag
```

That is the smallest version that directly solves the current iPhone pain point. Releases, Actions, PRs, and issues can remain deferred until the core workflow proves useful.
