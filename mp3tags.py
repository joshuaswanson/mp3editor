#!/usr/bin/env python3
"""
MP3 tag reader/writer using mutagen.
Used by MP3Editor Swift app for reliable ID3 tag handling.
"""

import sys
import json
from pathlib import Path

try:
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3, TIT2, TPE1, TALB, TCON, TYER, TRCK, TPOS, TBPM, TCMP
except ImportError:
    print(json.dumps({"error": "mutagen not installed. Run: pip3 install mutagen"}))
    sys.exit(1)


def read_tags(filepath: str) -> dict:
    """Read ID3 tags from an MP3 file and return as dict."""
    try:
        audio = MP3(filepath)
        tags = audio.tags

        if tags is None:
            return {
                "title": "", "artist": "", "album": "", "genre": "",
                "year": "", "track": "", "disc": "", "bpm": "", "compilation": False
            }

        def get_text(frame_id):
            frame = tags.get(frame_id)
            if frame and frame.text:
                return str(frame.text[0])
            return ""

        # Parse track number (format: "track/total" or just "track")
        track_str = get_text("TRCK")
        track = track_str.split("/")[0] if track_str else ""

        # Parse disc number
        disc_str = get_text("TPOS")
        disc = disc_str.split("/")[0] if disc_str else ""

        # Compilation flag (TCMP frame, value "1" means true)
        tcmp = tags.get("TCMP")
        compilation = bool(tcmp and tcmp.text and str(tcmp.text[0]) == "1")

        return {
            "title": get_text("TIT2"),
            "artist": get_text("TPE1"),
            "album": get_text("TALB"),
            "genre": get_text("TCON"),
            "year": get_text("TYER") or get_text("TDRC")[:4] if get_text("TDRC") else "",
            "track": track,
            "disc": disc,
            "bpm": get_text("TBPM"),
            "compilation": compilation
        }
    except Exception as e:
        return {"error": str(e)}


def write_tags(filepath: str, data: dict) -> dict:
    """Write ID3 tags to an MP3 file. Preserves existing tags not being modified."""
    try:
        audio = MP3(filepath)

        # Create ID3 tags if they don't exist
        if audio.tags is None:
            audio.add_tags()

        tags = audio.tags

        # Update only the fields provided
        if "title" in data:
            if data["title"]:
                tags["TIT2"] = TIT2(encoding=3, text=data["title"])
            elif "TIT2" in tags:
                del tags["TIT2"]

        if "artist" in data:
            if data["artist"]:
                tags["TPE1"] = TPE1(encoding=3, text=data["artist"])
            elif "TPE1" in tags:
                del tags["TPE1"]

        if "album" in data:
            if data["album"]:
                tags["TALB"] = TALB(encoding=3, text=data["album"])
            elif "TALB" in tags:
                del tags["TALB"]

        if "genre" in data:
            if data["genre"]:
                tags["TCON"] = TCON(encoding=3, text=data["genre"])
            elif "TCON" in tags:
                del tags["TCON"]

        if "year" in data:
            if data["year"]:
                tags["TYER"] = TYER(encoding=3, text=data["year"])
            elif "TYER" in tags:
                del tags["TYER"]

        if "track" in data:
            if data["track"]:
                tags["TRCK"] = TRCK(encoding=3, text=data["track"])
            elif "TRCK" in tags:
                del tags["TRCK"]

        if "disc" in data:
            if data["disc"]:
                tags["TPOS"] = TPOS(encoding=3, text=data["disc"])
            elif "TPOS" in tags:
                del tags["TPOS"]

        if "bpm" in data:
            if data["bpm"]:
                tags["TBPM"] = TBPM(encoding=3, text=data["bpm"])
            elif "TBPM" in tags:
                del tags["TBPM"]

        if "compilation" in data:
            if data["compilation"]:
                tags["TCMP"] = TCMP(encoding=3, text="1")
            elif "TCMP" in tags:
                del tags["TCMP"]

        audio.save()
        return {"success": True}
    except Exception as e:
        return {"error": str(e)}


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: mp3tags.py <read|write> <filepath> [json_data]"}))
        sys.exit(1)

    command = sys.argv[1]
    filepath = sys.argv[2]

    if command == "read":
        result = read_tags(filepath)
    elif command == "write":
        if len(sys.argv) < 4:
            # Read JSON from stdin
            data = json.loads(sys.stdin.read())
        else:
            data = json.loads(sys.argv[3])
        result = write_tags(filepath, data)
    else:
        result = {"error": f"Unknown command: {command}"}

    print(json.dumps(result))


if __name__ == "__main__":
    main()
