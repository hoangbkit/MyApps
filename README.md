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

## P3.5 changes

- Replaced the basic `UITextView` note editor with Runestone 0.5.2.
- Added line wrapping, selected-line emphasis, overscroll, native find support, spell checking, and more reliable large-note editing.
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
