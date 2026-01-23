# MP3 Editor

A little macOS app for editing MP3 metadata and audio without the command line or a full DAW.

## Features

- Edit common tags: title, artist, album, genre, year, track, disc, BPM, compilation flag
- Edit album art with drag-and-drop support (displays image dimensions)
- Edit macOS "Where from" download source metadata
- Audio editing: trim, pitch shift, speed adjustment
- Save in place or as a copy

## Building from Source

Requires macOS 13.0+ and Python 3. Double-click `build` or run `./build` to build a self-contained app bundle.

## Technical Details

UI built with SwiftUI. ID3 tag reading/writing handled by Python backend using [mutagen](https://mutagen.readthedocs.io/) and [pydub](https://github.com/jiaaro/pydub) with bundled ffmpeg. Swift communicates with Python via JSON over stdin/stdout pipes. Album art transferred as base64-encoded data.

## License

MIT
