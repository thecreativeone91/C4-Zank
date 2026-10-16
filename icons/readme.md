# Mini app icons

Put an icon here named after the app's `id` in `apps.json` (e.g. `netflix.png`,
`plex.png`), `custom.png` for the custom mini app, or `zank_android_remote.png`
for the main driver. Any size or aspect works; it is trimmed, centred on a
transparent square and resized for Composer and Navigator.

Fill it from your own box or files:

    python3 tools/import_icons.py from-box <box-ip>
    python3 tools/import_icons.py from-file netflix path/to/image-or-c4z-or-apk

then `python3 tools/build.py`. Images in this folder are git-ignored: app
logos belong to their owners and are not part of this open source project.
