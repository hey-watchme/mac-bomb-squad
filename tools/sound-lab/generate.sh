#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
output="$repo_root/tools/sound-lab/index.html"
assets_dir="$repo_root/tools/sound-lab/assets"
sound_dir="/System/Library/Sounds"

rm -rf "$assets_dir"
mkdir -p "$assets_dir"

{
  printf '%s\n' '<!doctype html>'
  printf '%s\n' '<html lang="ja">'
  printf '%s\n' '<head>'
  printf '%s\n' '  <meta charset="utf-8">'
  printf '%s\n' '  <meta name="viewport" content="width=device-width, initial-scale=1">'
  printf '%s\n' '  <title>Bomb Squad Sound Lab</title>'
  printf '%s\n' '  <style>'
  printf '%s\n' '    :root { color-scheme: light; --bg: #f4efe6; --panel: #fffaf3; --ink: #1f1b16; --muted: #73685c; --line: #d8cbbd; --accent: #b95c35; --accent-2: #255f85; }'
  printf '%s\n' '    * { box-sizing: border-box; }'
  printf '%s\n' '    body { margin: 0; font-family: "Iowan Old Style", "Palatino Linotype", serif; background: radial-gradient(circle at top, #fffdf8, var(--bg)); color: var(--ink); }'
  printf '%s\n' '    main { max-width: 1100px; margin: 0 auto; padding: 40px 24px 56px; }'
  printf '%s\n' '    h1 { margin: 0 0 8px; font-size: 40px; line-height: 1.05; }'
  printf '%s\n' '    p { margin: 0; line-height: 1.55; }'
  printf '%s\n' '    .lede { max-width: 760px; color: var(--muted); font-size: 17px; }'
  printf '%s\n' '    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 16px; margin-top: 28px; }'
  printf '%s\n' '    .card { background: color-mix(in srgb, var(--panel) 92%%, white); border: 1px solid var(--line); border-radius: 18px; padding: 18px; box-shadow: 0 12px 28px rgba(31, 27, 22, 0.06); }'
  printf '%s\n' '    .card h2 { margin: 0 0 8px; font-size: 20px; }'
  printf '%s\n' '    .card small { color: var(--muted); display: block; margin-top: 8px; }'
  printf '%s\n' '    .controls { display: flex; gap: 10px; margin-top: 14px; flex-wrap: wrap; }'
  printf '%s\n' '    button { border: 0; border-radius: 999px; padding: 10px 16px; cursor: pointer; font: inherit; background: var(--accent); color: white; }'
  printf '%s\n' '    button.alt { background: var(--accent-2); }'
  printf '%s\n' '    button.ghost { background: transparent; border: 1px solid var(--line); color: var(--ink); }'
  printf '%s\n' '    audio { width: 100%%; margin-top: 14px; }'
  printf '%s\n' '    .section-title { margin-top: 36px; margin-bottom: 12px; font-size: 25px; }'
  printf '%s\n' '    .meta { margin-top: 10px; color: var(--muted); font-size: 14px; }'
  printf '%s\n' '    .pill { display: inline-block; padding: 4px 10px; border-radius: 999px; background: #f2e0d4; color: #8f4728; font-size: 13px; margin-bottom: 10px; }'
  printf '%s\n' '  </style>'
  printf '%s\n' '</head>'
  printf '%s\n' '<body>'
  printf '%s\n' '  <main>'
  printf '%s\n' '    <h1>Bomb Squad Sound Lab</h1>'
  printf '%s\n' '    <p class="lede">Bomb Squad の開始音・終了音と、macOS 標準のシステム音を横並びで試聴するためのローカルページです。各カードの <code>Play</code> を押すとその場で鳴ります。まずは上の「Current Bomb Squad Cues」で方向性を決めて、その後に下のシステム音から近い質感を探すのが早いです。</p>'
  printf '%s\n' '    <h2 class="section-title">Current Bomb Squad Cues</h2>'
  printf '%s\n' '    <div class="grid">'
  printf '%s\n' '      <section class="card">'
  printf '%s\n' '        <span class="pill">Synth</span>'
  printf '%s\n' '        <h2>Start Cue</h2>'
  printf '%s\n' '        <p>いまの開始音。短い上昇感のある <code>pi</code>。</p>'
  printf '%s\n' '        <div class="controls">'
  printf '%s\n' '          <button type="button" onclick="playCue(cues.start)">Play</button>'
  printf '%s\n' '        </div>'
  printf '%s\n' '        <small>spec: 1180Hz → 1040Hz, 55ms</small>'
  printf '%s\n' '      </section>'
  printf '%s\n' '      <section class="card">'
  printf '%s\n' '        <span class="pill">Synth</span>'
  printf '%s\n' '        <h2>Stop Cue</h2>'
  printf '%s\n' '        <p>いまの終了音。少し落ちる <code>poko</code> 寄り。</p>'
  printf '%s\n' '        <div class="controls">'
  printf '%s\n' '          <button type="button" class="alt" onclick="playCue(cues.stop)">Play</button>'
  printf '%s\n' '        </div>'
  printf '%s\n' '        <small>spec: 720Hz → 540Hz, 90ms</small>'
  printf '%s\n' '      </section>'
  printf '%s\n' '      <section class="card">'
  printf '%s\n' '        <span class="pill">Compare</span>'
  printf '%s\n' '        <h2>Pair Test</h2>'
  printf '%s\n' '        <p>開始音のあと 350ms 後に終了音を鳴らします。体感のセット確認用です。</p>'
  printf '%s\n' '        <div class="controls">'
  printf '%s\n' '          <button type="button" class="ghost" onclick="playPair()">Play Pair</button>'
  printf '%s\n' '        </div>'
  printf '%s\n' '      </section>'
  printf '%s\n' '    </div>'
  printf '%s\n' '    <h2 class="section-title">macOS System Sounds</h2>'
  printf '%s\n' '    <div class="grid">'

  while IFS= read -r file; do
    base_name="$(basename "$file")"
    name="$(printf '%s' "$base_name" | sed 's/\.[^.]*$//')"
    duration="$(afinfo "$file" 2>/dev/null | awk -F: "/estimated duration/ {gsub(/^ +/, \"\", \$2); print \$2; exit}")"
    cp "$file" "$assets_dir/$base_name"
    printf '%s\n' '      <section class="card">'
    printf '        <h2>%s</h2>\n' "$name"
    printf '        <p>%s</p>\n' "system file: <code>$file</code>"
    printf '%s\n' '        <div class="controls">'
    printf '          <button type="button" onclick="document.getElementById('\''audio-%s'\'').play()">Play</button>\n' "$name"
    printf '          <button type="button" class="ghost" onclick="document.getElementById('\''audio-%s'\'').currentTime = 0">Reset</button>\n' "$name"
    printf '%s\n' '        </div>'
    printf '        <audio id="audio-%s" preload="metadata" controls src="./assets/%s"></audio>\n' "$name" "$base_name"
    printf '        <small>duration: %s</small>\n' "$duration"
    printf '%s\n' '      </section>'
  done < <(find "$sound_dir" -maxdepth 1 -type f \( -name '*.aiff' -o -name '*.caf' -o -name '*.wav' \) | sort)

  printf '%s\n' '    </div>'
  printf '%s\n' '    <p class="meta">generated from <code>/System/Library/Sounds</code>. Re-run <code>tools/sound-lab/generate.sh</code> to refresh.</p>'
  printf '%s\n' '  </main>'
  printf '%s\n' '  <script>'
  printf '%s\n' '    const cues = {'
  printf '%s\n' '      start: { startFrequency: 1180, endFrequency: 1040, duration: 0.055, amplitude: 0.18, attack: 0.002, release: 0.02, overtones: [{ multiplier: 2, gain: 0.16 }] },'
  printf '%s\n' '      stop: { startFrequency: 720, endFrequency: 540, duration: 0.09, amplitude: 0.20, attack: 0.002, release: 0.035, overtones: [{ multiplier: 2, gain: 0.14 }, { multiplier: 3, gain: 0.06 }] }'
  printf '%s\n' '    };'
  printf '%s\n' '    let ctx;'
  printf '%s\n' '    function ensureContext() {'
  printf '%s\n' '      if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();'
  printf '%s\n' '      if (ctx.state === "suspended") ctx.resume();'
  printf '%s\n' '      return ctx;'
  printf '%s\n' '    }'
  printf '%s\n' '    function playCue(spec) {'
  printf '%s\n' '      const audio = ensureContext();'
  printf '%s\n' '      const now = audio.currentTime + 0.01;'
  printf '%s\n' '      const osc = audio.createOscillator();'
  printf '%s\n' '      const gain = audio.createGain();'
  printf '%s\n' '      osc.type = "sine";'
  printf '%s\n' '      osc.frequency.setValueAtTime(spec.startFrequency, now);'
  printf '%s\n' '      osc.frequency.exponentialRampToValueAtTime(spec.endFrequency, now + spec.duration);'
  printf '%s\n' '      spec.overtones.forEach((o) => {'
  printf '%s\n' '        const overtone = audio.createOscillator();'
  printf '%s\n' '        const overtoneGain = audio.createGain();'
  printf '%s\n' '        overtone.type = "sine";'
  printf '%s\n' '        overtone.frequency.setValueAtTime(spec.startFrequency * o.multiplier, now);'
  printf '%s\n' '        overtone.frequency.exponentialRampToValueAtTime(spec.endFrequency * o.multiplier, now + spec.duration);'
  printf '%s\n' '        overtoneGain.gain.setValueAtTime(0, now);'
  printf '%s\n' '        overtoneGain.gain.linearRampToValueAtTime(spec.amplitude * o.gain, now + spec.attack);'
  printf '%s\n' '        overtoneGain.gain.linearRampToValueAtTime(0, now + spec.duration);'
  printf '%s\n' '        overtone.connect(overtoneGain).connect(audio.destination);'
  printf '%s\n' '        overtone.start(now);'
  printf '%s\n' '        overtone.stop(now + spec.duration + 0.02);'
  printf '%s\n' '      });'
  printf '%s\n' '      gain.gain.setValueAtTime(0, now);'
  printf '%s\n' '      gain.gain.linearRampToValueAtTime(spec.amplitude, now + spec.attack);'
  printf '%s\n' '      gain.gain.linearRampToValueAtTime(0, now + spec.duration);'
  printf '%s\n' '      osc.connect(gain).connect(audio.destination);'
  printf '%s\n' '      osc.start(now);'
  printf '%s\n' '      osc.stop(now + spec.duration + 0.02);'
  printf '%s\n' '    }'
  printf '%s\n' '    function playPair() {'
  printf '%s\n' '      playCue(cues.start);'
  printf '%s\n' '      setTimeout(() => playCue(cues.stop), 350);'
  printf '%s\n' '    }'
  printf '%s\n' '  </script>'
  printf '%s\n' '</body>'
  printf '%s\n' '</html>'
} > "$output"

echo "Generated $output"
