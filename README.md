# MP3Editor

A simple macOS app for editing ID3 tags on MP3 files.

## Features

- Edit common tags: title, artist, album, genre, year, track, disc, BPM, Compilation flag
- Save in place or as a copy

## Download

Grab the latest from the [Releases](../../releases) page. Just unzip and drag to your Applications folder.

## Building from Source

Requires macOS 13.0+ and Python 3. Double-click `build-app.command` to build. The app will be created at `MP3Editor.app`.

## Technical Details

UI built with SwiftUI. ID3 tag reading/writing handled by Python backend using [mutagen](https://mutagen.readthedocs.io/). Swift communicates with Python via JSON over stdin/stdout pipes. Album art transferred as base64-encoded data.

## License

MIT
