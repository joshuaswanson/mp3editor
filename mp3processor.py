#!/usr/bin/env python3
"""
MP3 processor: tag reading/writing and audio processing.
Used by MP3Editor Swift app.
"""

import sys
import json
import base64
import subprocess
import tempfile
import shutil
import plistlib
import xattr
from pathlib import Path

try:
    from mutagen.mp3 import MP3
    from mutagen.id3 import ID3, TIT2, TPE1, TALB, TCON, TYER, TRCK, TPOS, TBPM, TCMP, APIC
except ImportError:
    print(json.dumps({"error": "mutagen not installed. Run: pip3 install mutagen"}))
    sys.exit(1)

try:
    from pydub import AudioSegment
except ImportError:
    AudioSegment = None


def read_tags(filepath: str) -> dict:
    """Read ID3 tags from an MP3 file and return as dict."""
    try:
        audio = MP3(filepath)
        tags = audio.tags

        if tags is None:
            return {
                "title": "", "artist": "", "album": "", "genre": "",
                "year": "", "track": "", "disc": "", "bpm": "", "compilation": False,
                "artwork_data": None, "artwork_mime": None
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

        # Album art (APIC frame)
        artwork_data = None
        artwork_mime = None
        for key in tags.keys():
            if key.startswith("APIC"):
                apic = tags[key]
                artwork_data = base64.b64encode(apic.data).decode("utf-8")
                artwork_mime = apic.mime
                break

        # Get year from TYER (ID3v2.3) or TDRC (ID3v2.4)
        year = get_text("TYER")
        if not year:
            tdrc = get_text("TDRC")
            if tdrc:
                year = tdrc[:4]

        # Read "Where from" macOS extended attribute
        where_from = None
        try:
            attrs = xattr.xattr(filepath)
            if 'com.apple.metadata:kMDItemWhereFroms' in attrs:
                plist_data = attrs['com.apple.metadata:kMDItemWhereFroms']
                urls = plistlib.loads(plist_data)
                if urls:
                    where_from = urls[0]  # First URL is the direct source
        except Exception:
            pass  # Ignore errors reading extended attributes

        return {
            "title": get_text("TIT2"),
            "artist": get_text("TPE1"),
            "album": get_text("TALB"),
            "genre": get_text("TCON"),
            "year": year,
            "track": track,
            "disc": disc,
            "bpm": get_text("TBPM"),
            "compilation": compilation,
            "artwork_data": artwork_data,
            "artwork_mime": artwork_mime,
            "where_from": where_from
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

        # Handle album art
        if data.get("artwork_delete"):
            # Remove all APIC frames
            keys_to_delete = [k for k in tags.keys() if k.startswith("APIC")]
            for key in keys_to_delete:
                del tags[key]
        elif data.get("artwork_data") and data.get("artwork_mime"):
            # Remove existing APIC frames first
            keys_to_delete = [k for k in tags.keys() if k.startswith("APIC")]
            for key in keys_to_delete:
                del tags[key]
            # Add new album art
            image_data = base64.b64decode(data["artwork_data"])
            tags["APIC"] = APIC(
                encoding=3,
                mime=data["artwork_mime"],
                type=3,  # Cover (front)
                desc="Cover",
                data=image_data
            )

        audio.save()

        # Handle "Where from" extended attribute
        if "where_from" in data:
            try:
                attrs = xattr.xattr(filepath)
                if data["where_from"]:
                    # Write the URL as a plist array
                    plist_data = plistlib.dumps([data["where_from"]])
                    attrs['com.apple.metadata:kMDItemWhereFroms'] = plist_data
                elif 'com.apple.metadata:kMDItemWhereFroms' in attrs:
                    # Delete the attribute if empty
                    del attrs['com.apple.metadata:kMDItemWhereFroms']
            except Exception:
                pass  # Ignore errors with extended attributes

        return {"success": True}
    except Exception as e:
        return {"error": str(e)}


def get_waveform(filepath: str, num_samples: int = 200) -> dict:
    """Extract waveform amplitude samples from an MP3 file."""
    if AudioSegment is None:
        return {"error": "pydub not installed. Run: pip3 install pydub"}

    try:
        audio = AudioSegment.from_mp3(filepath)
        duration_ms = len(audio)
        duration_sec = duration_ms / 1000.0

        # Convert to mono for simpler processing
        audio = audio.set_channels(1)

        # Get raw samples
        samples = audio.get_array_of_samples()

        # Calculate samples per chunk
        chunk_size = max(1, len(samples) // num_samples)

        # Extract peak amplitude for each chunk
        waveform = []
        max_amplitude = max(abs(min(samples)), abs(max(samples))) if samples else 1

        for i in range(num_samples):
            start = i * chunk_size
            end = min(start + chunk_size, len(samples))
            if start >= len(samples):
                waveform.append(0.0)
            else:
                chunk = samples[start:end]
                # Get peak amplitude in chunk, normalized to 0-1
                peak = max(abs(min(chunk)), abs(max(chunk))) if chunk else 0
                waveform.append(peak / max_amplitude if max_amplitude else 0)

        return {
            "waveform": waveform,
            "duration": duration_sec
        }
    except Exception as e:
        return {"error": str(e)}


def process_audio(source: str, dest: str, data: dict) -> dict:
    """
    Process audio: trim, pitch shift, speed change.

    data keys:
    - trim_start: float (0.0 to 1.0, percentage of duration)
    - trim_end: float (0.0 to 1.0, percentage of duration)
    - pitch_shift: int (semitones, -12 to +12)
    - speed: float (0.5 to 2.0)
    """
    if AudioSegment is None:
        return {"error": "pydub not installed. Run: pip3 install pydub"}

    try:
        # Load audio
        audio = AudioSegment.from_mp3(source)
        duration_ms = len(audio)

        # Apply trim
        trim_start = data.get("trim_start", 0.0)
        trim_end = data.get("trim_end", 1.0)
        start_ms = int(duration_ms * trim_start)
        end_ms = int(duration_ms * trim_end)
        audio = audio[start_ms:end_ms]

        # Get pitch and speed parameters
        pitch_shift = data.get("pitch_shift", 0)
        speed = data.get("speed", 1.0)

        # If we need pitch or speed changes, use ffmpeg directly
        if pitch_shift != 0 or speed != 1.0:
            # Export trimmed audio to temp file
            with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp_in:
                tmp_in_path = tmp_in.name
                audio.export(tmp_in_path, format="mp3")

            try:
                # Build ffmpeg filter chain
                filters = []

                if pitch_shift != 0:
                    # Pitch shift using rubberband or asetrate+atempo combo
                    # Calculate rate multiplier for pitch (2^(semitones/12))
                    pitch_rate = 2 ** (pitch_shift / 12.0)
                    # asetrate changes pitch but also speed, so we compensate with atempo
                    sample_rate = 44100  # Standard sample rate
                    new_rate = int(sample_rate * pitch_rate)
                    filters.append(f"asetrate={new_rate}")
                    filters.append(f"aresample={sample_rate}")
                    # Compensate for speed change from pitch shift
                    if speed != 1.0:
                        # Combine with user speed adjustment
                        effective_speed = speed
                    else:
                        effective_speed = 1.0
                else:
                    effective_speed = speed

                # Apply speed change with atempo (atempo only accepts 0.5 to 2.0)
                if effective_speed != 1.0:
                    # Chain multiple atempo filters if needed for extreme values
                    remaining_speed = effective_speed
                    while remaining_speed < 0.5 or remaining_speed > 2.0:
                        if remaining_speed < 0.5:
                            filters.append("atempo=0.5")
                            remaining_speed /= 0.5
                        else:
                            filters.append("atempo=2.0")
                            remaining_speed /= 2.0
                    if remaining_speed != 1.0:
                        filters.append(f"atempo={remaining_speed}")

                with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp_out:
                    tmp_out_path = tmp_out.name

                # Run ffmpeg
                filter_str = ",".join(filters) if filters else "anull"
                cmd = [
                    "ffmpeg", "-y", "-i", tmp_in_path,
                    "-af", filter_str,
                    "-acodec", "libmp3lame", "-q:a", "2",
                    tmp_out_path
                ]

                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode != 0:
                    return {"error": f"ffmpeg error: {result.stderr}"}

                # Copy processed file to destination
                shutil.copy2(tmp_out_path, dest)

            finally:
                # Clean up temp files
                Path(tmp_in_path).unlink(missing_ok=True)
                if 'tmp_out_path' in locals():
                    Path(tmp_out_path).unlink(missing_ok=True)
        else:
            # No pitch/speed changes, just export trimmed audio
            audio.export(dest, format="mp3")

        # Copy tags from source to destination
        copy_tags(source, dest)

        return {"success": True}
    except Exception as e:
        return {"error": str(e)}


def copy_tags(source: str, dest: str):
    """Copy ID3 tags from source to destination file."""
    try:
        src_audio = MP3(source)
        if src_audio.tags is None:
            return

        dst_audio = MP3(dest)
        if dst_audio.tags is None:
            dst_audio.add_tags()

        # Copy all tags
        for key, value in src_audio.tags.items():
            dst_audio.tags[key] = value

        dst_audio.save()
    except Exception:
        pass  # Ignore tag copy errors


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: mp3processor.py <command> <filepath> [json_data]"}))
        sys.exit(1)

    command = sys.argv[1]
    filepath = sys.argv[2]

    if command == "read":
        result = read_tags(filepath)
    elif command == "write":
        if len(sys.argv) < 4:
            data = json.loads(sys.stdin.read())
        else:
            data = json.loads(sys.argv[3])
        result = write_tags(filepath, data)
    elif command == "waveform":
        num_samples = 200
        if len(sys.argv) >= 4:
            try:
                num_samples = int(sys.argv[3])
            except ValueError:
                pass
        result = get_waveform(filepath, num_samples)
    elif command == "process":
        if len(sys.argv) < 4:
            print(json.dumps({"error": "process requires destination path"}))
            sys.exit(1)
        dest = sys.argv[3]
        if len(sys.argv) < 5:
            data = json.loads(sys.stdin.read())
        else:
            data = json.loads(sys.argv[4])
        result = process_audio(filepath, dest, data)
    else:
        result = {"error": f"Unknown command: {command}"}

    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Ensure we always output valid JSON even on unexpected errors
        print(json.dumps({"error": f"Unexpected error: {str(e)}"}))
