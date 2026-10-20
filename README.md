# MyApps v1.0 P3.5

A lightweight, offline iOS notebook for managing the apps you build and keeping flexible Markdown notes with each app.

## Requirements

- Xcode 26 or newer
- XcodeGen 2.45 or newer
- iOS 26+
- Apple development team `J458WW3452`

## Generate the project

```bash
brew install xcodegen
./generate.sh
```

`generate.sh` removes any stale generated project before recreating `MyApps.xcodeproj`.

## AppFoundation Themes (PR #5)

- MyApps uses the **AppFoundation 0.1.8** package's `ThemeManager`, `ThemeCatalog`, `ThemePickerView`, and scene-wide `.appFoundationTheme(...)` integration.
- **Only** the six built-in Foundation themes appear: **Rose, Sunset, Lavender, Midnight, Paper, Champagne**. MyApps converts each catalog entry to **Free**, including the themes normally tagged Pro in AppFoundation.
- All themes are permanent selections; preview timers, Pro locks, upgrades, paywalls and purchase dependencies are **disabled / not used**. The default for fresh installs is **Rose**.
- Appearance is saved locally with `UserDefaultsThemeStateStore`; explicit legacy `Light` migrates to **Paper**, explicit `Dark` to **Rose**. The previous `System` selector is removed (there is no built-in Foundation theme called System). Backup exports now include the selected free theme ID; older backup manifests with only legacy appearance preferences are still accepted and mapped on restore. Restoring a backup updates the active theme immediately.
- Selecting a theme changes tint, preferred light/dark scheme, screen backgrounds and main content-card surfaces. Notes and Projects keep their app-specific icon designs, which are not theme selections.

## App Store Connect integration (PR #5)

The **App Store** tab lists apps available to a connected App Store Connect team API key, with each app's artwork shown beside its name and bundle ID. Artwork first comes from Apple's included `appStoreIcon` / `buildIcons` resources. When absent or its CDN download fails, MyApps uses a batched public App Store lookup by the exact Apple App ID (checking multiple storefronts), verifies matching IDs and bundle IDs, and tries the returned artwork. Successfully loaded images are cached in memory and via the shared URL cache. Apps with no usable artwork show a stable, colorful gradient tile with initials rather than a blank gray icon. Public lookup happens after the app list is displayed; unreleased apps still appear normally. Tap an app to see a workspace with a title dropdown:

- **Info** — app artwork, name, Apple App ID, bundle ID, SKU, primary locale, Made for Kids, and App Store versions and statuses.
- **Xcode Cloud** — product, workflows (including enabled state), the latest 100 build runs with status and date, and a pushable build detail screen. Each build shows workflow, branch/tag, source commit, timing, issue counts, and build actions. Tap an action to inspect Apple's reported compiler/build issues (with file and line location) and individual test results.

In **Xcode Cloud**, tap **Start Build**, select an enabled workflow, and choose a branch or tag from the workflow's own Git repository. The app confirms the exact workflow and reference before requesting `POST /v1/ciBuildRuns`. After Apple accepts the build, the new run is shown and the build list refreshed. An API key with Xcode Cloud build-start permission is required.

Go to **Settings → App Store Connect** and enter the team key's **Issuer ID**, **Key ID**, and `.p8` signing key. You can also import a `.p8` file. Credentials are validated against Apple's API before being saved or replaced.

Secrets are stored in this device's Keychain (this-device-only), never in SwiftData, UserDefaults, analytics, or library backups. The integration can start Xcode Cloud builds for enabled workflows after confirmation. It does not submit App Store versions, edit workflows, or cancel builds. Access depends on the API key's team/app permissions.

App Store apps and version history use paginated requests. Xcode Cloud build history displays the newest 100 runs returned by the API, sorted by descending build number. Active build history and individual build details refresh every 30 seconds while the relevant screen is active and the app is foregrounded; pull-to-refresh remains available. Diagnostics use Apple's structured build issues and test results APIs, **not** raw Xcode build logs. The app does not currently offer artifact downloads or build cancellation.

The Xcode project is generated from `project.yml`; run `./generate.sh` after pulling changes. The release workflow regenerates the project before building and publishes that exact project as `MyApps-xcodeproj-<tag>.zip` alongside the unsigned app archive for local mycli signing and deployment.

## DeepSeek-powered Notes and AI Profiles (PR #5)

