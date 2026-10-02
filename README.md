# ![record-it icon](icons/record-it.png) record-it

Record your screen and camera at full resolution into separate files

macOS

<!-- media: hero -->
<!-- ![record-it](docs/hero.png) -->
<!-- /media: hero -->

## What it is

This is the recorder I use for my videos. It can record the screen, the camera,
both, or just audio, and when you do both you get a separate file for each so
nothing gets squished into one canvas.

While it's recording, it shows a live dashboard of what's actually being written
to disk, and it shouts at me if something stalls or the mic goes quiet. It also
writes movies in small fragments, so a crash still leaves a file that plays.

## Get it

Paste this into your AI coding agent (Claude Code, Codex, Cursor...):

> Clone https://github.com/mikecann/record-it and make it my own. It's one of Mike
> Cann's personal tools, so read the README first, change anything specific to his
> setup to suit mine, then help me get it running.

### Or set it up by hand

You'll need macOS 14 or later and Xcode or its Command Line Tools with Swift 5.10
or later. Install the command-line tools with `xcode-select --install` if needed.
Video recording needs a hardware H.264 or HEVC encoder. Camera and audio-only
takes also need a separate built-in microphone for the recovery recording.

```bash
git clone https://github.com/mikecann/record-it.git
cd record-it
bash setup_mac.sh
bash install.sh
record-it
```

`setup_mac.sh` builds and signs `~/Applications/Record It.app`. `install.sh` links
this clone's launcher into `~/.local/bin`, or a directory you pass as its first
argument. If that directory isn't on PATH, the installer prints the line to add
to `~/.zshrc` or `~/.bashrc`. Run the installer again after moving the clone.

There are no API keys or `.env` settings. On first use, macOS asks for Screen
Recording, Camera, or Microphone access. If it asks you to restart after granting
Screen Recording access, quit the app and run `record-it` again.

## Using it

Choose **Screen**, **Camera**, **Both**, or **Audio**, select the devices and
output project, then start recording. For screen capture you can choose a whole
display or one window. Stop the take to finalize the files and reveal them in
Finder. **Preview…** lets you check camera framing before a take.

I have a few defaults for my setup: projects under `~/dev/convex/convex-videos`,
a `PA27JCV` display and a `Yeti` microphone. Choose your own devices in the app;
to change the project directory, edit `defaultProjectsRoot` in
`Sources/RecordItApp/RecordingViewModel.swift`. If that folder doesn't exist,
**No Project** saves to `~/Movies/record-it-output`.

You can also use `record-it restart`, `record-it stop`, or `record-it setup`.

## Screenshots

![Record It](docs/header.webp)

![Record It screen and camera capture](docs/ss1.png)

![Record It separate screen and camera recording outputs](docs/ss2.png)

## What it records

- Screen, camera, both, or audio only
- The selected screen at 30 fps, encoded with the selected hardware H.264 or
  HEVC encoder
- A display or individual window. Displays preserve their active framebuffer
  resolution without upscaling; windows capture at the display's pixel scale
- My preferred display is `PA27JCV`, falling back to the first available display
- The selected camera's best format at 30 fps, preferring native 3840 × 2160
- A **Preview…** button beside the camera selector opens a movable, resizable,
  uncropped live framing window without recording audio or creating a file.
  The preview window remembers its last position and size
- Selectable screen audio: **System Sound** or **None**. System Sound captures
  playback from music, browsers, videos, and other Mac apps, not a microphone
- Selectable camera microphone, defaulting to the first input with `Yeti` in its
  name. Camera and audio-only recordings require a primary microphone and a
  separate built-in recovery microphone
- Audio-only mode records AAC in an `audio.m4a` file, preserving the input's
  sample rate and channel count. Mono uses 96 kbps, other channel counts use
  128 kbps. It does not require a display, camera, or video encoder
- Separate `screen.mov` and `camera.mov` files when recording both, preserving each source's full resolution

## Encoder settings

Open **Encoder → Settings…** to choose from the H.264 and HEVC hardware
encoders currently available through VideoToolbox. The rate-control menu only
shows modes supported by the selected encoder:

- **CBR** uses a fixed bitrate target
- **CQP** pins the frame quantization level; lower values give higher quality
  and larger files
- **VBR** uses separate target and maximum bitrates

The selected encoder, rate-control mode, bitrates, and CQP level are saved
automatically and restored on the next launch.

**Screen quality** applies to screen recordings only. The camera always uses
the rate control above.

- **Edit Master** (default) records the screen at 95% constant quality. Dark
  gradients and text hold up to 3× punch-ins in the edit. Expect roughly 5 to
  15 Mbps for typical UI work at 5K, more while video or animation fills
  the screen
- **High** uses 90% constant quality. Text stays sharp, but subtle dark
  gradients can band when zoomed
- **Standard** uses the shared rate control above, the same as the camera

Constant quality spends bits only where the screen changes, so a static screen
stays small. Fixed QP or bitrate settings tuned for a camera starve screen
content: a CQP 30 screen recording averages under 1 Mbps and shows blocky
gradients when zoomed. Encoders without a constant-quality mode fall back to
Standard.

The selected recording mode, **Screen**, **Camera**, **Both**, or **Audio**, is also saved
immediately and restored the next time Record It opens.

## Display resolution

