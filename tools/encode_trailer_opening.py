"""Encode the opening take with imageio-ffmpeg or FFMPEG_EXE.

Run from the repository root. Framing changes; playback speed is unchanged.
"""
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path('.godot/trailer-python').resolve()))
ffmpeg = os.environ.get('FFMPEG_EXE')
if not ffmpeg:
    import imageio_ffmpeg
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()

source = Path('.godot/trailer-work/opening.avi')
output = Path('marketing/trailer/2026-09-11')
output.mkdir(parents=True, exist_ok=True)

for filename, framing in (
    ('opening-proof-v1.mp4', 'crop=960:540:320:180,scale=1280:720:flags=lanczos'),
    ('opening-full-frame-v1.mp4', 'null'),
):
    subprocess.run([
        ffmpeg, '-y', '-hide_banner', '-loglevel', 'error',
        '-ss', '0.1', '-i', str(source), '-t', '9.8', '-vf', framing,
        '-c:v', 'libx264', '-preset', 'medium', '-crf', '17',
        '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k',
        '-movflags', '+faststart', str(output / filename),
    ], check=True)

subprocess.run([
    ffmpeg, '-y', '-hide_banner', '-loglevel', 'error',
    '-ss', '5.9', '-i', str(output / 'opening-proof-v1.mp4'),
    '-frames:v', '1', str(output / 'opening-poster.png'),
], check=True)
