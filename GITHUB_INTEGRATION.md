# GitHub Integration

This branch extends the iOS-only MyApps app from the latest `master` with focused GitHub repository tooling.

## Product scope

MyApps remains the personal dashboard for apps the user builds. GitHub features are attached to each `ManagedApp` rather than turning MyApps into a generic GitHub client.

Initial scope:

1. Link a `ManagedApp` to a GitHub repository.
2. Authenticate securely, with credentials stored in Keychain.
3. Browse the repository tree at a selected branch or tag.
4. View text/source files.
5. Browse branches and tags.
6. Create tags from an existing branch, tag, or commit.
7. Keep GitHub data remote/on-demand and avoid persisting repository contents in SwiftData.

Follow-up scope:

- Releases and release creation.
- Actions runs and manual workflow dispatch.
- Lightweight pull-request and issue views where they add value beyond GitHub Mobile.

## Architecture

```text
ManagedApp
   |
   +-- githubRepository: String?
   |
   v
GitHubRepositoryView
   |
   +-- Code / tree
   +-- Branches
   +-- Tags
   +-- Releases       (follow-up)
   +-- Actions        (follow-up)
   |
   v
GitHubClient
   |
   +-- REST API
   +-- Keychain credential
```

## Constraints

- Base all work on the latest `master`.
- Do not merge in the experimental macOS/iCloud work from `develop`.
- Keep the existing iOS navigation and SwiftData model intact except for narrowly required additions.
- Do not store GitHub credentials in SwiftData, UserDefaults, backups, or source control.
- Preserve the existing offline MyApps library; GitHub connectivity is optional.
- Avoid duplicating GitHub Mobile features unless they directly support the repository-management workflow.
