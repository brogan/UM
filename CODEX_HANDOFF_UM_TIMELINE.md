# Codex Handoff - UM Timeline Editor Session

This note was saved from a Codex session that started in `/Users/broganbunt/SPATIAL` while working on `/Users/broganbunt/UMApp`.

Use this when starting a new Codex thread from `/Users/broganbunt/UMApp`.

Suggested first prompt:

> Please read `/Users/broganbunt/SPATIAL/CODEX_HANDOFF_UM_TIMELINE.md`, `UM_SWIFT_SPEC.md`, and the relevant timeline/canvas code. Continue helping me debug the UM timeline editor. The Loom reference timeline is in `/Users/broganbunt/Loom_2026/Loom_Swift_Integration`, and the Loom engine package used by UMEngine is `/Users/broganbunt/Loom_2026/loom_swift`.

## Project Context

- Current project: `/Users/broganbunt/UMApp`
- GitHub repo: `brogan/UM`
- UM was previously developed with Claude Code.
- Current focus is debugging the timeline editor before addressing remaining architecture items in `UM_SWIFT_SPEC.md`.
- Important distinction: UM has two timeline concepts.
  - `UMTimelinePanel.swift`: Loom-style docked keyframe timeline for camera/layer/sprite driver lanes.
  - `TimelineView.swift`: older recorded-state/cut timeline sheet for cut-based export.
- User's reference implementation is Loom timeline editor in `/Users/broganbunt/Loom_2026/Loom_Swift_Integration/Sources/Loom/Timeline/TimelinePanel.swift`.

## Timeline Files Already Mapped

- `UMApp/UMTimelinePanel.swift`: main keyframe timeline panel.
- `UMApp/UMTimelineTypes.swift`: lane enums, marker and clipboard types, selected KF structs.
- `UMApp/TimelineView.swift`: older recorded-state/cut timeline editor.
- `UMApp/AppController.swift`: playback state, frame range, selected keyframe state, sprite mutation helpers.
- `UMApp/QuickAdjustView.swift`: keyframe inspector fields.
- `UMApp/ContentView.swift`: canvas rendering and sprite drag handling.
- `UMEngine/Sources/UMEngine/Animation/DriverEvaluator.swift`: UM driver evaluation.
- `UMEngine/Sources/UMEngine/Composition/UMSprite.swift`: sprite model and `positionDriver`.

## Issue Investigated

User has a sprite layer with one sprite, wants to move it across screen over 240 frames using the purple `up-arrow` sprite lane while the sprite also has a Wander motion attached.

Observed problems:

1. It was hard to see when purple-lane keyframes were selected. Selected keyframes appeared to get smaller.
2. After creating a keyframe, dragging the sprite on the canvas often created new sprites instead of moving/writing sprite position keyframes.

## Root Causes Found

### Keyframe Selection Visual

In `UMTimelinePanel.drawDiamond`, UM selected keyframes only drew a thin white stroke. Dragged keyframes were enlarged, so selected-but-not-dragged keyframes could read as smaller or weaker.

Loom uses a clearer selected stroke. UM now uses a green outer halo plus white inner edge.

### Sprite Drag / Wander Motion Hit-Test

Sprite rendering used:

```text
base sprite position + parametric Motion Set offset (e.g. Wander) + positionDriver offset
```

But sprite hit-testing used only:

```text
base sprite position + positionDriver offset
```

So if Wander moved the visible sprite away from its base point, clicking the visible sprite missed. The sprite-layer tap fallback then treated the click as empty space and added a new sprite.

The keyframe writer also needed to subtract the current parametric motion offset, otherwise dragging while Wander is active would bake the Wander offset into the purple-lane keyframe value.

## Changes Made This Session

Files modified:

- `/Users/broganbunt/UMApp/UMApp/UMTimelinePanel.swift`
- `/Users/broganbunt/UMApp/UMApp/ContentView.swift`
- `/Users/broganbunt/UMApp/UMApp/AppController.swift`

### `UMTimelinePanel.swift`

Changed `drawDiamond` so selected keyframes draw:

- same base diamond size as normal
- green outer halo at `size + 2`
- white inner stroke

Also factored a `diamondPath(x:y:size:)` helper.

### `ContentView.swift`

Updated sprite canvas drag handling:

- When starting a sprite drag, compute current parametric sprite motion with a new helper `spriteMotion(for:index:frame:gridW:gridH:)`.
- Include that motion in `spriteDragOffset`.
- During keyframe drag, pass the current motion offset into `setSpritePositionKeyframe`.
- Updated `spriteHitTest` to include parametric motion (`motion.dx`, `motion.dy`) plus `positionDriver`.
- Hit-test size now includes parametric scale and has a minimum 6 px half-size.

