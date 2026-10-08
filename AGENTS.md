# Agent guidance for record-it

This repository contains one native macOS Swift app and its recovery-audio helper.
All paths below are relative to this repository's root.

## Working rules

- Use test-first development for non-trivial behaviour changes. Write or update the
  automated test first, then implement the change until the test passes. If there
  is no clean test seam, extract one first.
- When behaviour, UI copy, layout, persistence, or startup changes, update affected
  expectations and rerun the relevant tests.
- Test before committing. Run `swift test` and `bash tests/install-test.sh`, then
  verify the staged app when permissions and hardware are available. Check exits.
- Keep generated build output and binaries out of git.
- `install.sh` only links the launcher into PATH. `setup_mac.sh` stages the app.
  Reinstall the launcher after moving the clone; normal edits need no reinstall.
- Keep the bundle identifier and signing requirements stable so existing macOS
  privacy permissions and preferences survive updates.
- CI sets `RECORD_IT_SKIP_HARDWARE_TESTS=1` to skip the movie-writer hardware tests.
  Leave this unset when verifying the actual hardware encoding pipeline locally.
- Keep shell scripts compatible with the macOS system Bash 3.2.
- Do not add eyebrow or kicker labels to UI designs.
- PR descriptions start with `## Why`, explaining the reason for the change in
  plain, personal language. Avoid em dashes.

## record-it specifics

Native SwiftUI screen and camera recorder for macOS. ScreenCaptureKit records the
selected display and system audio. AVFoundation records the selected camera and
selected microphone. When both are selected, each source gets its own full-resolution
H.264 or HEVC `.mov` file.

### Dev workflow

After any Swift change, run the tests and restart the staged app:

```bash
swift test
bash restart.sh
```

Always launch the staged `~/Applications/Record It.app`. Do not run the raw
SwiftPM executable for permission testing because macOS keys Screen Recording,
Camera, and Microphone permissions to the signed app bundle.
`build-app.sh` signs with the first `Apple Development` identity in the keychain.
That certificate's default designated requirement (bundle ID plus certificate)
stays the same across rebuilds, so TCC permissions persist without help.
The stable-requirement workaround only applies when no Apple Development
identity exists. Then `build-app.sh` falls back to an ad-hoc signature and adds
an explicit `identifier "com.mikerosoft.record-it"` designated requirement.
Do not remove it: the default ad-hoc requirement is the changing binary hash
and invalidates TCC permissions after every rebuild. Grants made under that
ad-hoc requirement carried over to the certificate-signed app on this Mac
without a new prompt. If macOS does prompt once after switching, approve it and
later rebuilds keep the grant.

### Key behaviour

- `PA27JCV` is the preferred display, falling back to the first available display.
  These are personal defaults, not requirements for other users.
- Screen output always preserves the selected display's active framebuffer.
  Record It does not change display modes or upscale screen recordings.
- Screen video uses variable-duration frames. Do not restore the old catch-up
  loop that manufactured every missing 30 fps frame: a long static interval at
  4K can permanently backlog the hardware encoder while audio continues.
- A screen-callback and encoder-backpressure watchdog raises problems visibly
  without stopping the take. Diagnostics are written to `~/Library/Logs/Record It/record-it.log`.
- While recording, the configuration form becomes a live dashboard sourced
  from `MovieWriter` progress. It shows accepted video/audio sample counts,
  media duration, file size, output name, encoder, resolution, and health for
  each active source. Both screen and camera pipelines warn after three seconds
  without activity and raise problems after ten seconds or 60 rejected video samples.
  Static screens are not stalls; the user chooses whether to keep recording or stop.
- The first 4K/30-capable camera is selected by default. On this machine that is
  `Razer Kiyo Pro Ultra`.
- The camera **Preview…** button opens the selected camera in an uncropped 16:9
  titled window that can move and resize, and remembers its frame. It captures
  no audio, writes no file, and stops the camera session before closing.
- The file name field defaults to the timestamp prefix, accepts an override
  without `.mov`, and resets to a fresh timestamp after every recording.
- The selected Screen, Camera, Both, or Audio recording mode persists in `UserDefaults`
  and is restored on the next launch.
- Screen audio defaults to ScreenCaptureKit system playback and can be disabled.
  It does not use a microphone.
- Camera audio is independently selectable and defaults to the first microphone
  whose name contains `Yeti`.
- The webcam's picture runs behind its microphone (a clap test measured 75 ms
  on the Kiyo with the Yeti). **Camera delay** in Settings (default 80 ms, 0 to
  turn it off) places each camera frame that much earlier as `MovieWriter`
  writes it, so the file is in sync for every app. The file is tagged with
  `com.mikerosoft.record-it.camera-delay` (QuickTime metadata, seconds) so
  Tandem doesn't take the delay out a second time. Checked on 2026-10-08:
  with 80 ms, four claps' hands met 5 to 52 ms after their sound (28 ms on
  average, within the Kiyo's frame timing), Mike saw them in sync, and
  Tandem showed "In sync as recorded".
- The encoder menu lists only available VideoToolbox H.264 and HEVC hardware
  encoders. CBR, CQP, and VBR controls are capability-filtered and persist in
  `UserDefaults` between launches.
- Screen recordings use the **Screen quality** preset, default Edit Master
  (VideoToolbox `kVTCompressionPropertyKey_Quality` 0.95). It replaces the
  shared rate control for the screen only; the camera keeps CBR/CQP/VBR.
  Do not route screen capture back through a fixed QP: CQP 30 produced
  under 1 Mbps screen files with blocky gradients at 2-3× zoom.
- Camera and audio-only takes require a distinct built-in recovery microphone.
  The independently signed helper writes recovery audio under
  `~/Library/Application Support/Record It/Recovery Audio/`.
- Projects come from `~/dev/convex/convex-videos`, newest creation date first.
- **New…** beside the Project picker creates a named project and its `source`
  folder under that root, then selects it. Existing names and invalid or hidden
  folder names are rejected without changing the selected project.
- Project recordings go to `<project>/source`; No Project goes to
  `~/Movies/record-it-output`.
- Screen and camera outputs are separate files so neither source is scaled into
  a combined canvas.
- Quitting while recording finishes the active writers before the app exits.

### Key files

| Path | What it is |
|---|---|
| `Sources/RecordItApp/RecordItApplication.swift` | SwiftUI app and controls |
| `Sources/RecordItApp/CameraPreview.swift` | Live camera framing preview + session lifecycle |
| `Sources/RecordItApp/ScreenCaptureHealth.swift` | Screen watchdog + persistent recording diagnostics |
| `Sources/RecordItApp/RecordingTelemetry.swift` | Live writer progress and recording-health model |
| `Sources/RecordItApp/ScreenRecorder.swift` | ScreenCaptureKit pipeline |
| `Sources/RecordItApp/CameraRecorder.swift` | AVFoundation camera + microphone pipeline |
| `Sources/RecordItApp/EncoderSettings.swift` | Hardware encoder discovery + rate-control configuration |
| `Sources/RecordItApp/MovieWriter.swift` | Hardware H.264/HEVC + AAC `.mov` writer |
| `build-app.sh` | Builds, stages, and signs the app bundle |
| `restart.sh` | Stops, rebuilds, and launches the debug app |