Record It captures the selected display's active framebuffer exactly and never
changes display modes. For example, a display running at 1920 × 1080 HiDPI can
produce a native 3840 × 2160 recording. Use browser, editor, or terminal zoom
when individual application content needs to be larger.

## File names

The file name field defaults to the existing timestamp format, without a file
extension:

```text
2026-07-15_115705
```

You can replace it before recording. Record It adds `-screen.mov`,
`-camera.mov`, or `-audio.m4a` automatically, strips an accidentally entered
`.mov` or `.m4a` extension, and resets the field to a fresh timestamp after every
recording.

## Output folders

The Project menu lists directories under `~/dev/convex/convex-videos`, newest
first.
Click **New…** beside the menu, enter a project name, and choose **Create Project**.
Record It creates the project and its `source` folder in that default location,
then selects it for recording. Existing file and folder names cannot be reused.
Choosing a project saves into its `source` folder, creating it when needed:

```text
~/dev/convex/convex-videos/ai-tips/source/
```

Choosing **No Project** saves into:

```text
~/Movies/record-it-output/
```

Record It can reveal the completed files in Finder after stopping. That setting
is enabled by default and persists between launches.

## Recording diagnostics

While recording, the setup form is replaced with a live dashboard for each
active source. It shows the actual video and audio samples accepted by the
writer, media timeline, current file size, output format, output file name, and
pipeline health. This is writer telemetry, not just a recording timer, so a
green state confirms that media is reaching the output file.

Camera and audio-only recordings also show a live waveform from the selected
microphone. It updates ten times per second and keeps a short rolling history
so speech and silence are visible.

Every camera or audio-only take requires a second physical input. Record It
uses the built-in MacBook Pro microphone and launches a separate helper process
using `AVAudioEngine`, independent of the primary `AVCaptureSession`. The helper
writes a lossless mono recovery track to:

```text
~/Library/Application Support/Record It/Recovery Audio/
```

Recovery tracks use the take name with `-backup-audio.caf`, are intentionally
not opened in Finder after a normal take, and are retained for 14 days. Expired
finalized recovery tracks are removed when a new recording begins. Record It
refuses to start without a distinct built-in recovery microphone. The helper
records through problems and reports them as quiet warnings, since a backup
glitch never damages the main files. If Record It crashes, the helper notices
and closes the backup file cleanly.

Screen recordings use variable-duration frames, so a static screen does not
create a huge duplicate-frame backlog in the 4K hardware encoder. Record It
also watches screen and camera callbacks, every required audio stream, and
sustained encoder backpressure. The dashboard warns after three seconds without
video activity or microphone signal. A problem is raised if required video or
audio callbacks stall for ten seconds, an encoder rejects 60 consecutive
samples, or the selected microphone delivers digital-zero audio below -120 dB
for three seconds. A static screen is not a stall: ScreenCaptureKit stops
sending frames while nothing changes, so silence after an idle frame is ignored. It also detects byte-identical PCM loops from 0.5 to 30
seconds across arbitrary callback boundaries, confirms three seconds of exact
repetition, and monitors AVFoundation interruptions, device disconnection,
Core Audio device-alive state, and sample-rate changes. Ordinary room silence
never raises a problem.

Problems never stop the take. Every source keeps writing, Record It comes to
the front, sounds an alarm, and asks whether to **Keep Recording** or **Stop
Recording**. The dashboard lists each problem with its time into the take, and
a `<take>-problems.txt` file listing the same timecodes is saved next to the
recording so the bad section is easy to find in the edit.

Other protections against losing a take:

- Screen and camera movies are written in five-second fragments. A crash,
  force quit, or power loss leaves a file that plays up to the last fragment.
  A normally stopped file has the standard movie layout.
- Every recorder is finalized independently, so one failing source can't
  abandon another source's file halfway through finalizing.
- A take name that already exists gets a `-2`, `-3` suffix. Existing files are
  never overwritten.
- Recording won't start with less than 10 GB free, and an alarm sounds if free
  space drops below 5 GB mid-take.

Session starts, frame-status changes, 30-second health checks, failures, and
stops are written to:

```text
~/Library/Logs/Record It/record-it.log
```

## Development

```bash
swift test
bash tests/install-test.sh
bash restart.sh
```

`restart.sh` stops the current app, builds a debug app bundle, signs it, stages it
at `~/Applications/Record It.app`, and launches it. When no Apple Development
certificate is installed, the build uses a stable local designated requirement
so macOS privacy permissions survive subsequent ad-hoc rebuilds. The existing
`com.mikerosoft.record-it` bundle ID is kept so existing permissions and settings
continue to apply.

The movie-writer integration tests use real hardware video encoders. On hosted CI
or a machine without encoder access, run:

```bash
RECORD_IT_SKIP_HARDWARE_TESTS=1 swift test
```

This skips only those five video integration tests. Audio encoding and all other
tests still run. Run plain `swift test` on a Mac with hardware encoder access
before changing the recording pipeline.

For an isolated app build, set `RECORD_IT_APP_DIR` to another `.app` path.
`RECORD_IT_BUILD_CONFIGURATION` selects `debug` or `release` for `build-app.sh`,
and `RECORD_IT_CODESIGN_IDENTITY=-` forces ad-hoc signing. Leave the signing
identity unset to use the first available Apple Development certificate.

## More tools

You can find my other tools at [mikerosoft.app](https://mikerosoft.app).

MIT licensed.
