#!/usr/bin/env python3
"""Make quieter local copies of the original Solo Party critical-hit sounds."""

import argparse
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from urllib.parse import urlencode


FILE_IDS = (1240622, 1324858, 1240623, 1324859, 1240624, 1324860)
MEDIA = Path(__file__).resolve().parents[1] / "Media" / "LocalCrit"


def download_clip(file_id, build, path):
    query = urlencode({"version": build})
    subprocess.run(
        [
            "curl", "-fLsS", "--max-time", "30",
            f"https://wago.tools/api/casc/{file_id}?download&{query}", "-o", str(path),
        ],
        check=True,
    )
    with path.open("rb") as audio:
        header = audio.read(4)
    if header != b"OggS":
        raise ValueError(f"FileDataID {file_id} for build {build} did not return Ogg audio")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--source", type=Path, help="Directory containing the original <FileDataID>.ogg files")
    source.add_argument("--build", help="Forever client build to retrieve the originals for from wago.tools")
    args = parser.parse_args()

    with TemporaryDirectory(dir=MEDIA.parent) as temporary:
        directory = Path(temporary)
        for file_id in FILE_IDS:
            source_file = (args.source or directory) / f"{file_id}.ogg"
            if args.build:
                download_clip(file_id, args.build, source_file)
            subprocess.run(
                [
                    "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(source_file),
                    "-af", "volume=-3dB", "-c:a", "libmp3lame", "-q:a", "0", str(directory / f"{file_id}.mp3"),
                ],
                check=True,
            )
        MEDIA.mkdir(exist_ok=True)
        for file_id in FILE_IDS:
            (directory / f"{file_id}.mp3").replace(MEDIA / f"{file_id}.mp3")


if __name__ == "__main__":
    main()