### `AppController.swift`

Updated `setSpritePositionKeyframe` signature:

```swift
func setSpritePositionKeyframe(id: UUID, frame: Int,
                               canvasX: Double, canvasY: Double,
                               gridW: Double, gridH: Double,
                               motionDX: Double = 0, motionDY: Double = 0)
```

It now stores:

```swift
UMVec2(x: canvasX - sprite.x * gridW - motionDX,
       y: canvasY - sprite.y * gridH - motionDY)
```

This preserves `positionDriver` as the purple-lane additive motion on top of base sprite position and current parametric motion.

## Verification Done

Ran a lightweight Swift parse check on edited files:

```bash
TMPDIR=/private/tmp xcrun swiftc -parse UMApp/UMTimelinePanel.swift UMApp/ContentView.swift UMApp/AppController.swift
```

It exited successfully.

Full `xcodebuild` was not possible in the prior Codex sandbox because Xcode/SwiftPM needed write access to user cache/temp locations and only read access was granted.

## Build / Permission Notes

Existing launcher files:

- `Launcher/build_launcher.sh`
- `Launcher/UMLauncherMain.swift`
- `UM Launcher.app`

Launcher builds with `xcodebuild` into `/tmp/umapp-build` and opens the app.

Permission issue:

- Starting Codex from `/Users/broganbunt/SPATIAL` meant `/Users/broganbunt/UMApp` was outside the main workspace.
- Write access to `UMApp` appeared grantable in prompt output, but actual file writes from this session were still denied outside the original workspace.
- Write access to Xcode/SwiftPM cache folders was not granted, so full build failed at package resolution with `unable to make temporary file: Operation not permitted`.

For next session:

- Start a new Codex thread/chat with workspace folder `/Users/broganbunt/UMApp`.
- Confirm environment context shows `<cwd>/Users/broganbunt/UMApp</cwd>`.
- If full builds still fail, request write access to:
  - `/Users/broganbunt/Library/Developer/Xcode`
  - `/Users/broganbunt/Library/org.swift.swiftpm`
  - `/Users/broganbunt/Library/Caches/org.swift.swiftpm`
  - `/Users/broganbunt/Library/Logs/CoreSimulator`
- Read access is also needed to:
  - `/Users/broganbunt/Loom_2026/Loom_Swift_Integration`
  - `/Users/broganbunt/Loom_2026/loom_swift`

## Worktree Status At Handoff

Modified by Codex:

- `UMApp/AppController.swift`
- `UMApp/ContentView.swift`
- `UMApp/UMTimelinePanel.swift`

Handoff note saved at:

- `/Users/broganbunt/SPATIAL/CODEX_HANDOFF_UM_TIMELINE.md`

Other existing/unrelated untracked items seen and not touched:

- `.claude/`
- `Launcher/generate_icon`
- `Launcher/launch-um`
- `Loom_Sample_Project/`

Do not revert those unless the user explicitly asks.

## Suggested Next Debugging Steps

1. Start app via launcher or full build.
2. Create/open a sprite layer with one sprite and Wander motion.
3. Expand sprite layer in keyframe timeline.
4. Click the purple up-arrow lane to create a position keyframe.
5. Verify selected keyframe is visibly highlighted with green halo.
6. Drag the visible sprite on canvas while `positionDriver.mode == .keyframe`.
7. Confirm no new sprite is created when dragging the visible sprite.
8. Confirm keyframe values change and playback interpolates the sprite across the screen over the intended 240-frame range.

---

## 2026-06-21 Continuation - Sprite Timeline, Export, Launcher, and Project Persistence

This continuation happened from the correct workspace:

- `/Users/broganbunt/UMApp`

The practical goal was to make UM usable for the user's shark test project:

- `/Users/broganbunt/Documents/UM Projects/Sharks in the Sea.umproj/`

That project had two grid layers and one sprite layer (`Shark`). It exposed several related issues: sprite selection missed the visible animated sprite, position keyframes could be written in the wrong coordinate space, fields in Quick Adjust sometimes reverted, layer deletion reset the canvas aspect, background colour did not persist, and video render output did not match the live preview closely enough.

### Sprite Timeline / Sprite Selection Fixes

The main conceptual fix was to consistently treat the visible sprite position as:

```text
base normalized sprite position
+ parametric Motion Set offset
+ sprite positionDriver offset
```

