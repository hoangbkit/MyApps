# MyApps Backup Package Format

## Type

- Filename extension: `.myappsbackup`
- Uniform type identifier: `com.hoangbkit.myapps.backup`
- Conforms to: `com.apple.package`
- Current format version: `2`

A backup is a directory package presented by supported file browsers as one document.

## Layout

```text
<name>.myappsbackup/
├── manifest.json
├── apps.json
├── notes.json
└── Assets/
    ├── AppIcons/
    │   └── <app-uuid>.jpg
    └── Attachments/
        └── <attachment-uuid>.<extension>
```

## Files

### `manifest.json`

Contains the format identifier and version, exporting app version and date, saved preferences, and expected content counts.

### `apps.json`

Contains all app records. A custom icon is referenced through `iconAssetPath`; generated initials-and-gradient icons need no binary asset.

### `notes.json`

Contains all notes, app relationships, legacy checklist records, timestamps, and attachment metadata. Each image attachment is referenced through `assetPath`.

### `Assets`

Stores binary image data separately from JSON. Asset paths are relative to the package root and are validated before restore.

## Restore rules

Before replacing local data, MyApps validates:

- format identifier and supported version;
- manifest counts;
- unique app, note, checklist, and attachment IDs;
- valid app relationships;
- safe relative asset paths; and
- presence of every referenced image.

P3.4 format-version-1 JSON backups remain readable as a legacy import format. P3.4.1 always exports format version 2 packages.