- **Settings → DeepSeek:** store a personal API key securely in the device-only Keychain, validate using `GET /models`, and select either `deepseek-flash` (default, non-thinking for fast edits) or `deepseek-v4-pro`. A key is required for AI requests. Never store the key in notes, UserDefaults, backups, or logs.
- **Settings → AI Profiles:** edit, add, duplicate, delete, or set the default writing profile. A preloaded, editable **Indie Builder** profile matches the author's software-development background, direct communication style, and protected terminology.
- **Notes → sparkle menu:** Proofread, Improve Writing, Shorten, Expand, Summarize, Bullet Points, Professional/Casual Tone, Translate, Custom Rewrite, Lowercase All, Lowercase Except Special Words, Uppercase All, Title Case, and Sentence Case.
- Selected text is transformed when the Runestone editor has a nonempty selection; otherwise the whole note is used. Plain case conversions are local and immediate, with an **Undo Last Transformation** action. AI-powered conversions open a **result review sheet** with original/result text, profile picker, Retry, Replace, Insert Below (when safe), Copy, and Done.
- **Writing candidates:** select **1–3 candidates** (default **1**) in the AI result sheet. The app makes **one JSON-mode DeepSeek API request** for the chosen count, using the strict `{"candidates":["...", "..."]}` prompt/response contract established in `hoangbkit/ai-proxy-server/src/capabilities.ts`. It validates exact count, nonempty and distinct content, protection-token restoration, and existing image references **for every candidate** before offering a segmented candidate picker. Replace, Insert Below, and Copy apply to the selected candidate.
- **Editorial prompts v2:** use action-specific rules instead of one generic rewrite instruction. Proofread makes minimal corrections; Improve Writing emphasizes natural prose and retaining the author's stance; Shorten targets approximately 60–75% of verbose source length; Expand allows only source-supported clarification; Summarize avoids profile-driven inventions; Lowercase Except Special Words changes case only while retaining words and formatting.
- AI profiles are **soft writing preferences, not facts to insert** into a note. Proofreading, translating, summarizing, and case-only actions ignore unrelated biography and style; creative rewrites use relevant preferences only where they do not override the source.
- Multi-candidate requests now specify **distinct editorial directions** (balanced, sharper/leaner, alternative structure) instead of forcing synonym swaps. Proofread and Lowercase Except Special Words intentionally allow **one candidate only** to avoid inventing false alternatives.
- Short numeric protected markers reduce interference with generation. The completion token limit scales with input size and the number of requested candidates. The client still rejects invalid JSON, truncated completions, altered protected Markdown, and duplicate candidates.

- Notes do not change while waiting on DeepSeek. Applying results verifies that the note still matches the original snapshot and the `attachment://` references remain unmodified. Protected Markdown code, URLs and attachments are replaced by immutable placeholders for model requests, restored only when each placeholder survives intact. Unsafe results are rejected.
- Profiles and selected model are stored locally and included in new full backups; older backup packages still restore. **API keys are intentionally excluded.**
- Requests are sent **directly from the device to DeepSeek**. The requested note text and selected profile context leave the device; no request is sent until an AI action is selected. API usage may incur charges.

The Notes editor remains fully usable without an AI key. XcodeGen includes new Swift files under `MyApps` automatically.

## Consistent Sorting (PR #5)

The four sortable root tabs now use the same toolbar menu sections **Sort By** and **Order** and remember their choices across launches:

| Tab | Sort fields | Default |
| --- | --- | --- |
| Repos | Name, Created, Updated | Updated / Descending |
| Apps (App Store Connect) | Name, Bundle ID | Name / Ascending |
| Projects | Name, Created, Updated | Created / Descending |
| Notes | Created, Updated | Updated / Descending |

Every field offers Ascending/Descending, labeled A–Z/Z–A for text and Oldest/Newest for dates. Changing a field selects the sensible initial direction (text ascending, dates descending); users can override it. Each root tab persists its choice independently; existing saved sort-field keys are retained.

Pinned repositories/projects/notes remain ahead of unpinned items in either direction. Project Notes and Add Notes share both sort preferences and comparator with Notes. Repos decodes GitHub's optional `created_at` for the new Created field; missing dates sort last. App Store Connect apps without bundle IDs likewise sort last. Releases sort by published/creation date descending, while tags sort alphabetically, independent of GitHub API response order. Nested workflow/test listings retain their specialized ordering.

## Notes Undo & Redo (PR #5)

- **Undo** and **Redo** are available beside **Done** in the Notes editing keyboard toolbar and under the note's **…** menu (also available in Preview).
- Uses the **existing Runestone native undo manager**, so keyboard typing, Markdown formatting commands, imported image tokens, Preview task checkbox toggles, local text-case changes, and accepted AI edits share one history.
- Programmatic commands are routed through `Runestone.TextView.replace(_:withText:)` with one undo group per action; they no longer reset the text view or bypass native Undo.
- The Runestone editor remains mounted while switching **Edit ↔ Preview**, keeping the undo stack intact. Undo and Redo button availability follows the native undo manager.
- Undo history is **editor-session-only**; it is not persisted across closing a note or relaunching MyApps. The document content remains stored in SwiftData.

## P3.5 changes

- Replaced the basic `UITextView` note editor with Runestone 0.5.2.
- Added line wrapping, an enlarged 18-point editing font without current-line highlighting, overscroll, native find support, spell checking, and more reliable large-note editing.
- Replaced the handwritten Markdown renderer with MarkdownView 3.0.0.
- Added CommonMark rendering, GitHub-style tables and block quotes, and highlighted fenced code blocks.
- Preserved tappable task checkboxes in full preview mode.
- Preserved local `attachment://` images through a custom MarkdownView image renderer while remote image URLs continue through the package renderer.
- Kept the existing Markdown keyboard toolbar and plain-string note storage.
- Increased the internal build number to 11.

## P3.4.1 retained

- Custom `.myappsbackup` package documents with structured JSON metadata and binary asset folders.
- Full pre-restore validation and backward-compatible P3.4 JSON restore.

## P3.4 retained

- Six selectable generated app-icon styles using app initials over polished gradient backgrounds.
- Custom image icons override generated icons and can be reverted to the selected default style.
- Persistent app sorting by name, date created, or last updated.
- Persistent note sorting by date created or last updated in app details and the global Notes inbox.
- Pinned apps and notes remain above unpinned items while respecting the selected order inside each group.
- Full-library backup and destructive-confirmation restore.

## Existing foundations

- Horizontal status-filter pills with colored dots and live app counts.
- Offline SwiftData storage, image attachments, automatic P1/P2 note migration, app metadata, pinning, revenue fields, app deletion choices, and global Notes inbox.
- GitHub-style Markdown preview, fenced-code highlighting, local and remote images, and a Markdown keyboard toolbar.