The app previously rendered this combined position but did not always use the same calculation for hit-testing, lasso selection, dragging, and position-keyframe writing. That mismatch made it feel as if the visible shark could not be selected or dragged, especially when a motion set such as Wander was active.

Important changes:

- `ContentView.swift`
  - Sprite hit-testing now includes both Motion Set offset and `positionDriver` offset.
  - Sprite bounds account for current motion scale and resolved shape polygon bounds, not just the nominal base point.
  - Lasso selection works on sprite layers and tests the sprite's visible frame-aware position.
  - Lasso first prefers sprites whose visible centre is inside the rectangle, then falls back to largest bounds intersection.
  - Canvas sprite selection now calls `controller.selectSpriteFromCanvas(...)` so stale timeline keyframe selection is cleared.
  - Dragging a sprite at a selected keyframe writes to the sprite's position driver rather than creating a new sprite.

- `AppController.swift`
  - `setSpritePositionKeyframe(...)` stores a position-driver offset after subtracting the base sprite position and current parametric motion offset.
  - Added `normalizeSpritePositionDrivers()` and call it after project/legacy load so sprite position drivers with keyframes behave as one-shot/clamped movement rather than looping unintentionally.
  - Added `selectSpriteFromCanvas(_:)` to keep canvas sprite selection and timeline keyframe selection from fighting each other.

- `UMTimelinePanel.swift`
  - Selecting or creating sprite keyframes activates the related sprite/layer.
  - Sprite keyframe creation/paste sets the position driver to keyframe mode and loop mode `.once`.
  - Selecting a sprite keyframe seeks the current frame and makes the intended sprite/layer active.
  - Keyframe diamonds now have clearer selected styling.

Practical user guidance established during the session:

- To animate sprite position: create/select a sprite position keyframe, then drag the sprite to the desired visible location at that frame.
- Repeat at later frames for further movement.
- The position driver is an additive motion track over the sprite's base position and any parametric Motion Set output.
- For large off-stage sprites, selection must use the visible, motion-adjusted bounds, not the original small/base sprite location.

### Sprite Field / Scale / Canvas Size Fixes

Related UI problems were fixed while investigating the sprite workflow:

- `QuickAdjustView.swift`
  - Sprite inspector fields now bind to live sprite data rather than a stale snapshot. This fixed numeric fields such as scale reverting to `1` unless entered twice.
  - Canvas size preset/width/height controls now call `setProjectCanvasSize(...)`.

- `AppController.swift`
  - New sprites default to a larger, more visible scale (`2.0`) instead of the tiny legacy-feeling size.
  - `setProjectCanvasSize(width:height:)` updates project canvas dimensions and the per-layer dimensions together.
  - Deleting a layer no longer causes the drawing area to revert to default square proportions; HD proportions should be preserved.

### User Project Investigation

In `Sharks in the Sea.umproj`, the shark layer contained a large intended shark and also a small stray duplicate/older sprite state. The behaviour the user saw was consistent with earlier hit-testing using a stale base position: the app selected or displayed information for the small/base sprite while the visible large/motion-adjusted shark was somewhere else.

The fix was not to special-case that project, but to make selection/drag/keyframe logic evaluate the same visible transform that rendering uses.

### Render Output / Colour Matching

The video output was visibly less saturated and less like the live preview. Several issues were addressed in stages.

Files involved:

- `UMApp/UMExporter.swift`
- `UMApp/ContentView.swift`
- `UMApp/UMColorMapEngine.swift`

Main fixes:

- Added explicit sRGB/Rec.709 colour metadata for video export and pixel buffers.
- Ensured compositing contexts and colour-map sampling use sRGB consistently.
- Switched video codec settings toward a higher-fidelity ProRes-style output for graphics-heavy renders.
- Made export respect layer blend modes.
- Set relevant `ImageRenderer` paths to non-linear colour mode.
- Replaced the earlier per-layer flatten-and-CoreGraphics-composite video path with `UMExportFrameCapture`, a single-pass SwiftUI `Canvas` capture that draws all layers together in the same order and style as the live preview.
- Added a small final preview-match correction in `UMExporter.swift`:

```swift
private let umExportPreviewMatchSaturation = 1.06
private let umExportPreviewMatchBrightness = -0.04
```

Why the single-pass export mattered:

- The old export path rendered layers separately, then composited transparent images afterward.
- That did not match the live Canvas path closely enough, especially for translucent fills, strokes, blend modes, and accumulated overlaps.
- The new path makes video export use the same visual composition logic as the live preview as far as possible.

