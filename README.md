# Render Farm for Mac

A small macOS app for students who send Blender files to a school render farm. Before it uploads, it
collects every texture the `.blend` needs, so renders don't come out pink.

- Finds the farm's website on the local network over Bonjour (`_farmrender._tcp`). You can also type
  an address in Settings.
- Shows the site in a web view, so you sign in once and follow your job's progress there.
- Lists your `.blend` files (Spotlight), newest first. You can also choose a file, drag one onto the
  window, drop one on the Dock icon, or use Finder's Open With.
- **Send to farm** runs your own Blender (`/Applications/Blender.app`) in the background on a copy of
  the file (`Resources/collect.py`):
  - It copies every image, UDIM tile, image sequence, sound, font, movie clip, volume, cache and
    linked library into a staging folder.
  - It finds moved files with Spotlight.
  - It saves a copy of the `.blend` with relative paths. Your own file is never changed.
- Files that still can't be found are listed, each with a **Find…** button. The farm also looks for
  them itself.
- Uploads go in 8 MB pieces and continue where they stopped if the Wi-Fi drops.

Requirements: Apple Silicon, macOS 26, Blender in `/Applications`.

## Build

```sh
scripts/build.sh            # dist/Render Farm.app (ad-hoc signed)
swift test                  # unit tests + uploader against Tests/mock_farm.py
Tests/run_collect.sh        # collect.py with the real Blender on generated fixture scenes
```

Use the Swift that ships with Xcode (`/usr/bin/swift`). Some swift.org toolchains don't match the SDK.

## Server side

The farm's website must advertise itself, for example with avahi:
`_farmrender._tcp` on port 80. The upload API is the site's own folder upload: `POST /api/upload`,
`PUT /api/jobs/<id>/files`, then `POST /api/jobs/<id>/check`.
