"""Assemble real Godot takes into a short review cut with original temp music.

Run from repo root. Set FFMPEG_EXE or install imageio-ffmpeg under
.godot/trailer-python. Takes are described by the capture scene's JSON manifest.
"""
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import wave

import numpy as np
from PIL import Image

ROOT = Path.cwd()
WORK = ROOT / '.godot/trailer-work'
OUT = ROOT / 'marketing/trailer/2026-09-11'
sys.path.insert(0, str(ROOT / '.godot/trailer-python'))
FF = os.environ.get('FFMPEG_EXE')
if not FF:
    import imageio_ffmpeg
    FF = imageio_ffmpeg.get_ffmpeg_exe()

def run(args):
    subprocess.run([FF, '-y', '-hide_banner', '-loglevel', 'error', *args], check=True)

def camera(keys):
    """One continuous move between two native-image framing rectangles."""
    assert len(keys) == 2, 'Interior easing points would introduce extra stops'
    assert keys[0][0] == 0
    assert all(b[0] > a[0] for a, b in zip(keys, keys[1:]))
    for _, x, y, width in keys:
        assert 0 < width <= 1600
        assert width / 2 <= x <= 1600 - width / 2
        assert width * 9 / 32 <= y <= 900 - width * 9 / 32

    return {'camera': keys, 'sampling': 'floating-point affine, 60 fps',
            'easing': 'quintic, continuous velocity and acceleration'}

def camera_rect(framing, time):
    a, b = framing['camera']
    u = min(max(time / b[0], 0.0), 1.0)
    # Zero velocity AND acceleration at both endpoints, without interior stops.
    ease = u*u*u*(10 + u*(-15 + 6*u))
    x, y, width = [a[i] + (b[i]-a[i])*ease for i in (1, 2, 3)]
    return x-width/2, y-width*9/32, width, width*9/16