Image comparisons supplied by the user showed the render became much closer. One measured matched pair before the final tiny correction showed:

- Preview average luma/saturation: `YAVG=145.882`, `SATAVG=45.5967`
- Video average luma/saturation: `YAVG=147.542`, `SATAVG=46.2956`

So the last adjustment reduced the saturation boost slightly and darkened export very slightly.

### Background Colour Persistence

The project background colour was not being saved/restored reliably.

Fix:

- `AppController.ProjectConfig` bumped to version `9`.
- Added `backgroundColor: UMColor?` and `backgroundDraw: Bool?`.
- Save writes current background colour/draw state.
- Load defaults old projects to white / background draw enabled when missing.
- `newDocument` and legacy read paths reset to white/background draw enabled.

Verified in the user's shark project that `config.json` saved `backgroundColor` and `backgroundDraw` after the fix.

### Launcher and Xcode Build Notes

The user normally launches via:

- `/Users/broganbunt/UMApp/UM Launcher.app`

The Dock/launcher-bar icon points to that app bundle. Rebuilding the launcher in place updates the existing Dock shortcut; the user does not need to remove/re-add the icon unless the app is moved or the Dock icon becomes invalid.

Launcher fixes:

- `Launcher/UMLauncherMain.swift`
  - Shows an AppKit alert if build/open fails instead of silently doing nothing.
  - Writes useful log information to `/tmp/um-launcher.log`.

- `Launcher/build_launcher.sh`
  - Rebuilds `UM Launcher.app` in place.
  - Uses a temporary iconset path.
  - If `iconutil` rejects the generated iconset, keeps the existing app icon and continues. This warning is harmless.

Build strategy:

- Lightweight parse checks from Codex work:

```bash
TMPDIR=/private/tmp CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache xcrun swiftc -parse $(rg --files UMApp -g '*.swift')
```

- Full `xcodebuild` from the Codex sandbox may fail because SwiftPM/Xcode wants to write into user cache folders outside the granted workspace. This has produced errors such as `unable to make temporary file` or SwiftPM cache permission failures.
- The launcher build script itself can be rebuilt from Codex, but the app's full Xcode build is often better tested by the user launching `UM Launcher.app` from Finder/Dock.

### Animated Sprite / Sprite Replacement Concept Added to Spec

The user asked about a sprite replacement driver for building loops from multiple sprite states. Current UM already has a related capability: a sprite can use a Motion Set with SEQUENCE cycling over multiple shapes.

However, the better long-term design is a first-class reusable animated sprite asset. Added to `UM_SWIFT_SPEC.md`:

- `15.13 Animated Geometry / Sprite Set Assets (Future)`

The concept separates:

- main timeline = where the sprite goes
- animated geometry / sprite set = how the sprite internally cycles/swims/changes state

This future feature should follow Loom's layered geometry-file model and eventually reuse `LoomEditorKit` when the Loom geometry editor is extracted.

### Current Modified Files Worth Knowing

At the end of this continuation, modified tracked files included:

- `Launcher/UMLauncherMain.swift`
- `Launcher/build_launcher.sh`
- `UM Launcher.app/Contents/MacOS/launch-um`
- `UM Launcher.app/Contents/Resources/UMLauncherMain.swift`
- `UMApp/AppController.swift`
- `UMApp/ContentView.swift`
- `UMApp/QuickAdjustView.swift`
- `UMApp/UMColorMapEngine.swift`
- `UMApp/UMExporter.swift`
- `UMApp/UMTimelinePanel.swift`
- `UM_SWIFT_SPEC.md`

Untracked items seen:

- `.claude/`
- `CODEX_HANDOFF_UM_TIMELINE.md`
- `Loom_Sample_Project/`

Do not revert unrecognised changes. Some changes were made by earlier agents/user work and should be treated as intentional unless the user explicitly asks otherwise.

### Useful Next-Agent Checklist

1. Read this file and `UM_SWIFT_SPEC.md`.
2. Do not assume full `xcodebuild` failures from Codex mean the app is broken; check whether the failure is sandbox/cache related.
3. Use the launcher for user-facing testing when possible.
4. For sprite bugs, always compare render transform, hit-test transform, drag transform, and stored keyframe transform.
5. For export bugs, compare live Canvas drawing with `UMExportFrameCapture` and avoid reintroducing per-layer flattening unless colour/blend behaviour is proved equivalent.
6. For project persistence bugs, inspect `config.json` inside `.umproj` and check `ProjectConfig` version/default paths.
