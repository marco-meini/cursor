#!/usr/bin/env python3
"""Assemble the allegorical short from stills + placeholder voice."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FRAMES_IN = Path("/opt/cursor/artifacts/assets")
FRAMES = ROOT / "frames"
AUDIO = ROOT / "audio"
VIDEO = ROOT / "video"
FONT_REG = "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf"
FONT_ITA = "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf"
EDGE = os.path.expanduser("~/.local/bin/edge-tts")
W, H, FPS = 1280, 720, 25

SHOTS = [
    # file stem in artifacts, duration seconds, zoom direction
    ("00_vicolo_vuoto", 4.2, "in"),
    ("02_vicolo_arrivo", 4.0, "in"),
    ("01_nunzio_ritratto", 3.8, "in"),
    ("03_teschio_cenere", 3.6, "in"),
    ("04_proclama", 4.2, "in"),
    ("05_fuoco_purgatorio", 4.0, "in"),
    ("06_cenere_sale", 4.2, "out"),
    ("07_sguardo_finale", 4.6, "in"),
    ("08_cartello_clean", 5.4, "in"),
]
XFADE = 0.7


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    print("+", " ".join(str(c) for c in cmd[:12]), "..." if len(cmd) > 12 else "")
    return subprocess.run(cmd, check=True, **kwargs)


def copy_frames() -> None:
    FRAMES.mkdir(parents=True, exist_ok=True)
    if not FRAMES_IN.exists():
        return
    for src in FRAMES_IN.glob("*.png"):
        dst = FRAMES / (src.stem + ".jpg")
        run(
            [
                "ffmpeg", "-y", "-i", str(src),
                "-q:v", "2", str(dst),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def make_title_card() -> Path:
    bg_src = FRAMES / "03_teschio_cenere.jpg"
    if not bg_src.exists():
        bg_src = FRAMES / "00_vicolo_vuoto.jpg"
    im = Image.open(bg_src).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
    im = ImageEnhance.Brightness(im).enhance(0.38)
    im = ImageEnhance.Color(im).enhance(0.7)
    im = im.filter(ImageFilter.GaussianBlur(radius=1.2))
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rectangle((0, 0, W, H), fill=(20, 10, 4, 90))
    draw.rectangle((0, 0, W, 90), fill=(0, 0, 0, 110))
    draw.rectangle((0, H - 90, W, H), fill=(0, 0, 0, 110))

    font_small = ImageFont.truetype(FONT_ITA, 28)
    font_line = ImageFont.truetype(FONT_BOLD, 58)
    ivory = (236, 224, 196, 235)
    muted = (196, 176, 140, 200)

    def center(text: str, y: int, font, fill) -> None:
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) / 2, y), text, font=font, fill=fill)

    center("un'allegoria", 118, font_small, muted)
    center("RICORDATI CHE", 278, font_line, ivory)
    center("TI SEI RIPURGATO", 360, font_line, ivory)
    center("memento te purgatum esse", 470, font_small, muted)

    out = Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB")
    path = FRAMES / "08_cartello_clean.jpg"
    out.save(path, quality=92)
    return path


def make_voice() -> Path:
    AUDIO.mkdir(parents=True, exist_ok=True)
    for name in ("voce_elevenlabs.wav", "voce_elevenlabs.mp3"):
        custom = AUDIO / name
        if custom.exists():
            print(f"using ElevenLabs take {custom}")
            return custom
    placeholder = AUDIO / "voce_placeholder.wav"
    if placeholder.exists() and "--refresh-voice" not in sys.argv:
        print(f"reusing {placeholder}")
        return placeholder
    takes = [
        (
            "voce_1.mp3",
            "-16%",
            "-6Hz",
            "Ricordati che ti sei ripurgato.",
        ),
        (
            "voce_2.mp3",
            "-24%",
            "-8Hz",
            "Ricordati... che ti sei... ripurgato.",
        ),
        (
            "voce_3.mp3",
            "-12%",
            "-5Hz",
            "Ricordati che ti sei ripurgato.",
        ),
    ]
    parts = []
    for name, rate, pitch, text in takes:
        dst = AUDIO / name
        run(
            [
                EDGE,
                "--voice",
                "it-IT-GiuseppeMultilingualNeural",
                f"--rate={rate}",
                f"--pitch={pitch}",
                "--text",
                text,
                "--write-media",
                str(dst),
            ]
        )
        parts.append(dst)

    # Layout on the timeline: silence, line, silence, line, silence, line, tail
    # Matches storyboard beats (arrival / proclamation / purification).
    concat_list = AUDIO / "voce_concat.txt"
    # Hits: arrival/portrait, proclamation, purification look.
    silences = [7.2, 5.4, 4.0, 6.5]
    wavs = []
    for i, dur in enumerate(silences):
        sil = AUDIO / f"sil_{i}.wav"
        run(
            [
                "ffmpeg", "-y", "-f", "lavfi",
                "-i", f"anullsrc=r=24000:cl=mono",
                "-t", str(dur), sil,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wavs.append(sil)
        if i < len(parts):
            wav = AUDIO / f"voce_{i+1}.wav"
            run(
                [
                    "ffmpeg", "-y", "-i", str(parts[i]),
                    "-ar", "24000", "-ac", "1", str(wav),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            wavs.append(wav)

    lines = []
    for w in wavs:
        lines.append(f"file '{w}'")
    concat_list.write_text("\n".join(lines) + "\n")
    mixed = AUDIO / "voce_placeholder.wav"
    run(
        [
            "ffmpeg", "-y", "-f", "concat", "-safe", "0",
            "-i", str(concat_list),
            "-c:a", "pcm_s16le", str(mixed),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return mixed


def make_ambience(duration: float) -> Path:
    AUDIO.mkdir(parents=True, exist_ok=True)
    out = AUDIO / "ambience.wav"
    # Brown noise dust + low drone + a distant bell at the start.
    filter_complex = (
        "anoisesrc=color=brown:amplitude=0.035:duration={d}[n];"
        "sine=frequency=62:duration={d}[d1];"
        "sine=frequency=93:duration={d}[d2];"
        "aevalsrc=sin(2*PI*392*t)*exp(-t*1.6):s=44100:d=3.2[bell];"
        "[n]lowpass=f=700[n2];"
        "[d1]volume=0.07[d1v];"
        "[d2]volume=0.045[d2v];"
        "[bell]volume=0.18[bv];"
        "[n2][d1v][d2v]amix=inputs=3:duration=longest:dropout_transition=0,volume=2.2[bed];"
        "[bed][bv]amix=inputs=2:duration=longest:dropout_transition=2,alimiter=limit=0.85"
    ).format(d=duration)
    run(
        [
            "ffmpeg", "-y", "-filter_complex", filter_complex,
            "-ar", "44100", "-ac", "2", str(out),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return out


def ken_burns(src: Path, dst: Path, seconds: float, direction: str) -> None:
    frames = int(seconds * FPS)
    if direction == "out":
        zexpr = "1.14-0.14*(on/{0})".format(max(frames - 1, 1))
    else:
        zexpr = "1.0+0.12*(on/{0})".format(max(frames - 1, 1))
    vf = (
        f"scale=3600:-1,"
        f"zoompan=z='{zexpr}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
        f":d={frames}:s={W}x{H}:fps={FPS},"
        f"format=yuv420p"
    )
    run(
        [
            "ffmpeg", "-y", "-loop", "1", "-i", str(src),
            "-vf", vf, "-frames:v", str(frames),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
            str(dst),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def concat_xfade(clips: list[Path], dst: Path, durations: list[float]) -> float:
    if len(clips) == 1:
        shutil.copy(clips[0], dst)
        return durations[0]

    inputs = []
    for c in clips:
        inputs += ["-i", str(c)]

    parts = []
    # Chain xfade. After first fade, output duration is d0+d1-xfade, etc.
    current_dur = durations[0]
    last = "[0:v]"
    for i in range(1, len(clips)):
        offset = max(current_dur - XFADE, 0)
        out = f"[v{i}]" if i < len(clips) - 1 else "[vout]"
        parts.append(
            f"{last}[{i}:v]xfade=transition=fade:duration={XFADE}:offset={offset:.3f}{out}"
        )
        last = f"[v{i}]"
        current_dur = current_dur + durations[i] - XFADE

    fc = ";".join(parts)
    run(
        [
            "ffmpeg", "-y", *inputs,
            "-filter_complex", fc, "-map", "[vout]",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
            str(dst),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return current_dur


def mix(video: Path, voice: Path, ambience: Path, duration: float, dst: Path) -> None:
    # Duck ambience a little under the voice.
    fc = (
        f"[1:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo,"
        f"volume=2.4,apad=pad_dur={duration}[v];"
        f"[2:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo,"
        f"volume=0.55,atrim=0:{duration},asetpts=PTS-STARTPTS[a];"
        f"[a][v]amix=inputs=2:duration=first:dropout_transition=2,alimiter=limit=0.9[mix]"
    )
    run(
        [
            "ffmpeg", "-y",
            "-i", str(video),
            "-i", str(voice),
            "-i", str(ambience),
            "-filter_complex", fc,
            "-map", "0:v", "-map", "[mix]",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-shortest",
            str(dst),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> int:
    VIDEO.mkdir(parents=True, exist_ok=True)
    copy_frames()
    make_title_card()

    clip_dir = VIDEO / "clips"
    clip_dir.mkdir(exist_ok=True)
    silent = VIDEO / "picture_silent.mp4"
    if silent.exists() and "--rebuild-picture" not in sys.argv:
        probe = subprocess.check_output(
            [
                "ffprobe", "-v", "error", "-show_entries", "format=duration",
                "-of", "default=nw=1:nk=1", str(silent),
            ],
            text=True,
        ).strip()
        total = float(probe)
        print(f"reusing picture {silent} ({total:.2f}s)")
    else:
        clips = []
        durs = []
        for stem, seconds, direction in SHOTS:
            src = FRAMES / f"{stem}.jpg"
            if not src.exists():
                raise SystemExit(f"missing frame {src}")
            dst = clip_dir / f"{stem}.mp4"
            ken_burns(src, dst, seconds, direction)
            clips.append(dst)
            durs.append(seconds)
        total = concat_xfade(clips, silent, durs)
        print(f"picture duration ~ {total:.2f}s")

    voice = make_voice()
    ambience = make_ambience(total + 1.0)
    out = VIDEO / "ricordati_che_ti_sei_ripurgato.mp4"
    mix(silent, voice, ambience, total, out)
    print(f"wrote {out}")
    run(["ffprobe", "-hide_banner", str(out)])
    return 0


if __name__ == "__main__":
    sys.exit(main())