def render_camera(source, start, length, framing, dest):
    """Sample the source with a floating crop, avoiding zoompan's integer window.

    Source gameplay stays at 30 fps. Each source frame is displayed for its
    original 1/30 second, with two distinct 60 Hz camera transforms. No optical
    flow or extra gameplay states are invented.
    """
    count = round(length * 60)
    decoder = subprocess.Popen([FF, '-v', 'error', '-ss', str(start), '-i', str(source),
        '-t', str(length), '-an', '-vf', 'fps=30', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
        'pipe:1'], stdout=subprocess.PIPE)
    encoder = subprocess.Popen([FF, '-y', '-v', 'error', '-f', 'rawvideo', '-pix_fmt',
        'rgb24', '-s', '1280x720', '-r', '60', '-i', 'pipe:0', '-ss', str(start),
        '-i', str(source), '-t', str(length), '-map', '0:v:0', '-map', '1:a:0',
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '17', '-pix_fmt', 'yuv420p',
        '-color_range', 'tv', '-colorspace', 'bt470bg',
        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', str(dest)], stdin=subprocess.PIPE)
    try:
        for frame in range(count):
            if frame % 2 == 0:
                raw = decoder.stdout.read(1600*900*3)
                if len(raw) != 1600*900*3:
                    raise RuntimeError(f'{source.name}: source ended during camera render')
                picture = Image.frombytes('RGB', (1600, 900), raw)
            left, top, width, height = camera_rect(framing, frame/60)
            view = picture.transform((1280, 720), Image.Transform.AFFINE,
                (width/1280, 0, left, 0, height/720, top), Image.Resampling.BICUBIC)
            encoder.stdin.write(view.tobytes())
        encoder.stdin.close()
        decoder.stdout.close()
        decode_code, encode_code = decoder.wait(), encoder.wait()
        if decode_code or encode_code:
            raise RuntimeError(f'Camera render failed: decoder={decode_code}, encoder={encode_code}')
    finally:
        for process in (decoder, encoder):
            if process.poll() is None:
                process.terminate()
                process.wait()

def temp_score(duration, resolve_at):
    """Original D-minor synth sketch: no sampled or licensed third-party material."""
    rate = 48000
    mix = np.zeros((round(duration * rate), 2), dtype=np.float64)
    rng = np.random.default_rng(9112026)
    beat = 60 / 110

    def add(at, signal, gain, pan=0.0):
        start = round(at * rate)
        end = min(len(mix), start + len(signal))
        if start < 0 or end <= start:
            return
        value = signal[:end-start] * gain
        mix[start:end, 0] += value * math.sqrt((1-pan)/2)
        mix[start:end, 1] += value * math.sqrt((1+pan)/2)

    def tone(note, length, decay=4):
        t = np.arange(round(length * rate)) / rate
        freq = 440 * 2 ** ((note - 69)/12)
        env = np.minimum(t / .012, 1) * np.exp(-decay*t) * np.minimum((length-t)/.06, 1)
        return (np.sin(2*np.pi*freq*t) + .16*np.sin(4*np.pi*freq*t)) * env

    chords = [(38, 50, 53, 57), (34, 46, 50, 53), (41, 53, 57, 60), (36, 48, 52, 55)]
    for step in range(math.ceil(duration / (beat/2))):
        at = step * beat / 2
        if at > resolve_at:
            break
        chord = chords[(step // 16) % len(chords)]
        energy = .55 if at < 5.4 else (.8 if at < 13 else 1.0)
        if step % 2 == 0:
            add(at, tone(chord[0], .42, 6), .16 * energy)
        if at > 5.4 or step % 4 == 0:
            note = chord[1 + step % 3] + 12
            add(at, tone(note, .38, 8), .065 * energy, .35 if step % 2 else -.35)
        if step % 4 == 0:
            t = np.arange(round(.24 * rate)) / rate
            kick = np.sin(2*np.pi*(48*t + 8*(1-np.exp(-t*25)))) * np.exp(-t*22)
            add(at, kick, .22 * energy)
        if step % 4 == 2 and at > 5.4:
            t = np.arange(round(.13 * rate)) / rate
            noise = rng.normal(0, .3, len(t))
            snare = (noise + .22*np.sin(2*np.pi*180*t)) * np.exp(-t*34)
            add(at, snare, .13 * energy)
        if at > 13:
            t = np.arange(round(.035 * rate)) / rate
            noise = rng.normal(0, .2, len(t))
            high = noise - np.roll(noise, 1)
            add(at, high * np.exp(-t*120), .045, .3)
    # A held final chord gives the end card room to breathe.
    for note in (38, 50, 53, 57, 62):
        add(resolve_at, tone(note, duration-resolve_at, .65), .045)
    fade = np.minimum(np.arange(len(mix)) / rate / .25, 1)
    fade *= np.minimum((len(mix) - np.arange(len(mix))) / rate / .8, 1)
    mix *= fade[:, None]
    peak = np.max(np.abs(mix))
    if peak > .65:
        mix *= .65 / peak
    path = WORK / 'original-temp-score.wav'
    with wave.open(str(path), 'wb') as wav:
        wav.setparams((2, 2, rate, 0, 'NONE', 'not compressed'))
        wav.writeframes((mix * 32767).astype('<i2').tobytes())
    return path

def main():
    takes = {t['name']: t for t in json.loads((WORK / 'extended-takes.json').read_text())}
    for name in ('ships', 'upgrades', 'lancer_action', 'bulwark_action'):
        takes[name] = json.loads((WORK / f'{name}-takes.json').read_text())[0]
    # A recaptured take, when present, replaces only that segment.
    for name in takes:
        replacement = WORK / f'{name}-takes.json'
        if replacement.exists():
            takes[name] = json.loads(replacement.read_text())[0]
            takes[name]['source'] = name + '.avi'
    if (WORK / 'endcard-filled.avi').exists():
        takes['endcard']['source'] = 'endcard-filled.avi'
    board = 'crop=960:540:320:180,scale=1280:720:flags=lanczos'
    full = 'scale=1280:720:flags=lanczos'
    shots = [
        ('opening', 1.8, 5.4, camera([
            (0, 565, 286, 420), (4.8, 800, 450, 960)])),
        ('draft_dash', 1.4, 2.4, full),
        ('draft_dash', 5.0, 1.5, camera([
            (0, 610, 325, 620), (1.5, 710, 375, 760)])),
        ('draft_dash', 8.5, 1.5, board),
        ('chart', .7, 2.0, full),
        ('ships', 1.2, 3.0, full),
        ('lancer_action', .4, 2.8, camera([
            (0, 875, 335, 720), (2.5, 800, 450, 960)])),
        # Normal-speed excerpts: right launch, stacking, then the capture payoff.
        ('bulwark_action', .5, 1.5, camera([
            (0, 1030, 550, 620), (1.5, 955, 530, 700)])),
        ('bulwark_action', 9.0, 4.8, camera([
            (0, 800, 450, 960), (4.7, 760, 450, 880)])),
        ('bulwark_action', 15.8, 1.7, board),
        ('upgrades', 1.2, 2.7, full),
        ('infestation', .2, 2.6, board),
        ('reactor', .2, 1.0, camera([
            (0, 710, 545, 680), (1.0, 735, 510, 730)])),
        ('reactor', 3.2, 1.9, board),
        ('race', .2, 3.4, full),
        ('rival', .2, 3.0, full),
        ('prism', .2, 2.6, camera([
            (0, 800, 450, 960), (2.5, 840, 440, 880)])),
        ('maw', .2, 3.6, camera([
            (0, 820, 400, 860), (3.2, 800, 435, 1040)])),
        ('endcard', .3, 3.6, full),
    ]
    timeline = []
    timeline_time = 0.0
    clips = []
    for index, (name, offset, length, framing) in enumerate(shots):
        if name == 'opening':
            source, start = WORK / 'opening.avi', offset
        else:
            take = takes[name]
            if take['failed'] and take.get('events', {}).get('hit', 0) < offset + length:
                raise RuntimeError(f'Recapture {name}: a hull loss occurs in the selected range')
            source = WORK / take.get('source', 'extended.avi')
            start = take['start'] + offset
            if offset + length > take['duration'] + 1/30:
                raise RuntimeError(f'{name}: selected range exceeds the recorded take')
        dest = WORK / f'edit-{index:02d}.mp4'
        if isinstance(framing, dict):
            render_camera(source, start, length, framing, dest)
        else:
            run(['-ss', str(start), '-i', str(source), '-t', str(length),
                 '-vf', framing + ',scale=out_range=tv,setsar=1,format=yuv420p', '-r', '60',
                 '-c:v', 'libx264', '-preset', 'fast', '-crf', '17',
                 '-color_range', 'tv', '-colorspace', 'bt470bg',
                 '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', str(dest)])
        clips.append(dest)
        timeline.append({'shot': name, 'at': round(timeline_time, 3), 'length': length,
                         'source': source.name, 'source_start': start, 'framing': framing})
        timeline_time += length
        print(f'Encoded {name}: {timeline_time:.1f}s', flush=True)
    concat = WORK / 'rough-cut-concat.txt'
    concat.write_text(''.join(f"file '{p.as_posix()}'\n" for p in clips))
    joined = WORK / 'rough-cut-native-audio.mp4'
    run(['-f', 'concat', '-safe', '0', '-i', str(concat), '-c', 'copy', str(joined)])
    score = temp_score(timeline_time, timeline[-1]['at'])
    final = OUT / 'galaxtix-roguelite-trailer-rough-v7.mp4'
    run(['-i', str(joined), '-i', str(score), '-filter_complex',
         '[0:a]volume=0.9[g];[1:a]volume=0.8[m];[g][m]amix=inputs=2:duration=first:normalize=0,volume=2.0,alimiter=limit=0.85[a]',
         '-map', '0:v:0', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
         '-t', str(timeline_time), '-movflags', '+faststart', str(final)])
    (OUT / 'rough-v7-timeline.json').write_text(json.dumps(timeline, indent=2))
    run(['-ss', str(timeline_time - 2), '-i', str(final), '-frames:v', '1', str(OUT / 'rough-v7-poster.png')])
    print(f'Wrote {final} ({timeline_time:.1f}s)', flush=True)

if __name__ == '__main__':
    main()
