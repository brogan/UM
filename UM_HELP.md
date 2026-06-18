# UM — User Guide

_Current as of build: 2026-06-18 (rev 13). Covers what is implemented and testable today._

---

## Contents

1. [Overview](#1-overview)
2. [Interface Layout](#2-interface-layout)
3. [Painting Tools](#3-painting-tools)
4. [Grid Transforms](#4-grid-transforms)
5. [Transform Mode — Move vs Stamp](#5-transform-mode--move-vs-stamp)
6. [Phase Policy](#6-phase-policy)
7. [Stretch](#7-stretch)
8. [Playback and Recording](#8-playback-and-recording)
9. [Quick Adjust](#9-quick-adjust)
9b. [Export — Stills and Video](#9b-export--stills-and-video)
10. [Resample Grid](#10-resample-grid)
11. [Undo and Redo](#11-undo-and-redo)
12. [Style Palette and Library](#12-style-palette-and-library)
13. [Save and Load](#13-save-and-load)
14. [What Is Not Yet Implemented](#14-what-is-not-yet-implemented)

---

## 1. Overview

UM is a grid-based drawing and animation program. The workspace is a rows × columns grid; you paint cells on or off and the result plays back as a live animation. The key distinction from a pixel editor is that the grid governs **structure** — adjacency, flip/rotate meaning, what resolution change means — while the *visual* position of each sprite and its *animation phase* are independent per-cell properties that survive every grid operation.

This means:
- You can nudge sprites off their grid centres without losing their grid relationships.
- You can give different cells different animation phases so they don't all animate in lock-step.
- Both of those qualities are preserved when you flip, rotate, or change the grid resolution.

### Animation model

UM has two independent animation layers that compose on every cell, every frame:

**Parametric presets** — attached to a *style*. Six built-in oscillator patterns (Spin, Pulse, Wave, Wander, Jitter, Color Cycle) driven by continuous sine/cosine functions. Fast, zero-setup, ideal for ambient character motion.

**Keyframe motion paths** — attached to individual *cells*. A named, reusable sequence of keyframes (position offset, rotation, scale) that plays back at a set frame rate and loops. Paths are created in the palette, edited in the PATH EDITOR inspector panel, and assigned to selected cells via PLACE & TIME. Multiple cells can share one path; their phase offsets stagger them around the path loop automatically.

Both layers are additive: a cell with the Spin preset and an Orbit path will spin in place *while* following the orbit. Parametric motion sets the sprite's character; the keyframe path sets where it goes.

**Color map** — a project-level image or video source that drives sprite color from sampled pixel data rather than from style settings. When active, UM samples the average color of each grid cell's region from the source image (or the video frame matching the current animation frame) and applies it as the fill and/or stroke color of the sprites in that cell. The source image is never shown directly — it exists purely as a color input. Color map is independent of both animation layers: a sprite can simultaneously follow a keyframe path, use the Jitter preset, and take its color from a video source.

---

## 2. Interface Layout

```
┌──────────────────────────────────────────────────────────┐
│  Tool Strip                                              │
├───────────┬──────────────────────────┬───────────────────┤
│           │                          │                   │
│  Style    │  Grid Canvas             │  Quick Adjust     │
│  Palette  │  (live, animated)        │                   │
│           │                          │                   │
├───────────┴──────────────────────────┴───────────────────┤
│  Transport Bar                                           │
└──────────────────────────────────────────────────────────┘
```

**Tool Strip** — across the top. Contains painting tools, grid transform buttons, the Move/Stamp toggle, Δφ phase offset control, transform buttons, the Phase Policy picker, φ step stepper, Scatter slider, the Stretch checkbox, and the resolution button.

**Style Palette** — left column. Two tabs: **Project** lists styles and paths belonging to this document; **Library** lists the global user library shared across all projects. Click a project style to make it the active painting style. Click a project path to make it the active path for keyframe editing.

**Grid Canvas** — centre. The live, always-animated workspace. The canvas is letterboxed to maintain the output aspect ratio set in the PROJECT section; the neutral grey border outside the canvas is not part of the output. Draw here with the painting tools.

**Quick Adjust** — right column. Collapsible sections for project-wide settings (PROJECT, CANVAS, EXPORT) and per-style or per-cell parameters (ORDER/CHAOS, PLACE & TIME, RENDER, MOTION, PATH EDITOR, SEQUENCE, ADVANCED).

**Transport Bar** — across the bottom. Rewind, play/pause, record, frame counter, and timeline navigation controls.

---

## 3. Painting Tools

The tool buttons appear at the left of the Tool Strip. The active tool is highlighted with an accent background. Click any button to switch tools, or press the keyboard shortcut.

| Button | Key | Tool | What it does |
|---|---|---|---|
| Draw | D | Draw | Click or drag to mark cells as drawn with the active style. |
| Erase | E | Erase | Click or drag to mark cells as undrawn. |
| Select | S | Select | Click to select or deselect cells; Shift-click to add/remove from an existing selection. Drag on an empty area to rubber-band select all drawn cells whose centres fall within the rectangle. Shift-drag extends the current selection. |
| Sample | A | Sample | Click a drawn cell to make its style the active painting style. To go the other direction — apply a style to existing cells — select those cells and use the Style picker in PLACE & TIME. |
| Fill | F | Fill | Flood-fill contiguous undrawn cells with the active style, starting from the clicked cell. Only propagates to 4-connected undrawn neighbours. |
| Nudge | N | Nudge | Click a drawn cell to select it; drag to move its visual position. See [Nudge Tool](#nudge-tool) below. |

Keyboard shortcuts are suppressed when a text field has focus, so they do not interfere with typing in Quick Adjust fields or style names. Shortcuts with no modifier key (D, E, etc.) are also suppressed when Command, Option, or Control is held, so they do not conflict with menu shortcuts.

### Draw tool behaviour

When a cell is drawn:
- It is assigned the currently active Cell Style.
- Its `positionOffset` is set according to the **Scatter** slider in the Tool Strip (see [Spatial Scatter](#spatial-scatter)). At `0` (default), the sprite lands at the exact cell centre.
- Its `phaseOffset` is set according to the **Phase Policy** and **φ step** controls in the Tool Strip (see [Phase Policy](#6-phase-policy)).

Painting is a stroke operation: click and hold, then drag across multiple cells. The entire stroke is a single undo operation.

### Nudge tool

Select one or more cells first (use the **Select** tool or click in **Nudge** mode to auto-select). Then drag to move their visual position.

- The drag delta is accumulated continuously (pixel-accurate, not quantised to cell boundaries).
- The magnitude is stored in **reference-pixel space** so the visual displacement scales correctly when the window is resized or the grid resolution changes.
- The **Place & Time** section in Quick Adjust shows the resulting `positionOffset` values and updates live as you drag.
- Nudging multiple selected cells moves them all by the same delta simultaneously.
- The first touch of a Nudge drag records an undo snapshot; Cmd+Z restores all nudged cells to their pre-drag positions as a single operation.

### Arrow-key nudge

When one or more cells are selected, the arrow keys move their `positionOffset` regardless of which tool is currently active:

| Key | Movement | Distance |
|---|---|---|
| ← → | Left / right | 1 px per press |
| ↑ ↓ | Up / down | 1 px per press |
| Shift + ← → | Left / right | 10 px per press |
| Shift + ↑ ↓ | Up / down | 10 px per press |

The first press in a sequence pushes an undo snapshot; held-key repeats continue nudging without adding further snapshots. One Cmd+Z undoes the entire held-key sequence.

---

## 4. Grid Transforms

Transform buttons appear in the Tool Strip after a divider, to the right of the painting tools.

| Button | Transform | Notes |
|---|---|---|
| ↔ | Flip horizontal | Mirrors drawn cells left–right. `positionOffset.dx` is negated on each cell. |
| ↕ | Flip vertical | Mirrors drawn cells top–bottom. `positionOffset.dy` is negated on each cell. |
| ↺ | Rotate left 90° | Requires a square grid (rows = cols). `positionOffset` vector is rotated 90° left. |
| ↻ | Rotate right 90° | Requires a square grid (rows = cols). `positionOffset` vector is rotated 90° right. |
| ⊡ | Clear all | Marks all cells as undrawn. `positionOffset` and `phaseOffset` values are preserved (the cells are still there, just undrawn). |
| ⊟ | Invert | Toggles the drawn state of every cell. Drawn become undrawn; undrawn become drawn. |

Every transform records a single undo snapshot — one Cmd+Z reverses the entire operation.

**How position offsets survive transforms:** when you flip or rotate the grid, each cell's `positionOffset` vector is transformed geometrically to match. A sprite nudged 10px to the right of its cell centre will, after a horizontal flip, be 10px to the left of the (now-mirrored) cell centre. The spatial arrangement the user built is preserved.

**How phase offsets survive transforms:** flip and rotate do not modify `phaseOffset`. Timing does not mirror geometrically. Each cell carries its phase to its new position unchanged.

---

## 5. Transform Mode — Move vs Stamp

A small **Move | Stamp** toggle sits in the Tool Strip between the painting tools and the transform buttons.

### Move mode (default)

Standard transform behaviour: cells relocate to their transformed positions. The grid "turns over" or "flips". Cells that were at position A are now at position B.

### Stamp mode

Originals stay in place. The transform deposits a copy of all drawn cells at their transformed positions, on top of whatever is already there. This lets you build symmetrical patterns by accumulation:

- Draw a pattern in one quadrant.
- Switch to **Stamp**, click ↔ → the original cells remain and a mirrored copy appears.
- Click ↕ → four-way mirror symmetry built in two clicks.
- Click ↺ → adds a rotated copy; click again → adds another. Each application layers on top.

### Phase offset in Stamp mode (Δφ control)

When in Stamp mode, a **Δφ** control appears next to the toggle. It shows a signed value such as `+8` or `−4`.

Use **−** and **+** to step the value. When a stamp transform is applied, the copied cells receive their `phaseOffset` plus this Δφ value. The original cells are unchanged.

This lets you build patterns where spatially mirrored or rotated copies are also temporally offset — so the copies animate at a different beat from the originals.

Example: draw cells with sequential phases (0, 8, 16…), set Δφ to +24, flip horizontal in Stamp mode → the mirrored copies have phases 24, 32, 40…

Δφ `0` is the neutral case (same as before Stamp mode had phase offset). The control is dimmed and disabled in Move mode.

---

## 6. Phase Policy

A compact popup menu in the Tool Strip controls the **phase policy** — how newly painted cells get their `phaseOffset` assigned. It sits to the right of the transform buttons, followed by the φ step stepper and Scatter slider (both described below), then the Stretch checkbox and resolution button.

| Policy | Effect on new cells |
|---|---|
| Synchronized | `phaseOffset = 0`. All cells animate in lock-step. |
| Random | `phaseOffset = random value (0–119)`. Each cell gets a different starting point. Organic feel. |
| Sequential | `phaseOffset` increments by `phaseStepFrames` in painting order. Creates a travelling wave as you drag. |
| Spatial | `phaseOffset = (row + col) × phaseStepFrames`. Produces a diagonal wave across the grid regardless of paint order. |
| Radial | `phaseOffset = distanceFromCentre × phaseStepFrames`. Rings ripple outward from the grid centre. |

The test grid is loaded with **Sequential** policy (phaseStepFrames = 8), so painted cells receive progressively higher phase offsets.

### Phase step (φ step)

Immediately after the Phase Policy picker, a compact **φ step** stepper controls `phaseStepFrames` — the frame increment used by Sequential, Spatial, and Radial policies. Range: 1–240 frames. Default: 4.

- **Sequential:** each cell painted in sequence gets `phaseOffset = N × phaseStepFrames`, where N is its paint order within the stroke.
- **Spatial:** `phaseOffset = (row + col) × phaseStepFrames`.
- **Radial:** `phaseOffset = distanceFromCentre × phaseStepFrames`.

Larger steps spread cells further around the animation cycle. Smaller steps cluster them together. Synchronized and Random policies ignore this value.

Click **−** / **+** to step by 1 frame at a time. The display shows the value in frames (e.g. `8 fr`).

**Phase offset and motion paths:** `phaseOffset` also controls where each cell enters its keyframe path loop. A field of cells sharing one path but painted with Sequential policy will produce a travelling wave along the path — each sprite is at a different point in the same orbit. This is the primary way to differentiate cells that share a path.

**Important:** changing the policy affects only cells painted after the change. Existing cells keep their current `phaseOffset`. This is intentional — you can deliberately mix policies by painting layers with different settings.

### Spatial Scatter

To the right of the phase step stepper, a **Scatter** slider controls `spatialScatter` (0.0–1.0). When non-zero, each cell painted receives a random `positionOffset` applied at paint time:

- `0` (leftmost, default) — sprites land exactly at cell centres.
- `0.5` — random offset up to ±0.5 × cell dimensions on each axis.
- `1` (rightmost) — random offset up to ±1 full cell width/height on each axis.

Scatter is applied once when a cell is drawn. Existing cells are unaffected by moving the slider — use **Rescatter** in PLACE & TIME to re-scatter selected cells with the current setting.

---

## 7. Stretch

The **Stretch** checkbox in the Tool Strip (immediately left of the resolution label) controls how sprites scale within their cells.

| State | Behaviour |
|---|---|
| Checked (default) | Sprites stretch to fill the full cell width and height independently. A tall narrow cell produces a tall narrow sprite; a wide short cell produces a wide short one. This keeps every cell visually occupied regardless of the grid's aspect ratio. |
| Unchecked | Sprites scale proportionally — the shape fits the largest square inscribed in the cell and is centred. The sprite's proportions are unchanged but the cell corners are empty when the cell is not square. |

Stretch is a global canvas setting, not per-style. It takes effect immediately and can be toggled while playing to compare the two looks in real time.

---

## 8. Playback and Recording

The **Transport Bar** at the bottom of the window controls animation playback and timeline recording.

### Playback controls

| Control | Key | Function |
|---|---|---|
| ⏮ | — | Rewind to frame 0 and return to live mode. Works whether playing or paused. |
| ▶ / ⏸ | Space | Play / Pause. Toggles animation playback at 24 fps. Pausing holds the current frame. |
| ● / ■ | — | Record / Stop recording. See below. |
| Frame counter | — | Shows the current frame number in the form `N fr`. |
| PNG | — | Export the current frame as a PNG still. See [Export](#export-stills-and-video) below. |
| SVG | — | SVG export (not yet implemented). |
| Video | — | Export an animation as a .mov video. See [Export](#export-stills-and-video) below. |

**Space** toggles playback from anywhere in the window, as long as a text field does not have keyboard focus.

The frame counter is unbounded; animation cycles because cell styles loop. Keyframe paths also loop by default (configurable per path in PATH EDITOR).

### Timeline recording

UM can capture a sequence of grid-state snapshots while you paint, forming a **timeline** that drives cut-based animation.

#### How to record

1. Press **●** (Record) in the Transport Bar. Playback starts automatically and the button turns red (■).
2. Paint, erase, and modify the canvas. Every **N frames** (set by the Capture interval in the CANVAS section of Quick Adjust), the current state of the grid is automatically snapped into the timeline.
3. Press **■** (Stop) when done. Playback stops and the recorded states remain.

The **Capture** interval (default 2.0 s = 48 frames) controls the gap between auto-captures. At 2 s, painting for 10 seconds produces roughly 5 states. Adjust it in CANVAS → Capture before recording.

The timeline is capped at 500 states. When the cap is reached, the oldest state is discarded to make room.

#### Navigating recorded states

Once states have been recorded, timeline navigation controls appear in the Transport Bar:

| Control | Function |
|---|---|
| **◀** | Load the previous state into the live canvas. |
| **N/M** (e.g. 3/7) | Shows current position (state 3 of 7). Click to open the Timeline Editor. |
| **▶** | Load the next state into the live canvas. |
| **⏮** | Return to live mode (exits timeline navigation, rewinds to frame 0). |

Loading a state replaces the live canvas with that state's cells and styles. You can paint over it and then continue recording — new captures start from whatever is on the canvas at that moment.

#### Playback with a timeline

When timeline navigation has been used (current position ≥ 0) and you press Play, the timeline advances automatically: each state holds for its set duration, then cuts to the next. After the last state, it loops back to state 1.

Pressing ⏮ exits timeline playback and returns to live mode.

#### Timeline Editor

Click the position indicator (e.g. **3/7**) to open the Timeline Editor sheet.

| Column | Description |
|---|---|
| Number | State index. The currently loaded state is highlighted. |
| → | Load this state into the live canvas. |
| Sprites | Count of drawn cells in this state. |
| Hold slider | Drag to change how long this state holds before cutting to the next. Range: 0.25 s – 10 s. Displayed in seconds. |
| × | Delete this state from the timeline. |

**Clear All** — removes all states from the timeline and closes the editor.

States are saved with the project file (`.umproj`). Loading a project with a timeline preserves the recorded states.

---

## 9. Quick Adjust

The right panel contains collapsible sections. The top three sections (PROJECT, EXPORT, CANVAS) hold project-wide settings that apply regardless of which style is active. The sections below them are per-style or per-cell.

Click a section header to expand or collapse it. A chevron (▶ collapsed / ▼ expanded) indicates the state.

### PROJECT

Controls the fundamental output properties of the document.

| Field | Description |
|---|---|
| Canvas | Preset picker for common output sizes. Choosing a preset sets Width and Height immediately. |
| Width | Output canvas width in pixels. Edit directly for a custom size. |
| Height | Output canvas height in pixels. Edit directly for a custom size. |

**Presets:**

| Preset | Dimensions | Use |
|---|---|---|
| HD 1920×1080 | 1920 × 1080 px | HD video, broadcast |
| 4K 3840×2160 | 3840 × 2160 px | 4K video |
| Square 1080×1080 | 1080 × 1080 px | Social media (default) |
| A4 Portrait | 2480 × 3508 px | A4 print at 300 dpi |
| A4 Landscape | 3508 × 2480 px | A4 landscape at 300 dpi |
| Custom | — | Shown automatically when Width or Height don't match any preset |

The canvas is **letterboxed** on screen: the drawing area always preserves the output aspect ratio regardless of window shape. The neutral grey area outside the canvas boundary is not part of the output.

### EXPORT

Controls the resolution and timing parameters for PNG and video export. These are project-wide settings and apply to both the PNG and Video buttons in the Transport Bar.

| Field | Description |
|---|---|
| Multiplier | Scale factor applied to the canvas dimensions at export time. 1× = native canvas size (e.g. 1080 × 1080). 2× = double (2160 × 2160). 4× or 8× for very high quality stills or large-format output. |
| Scale drawing | When checked (default), stroke widths scale proportionally with the multiplier so lines appear visually identical to the on-screen preview regardless of output size. When unchecked, stroke widths stay at their nominal pixel values and will appear thinner relative to the image at higher multipliers. |
| Output | Read-only display of the actual pixel dimensions that will be written — canvas width × multiplier by canvas height × multiplier. |
| FPS | Frames per second for video export. 24 or 30. |
| Frames | Total number of animation frames to render for video. The duration in seconds is shown alongside (Frames ÷ FPS). Default is 96 frames (4 s at 24 fps). |

**Output resolution** is computed at export time. Changing the canvas size in PROJECT or the multiplier here both affect it — the Output field updates live.

**Scale drawing** is the equivalent of Loom's "Scale Image" toggle. Leave it on for production output; turn it off only if you specifically want the stroke widths unchanged (e.g. when testing at high multiplier to verify geometry rather than final look).

### CANVAS

Controls the appearance of the drawing surface itself, independent of any cell style.

| Field | Description |
|---|---|
| Background | Colour of the canvas background. Default is white. Click the swatch to open the system colour picker. |
| Draw | **Background draw** checkbox. When checked (default), the canvas is cleared to the background colour before each frame is drawn — each frame is a fresh render. When unchecked, each frame's sprites are drawn on top of the previous frame's content without clearing first, accumulating over time. Rewinding to frame 0 clears the accumulation. |
| Capture | The auto-capture interval used during recording (0.5 s – 8.0 s, default 2.0 s). Controls how frequently a grid-state snapshot is added to the timeline while the Record button is active. |
| Grid | "Show grid" checkbox. When checked, lines divide the canvas into cells. Hidden by default. |
| Grid color | Colour and opacity of the grid lines. Default is 50% gray. The picker supports opacity. Dimmed when Show grid is off. |
| Grid width | Stroke width of the grid lines in pixels. Default is 0.5 px. Dimmed when Show grid is off. |

**Background draw and accumulation** — switching Background draw off is the primary way to create time-based build-up effects. Sprites from earlier frames remain visible as new sprites are drawn on top. Combined with a keyframe path or the Wave/Wander presets, this traces visible motion trajectories across the canvas. The accumulation persists until you press the rewind button (⏮) or toggle Background draw back on.

#### Color Map

The bottom of the CANVAS section contains the **Color Map** controls — a divider separates them from the display settings above.

A color map is a static image or video file whose pixel colors are sampled per grid cell and applied to sprite fill and/or stroke color, overriding whatever color the cell's style would have produced. The image itself is never drawn on the canvas; it is used purely as a color source.

**Loading a color source:**

Click **Choose…** to open a file picker. Any common image format (JPEG, PNG, TIFF, HEIC, etc.) or video format (MP4, MOV, M4V) is accepted.

- **Static image** — the image is sampled once at load time. The color grid is fixed for the entire animation: cell (row, col) always receives the average color of the corresponding region of the image.
- **Video** — up to 240 frames are extracted from the video at load time (shown as *N fr extracted* below the controls). During playback, each animation frame maps to the corresponding extracted video frame. Video beyond 240 frames loops within the extracted range by default.

A **photo** icon indicates a static image source; a **film** icon indicates video. A spinner appears while video frames are being extracted — the canvas continues rendering with style colors during this time.

Click the **✕** button to remove the color source and revert all sprites to their style colors.

**Color Map settings (visible when a source is loaded):**

| Field | Description |
|---|---|
| Apply to | **Fill** — sampled color replaces sprite fill only (default). **Stroke** — replaces stroke only. **Both** — replaces fill and stroke simultaneously. |
| Style α | **Preserve** (checked by default) — the sprite keeps its style's fill opacity; only the RGB values come from the image. When unchecked, alpha is also taken from the image (relevant for PNG sources with transparency). |
| Loop | **Loop** (default) — when the animation frame exceeds the extracted frame count, it wraps back to the start. **Clamp** — holds the last extracted frame. Visible for video sources only. |

**How sampling works:**

UM draws the source image into a tiny `rows × cols` pixel buffer — one pixel per grid cell. This is a GPU-accelerated bilinear downscale: the resulting pixel value is effectively the average color of all source pixels that mapped to that cell's region. A 4K image sampled into a 6×6 grid resolves to 36 average colors in microseconds.

**Interaction with styles:**

The color map overrides style fill and/or stroke color. All other style properties — render mode, stroke width, opacity (when Style α is preserved), motion preset, path assignment — are unaffected. Styles continue to define the visual character of sprites; the color map simply recolors them.

The color map applies to all drawn cells equally. There is no per-cell or per-style opt-out in the current build.

**Grid resize:**

When the grid is resampled, the color source is automatically re-sampled at the new grid dimensions. No file reload is needed.

**Saving:**

The color source file path is saved in the `.umproj` JSON. The file itself is not embedded — it is referenced by absolute path. If the project is moved to a different machine or the source file is relocated, the color source will fail to reload and the canvas will fall back to style colors. Copying the source file alongside the project avoids this.

### ORDER / CHAOS

A single slider from Order (left) to Chaos (right). This is the primary creative feel control for a style.

At **Order**: maximum regularity, predictable motion, tight shapes.  
At **Chaos**: subdivision irregularity, position and rotation jitter, unpredictable patterns.

Double-click the slider to reset it to `0` (Order). The full materialisation into concrete subdivision and motion parameters will be wired when the Loom rendering pipeline is integrated.

### PLACE & TIME

Shows and edits the style, spatial, temporal, scale, rotation, and path properties of the currently selected cells. All controls apply simultaneously to every selected cell.

When multiple cells with different values are selected, each control shows the value of the first selected cell. Editing applies to all selected cells at once.

**Style** — reassigns every selected cell to the chosen style immediately.

**Path** — assigns a keyframe motion path to the selected cells. Choose **None** to remove the path assignment. Paths are created and named in the Style Palette; their keyframes are edited in the PATH EDITOR section below.

**Offset X / Offset Y** — the `positionOffset.dx` and `positionOffset.dy` of the selected cell(s), in reference pixels.

**Phase** — the `phaseOffset` of the selected cell(s), in frames. The cell evaluates its animation at `currentFrame + phaseOffset`. This applies to both the parametric motion preset and the keyframe path — cells with different phase offsets are at different positions in the path loop.

**Scale** — a live slider (0.1 – 3.0, double-click to reset to 1.0) controlling the resting-pose size of the sprite. Scale is multiplicative with any scale added by the parametric preset or keyframe path at render time. The X and Y axes are linked by default (proportional scaling); click the link icon to unlock them.

**Rotation** — a live slider (−180° to +180°, double-click to reset to 0°) rotating the sprite counter-clockwise in world space. This is the resting-pose value; animated rotation from the MOTION preset and PATH EDITOR are added on top at render time.

**Rescatter** button — re-randomises the `positionOffset` of each selected cell and re-assigns `phaseOffset` using the current Phase Policy.

### RENDER

Controls the visual appearance of the active style's shapes.

| Field | Description |
|---|---|
| Fill | Colour and opacity of the shape fill. |
| Stroke | Colour and opacity of the shape outline. |
| Width | Stroke width in pixels. |
| Mode | **Filled** — fill only. **Stroked** — outline only. **Fill & Stroke** — both (default). |

### MOTION

Controls the parametric animation preset of the active style. All presets are driven continuously by `currentFrame + cell.phaseOffset`.

| Field | Description |
|---|---|
| Preset | Motion preset. See table below. |
| Speed | Cycle rate multiplier (0–2, default 1). Higher values run the oscillation faster. Double-click to reset. |
| Amount | Amplitude of the effect (0–1, default 0.5). Double-click to reset. |
| Phase | Shifts the starting point of the oscillation within the cycle (0–1). Per-style design parameter, separate from the per-cell phase offset. Double-click to reset. |

**Motion presets:**

| Preset | What it does |
|---|---|
| Static | No motion. Default. |
| Spin | Continuous rotation. At Speed 1, Amount 1: one full rotation every ~3 seconds. |
| Pulse | Sine-wave scale oscillation on both axes simultaneously. |
| Wave | Horizontal sine displacement. Sprites swing left and right. |
| Wander | Slow 2D drift using two sine waves at a golden-ratio frequency ratio. |
| Jitter | High-frequency small-amplitude noise on both axes plus rotation noise. |
| Color Cycle | Rotates fill and stroke hues continuously. Achromatic colours are unaffected. |
| Custom | Reserved — no effect in the current build. |

**Composition with keyframe paths:** MOTION and PATH EDITOR results are additive. Position and rotation add; scale multiplies. A cell can simultaneously have Jitter (organic noise character) and a Bounce path (scripted up-and-down trajectory).

### PATH EDITOR

Edits the keyframe sequence of the currently active path (selected by clicking a path row in the Style Palette).

#### Concepts

A **motion path** is a named sequence of keyframes. Each keyframe specifies a frame number and a set of transform values: position offset, rotation, and scale. At render time the path is evaluated at `currentFrame + cell.phaseOffset` to produce a transform that is added to the cell's parametric motion output.

Position offsets in keyframes are stored in **cell-fraction units**: `1.0` = shift by one full cell width (X) or height (Y). This keeps paths resolution-independent — the same path looks proportionally identical on a 4×4 grid and a 20×20 grid.

Paths **loop by default**: when the current frame passes the last keyframe, evaluation wraps back to the start. Toggle **Loop** off to clamp at the last keyframe instead.

The **duration** is the frame number of the last keyframe. A path with its last keyframe at frame 96 has a 96-frame loop (4 seconds at 24 fps).

Per-cell `phaseOffset` controls where each cell enters the loop. Cells painted with Sequential phase policy will spread around the path at even intervals — a ring of cells on an orbit path will distribute themselves evenly around the orbit without any additional setup.

#### PATH EDITOR controls

| Control | Description |
|---|---|
| Path picker | Selects which path is being edited. Shows all paths in the project. Paths can also be selected by clicking their row in the Style Palette. |
| **+** button | Creates a new empty path, adds it to the project, and selects it for editing. |
| **Trash** button | Deletes the active path from the project and removes its reference from all cells. |
| Name | Editable text field for the path name. |
| Loop | When checked (default), the path loops continuously. When unchecked, evaluation clamps at the last keyframe and holds. |
| Duration | Read-only. Frame number of the last keyframe. |

#### Keyframe list

Each row in the keyframe list shows:

```
[frame]  dx[value]  dy[value]  rot[value]°    [−]
```

Click a row to select it and expand the keyframe editor controls below the list. Click it again to collapse. Only one keyframe can be selected at a time.

The **−** button on each row removes that keyframe. Paths always keep at least 2 keyframes (deletion is disabled at 2).

#### Add keyframe

Below the keyframe list, the **Add at [N] fr** control adds a new keyframe at the specified frame. The initial transform values are interpolated from the path's current state at that frame — inserting a keyframe is non-destructive, meaning the animation is unchanged immediately after insertion. Edit the new keyframe's values to diverge from the interpolated baseline.

Adjust the frame number with the stepper, then click the **+** button to add.

#### Keyframe property editor

When a keyframe is selected, sliders appear for each transform property:

| Field | Range | Unit | Description |
|---|---|---|---|
| Frame | 0 – 9999 | fr | Frame number. Use the stepper; the list re-sorts automatically after each step. |
| Offset X | −3 – 3 | c | Horizontal offset in cell-width fractions. 0 = cell centre. Double-click slider to reset. |
| Offset Y | −3 – 3 | c | Vertical offset in cell-height fractions. 0 = cell centre. Double-click slider to reset. |
| Rotation | −360 – 360 | ° | Rotation in degrees added to the cell's resting-pose rotation and any parametric rotation. Double-click to reset. |
| Scale X | 0.1 – 3 | × | Horizontal scale multiplier. Multiplied with cell scale and parametric scale. Double-click to reset to 1. |
| Scale Y | 0.1 – 3 | × | Vertical scale multiplier. Double-click to reset to 1. |
| Easing | — | — | Interpolation curve from this keyframe to the next one. |

**Easing options:**

| Easing | Shape |
|---|---|
| Linear | Constant rate — uniform motion between keyframes. |
| Ease In | Starts slow, accelerates into the next keyframe. |
| Ease Out | Arrives fast, decelerates into the next keyframe. |
| Ease In/Out | Slow at both ends, fastest through the middle. Default. |
| Step | Holds the FROM keyframe's values until the next keyframe, then jumps instantly. |

#### Typical workflow

1. **Create a path** — click **+** in PATH EDITOR or **+ New Path** in the Style Palette. Two identity keyframes at frames 0 and 48 are created automatically.
2. **Edit keyframe 0** — select it; set Offset X, Y, Rotation, Scale to the starting transform.
3. **Edit keyframe 48** — set the ending transform. With Loop on, the animation will interpolate from 0 → 48 then jump back to 0 smoothly if the values match.
4. **Add intermediate keyframes** — use **Add at [N] fr** for more complex paths. The interpolated initial values keep the motion smooth.
5. **Assign to cells** — select cells in the canvas (Select tool), then choose this path from PLACE & TIME → Path.
6. **Play** — press Space. Cells follow the path. Use Sequential or Spatial phase policy to stagger them.

#### Path library

Paths can be promoted to the global library and imported across projects, in the same way as styles. Use the **↑** button on a path row in the Style Palette's Project tab, or right-click for the context menu.

### SEQUENCE

Controls how the active style cycles through its shapes over time.

| Field | Description |
|---|---|
| Mode | Sequential, All, or Random. Sequential cycles through shapes one at a time; All displays all shapes simultaneously; Random picks a shape each frame. |
| Frames/Step | How many animation frames each shape holds before advancing. Range: 1–240 frames. |

### ADVANCED

Collapsed by default. Will contain subdivision parameters and animation driver controls in a future build.

---

## 9b. Export — Stills and Video

The **PNG** and **Video** buttons in the Transport Bar produce output files from the current canvas state. Export settings are configured in the EXPORT section of Quick Adjust (see [§9 EXPORT](#export)).

### PNG export

Renders the current frame at the configured output resolution and saves it as a PNG.

1. Set **Multiplier** and **Scale drawing** in EXPORT.
2. Navigate to the frame you want to export (pause, scrub, or leave at frame 0).
3. Click **PNG** in the Transport Bar.
4. A save panel opens, defaulted to a `renders/stills/` directory alongside the saved project file. The suggested filename is `<projectname>_YYYYMMDD_HHmmss.png`.
5. Choose a location and click Save.

The image is rendered at `canvasWidth × multiplier` × `canvasHeight × multiplier` pixels using `ImageRenderer` — the same drawing code as the live canvas but at the target resolution. If **Background draw** is off (accumulation mode), the current accumulation buffer is composited as the background layer before rendering the current frame.

### Video export

Renders a sequence of animation frames and writes a `.mov` file using H.264.

1. Set **Multiplier**, **Scale drawing**, **FPS**, and **Frames** in EXPORT.
2. Click **Video** in the Transport Bar.
3. A save panel opens, defaulted to a `renders/animations/` directory alongside the project file.
4. Choose a location and click Save. The save panel closes immediately and export begins in the background.
5. A progress bar replaces the Video button in the Transport Bar. It shows `N%` as frames are rendered. The UI remains responsive during export.
6. When export completes the Video button returns.

**Accumulation mode in video:** if **Background draw** is off, each exported frame composites onto the previous frame's output, exactly as it appears on screen during live playback. The exported video correctly shows the build-up over time.

**Render directories** are created automatically on first use alongside the saved project file:
```
<project_dir>/renders/stills/       ← PNG exports
<project_dir>/renders/animations/   ← video exports
```
If the project has not yet been saved, the save panel defaults to `~/Documents/UM Projects/renders/`.

**Codec:** H.264 in a `.mov` container. ProRes and HEVC are available in Loom's exporter and may be added to UM in a future build.

---

## 10. Resample Grid

Click the resolution label (e.g. **6 × 6**) at the far right of the Tool Strip to open the Resample Grid sheet.

The grid always fills the full output canvas: columns divide the canvas width equally, rows divide the canvas height equally. Cells are rectangular — their aspect ratio depends on the row/column count and the canvas dimensions set in PROJECT.

### TARGET SIZE

Set the destination dimensions directly:

- **Rows** — number of rows in the new grid.
- **Cols** — number of columns in the new grid.

### SCALE FACTOR

Type a decimal multiplier in the **Factor** field and click **Apply** to scale the current target dimensions:

- `2` — doubles both rows and cols.
- `0.5` — halves both rows and cols.
- Apply can be used repeatedly.

### RESIZE POLICIES

**Offset policy:**

| Option | Effect |
|---|---|
| Preserve | Position offsets copy unchanged (default). |
| Scale | Offsets scale proportionally with the change in cell size. |
| Reset | All position offsets are zeroed. |

**Phase policy:**

| Option | Effect |
|---|---|
| Inherit | Phase offsets copy unchanged (default). |
| Scatter | Each cell inherits its source phase plus a random perturbation. The Scatter slider controls magnitude. |
| Reset | All phase offsets are zeroed. |

Path assignments (`pathID`) are preserved across all resize policies — if a cell was assigned to a path, it remains assigned after resampling.

### Resample button

Applies nearest-neighbour centre-to-centre mapping. **Cancel** (Escape) closes the sheet without changes. Both actions are undoable.

---

## 11. Undo and Redo

| Shortcut | Action |
|---|---|
| Cmd+Z | Undo the last operation |
| Cmd+Shift+Z | Redo |

**What is recorded as a single undo step:**
- Each paint stroke (from first touch to release), regardless of how many cells it crosses.
- Each grid transform (flip, rotate, clear, invert).
- Each stamp transform.
- Each resample.
- Each nudge drag (from first touch to release).
- Each arrow-key nudge sequence.
- Each Rescatter operation.
- Path assignment to selected cells (PLACE & TIME → Path).
- Quick Adjust field edits (committed on Return or focus-loss).

**What is not recorded:**
- Phase policy changes in the tool strip.
- Resize policy selections in the resample sheet.
- Keyframe edits in PATH EDITOR (sliders update immediately and are reflected in live playback; undo for keyframe editing is planned for a future build).

The undo stack holds up to 40 snapshots. Timeline state is not part of the undo stack — recorded states accumulate independently and are managed via the Timeline Editor.

---

## 12. Style Palette and Library

### Project tab

The **Project** tab shows all styles and paths belonging to the current document.

#### Layers

The top of the Project tab lists all layers in the composition. Each row shows a visibility eye, an active-layer dot, the layer name, and its opacity.

- **Click** a row to make it the active layer.
- **Double-click** the layer name to rename it inline. Press Return or click elsewhere to commit.
- **Drag** a row up or down to reorder layers. An accent-colour line marks where the layer will land.
- **Opacity slider** — each row contains a compact slider on the right. Drag it to adjust the layer's opacity continuously; the percentage updates live alongside it.
- **Right-click** for the context menu: Rename, Duplicate, Opacity presets (100/75/50/25%), Delete.
- **+ New Layer** appends a new layer at the same grid resolution as the current active layer.

#### Styles

Click a style row to make it the active painting style — new cells you draw will use it.

**+ New Style** — adds a blank style to the project.

Each style row has a **↑** (promote) button. Clicking it saves a copy to the global user library. If a style with the same ID is already in the library, it is updated in place.

**Right-click** a project style row:

| Menu item | Effect |
|---|---|
| Create Variant → Inverted | New style with fill and stroke RGB values flipped; alpha preserved. |
| Create Variant → Faint | New style with fill alpha reduced to 0.15 and stroke alpha to 0.25. |
| Create Variant → Strong | New style with fill and stroke alpha set to 1.0. |
| Create Variant → Swap Colors | New style with fill and stroke colours exchanged. |
| Create Variant → Outline Only | New style in Stroked render mode; fill alpha set to 0. |
| Create Variant → Filled Only | New style in Filled render mode; stroke alpha set to 0. |
| Save to Library | Promotes the style to the global library. |
| Delete Style | Removes the style from the project; cells using it are reassigned to the first remaining style. Disabled if only one style exists. |

#### Paths

Click a path row to make it the **active path** for editing — its keyframes appear in PATH EDITOR. The active path row is highlighted. **Click the highlighted row again to deselect it** — the active path becomes nil, PATH EDITOR shows an empty state, and newly drawn or filled cells are painted with no path assigned.

Each path row shows a keyframe count badge (e.g. `4 kf`) and a **↑** (promote) button to save it to the global library.

**+ New Path** — creates a new path with two identity keyframes (frames 0 and 48), adds it to the project, and selects it as the active path.

**Right-click** a project path row:

| Menu item | Effect |
|---|---|
| Save to Library | Promotes the path to the global library. |
| Delete Path | Removes the path from the project and clears its reference from all assigned cells. |

#### Shapes

The **Shapes** section lists the geometry assets imported into this project from Loom. Each shape is a named Loom polygon set — the source file's bezier geometry, stored inside the `.umproj` file.

**Assigning a shape to a style:** Click a shape row to assign it to the currently active style. The row highlights in accent when the active style uses that shape. Click the highlighted row again to remove the assignment (the style reverts to the default hard-wired geometry). Only the active style is affected — other styles are unchanged.

**Importing shapes:** Click **+ Import Shape…** to open a file picker. The picker defaults to `~/.loom_projects` so you can navigate directly to your Loom projects and select `.json` polygon set files. Multiple files can be selected in one operation. The name shown in the list is taken from the filename (without extension) — rename the file in Loom before importing if you want a different name.

Each shape row has a **↑** (promote) button that saves the shape to the global library (`~/Library/Application Support/UM/shapes/<uuid>.json`), making it available to all projects.

**Right-click** a project shape row:

| Menu item | Effect |
|---|---|
| Save to Library | Promotes the shape to the global library. |
| Delete Shape | Removes the shape from the project. Any styles that referenced it revert to the default geometry. |

**Note on rendering:** shape assignment is stored in the project and will drive sprite geometry once the full Loom rendering pipeline is integrated. In the current build, all sprites still render using the hard-wired default shape regardless of assignment. The assignment is visible in the palette and persists in the saved file.

### Library tab

The **Library** tab shows your global user library — styles, paths, and shapes saved across all projects.

**Styles** — the library is stored in `~/Library/Application Support/UM/library.json`. Style rows show whether the style is already in the current project. If not, a **↓** (import) button adds it and makes it the active style.

**Paths** — **↓** imports a copy to the project.

**Shapes** — global shapes are stored as individual files in `~/Library/Application Support/UM/shapes/`. Shape rows show whether the shape is already in the current project. **↓** copies it into the project.

**Right-click** any library row to remove it from the library.

---

## 13. Save and Load

UM projects are saved as `.umproj` files — plain JSON containing the full document state: grid configuration, all cells (including their `pathID` references), styles, paths, shapes (including full geometry), canvas size, timeline, and color source settings. Files are human-readable in any text editor.

Projects saved by earlier builds load correctly — cells default to `pathID = nil` (no path), `colorSource = nil` (no color map), and `shapes = []` (no imported shapes) automatically.

**Shape geometry is embedded** in the `.umproj` JSON — you do not need to keep the original Loom `.json` files alongside the project. Once imported, the geometry is self-contained in the project file.

**Color source files** are referenced by absolute path, not embedded in the `.umproj`. If you share a project or move it to another machine, copy the image or video file alongside it and reload it via CANVAS → Color Map → Choose….

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Cmd+N | New — resets to a blank 8×8 square grid |
| Cmd+O | Open — opens a file chooser |
| Cmd+S | Save — writes to the current file; opens Save As for unsaved documents |
| Cmd+Shift+S | Save As — always shows the save panel |

### Default projects folder

New documents open their save panel at `~/Documents/UM Projects/`, created automatically on first launch.

To change it, open **UM → Preferences…** (Cmd+,) and click **Choose…**. Click **Reset** to revert to the default.

### Window title

`UM — Untitled` for an unsaved document; `UM — FileName` once saved.

---

## 14. What Is Not Yet Implemented

**Shape rendering** — shapes can be imported from Loom and assigned to styles, but the assignment does not yet affect rendering. All sprites still use the hard-wired default geometry. Shape assignments are stored in the project and will take effect when the Loom rendering pipeline is integrated.

**Keyframe undo** — edits made in PATH EDITOR (moving sliders, changing frame numbers) update the path immediately and are reflected in live playback, but are not currently tracked in the undo stack. Undo for keyframe editing is planned. In the meantime, avoid destructive keyframe edits you cannot reconstruct manually.

**ORDER/CHAOS, SEQUENCE, ADVANCED** — values are persisted in the document but have no visual effect in the current build. Full integration awaits the Loom rendering pipeline.

**Style thumbnails** — style rows show a small filled/unfilled circle rather than a live animated preview.

**Timeline scrubber** — a graphical horizontal scrubber (drag state boundaries to resize hold durations) is planned as an alternative to the list-based timeline editor.

**Video export from timeline** — the Video button exports live animation (parametric and keyframe motion), not the recorded timeline state sequence. Timeline-driven cut video export (render states as discrete cuts) is planned separately.

**SVG export** — the SVG button in the Transport Bar is a stub.

**Zoom and pan** — the canvas fills the available panel area and resizes with the window but cannot be zoomed or panned independently. Planned: pinch-to-zoom, two-finger drag, Cmd+0 to fit.

**Geometry mode** — a dedicated Geometry mode (toggled from the toolbar) is planned for when the Loom geometry editor is available as an embeddable component. In the meantime, shapes are authored in standalone Loom and imported into UM via the Style Palette SHAPES section.

**Background image** — the CANVAS section supports a solid background colour only. Loading a visible image that sits behind the grid as a compositing backdrop is planned. This is distinct from the **Color Map** (which samples pixel color to colorize sprites but never renders the image itself).

---

_End of UM Help — v0.9_
