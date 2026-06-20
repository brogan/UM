# UM Swift — Technical Specification

_Generated 2026-06-17. Revised 2026-06-18 (UI design direction, spatial/temporal nuance model; backlog and image color system added). Revised 2026-06-18 (geometry integration strategy; shape library manager added). Revised 2026-06-18 (built-vs-remaining status updated; §15 Outstanding Work added). Revised 2026-06-18 (shape rendering wired; Order/Chaos sine-oscillator jitter built; SEQUENCE cycling built; `shapeIDs` multi-shape model; §15 updated). Revised 2026-06-18 (multi-layer composition system built; §6.8 added; §7.1, §12.3, §15 updated; §15.8 Camera & Parallax added). Revised 2026-06-18 (layer rename and drag-to-reorder built; §6.8 and §12.3 updated; crash fix for styleNameHeader binding). Revised 2026-06-18 (layer opacity slider added to palette rows; §6.8 and §12.3 updated). Revised 2026-06-19 (four-axis cell model implemented: CellStyle render-only, UMMotionSet new palette entity, UMGridCell gains motionID/shapeID/pathID, project-level shape/motion palettes, legacy migration; §6.1, §6.2, §6.4, §6.5, §6.9 added, §7.1, §12.3, §13.2, §15 updated). Revised 2026-06-19 (MOTION section wired in right panel; 4 new path easing curves; position scatter on resample; accumulation trail bug fixed; layer-switch crash fixed; §5.7, §6.3, §12.3, §15.4, §15.9 updated). Revised 2026-06-19 (stamp transform bug fixed: all four stamp operations now copy the full cell struct; §12.3 updated). Revised 2026-06-19 (colour palette chooser built: `UMColorPalette` model, grid sampling from colour map, project/library CRUD, swatch picker popover in RENDER section; §6, §12.3, §15.10 updated). Revised 2026-06-19 (per-layer color maps built: each layer owns a `UMColorMapEngine`; §6.8, §12 color map section, §12.3, §15 summary updated). Revised 2026-06-19 (color map lock/unlock built: `lockedFillColor`/`lockedStrokeColor` on `UMGridCell`; §12 color map section and §12.3 updated). Revised 2026-06-19 (camera and parallax system built: `UMCamera`, `UMDoubleDriver`, `UMVectorDriver`, `DriverEvaluator`, `UMVec2`, `UMLoopMode` ported into UMEngine; `UMLayer` gains `parallaxFactor`/`layerOffset`/`opacityDriver`; CAMERA section in Quick Adjust; parallax slider per layer row; §15.8 updated to built status). Revised 2026-06-19 (spec §6.8 layer row description updated with parallax slider and camera ref; §6.8 limitations updated; help pendingBody camera row removed; qa-project CAMERA section added; layers page camera section already present). Revised 2026-06-19 (§15.11 Keyframe Timeline added: full spec for Loom-based timeline panel, lane model, model changes, keyframe inspector, transport integration, phased build plan). Revised 2026-06-20 (§15.9 updated: left panel restructure built — MOTIONS section with full CRUD, 4-axis cell inspector in PLACE & TIME, SEQUENCE cycling re-integrated as UMMotionSet feature with SequenceMode enum + shapeIDs; remaining outstanding work clarified; summary table updated). Revised 2026-06-20 (§15.11 updated to built status: keyframe timeline fully implemented — UMTimelinePanel 1174 lines, three layer lanes including gridScroll, camera lanes, KF inspector in QuickAdjust, named markers, copy/paste/undo/delete; timing-scale % field and ruler drag handles not built; summary table updated). Revised 2026-06-20 (canvas zoom and pan built: §15.2 updated; CGAffineTransform applied in Canvas closure; pinch, trackpad scroll, Cmd+0/=/- shortcuts; hit-testing via inverse transform). Revised 2026-06-20 (per-axis motion amounts built: `axisX`, `axisY`, `axisRotation`, `axisScale` added to `UMMotionSet`; applied in `computeParametric` after preset switch; axis mix sliders added to MOTION inspector; §6.9 updated)._
_Based on full source analysis of the UM Java project and the Loom_2026 Swift project._

---

## 1. Executive Summary

UM is a grid-based drawing and animation program where each cell in a rows × cols grid can be independently activated and rendered with a configured shape, renderer, and animator. The goal is to rewrite it as a native macOS Swift app while adopting Loom's geometry editor, animation driver system, subdivision engine, and rendering pipeline wholesale.

The grid is UM's greatest strength: it enables pattern transformations, resolution changes, systematic regularity, and color sampling from background images in ways that fully freeform tools cannot. But the same grid is also a limitation: sprites are locked to cell centres, and resolution changes currently destroy careful spatial positioning and collapse all animation timing to a uniform phase.

The Swift UM resolves this through a fundamental architectural distinction: **the grid governs topology, not geometry**. The grid determines which cells are adjacent, which flip together, what resolution change means — but the visual position of each sprite and its animation phase are independent, per-cell properties that are preserved across all grid operations. This gives the user the full structural power of grid-based drawing alongside the natural placement and temporal variety of freeform work.

The creative process is **time-based and iterative**: paint cells, watch the animated result, adjust scale and regularity/irregularity, paint more. The UI must support that fast feedback loop — the single always-live canvas, persistent painting palette, and compact quick-adjust strip keep everything in one view without tab switching.

---

## 2. UM Java — Current Architecture

### 2.1 Core Concept

A 2D grid of `GridSquare` objects (rows × cols). Each square has a **drawn** state (boolean). Drawn squares render their assigned shape set; undrawn squares are blank. The user paints/erases squares by clicking, selects a shape preset, and the grid plays back as an animation.

### 2.2 Object Hierarchy

```
IconDrawManager
├── IconUIFrame          (config/settings window — separate frame)
└── IconDrawFrame        (drawing window — separate frame)
    └── IconDrawPanel    (rendering canvas, drawing thread)
        └── SquaresGrid
            └── GridSquare[rows×cols]
                └── DrawSet
                    └── Drawer[]
                        ├── BShape          (geometry)
                        ├── BRenderer       (fill/stroke/mode)
                        └── Animator
                            └── KeyFrames
                                └── KeyFrame[]
                                    └── ShapeState (scale/rot/trans/colors)
```

### 2.3 Shape Types (Java)

| Type | Implementation |
|---|---|
| Regular polygon | N-sided; alternating inner/outer radius for stars |
| Oval | Ellipse stored as centre + radii |
| Quadratic curve | Single quad Bezier |
| Cubic curve | Multi-segment cubic Bezier (4 points per segment) |

All geometry stored as normalized `Point2D.Double[]` in (0,0)–(1,1) space, scaled to the square's pixel bounds at render time.

### 2.4 Animation Model

- **Keyframe modes:** TWEENING (interpolated with easing), DISCRETE (snap), RANDOM (jitter within ranges)
- **Per-keyframe state:** scale(x,y), rotation(degrees + offset), translation(x,y), fill color, stroke color, stroke weight
- **Oscillator:** Sinusoidal lateral movement overlay on a translation path; `amplitude × sin(2π × freq × t)`
- **Easing library:** 45+ functions (Sine, Cubic, Quad, Quart, Quint, Expo, Back, Bounce, Circ, Elastic; In/Out/InOut/OutIn variants)

### 2.5 Rendering Pipeline

Java2D `Graphics2D` → `GeneralPath`/`Ellipse2D`. Four modes: points, lines (stroked), filled, filled-stroked. No blur, no brush, no stamp, no SVG/video export.

### 2.6 Persistence

XOM XML library. Project file contains grid dimensions, per-square draw state, DrawSet/Drawer/Animator/KeyFrame trees, and renderer presets. Config XML stores UI preferences and shape/animator/renderer libraries.

### 2.7 Known Weaknesses

- Two-window layout (config + draw) constantly interrupts creative flow
- Drawers tab and DrawSets tab configure a single conceptual thing (cell appearance) across two separate panels — the primary UX problem
- No bezier point editing in the draw canvas; shapes edited in a separate side dialog
- Renderer limited to four basic modes; no brush, stamp, blur, or opacity animation
- No video or SVG export
- Grid parameter controls (resolution, offsets) buried in config window, not accessible during painting
- Regularity/irregularity — one of the most-used creative dimensions — has no dedicated control surface
- **Space:** sprites are locked to cell centres; any fine positioning is lost when resolution changes
- **Time:** all cells animate from the same phase (frame 0); changing resolution resets any incidental timing variety, producing lock-stepped animation

---

## 3. Loom Components Available for Reuse

### 3.1 Geometry Editor — Direct Adoption

`EditableGeometry.swift` is a fully-featured, production-ready bezier editor:

- `EditableClosedPolygon`, `EditableOpenCurve`, `EditableStandalonePoint`
- `EditableGeometryLayer` (layers), `EditableGeometryDocument` (multi-layer doc)
- `EditableGeometryHistory` (undo/redo stack)
- Weld groups (`EditableWeldGroup`) for mesh editing
- Freehand fitting (`FreehandCurveFitter`), mesh extrude/fill, knife tool
- Oval and regular polygon creation with live parametric metadata
- JSON round-trip (`EditableGeometryJSONLoader`)

**UM replacement:** UM's `CubicCurveManager`, `CubicCurves`, `CubicPoint`, `BezierDrawPanel`, and `RegularPolygonFrame` are all subsumed by this one module. In the new UI, the geometry editor appears as a canvas overlay (not a separate tab) when editing a shape preset.

### 3.2 Subdivision Engine — Direct Adoption

`SubdivisionEngine.swift` with 20+ algorithms (quad, tri, triBordA/B/C, triStar, echo, split, custom). Pressure propagation (spatial, inheritPath, random). UM has no subdivision at all — this is a net-new capability that directly serves the regularity/irregularity creative dimension.

### 3.3 Animation Driver System — Direct Adoption

`AnimationDriver.swift` → `DoubleDriver`, `VectorDriver`, `ColorDriver`, `NameDriver`. Each supports:

- Constant, jitter, noise, oscillator (sine/triangle/square/sawtooth), keyframe modes
- Loop / once / pingPong repeat
- Deterministic seed-based hash for reproducible randomness

`TransformAnimator.swift` evaluates drivers per-frame per-sprite for position, scale, rotation, opacity, blur, color, subdivision set, and renderer set.

**UM replacement:** UM's `Animator`/`KeyFrame`/`Oscillator`/`Ease` system is superseded.

**Migration mapping:**

| UM mode | Loom driver equivalent |
|---|---|
| TWEENING keyframe | `DoubleDriver`/`VectorDriver` in `.keyframe` mode |
| DISCRETE keyframe | Keyframe driver with step easing |
| RANDOM | `.jitter` mode |
| Oscillator | `.oscillator` mode (sine/sawtooth/triangle/square) |

In the UM UI these are exposed as named **Motion Presets** (see §4), not as raw driver configuration. The full driver inspector remains accessible via "Advanced…" disclosure.

### 3.4 Rendering Engine — Direct Adoption

`RenderEngine.swift` draws `Polygon2D` values into `CGContext`:

- Modes: points, stroked, filled, filledStroked, brushed, stenciled, stamped
- Brushed: `BrushStampEngine` stamps a brush image along the polygon path
- `PathPerturbation`: smooth noise warp of path geometry
- `RendererDrivers`: per-renderer animated blur, opacity, stroke-width, fill-color, stroke-color
- Palette cycling animation (`FillColorChange`, `StrokeColorChange`, `StrokeWidthChange`)

**UM replacement:** UM's four-mode `BRenderer` is replaced entirely.

### 3.5 Export Pipeline — Direct Adoption

- `StillExporter` → PNG with quality multiplier
- `VideoExporter` → animated video (AVFoundation)
- `SVGExporter` → SVG with full polygon pipeline

### 3.6 Loom UI Components — Partially Adopted

Loom's inspector components (subdivision inspector, rendering inspector, animation driver inspector, brush editor, stamp editor, palette editor) are reused as **disclosure panels** within the UM quick-adjust strip — accessible when needed, not occupying primary screen space.

Loom's `TimelinePanel`, `PlaybackState`, and `RunControlBar` are reused for transport controls.

Loom's tab-based left panel architecture is **not** adopted for UM's primary view. The Style Palette replaces it.

---

## 4. Grid as Topology, Not Geometry

This is the central architectural idea that resolves UM's longstanding space and time problems.

### 4.1 The Decoupling Principle

The grid structure determines **topology**: which cells are adjacent, which row and column each cell belongs to, what flip/rotate/resolution operations mean, how fill propagates. It does not determine the exact pixel position of the sprite within the cell, and it does not determine the animation phase at which the cell starts.

These are separated into two independent per-cell properties:

- **`positionOffset: CGVector`** — a visual nudge from the cell's nominal centre, in absolute pixels
- **`phaseOffset: Int`** — an animation phase offset in frames, shifting when the cell's animation begins

Both properties survive all grid operations. Flipping the grid transforms position offsets geometrically (mirroring X or Y). Rotating the grid rotates the offset vectors. Resolution changes carry offsets and phases to child cells. Neither property is ever silently reset.

### 4.2 Position Offset

```
Nominal position:  gridOrigin + (col × cellWidth, row × cellHeight)
Visual position:   nominalPosition + positionOffset
```

**Units — absolute pixels, not cell-relative fractions.** This is the key choice. A 12px rightward nudge remains 12px rightward after a resolution change (not suddenly 12% of a new smaller cell). The visual arrangement the user has built is preserved.

The offset range is generous — up to ±200% of cell size — so a sprite can visually sit between cells if desired. Its topological home (grid index) is still used for all grid operations; only the visual position floats freely.

**How grid transforms affect offsets:**

| Transform | Effect on positionOffset |
|---|---|
| Flip horizontal | negate all dx values (mirrors the spatial arrangement) |
| Flip vertical | negate all dy values |
| Rotate left 90° | `(dx, dy) → (dy, -dx)` for each cell |
| Rotate right 90° | `(dx, dy) → (-dy, dx)` for each cell |
| Clear / invert drawn | offsets preserved (drawing state changes, not placement) |

**How resolution change affects offsets:**

When the grid is resampled (e.g., 4×4 → 8×8), each new cell inherits its parent cell's `positionOffset` unchanged. The four child cells of a single parent all start at the same visual nudge. Optional **Position Scatter on Resize** (see §4.5) adds a small random perturbation to child offsets so a higher-resolution version of the composition feels organically different rather than a mechanical subdivision.

When going coarser (8×8 → 4×4), merged cells adopt the position offset of whichever child was closest to the centre of the merged area (or the average, user-settable).

**Background image color sampling** uses the sprite's visual position (nominal + offset), not the grid centre. A repositioned sprite pulls the color from where it actually appears.

**Nudge mode in the canvas:** when cells are selected, dragging moves their `positionOffset`. The cell's nominal grid outline is shown as a faint reference square; the sprite floats relative to it. Arrow keys nudge by 1px; shift-arrow by 10px. This is a static offset distinct from Motion Preset animation which moves the sprite over time.

### 4.3 Phase Offset

Each cell stores a `phaseOffset: Int` (frames). The engine evaluates a cell's animation at frame `currentFrame + phaseOffset` rather than at `currentFrame`. A cell with `phaseOffset = 12` is always 12 frames ahead of a cell with `phaseOffset = 0`.

**Phase Policies — applied at paint time:**

| Policy | Behaviour |
|---|---|
| Synchronized | `phaseOffset = 0` for all cells. Intentional lock-step. |
| Random | `phaseOffset = random(0 ..< animationLength)`. Different each cell. Organic feel. |
| Sequential | Increments by `phaseStepFrames` in painting order. Creates a wave as you draw. |
| Spatial | `phaseOffset = (row + col) × phaseStepFrames`. Diagonal wave across the grid. |
| Radial | `phaseOffset = distance(cell, centre) × phaseStepFrames`. Rings ripple outward. |

The active Phase Policy is a global setting shown in the tool strip. Changing the policy affects newly painted cells, not existing ones. This lets you deliberately mix policies — paint a synchronized foundation, switch to Spatial, add a wave layer.

**How grid transforms affect phase:**

Flip/rotate transform the *positions* of cells but do not modify phase offsets — timing doesn't mirror geometrically. Phase offsets travel with the cell regardless of its new grid position.

**How resolution change affects phase:**

Child cells inherit the parent's `phaseOffset`. Optional **Phase Scatter on Resize** adds a small bounded random perturbation to child phases, preventing the uniform look of a purely mechanical subdivision. The scatter range is controllable (0 = no scatter, 1 = ±½ of the animation length).

**Manual phase editing:** in Quick Adjust, when cells are selected, a **Phase** field shows the current offset (or "—" for mixed). The user can type a frame value or drag a small dial. This lets specific cells be deliberately choreographed when the automatic policies are not sufficient.

### 4.4 Spatial Scatter

When the Draw tool paints a cell, a **Spatial Scatter** parameter (0–1) controls how much random `positionOffset` is injected:

- `0` — all sprites land exactly at nominal cell centres
- `0.25` — gentle organic displacement; cells feel hand-placed
- `1` — offsets randomised within ±100% of cell size; composition becomes loose and open

Spatial Scatter is a global setting (shown in the tool strip alongside Phase Policy). It applies at paint time; existing cells are not affected unless explicitly re-scattered via Edit > Re-scatter Selection.

Spatial Scatter and Phase Scatter on Resize are the primary tools for making higher-resolution compositions feel distinct from their lower-resolution parents rather than mechanical enlargements.

---

## 5. UI Design — The Creative Workflow Model

### 5.1 Primary Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│  [Draw] [Erase] [Select] [Sample] [Fill] [Nudge]                        │
│  [↔] [↕] [↺] [↻] [⊡] [⊟]   Phase:[Spatial ▼] step:4  Scatter:──●──  │
│  grid: 8×8  cell: 60×60   [4×4] [8×8] [16×16] [32×32]   rows[_] cols[_]│
├──────────────────┬──────────────────────────────┬───────────────────────┤
│                  │                              │                       │
│  STYLE PALETTE   │    GRID CANVAS               │  QUICK ADJUST         │
│                  │    (live, animated)          │                       │
│  ┌────┐ ┌────┐  │                              │  Shape  [hexagon ▼]   │
│  │ ▲▲ │ │ ●● │  │  ·  ·  ■  ·  ·              │  Render [stroked ▼]   │
│  └────┘ └────┘  │  ·  ■  ■  ■  ·              │  Fill   [■]           │
│  ┌────┐ ┌────┐  │  ·  ·  ■  ·  ·              │  Stroke [■]  ─●──     │
│  │ ○  │ │ ≋≋ │  │                              │                       │
│  └────┘ └────┘  │  (faint grid lines;          │  Order ●────── Chaos  │
│                  │   sprites float at           │                       │
│  [+ new style]   │   their visual positions)    │  PLACE & TIME         │
│                  │                              │  Position  x[ 0] y[ 0]│
│                  │                              │  Phase     [ 0 frames] │
│                  │                              │  [Re-scatter Sel.]    │
│                  │                              │                       │
│                  │                              │  MOTION               │
│                  │                              │  [Wave ▼]             │
│                  │                              │  Speed  ──●───        │
│                  │                              │  Amount ────●─        │
│                  │                              │                       │
│                  │                              │  SEQUENCE             │
│                  │                              │  [▲][●][○]  + −       │
│                  │                              │  ○ Seq ● All ○ Rand   │
│                  │                              │  frames  ─●───        │
│                  │                              │                       │
│                  │                              │  [Advanced…]          │
├──────────────────┴──────────────────────────────┴───────────────────────┤
│  ▶  ■   fps ─●──  frame 42/120   [PNG] [Video] [SVG] [Open Folder]     │
└──────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Tool Strip (top bar)

Always visible. Three groups:

**Painting tools** — Draw, Erase, Select (rubber-band), Sample (eyedropper), Fill (flood), Nudge:
- Keyboard shortcuts: D, E, S, A, F, N
- **Nudge tool** — click a drawn cell to select it; drag to move its `positionOffset`; arrow keys for precise nudging; the nominal cell outline shows as a faint reference. This is the primary spatial placement tool.

**Grid transforms** — flip horizontal (↔), flip vertical (↕), rotate left (↺), rotate right (↻), clear (⊡), invert (⊟):
- One-click operations; each records an undo snapshot
- All transforms carry position offsets and phase offsets with their cells

**Grid parameters:**
- Phase Policy pop-up: [Synchronized / Random / Sequential / Spatial / Radial]
- Phase Step frames field (used by Sequential, Spatial, Radial policies)
- Spatial Scatter slider (0–1): controls position randomness at paint time
- Resolution presets: [4×4] [8×8] [16×16] [32×32] plus editable rows/cols fields
- Resolution change opens a small sheet: "Inherit offsets / Scale proportionally / Reset" and "Inherit phase / Scatter / Reset" — so the user controls what the resize carries forward

### 5.3 Style Palette (left column)

Replaces the Java shape library and DrawSets/Drawers concept. Each entry is a **Cell Style**: a saved combination of shape, renderer, motion preset, sequence configuration, Order/Chaos value, and spatial scatter. Displayed as animated thumbnails.

- Click to set as active painting style
- Double-click to edit in the geometry editor overlay or Quick Adjust panel
- Drag to reorder; right-click → Duplicate / Delete / Rename
- `+` new blank style; right-click any drawn cell → "Save as Style"
- Styles are saved as part of the project

### 5.4 Grid Canvas (centre)

The dominant workspace. Always shows the live animated output. Grid lines are overlaid subtly and can be toggled off. In Nudge mode, selected cells show their nominal grid outline as a faint square alongside their actual (offset) position.

**Painting interactions:**
- **Draw** — click or drag to mark cells drawn with the active style; position offset applied per Spatial Scatter; phase offset applied per Phase Policy
- **Erase** — click or drag to mark cells undrawn
- **Select** — drag to rubber-band; shift-click to add; arrow keys move selection
- **Sample** — click a drawn cell to load its style (does not copy position/phase offset)
- **Fill** — flood-fill contiguous undrawn region with active style
- **Nudge** — click a drawn cell to select; drag to move its `positionOffset`; shows nominal outline as reference

**Geometry editor overlay** — double-click a style thumbnail to enter bezier editing mode directly on the canvas. Done returns to painting.

**Zoom/pan** — pinch to zoom, two-finger drag to pan, ⌘0 to fit, ⌘= / ⌘-.

### 5.5 Quick Adjust (right strip)

The permanent right panel. No tab switching required. Six sections:

#### Shape & Render

```
Shape   [hexagon ▼]
Render  [stroked ▼]
Fill    [■]
Stroke  [■]  ─●──
```

#### Order ←→ Chaos

```
Order ●────────── Chaos
```

At **Order**: subdivision regularity maximised, no path perturbation, motion disabled.
At **Chaos**: centre jitter on, random visibility rules, path perturbation active, rotation/position jitter drivers enabled.

Internally maps to `SubdivisionParams.ranMiddle`, `visibilityRule`, `ranDiv`, `PathPerturbation` amplitude, `DoubleDriver` jitter on rotation.

#### Place & Time

```
Position   x [  0 px]  y [  0 px]
Phase      [  0 frames]
[Re-scatter Selection]
```

Shows the `positionOffset` and `phaseOffset` of the selected cell(s). When multiple cells with different values are selected, shows "—". Editing applies to all selected cells simultaneously — the primary tool for manually choreographing placement or timing of specific cells.

**Re-scatter Selection** randomises `positionOffset` for all selected cells using the current Spatial Scatter amount and randomises `phaseOffset` using the current Phase Policy — a quick way to "un-lock-step" a region that was painted with Synchronized policy.

#### Motion

```
[Wave ▼]     ← Static / Spin / Pulse / Wave / Wander / Jitter / Color Cycle / Custom
Speed  ──●───
Amount ────●─
Phase  ─●────
```

Note: the Phase knob here is the **motion phase** (offset within the animation cycle of the Motion Preset oscillator) — distinct from the cell's **phase offset** in the Place & Time section above. These are independent: phase offset shifts when the animation begins; motion phase shifts the starting point within the oscillation cycle.

| Preset | Loom mapping |
|---|---|
| Static | all drivers disabled |
| Spin | `rotationDriver: .oscillator`, wave = sine |
| Pulse | `scaleDriver: .oscillator`, wave = sine |
| Wave | `positionDriver: .oscillator`, X freq ≠ Y freq (Lissajous) |
| Wander | `positionDriver: .noise` |
| Jitter | `positionDriver: .jitter`, `rotationDriver: .jitter` |
| Color Cycle | `ColorDriver: .keyframe` on renderer palette |
| Custom | opens full `AnimationDriverInspector` in-place |

#### Sequence

```
[★5] [★6] [★3]   + −
○ Sequential  ● All  ○ Random
frames  ─●───
```

Merged Drawers + DrawSets concept. Filmstrip shows each shape in the Cell Style's sequence. Mode: Sequential / All-at-once / Random. Frames slider: hold duration per step.

#### Advanced…

Disclosure expanding to Loom's full inspector components: subdivision, rendering, animation drivers, global project settings.

### 5.6 Transport Bar (bottom)

```
▶  ■   fps ─●──  frame 42/120   [PNG] [Video] [SVG] [Open Folder]
```

Play/pause (Space), FPS slider, frame scrubber, export buttons. Adapted from Loom's `RunControlBar`.

### 5.7 Resolution Change Sheet

When the user changes resolution (via presets or custom fields), a compact sheet slides in:

```
┌─────────────────────────────────────────────────┐
│  Change grid from 8×8 to 16×16?                │
│                                                 │
│  Position offsets                               │
│  ● Preserve absolute (sprites stay put)         │
│  ○ Scale proportionally with cell size          │
│  ○ Reset to zero (re-centre all sprites)        │
│                                                 │
│  Phase offsets                                  │
│  ● Inherit from parent cell                     │
│  ○ Inherit + scatter  amount ──●──              │
│  ○ Reset to zero                                │
│                                                 │
│  Position scatter  ──●──                        │
│  (random sub-cell offset added to each cell;   │
│   0 = none, 1 = ±½ cell width/height)          │
│                                                 │
│                    [Cancel]  [Apply]            │
└─────────────────────────────────────────────────┘
```

The user's choice is remembered per project and pre-filled next time. "Preserve absolute" + "Inherit" is the default — it's the option that most faithfully carries the composition forward.

**Position Scatter on Resize** (`resizePositionScatter`, 0–1) adds a random sub-cell position offset to every cell after the offset policy is applied. At 1.0 each sprite can be displaced up to ±½ cell width/height. This is independent of the per-policy offset — it layers on top of whatever the offset policy preserved or reset. Values are in cell-fraction units (same as `positionOffset`), so scatter is resolution-independent.

---

## 6. Data Model

### 6.1 Cell Style

A **style** is now render-only: it controls only the visual appearance of a sprite's fill, stroke, and render mode. Motion, shape, and path are independent axes assigned separately to each cell (see §6.9).

```swift
struct CellStyle: Codable, Identifiable {
    var id:              UUID
    var name:            String
    // Render-only visual properties
    var lockedFillHex:   String?         // nil = use fillColor, non-nil = palette-locked hex
    var lockedStrokeHex: String?
    var fillColor:       UMColor
    var strokeColor:     UMColor
    var strokeWidth:     Double
    var renderMode:      UMRenderMode    // .filled / .stroked / .filledStroked
}

enum UMRenderMode: String, Codable { case filled, stroked, filledStroked }
```

Backward compatibility: old project files that contain motion/shape/sequence fields in a style's JSON are silently ignored on read — the removed fields produce a no-op `decodeIfPresent` miss, not a decode error. The legacy migration path (§6.10) converts those fields into the new independent palettes.

**Style variants** (right-click context menu in palette): Inverted, Faint, Strong, Swap Colors, Outline Only, Filled Only — all transform only the visual fields that remain in the slim struct.

### 6.10 Legacy Migration

When opening a project file written by an earlier build (pre-4-axis model), `AppController.readLegacy` runs a one-time migration:

1. **`LegacyCellStyle` decoder** — re-encodes each old `CellStyle` to JSON and re-decodes it through a private `LegacyCellStyle: Decodable` struct that reads the old motion/shape fields (`motionPreset`, `motionSpeed`, `motionAmount`, `motionPhase`, `orderChaos`, `framesPerStep`, `shapeIDs`).

2. **`migrateLegacyMotion`** — creates one `UMMotionSet` per old style (carrying its motion and orderChaos values) and patches every cell in every layer with the derived `motionID` and `shapeID` (first shape in the old style's `shapeIDs` list).

3. The migrated `projectMotionSets` array is stored at project level and saved with the next write (v3 format). The old per-style motion fields are discarded.

The migration is transparent: the user opens an old file and sees their composition unchanged, with styles converted to render-only and motion now available as named motion sets in the motion palette.

### 6.2 Grid Cell

Each cell carries four independent creative axis references — any combination of nil (use default) or a specific palette entry:

```swift
struct UMGridCell: Codable, Identifiable {
    var id:             UUID
    var gridIndex:      Int          // row * cols + col
    var isDrawn:        Bool

    // Four independent axes — all optional; nil = use project default or fallback
    var styleID:        UUID         // references CellStyle (render: fill, stroke, mode)
    var motionID:       UUID?        // references UMMotionSet (animation + orderChaos)
    var shapeID:        UUID?        // references UMShape in project shape palette
    var pathID:         UUID?        // references UMMotionPath in document.paths

    // Spatial nuance — preserved across all grid operations
    var positionOffset: UMOffset     // absolute pixels from nominal cell centre; default .zero

    // Temporal nuance — preserved across all grid operations
    var phaseOffset:    Int          // frames; cell animates at (currentFrame + phaseOffset)

    // Resting-pose transform (combined multiplicatively with animated values)
    var scaleX:         Double       // default 1.0
    var scaleY:         Double       // default 1.0
    var rotation:       Double       // degrees; default 0.0
}
```

When a cell is drawn with the Draw or Fill tool, all four active palette selections are captured into the cell's four axis IDs simultaneously. This means the composition is a snapshot of the palette state at paint time — changing a style/motion/shape after drawing does not retroactively change cells that were painted before.

### 6.3 Grid Config

```swift
struct UMGridConfig: Codable {
    var rows:             Int
    var cols:             Int
    var cellWidth:        Double
    var cellHeight:       Double
    var xOffset:          Int
    var yOffset:          Int
    var borderWidth:      Int
    // Paint-time policies (applied to newly painted cells; don't retroactively affect existing)
    var phasePolicy:      PhasePolicy
    var phaseStepFrames:  Int             // used by .sequential, .spatial, .radial
    var spatialScatter:   Double          // 0.0–1.0; position randomness at paint time
    // Resolution-change policies (remembered per project)
    var resizeOffsetPolicy:    ResizeOffsetPolicy
    var resizePhasePolicy:     ResizePhasePolicy
    var resizePhaseScatter:    Double     // 0.0–1.0; scatter added to inherited phase on resize
    var resizePositionScatter: Double     // 0.0–1.0; random sub-cell offset added to cells on resample
}

enum PhasePolicy: String, Codable {
    case synchronized, random, sequential, spatial, radial
}

enum ResizeOffsetPolicy: String, Codable {
    case preserveAbsolute   // sprites stay at same screen pixels
    case scaleProportional  // offset scales with new cell size
    case reset              // offset zeroed; sprites recentre
}

enum ResizePhasePolicy: String, Codable {
    case inherit            // child gets parent's phaseOffset
    case inheritWithScatter // child gets parent's phaseOffset ± random scatter
    case reset              // child phaseOffset = 0
}
```

### 6.4 Grid Document

`UMGridDocument` is the per-layer document stored within each `UMLayer`. Styles, shapes, and motion sets are **project-level**, not per-layer — they are held in `AppController` and shared across all layers.

```swift
struct UMGridDocument: Codable {
    var gridConfig:   UMGridConfig
    var cells:        [UMGridCell]
    var styles:       [CellStyle]        // render styles — project-level (mirrored from AppController)
    var paths:        [UMMotionPath]     // keyframe paths — per-layer
    var colorSource:  UMColorSource?     // color map — per-layer
    var timeline:     [UMTimelineState]  // recorded states — per-layer
}
```

**AppController** holds project-level palettes shared across all layers:

```swift
var projectStyles:        [CellStyle]       // render palette (all layers share these)
var projectMotionSets:    [UMMotionSet]     // motion palette (§6.9)
var projectShapes:        [UMShape]         // shape palette
var projectColorPalettes: [UMColorPalette]  // colour palettes (§15.10)

// Active palette selections (written into new cells at paint time)
var activeStyleID:        UUID?
var activeMotionID:       UUID?
var activeShapeID:        UUID?
var activePathID:         UUID?
var activeColorPaletteID: UUID?
```

The project is saved as a directory package (`.umproj/`) containing:

```
config.json               ← v3: layerStates + projectMotionSets + projectStyles + projectShapes (by ref)
shapes/
    <uuid>.json           ← individual UMShape geometry JSON files
colorSources/
    backdrop.jpg          ← color map files copied in on load or first save
    clouds.mp4
renders/
    stills/
    animations/
```

### 6.5 Order/Chaos Materialisation

`UMMotionSet.orderChaos` is a 0–1 scalar (moved from CellStyle in the 4-axis refactor). Materialisation happens in two phases — the first is built; the second (polygon-level warping) is pending subdivision integration.

**Phase 1 — built: per-cell sine-oscillator jitter**

Applied in `computeMotion` in ContentView.swift, additive on top of the parametric preset and keyframe path. Each cell gets a unique phase seed from its grid index (golden-ratio multiplication), so neighbouring sprites never synchronise:

```swift
let seed = Double(cellIndex) * 1.6180339887
let t    = Double(frame + phaseOffset) / 60.0   // seconds
m.dx       += cellW * 0.30 * oc * sin(t * 2.3τ + seed * 7.0)
m.dy       += cellH * 0.30 * oc * sin(t * 1.7τ + seed * 11.0)
m.rotation += 90.0        * oc * sin(t * 1.1τ + seed * 5.0)
let sj      =               oc * 0.4 * sin(t * 0.9τ + seed * 3.0)
m.scaleX   *= max(0.05, 1.0 + sj)
m.scaleY   *= max(0.05, 1.0 + sj * 0.8)
```

At `orderChaos=1`: ±30% cell-size position drift, ±90° rotation, ±40%/32% scale. All smooth — no per-frame random.

**Phase 2 — pending: polygon-level warping via SubdivisionEngine**

The original spec intent (mapping `orderChaos` → `SubdivisionParams` → `SubdivisionEngine.process`) is the deeper materialisation and requires subdivision integration (§15.1). That is distinct from the jitter above and not yet built:

```swift
// Not yet implemented:
func materializeOrderChaos(_ t: Double,
                            into params: inout SubdivisionParams,
                            animation: inout SpriteAnimation) {
    params.ranMiddle      = t > 0.3
    params.ranDiv         = 2.0 + t * 8.0
    params.visibilityRule = t > 0.7 ? .random1in3 : t > 0.5 ? .random1in2 : .all
    animation.rotationDriver.amplitude = t * 15.0
    animation.rotationDriver.mode      = t > 0.1 ? .jitter : .constant
    animation.positionDriver.amplitude = t * 8.0
    animation.positionDriver.mode      = t > 0.2 ? .jitter : .constant
}
```

### 6.6 Phase Offset Application

The engine applies `phaseOffset` at evaluation time — it does not modify the cell's driver clocks, only shifts the frame index used to evaluate them:

```swift
func evaluateCell(_ cell: UMGridCell, currentFrame: Int) -> SpriteState {
    let frame = currentFrame + cell.phaseOffset
    return TransformAnimator.evaluate(animation: style.animation, frame: frame, seed: cell.id)
}
```

Because Loom's `DriverEvaluator` is already stateless and deterministic (it takes `(seed, frame)` → value), the phase shift is free: no mutable state is needed on any cell.

### 6.8 Layer System

UM supports a stack of independent composition layers. Each layer owns its own grid document (rows/cols, cells, styles, shapes, paths) and renders into the shared canvas at a configurable opacity. Layers are composited bottom-to-top.

#### Data model

```swift
// UMEngine/Composition/UMLayer.swift
public struct UMLayer: Codable, Identifiable, Sendable {
    public var id:        UUID
    public var name:      String
    public var isVisible: Bool
    public var opacity:   Double      // 0–1; 1 = fully opaque
    public var document:  UMGridDocument
}

// UMApp/AppController.swift
@Observable @MainActor
final class UMLayerState: Identifiable {
    let  id:           UUID
    var  name:         String
    var  isVisible:    Bool
    var  opacity:      Double
    var  engine:       UMGridEngine    // document + undo stack
    var  activeStyleID: UUID?

    func toUMLayer() -> UMLayer { ... }   // called at save time
}
```

`UMLayer` is the serialised form (Codable value type stored in the `.umproj` JSON array). `UMLayerState` is the live in-memory form that holds the engine and per-layer UI state.

#### AppController integration

`AppController` holds `layerStates: [UMLayerState]` and `activeLayerIndex: Int`. The existing `engine: UMGridEngine` stored property is preserved but updated by `selectLayer()` to always point to the active layer's engine — all 187+ existing `controller.engine.X` call sites in view files remain unchanged.

Key methods:
- `selectLayer(_ index: Int)` — saves departing layer's `activeStyleID`, switches `engine`
- `addLayer(name:)` — appends a new layer with the active layer's grid resolution
- `removeLayer(at:)`, `duplicateLayer(at:)`, `moveLayer(from:to:)` — full CRUD

Save encodes `[UMLayer]` (via `UMLayerState.toUMLayer()`); load decodes `[UMLayer]` and creates fresh `[UMLayerState]` instances.

#### Playback

The playback loop advances **all** layer engines in lockstep each tick:

```swift
for ls in self.layerStates { ls.engine.advance() }
```

All layers share the same frame clock. Timeline recording and navigation operate on the active layer only.

#### Canvas rendering

The live SwiftUI Canvas loops over all visible layers and renders each into an isolated compositing group:

```swift
for ls in controller.layerStates where ls.isVisible {
    ctx.drawLayer { layerCtx in
        layerCtx.opacity = ls.opacity
        // draw ls.engine.document.cells using per-layer cellW/cellH
    }
}
```

Each layer computes its own cell dimensions from its grid resolution (`lCellW = gridW / Double(lConfig.cols)`), so layers can have different grid resolutions occupying the same canvas area. Selection highlights apply only to the active layer.

#### Export compositing

For PNG and video export, layers are composited in CoreGraphics:

1. Render each visible layer's cells to a transparent-background `CGImage` via `ImageRenderer(content: FrameCapture(..., drawBackground: false))`
2. Draw into a `CGBitmapContext` at the layer's opacity using `ctx.setAlpha(ls.opacity)`

`umRenderComposited()` in ContentView.swift handles PNG export. `UMVideoExporter.export(layers: [UMLayer], ...)` handles video, rendering from the serialised layer snapshots captured at export start.

#### Accumulation (background-draw OFF)

In accumulation mode the frame buffer is the composite of all layers from the previous tick. Each new frame blends all current layers on top of the existing buffer.

#### Layer UI

A **LAYERS** section appears at the top of the Project tab in the Style Palette. Each row shows:
- Visibility toggle (eye icon)
- Active-layer indicator dot (accent colour when active, faint when not)
- Layer name (double-click to rename inline; press Return or click elsewhere to commit)
- Mini opacity slider (56 px) with live percentage readout alongside it
- Camera icon + parallax slider (0–1) — how strongly camera pan affects this layer (0 = background-fixed, 1 = world-space foreground; default 1.0)

Tap a row to switch the active layer. Drag a row to reorder layers (an accent-colour line indicates the drop target). Context menu: Rename, Duplicate, Opacity presets (100/75/50/25%), Delete. `+ New Layer` button appends a new layer with the same grid resolution as the current active layer.

Camera state (pan, zoom, rotation) lives in `AppController.camera: UMCamera` and is edited via the **CAMERA** section in Quick Adjust — see §15.8.

#### Current limitations

- No layer blend modes beyond normal (opacity)
- No animated layer opacity or parallax drivers (opacityDriver / layerOffset oscillator/keyframe UI is Phase 2 of §15.8)

---

### 6.9 UMMotionSet

A **motion set** is a named, saveable entity that carries all animation-related properties for a cell. It is the motion axis of the four-axis cell model.

```swift
public struct UMMotionSet: Codable, Identifiable, Sendable {
    public var id:           UUID
    public var name:         String
    public var motionPreset: MotionPreset   // .static / .spin / .pulse / .wave / .wander
                                            //   .jitter / .colorCycle / .custom
    public var motionSpeed:  Double         // 0.0–2.0; default 1.0
    public var motionAmount: Double         // 0.0–1.0; default 0.5
    public var motionPhase:  Double         // 0.0–1.0; starting phase within the oscillation cycle
    public var orderChaos:   Double         // 0.0 = ordered, 1.0 = chaotic (moved from CellStyle)
    public var framesPerStep: Int           // for SEQUENCE cycling; default 4
    // Per-axis multipliers (0 = suppressed, 1 = full). Applied after the preset's parametric
    // output; omitted from encoding when 1.0 so existing project files are unchanged.
    public var axisX:        Double         // position X multiplier; default 1.0
    public var axisY:        Double         // position Y multiplier; default 1.0
    public var axisRotation: Double         // rotation multiplier; default 1.0
    public var axisScale:    Double         // scale-deviation multiplier; default 1.0
}
```

**Per-axis amounts** (`axisX`, `axisY`, `axisRotation`, `axisScale`) are applied in `computeParametric` (ContentView.swift) after the switch statement. Position and rotation are simple multipliers (`m.dx *= axisX`). Scale uses deviation-from-identity so that 0 collapses to no motion rather than zero scale: `m.scaleX = 1.0 + (m.scaleX - 1.0) * axisScale`. The Quick Adjust MOTION section shows only the sliders relevant to the active preset (X/Y for wave/wander/jitter; Rotation for spin/jitter; Scale for pulse).

Motion sets live in `AppController.projectMotionSets` — a project-level palette shared across all layers, analogous to `projectStyles`. They are listed in the MOTIONS section of the Style Palette (not yet built as a distinct UI panel — see §15.9).

**Rendering:** In the render loop, `cell.motionID` is looked up in a `motionMap: [UUID: UMMotionSet]` built from `projectMotionSets`. The resulting `UMMotionSet?` is passed to `computeMotion(motionSet:style:path:...)` and `computeParametric(motionSet:style:...)`. If `motionID` is nil, the cell renders with no motion (Static preset, no orderChaos).

**Library integration:** Motion sets can be promoted to the global library (`UMLibrary.motionSets: [UMMotionSet]`) and imported back into any project, following the same promote/import pattern as styles and paths.

---

### 6.7 Project Structure on Disk

```
<ProjectName>/
    um_project.json         ← UMGridDocument
    polygonSets/            ← EditableGeometry JSON docs (Loom format)
    configuration/          ← subdivisionParams, rendering, shapes (Loom format)
    brushes/
    stamps/
    svgs/
    renders/
        stills/
        animations/
```

---

## 7. Swift Architecture

### 7.1 Package Structure

```
UMEngine (Swift Package — library)
├── Grid/
│   ├── UMGridConfig.swift
│   ├── UMGridCell.swift
│   ├── UMGridDocument.swift
│   ├── UMGridEngine.swift
│   ├── UMGridTransforms.swift
│   └── UMGridLoader.swift
├── Style/
│   ├── CellStyle.swift              // render-only (fill, stroke, mode) — ✓ built
│   ├── UMMotionSet.swift            // named motion entity with preset/speed/amount/phase/orderChaos — ✓ built
│   ├── UMLibrary.swift              // global library container (styles + paths + motionSets) — ✓ built
│   ├── MotionPreset.swift
│   └── OrderChaosEngine.swift       // pending: maps orderChaos → SubdivisionParams
├── Composition/
│   └── UMLayer.swift            // Codable layer value type — ✓ built
├── Placement/
│   ├── PhasePolicy.swift        // phase offset application at paint time
│   └── ResolutionResampler.swift // carries offsets + phases through resize
└── depends on: LoomEngine (loom_swift at /Users/broganbunt/Loom_2026/loom_swift)

UMApp (macOS App target)
├── AppController.swift
├── ContentView.swift
├── ToolStrip/
│   ├── ToolStripView.swift          (painting tools + transforms + resolution + phase/scatter)
│   └── TransportBar.swift
├── StylePalette/
│   ├── StylePaletteView.swift
│   └── StyleThumbnailView.swift
├── Canvas/
│   ├── GridCanvasView.swift         (painting, nudge, hit testing, rubber-band)
│   └── GeometryEditorOverlay.swift
├── QuickAdjust/
│   ├── QuickAdjustView.swift
│   ├── ShapeRenderSection.swift
│   ├── OrderChaosSection.swift
│   ├── PlaceTimeSection.swift       (NEW — positionOffset + phaseOffset editor)
│   ├── MotionSection.swift
│   ├── SequenceSection.swift
│   └── AdvancedDisclosure.swift
├── Advanced/
│   ├── SubdivisionInspector.swift   (REUSE)
│   ├── RenderingInspector.swift     (REUSE)
│   ├── AnimationDriverInspector.swift (REUSE)
│   └── GlobalInspector.swift
└── Export/
    └── ExportSheet.swift            (REUSE)
```

### 7.2 Rendering Pipeline

```
DisplayLinkFrameLoop.tick(deltaTime)
    ↓
UMGridEngine.advance(deltaTime)   // increments currentFrame
    ↓
For each drawn UMGridCell (row-major order):
    1. Resolve CellStyle → active shape (per sequenceMode, frame + phaseOffset)
    2. Load geometry: EditableGeometryDocument → [Polygon2D]
    3. Apply Order/Chaos materialisation → SubdivisionParams
    4. Subdivide: SubdivisionEngine.process(polygons, paramSet)
    5. Evaluate motion drivers at (currentFrame + cell.phaseOffset) → SpriteState
    6. Apply cell position transform:
         nominalPos = gridOrigin + (col * cellWidth + gridConfig.xOffset,
                                    row * cellHeight + gridConfig.yOffset)
         visualPos  = nominalPos + cell.positionOffset
       Apply SpriteState (scale, rotation) centred on visualPos
    7. Render: RenderEngine.draw(polygon, renderer, context, transform)
    ↓
Composite → CGImage → GridCanvasView
```

Background image color sampling at step 7 uses `visualPos`, not `nominalPos`.

### 7.3 Grid Transform Operations

```swift
enum UMGridTransform {
    case flipHorizontal
    case flipVertical
    case rotateLeft90
    case rotateRight90
    case clearAll
    case invertDrawn
    case resampleToGrid(rows: Int, cols: Int,
                        offsetPolicy: ResizeOffsetPolicy,
                        phasePolicy: ResizePhasePolicy,
                        phaseScatter: Double)
    case copyRegion(indices: Set<Int>, toIndex: Int)
    case nudgeSelection(indices: Set<Int>, delta: CGVector)
    case setPhaseOffset(indices: Set<Int>, phase: Int)
    case rescatterSelection(indices: Set<Int>, scatter: Double, phasePolicyOverride: PhasePolicy?)
}
```

Offset transform logic for flip/rotate:

```swift
static func transformOffset(_ v: CGVector, transform: UMGridTransform) -> CGVector {
    switch transform {
    case .flipHorizontal:  return CGVector(dx: -v.dx, dy:  v.dy)
    case .flipVertical:    return CGVector(dx:  v.dx, dy: -v.dy)
    case .rotateLeft90:    return CGVector(dx:  v.dy, dy: -v.dx)
    case .rotateRight90:   return CGVector(dx: -v.dy, dy:  v.dx)
    default:               return v
    }
}
```

### 7.4 Resolution Resampler

`ResolutionResampler` handles the 4×4 → 8×8 (or coarser) mapping:

```swift
struct ResolutionResampler {
    // Build new cells array by nearest-cell parent lookup.
    // Each new cell:
    //   - isDrawn, styleID from parent
    //   - positionOffset per offsetPolicy
    //   - phaseOffset per phasePolicy (+ optional scatter)
    static func resample(
        document: UMGridDocument,
        toRows: Int, toCols: Int,
        offsetPolicy: ResizeOffsetPolicy,
        phasePolicy: ResizePhasePolicy,
        phaseScatter: Double
    ) -> [UMGridCell]
}
```

For scatter, uses the same Loom Murmur3-inspired hash `(cellID, seed)` → `[0,1)` so scatter is deterministic — the same resize always produces the same result unless the cell UUIDs change.

### 7.5 `UMGridEngine` API

```swift
final class UMGridEngine {
    var document: UMGridDocument
    // FrameLoop
    func start(with loop: any FrameLoop)
    func stop()
    func seek(toFrame frame: Int)
    func advance(deltaTime: Double)
    // Rendering
    func render(into context: CGContext)
    func makeFrame() -> CGImage?
    var currentFrame: Int { get }
    var canvasSize: CGSize { get }
    var maxAnimationFrames: Int { get }
    // Grid editing
    func apply(_ transform: UMGridTransform)
    func setCellDrawn(_ index: Int, drawn: Bool, styleID: UUID)
    func floodFill(from index: Int, styleID: UUID)
    func sampleStyle(at index: Int) -> CellStyle?
    func setPositionOffset(_ offset: CGVector, for indices: Set<Int>)
    func setPhaseOffset(_ phase: Int, for indices: Set<Int>)
    func rescatterSelection(_ indices: Set<Int>)
    // Undo
    func pushUndoSnapshot()
    func undo()
    func redo()
}
```

---

## 8. Reuse vs New Work

### Direct Reuse

| Loom Module | Notes |
|---|---|
| `loom_swift/Sources/LoomEngine/` (entire package) | Local Swift package dependency |
| `EditableGeometry.swift` | Shape preset editing via canvas overlay |
| `SubdivisionEngine` + all algorithm files | Driven by Order/Chaos slider |
| `AnimationDriver.swift`, `TransformAnimator.swift` | Backing store for Motion Presets; phase offset applied to frame index |
| `DriverEvaluator` | Already stateless — phase offset is free |
| `RenderEngine.swift`, `BrushStampEngine.swift`, `StampEngine.swift` | Replaces UM BRenderer |
| `SpriteAnimation`, `ShapeConfig`, `RenderingConfig`, `SubdivisionConfig` | ProjectConfig reused |
| `SVGExporter`, `VideoExporter`, `StillExporter` | Net-new export |
| `SubdivisionInspector`, `RenderingInspector`, `AnimationDriverInspector` | Advanced disclosure |
| `BrushEditorWindow`, `StampEditorWindow`, `PaletteEditors` | Advanced disclosure |
| `TimelinePanel`, `PlaybackState` | Transport bar |
| `FreehandCurveFitter`, `LoomSVGImporter`, `LoomSVGWriter` | As-is |

### Adapted from Loom

| Module | Change |
|---|---|
| `AppController.swift` | Owns `UMGridEngine`; grid selection state; phase/scatter settings |
| `RunControlBar.swift` | Becomes `TransportBar`; FPS slider surfaced |
| `GeometryTabView.swift` | Becomes `GeometryEditorOverlay` (canvas overlay, not tab) |
| `GlobalInspector.swift` | Moved into Advanced disclosure |

### New Work

| Module | Estimated Effort |
|---|---|
| `CellStyle`, `MotionPreset`, `OrderChaosEngine` | ~1.5 days |
| `UMGridConfig`, `UMGridCell`, `UMGridDocument` | ~1 day |
| `PhasePolicy`, `ResolutionResampler` | ~1.5 days |
| `UMGridEngine` (rendering loop + cell layout + phaseOffset + undo) | ~3.5 days |
| `UMGridTransforms` (flip/rotate with offset vectors; rescatter) | ~1.5 days |
| `UMGridLoader` (JSON save/load + legacy XML import) | ~2 days |
| `GridCanvasView` (painting, nudge tool, hit-test, rubber-band, zoom) | ~3 days |
| `ToolStripView` (tools + transforms + phase policy + scatter + resolution) | ~1.5 days |
| `StylePaletteView` + `StyleThumbnailView` | ~2 days |
| `QuickAdjustView` + six sections incl. `PlaceTimeSection` | ~3 days |
| `AdvancedDisclosure` + wiring | ~1 day |
| Resolution Change Sheet UI | ~0.5 days |
| `TransportBar` | ~0.5 days |
| **Total estimate** | **~23 working days** |

---

## 9. Rendering Output — Upgrade Path

| Feature | Java UM | Swift UM |
|---|---|---|
| Stroked shapes | ✓ | ✓ |
| Filled shapes | ✓ | ✓ |
| Points | ✓ | ✓ |
| Brushed (stamp-along-path) | ✗ | ✓ via BrushStampEngine |
| Stamped (bitmap at point positions) | ✗ | ✓ via StampEngine |
| Path perturbation (noise warp) | ✗ | ✓ via PathPerturbation |
| Animated blur | ✗ | ✓ via RendererDrivers |
| Opacity animation | ✗ | ✓ via RendererDrivers |
| Colour oscillator / noise | ✗ | ✓ via ColorDriver |
| Subdivision (20+ algorithms) | ✗ | ✓ via SubdivisionEngine |
| Order/Chaos single-slider control | ✗ | ✓ new |
| Per-cell position offset (spatial nuance) | ✗ | ✓ new |
| Per-cell phase offset (temporal nuance) | ✗ | ✓ new |
| Phase policies (sync/random/spatial/radial/sequential) | ✗ | ✓ new |
| Spatial scatter at paint time | ✗ | ✓ new |
| Offset/phase inheritance on resolution change | ✗ | ✓ new |
| Background image color sampling at visual position | ✗ | ✓ new |
| Motion presets | ✗ | ✓ new |
| SVG export | ✗ | ✓ via SVGExporter |
| Video export | ✗ | ✓ via VideoExporter |
| PNG still | ✓ | ✓ via StillExporter |
| Morph targets | ✗ | ✓ via MorphInterpolator |

---

## 10. Migration Strategy

### Phase 1 — Foundation (weeks 1–2)

1. Create Xcode project `UMApp`, macOS 14+
2. Add `loom_swift` as local Swift package dependency
3. Implement `CellStyle`, `UMGridDocument`, `UMGridEngine` with hard-coded test grid
4. Implement `ResolutionResampler` and `PhasePolicy` application
5. Wire `GridCanvasView` showing live animated output with per-cell phaseOffset applied

### Phase 2 — Painting & Palette (weeks 3–4)

6. Implement `ToolStripView` (tools, transforms, phase policy, scatter, resolution presets)
7. Implement `GridCanvasView` full interaction (draw, erase, select, sample, fill, nudge, zoom)
8. Implement `StylePaletteView` with live animated thumbnails
9. Resolution Change Sheet
10. JSON save/load; undo/redo for all operations

### Phase 3 — Quick Adjust (weeks 5–6)

11. All six Quick Adjust sections including `PlaceTimeSection`
12. Order/Chaos slider → `OrderChaosEngine` materialisation
13. Motion Presets → Loom driver configuration
14. Sequence filmstrip
15. `AdvancedDisclosure` linking to Loom inspector components

### Phase 4 — Geometry Editor Overlay (week 7)

16. `GeometryEditorOverlay` — Loom geometry editor on the canvas
17. Double-click style → enter edit mode → Done returns to painting

### Phase 5 — Export & Legacy Import (week 8)

18. PNG, video, SVG export — reuse Loom components; verify visual positions used correctly
19. Legacy UM XML importer (all cells get `positionOffset: .zero`, `phaseOffset: 0`)

### Phase 6 — Polish (week 9)

20. Keyboard shortcuts: D/E/S/A/F/N tools; Space play/pause; ⌘Z/⌘⇧Z; arrows
21. Drag-and-drop from style palette to canvas
22. Hover preview on undrawn cells showing active style at current Spatial Scatter
23. Visual indicator on canvas showing phase offset magnitude (optional heat-map overlay, toggleable)
24. App icon, launch screen

---

## 11. Key Design Decisions

**Grid as topology, not geometry.** The grid determines structure (adjacency, flip/rotate semantics, resolution change mapping). Visual position and animation phase are independent per-cell properties that survive every grid operation. This is the architectural resolution to the longstanding space/time tension in UM.

**Absolute pixels for position offset.** Preserving position offsets in absolute pixel units (rather than cell-relative fractions) means that resolution changes leave sprites visually where the user placed them. A sprite nudged 12px rightward is still 12px rightward in the new grid.

**Phase offset is free.** Loom's `DriverEvaluator` is already stateless — it takes `(seed, frame)` → value with no mutable animation clock. Applying a per-cell phase offset is simply a frame-index shift at evaluation time, requiring no additional engine machinery.

**Phase policies at paint time, not retroactively.** Changing the Phase Policy affects newly painted cells only. This lets the user compose layers with different temporal characters: paint a synchronized base, switch to Spatial, paint a wave layer.

**Rescatter on demand.** Rather than forcing a policy choice at creation time, `Re-scatter Selection` lets the user apply scatter (spatial or temporal) to any selection at any time. This preserves creative flexibility without requiring up-front decisions.

**The Drawers/DrawSets problem is solved by `CellStyle`.** A single struct encodes what a Java DrawSet + its Drawers expressed across two tabs. The Sequence filmstrip in Quick Adjust makes the shape-cycling concept visible and editable in one place.

**~70% reuse.** All engine, geometry, subdivision, rendering, and export work comes from Loom unchanged. New work is concentrated in: the topology/geometry decoupling (`positionOffset`, `phaseOffset`, policies), the painting UI (`GridCanvasView`, `ToolStripView`, nudge tool), and the quick-adjust creative controls (Order/Chaos, Motion Presets, Place & Time).

---

## 12. Feature Backlog

Features deferred for future implementation, recorded here to preserve intent and enough design context to scope the work when the time comes.

---

### 12.1 Cubic Bezier Path Editing

**What:** Allow keyframe motion paths to be shaped as cubic bezier curves with interactive tangent handles on the canvas, rather than point-to-point segments with a per-segment easing picker.

**Why:** The current system interpolates linearly between keyframe positions and applies a scalar easing curve (easeIn/Out/etc.) to that segment. This produces smooth motion but gives no control over the *direction* of arrival and departure at each keyframe. Bezier tangent handles let you express arcing, looping, and overshoot trajectories — motion paths that feel physically natural rather than mechanically interpolated.

**Design:**

- Add `inTangent: CGPoint` and `outTangent: CGPoint` to `PathKeyframe`, stored in the same cell-fraction unit space as `dx`/`dy`. Default both to `(0, 0)` (degenerate = current linear behaviour; backward compatible).
- Replace the per-segment easing picker with the handle pair — the handle shape *is* the easing. The easing enum can be retained as a fast-path default for the degenerate (no-handle) case.
- Rewrite `UMMotionPath.evaluate(atFrame:cellW:cellH:)` to use the cubic parametric form:

  ```
  P(t) = (1-t)³·P0 + 3(1-t)²t·(P0+out0) + 3(1-t)t²·(P1+in1) + t³·P1
  ```

  where `t` is the normalised position within the segment (after frame-to-alpha mapping + legacy easing applied to the alpha).

- Canvas overlay: when a keyframe is selected in PATH EDITOR, draw its two tangent handles as small circles connected to the keyframe dot by thin lines. Handles are independently draggable. A "smooth" toggle mirrors the out-handle across the keyframe when the in-handle is dragged (C1 continuity).
- Handle hit-testing sits on top of the existing path overlay drag gesture layer. The PATH EDITOR section shows numeric Tangent X / Tangent Y fields alongside the handle UI for precision entry.
- Handle dots are a distinct colour (e.g. white fill, accent stroke) to distinguish them from keyframe dots.

**Scope:** medium — roughly 3–4 days. Data model change is small and backward-compatible; the evaluation rewrite is self-contained; the canvas interaction (hit testing, drag, mirroring) is the majority of the work.

**Dependencies:** none — builds directly on the existing `UMMotionPath` / `PathKeyframe` / canvas overlay infrastructure.

---

### 12.2 Image-Based Color System

**What:** Allow the fill and/or stroke color of sprites to be driven by the colors of an underlying source image or video, sampled per grid cell. This is the Swift equivalent of the Java UM's bitmap color mode: the image is divided into a rows × cols grid of regions, the color of each region is extracted, and that color is applied to the sprite(s) occupying the corresponding grid cell.

**Why:** Static style colors are adequate for solid-color compositions but cannot produce the spatially-varying, image-sourced palettes that are one of UM's most distinctive creative capabilities. The original Java UM supported both static images and per-frame image sequences. The Swift version should extend this to video, which avoids the file-management burden of numbered image sequences while being more expressive (smooth color changes, temporal colour sampling at sub-frame precision).

#### Design principle: per-layer compositor, not style property

The color map is a **per-layer compositor that sits above the style system**. Each layer owns its own `UMColorMapEngine`; layers without a loaded color source are unaffected by any other layer's engine. Styles define character — shape, render mode, stroke width, alpha, motion preset — and the color map overrides the color component of that character at render time. This means:

- `CellStyle` requires no changes for basic color map support
- All drawn cells are equally affected by an active color map by default
- The rendering loop checks for a color override after style and motion evaluation — the existing `fillOverride` / `strokeOverride` channels on `SpriteMotion` are the injection point
- A future per-style `ignoreColorMap: Bool = false` flag gives escape hatches for cells that must keep explicit style colors (e.g. a foreground overlay style that should not be colorized)

#### Data model

```swift
// In UMGridDocument
var colorSource: UMColorSource?

// UMEngine/Sources/UMEngine/Style/UMColorSource.swift
public struct UMColorSource: Codable, Sendable, Equatable {
    public var filePath:           String    // absolute path, resolved at load time; legacy fallback
    public var relativeFilePath:   String?   // filename within project's colorSources/ dir (preferred)
    public var applyTo:            ColorApplyTarget
    public var preserveStyleAlpha: Bool
    public var videoLoopMode:      VideoLoopMode
}

public enum ColorApplyTarget: String, Codable, Sendable, CaseIterable { case fill, stroke, fillAndStroke }
public enum VideoLoopMode:    String, Codable, Sendable, CaseIterable { case loop, clamp }
```

The file is **never embedded in the JSON**. When a project is saved as a `.umproj` package:
- If a color source was loaded while the project was already saved, it is copied into `colorSources/` immediately on load and `relativeFilePath` is set to the destination filename (e.g. `"backdrop.jpg"`).
- If loaded before the project was first saved, it is copied on first save.
- `relativeFilePath` stores just the filename — the `colorSources/` directory prefix is implied. At read time, each layer's `filePath` is patched to the resolved absolute URL so the rest of the code never needs to know about the directory convention.
- Legacy projects with no `relativeFilePath` fall back to the stored absolute `filePath`.

The runtime layer (`UMColorMapEngine`) holds the loaded assets and sampled color grids. Each layer has its own engine, stored in `AppController`:

```swift
// Per-layer engines keyed by layer UUID
var layerColorMapEngines: [UUID: UMColorMapEngine] = [:]
// Active layer's engine — what the UI binds to; swapped on layer switch
var colorMapEngine: UMColorMapEngine = UMColorMapEngine()
// Render-time accessor used by the canvas loop and exporters
func colorMapEngine(forLayerID id: UUID) -> UMColorMapEngine? { layerColorMapEngines[id] }
```

On project load, a `UMColorMapEngine` is created and (if `colorSource` is set) loaded for every layer. When the user switches layers, `colorMapEngine` is swapped to the incoming layer's engine so all existing UI controls (load, clear, resample, palette generation) continue to operate on the active layer's engine without change.

#### Runtime layer: `UMColorMapEngine`

```swift
@Observable @MainActor
final class UMColorMapEngine {
    // Loaded state
    private(set) var isLoaded: Bool = false
    private(set) var sourceType: ColorSourceType = .staticImage

    // Static image: one pre-sampled grid
    private var staticGrid: [[UMColor]] = []

    // Video: pre-sampled grid per extracted frame
    private var videoFrameGrids: [[[ UMColor]]] = []  // [frameIndex][row][col]
    private var videoFrameCount: Int = 0

    // Query API (called per cell per frame in the render loop)
    func color(atRow row: Int, col: Int, animationFrame: Int) -> UMColor? {
        guard isLoaded else { return nil }
        switch sourceType {
        case .staticImage:
            guard row < staticGrid.count, col < staticGrid[row].count else { return nil }
            return staticGrid[row][col]
        case .video:
            let fi = resolvedVideoFrame(animationFrame)
            guard fi < videoFrameGrids.count,
                  row < videoFrameGrids[fi].count,
                  col < videoFrameGrids[fi][row].count else { return nil }
            return videoFrameGrids[fi][row][col]
        }
    }

    // Load a static image
    func load(image: CGImage, rows: Int, cols: Int) {
        staticGrid = Self.sample(image: image, rows: rows, cols: cols)
        isLoaded = true
        sourceType = .staticImage
    }

    // Load a video and pre-extract up to maxFrames frames
    func load(asset: AVAsset, rows: Int, cols: Int,
              animationFPS: Int = 24, maxFrames: Int = 240) async {
        // ... see extraction detail below
    }

    func clear() { staticGrid = []; videoFrameGrids = []; isLoaded = false }

    private func resolvedVideoFrame(_ animFrame: Int) -> Int {
        guard videoFrameCount > 0 else { return 0 }
        // loop mode determined by UMColorSource.videoLoopMode
        return animFrame % videoFrameCount
    }
}
```

#### Sampling algorithm

The key insight is that "average color across a cell region" can be computed in a single GPU-accelerated draw call by downscaling the source image to exactly `rows × cols` pixels:

```swift
private static func sample(image: CGImage, rows: Int, cols: Int) -> [[UMColor]] {
    let cs   = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let ctx = CGContext(data: nil, width: cols, height: rows,
                              bitsPerComponent: 8, bytesPerRow: cols * 4,
                              space: cs, bitmapInfo: info.rawValue) else { return [] }
    ctx.interpolationQuality = .high     // bilinear — equivalent to area average for large → small
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: rows))

    let ptr = ctx.data!.bindMemory(to: UInt8.self, capacity: rows * cols * 4)
    var grid = [[UMColor]](repeating: [UMColor](repeating: .defaultFill, count: cols), count: rows)
    for r in 0..<rows {
        for c in 0..<cols {
            let i = (r * cols + c) * 4
            grid[r][c] = UMColor(r: Double(ptr[i])/255, g: Double(ptr[i+1])/255,
                                 b: Double(ptr[i+2])/255, a: Double(ptr[i+3])/255)
        }
    }
    return grid
}
```

Drawing a large image into a tiny `rows × cols` bitmap is exactly what GPUs are optimised for. A 4K image sampled into an 8×8 grid takes microseconds. No manual pixel averaging is required.

#### Video frame extraction

Pre-extract on load using `AVAssetImageGenerator`. The animation frame rate is 24fps; the video may be at any rate. The mapping is time-based, not frame-number-based, to handle arbitrary video frame rates correctly:

```swift
func load(asset: AVAsset, rows: Int, cols: Int,
          animationFPS: Int = 24, maxFrames: Int = 240) async {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    // Allow ±1 animation frame of tolerance for fast extraction
    let tolerance = CMTime(value: 1, timescale: CMTimeScale(animationFPS))
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter  = tolerance

    let duration     = (try? await asset.load(.duration))?.seconds ?? 0
    let totalFrames  = min(Int(duration * Double(animationFPS)), maxFrames)
    let times: [NSValue] = (0..<totalFrames).map { f in
        NSValue(time: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(animationFPS)))
    }

    var grids = [[[UMColor]]](repeating: [], count: totalFrames)
    await withCheckedContinuation { cont in
        var remaining = totalFrames
        generator.generateCGImagesAsynchronously(forTimes: times) { requested, cgImage, _, result, _ in
            if result == .succeeded, let img = cgImage {
                let fi = Int(requested.seconds * Double(animationFPS))
                if fi < totalFrames {
                    grids[fi] = Self.sample(image: img, rows: rows, cols: cols)
                }
            }
            remaining -= 1
            if remaining == 0 { cont.resume() }
        }
    }

    await MainActor.run {
        self.videoFrameGrids  = grids
        self.videoFrameCount  = totalFrames
        self.isLoaded         = true
        self.sourceType       = .video
    }
}
```

For video longer than `maxFrames` (default 240 = 10 seconds at 24fps), the extracted 240 frames loop. A user working with a 2-minute video who needs full temporal color variety can raise this limit in CANVAS settings. The tradeoff is memory: 240 frames × 16×16 grid × 4 bytes ≈ under 1 MB — negligible for the default case; 240 frames × 32×32 × 4 ≈ under 4 MB.

#### Rendering integration

In the canvas draw loop, after `computeMotion()` returns a `SpriteMotion`, inject the color map override before the sprite is drawn:

```swift
// existing: let motion = computeMotion(style: style, path: path, ...)

// Per-layer lookup: each layer has its own engine; layers without a source return nil here
let colorGrid = controller.colorMapEngine(forLayerID: ls.id)?.currentGrid(
    animationFrame: currentFrame,
    loopMode: ls.engine.document.colorSource?.videoLoopMode ?? .loop)

if let colorGrid,
   let lColorSrc = ls.engine.document.colorSource,
   let sampled = colorGrid[safe: r]?[safe: c] {
    let alpha = lColorSrc.preserveStyleAlpha

    let mapped = alpha
        ? UMColor(r: sampled.r, g: sampled.g, b: sampled.b,
                  a: (style?.fillColor.a ?? 1.0))    // keep style alpha
        : sampled

    switch source?.applyTo ?? .fill {
    case .fill:
        motion.fillOverride = mapped
    case .stroke:
        motion.strokeOverride = mapped
    case .fillAndStroke:
        motion.fillOverride   = mapped
        motion.strokeOverride = mapped
    }
}
```

The same injection must be applied inside `FrameCapture.body` for background-draw accumulation frames.

#### Grid resize interaction

When the grid is resampled (e.g. 8×8 → 16×16), the color source file stays the same but the grid dimensions change. `UMColorMapEngine.resample(rows:cols:)` re-runs the sampling at the new grid size — for a static image this is one draw call; for video it re-extracts all pre-cached frames at the new resolution. This is automatically triggered by the grid resample operation in `AppController`.

#### UI — COLOR MAP section in Quick Adjust

New collapsible section in Quick Adjust, between CANVAS and ORDER/CHAOS:

```
COLOR MAP
  Source  [Choose Image or Video…]  [Clear]
           "backdrop.jpg"  (static image)   — or —
           "clouds.mp4"  (48 fr / 240 extracted)

  Apply to    ● Fill  ○ Stroke  ○ Both
  Style alpha ☑ Preserve (use style fill/stroke opacity)
  Video loop  ● Loop  ○ Clamp  ○ Ping-pong   (video only, dimmed for static)
```

The section header shows a coloured dot (sampled center-cell color) when a color source is active, so the user gets a quick visual confirmation without expanding.

#### File storage

Color source files are copied into the project package and referenced by filename:

```
MyProject.umproj/
    colorSources/
        backdrop.jpg
        clouds.mp4
```

`UMColorSource.relativeFilePath` stores the filename only (e.g. `"backdrop.jpg"`). The `colorSources/` prefix is implied. On pick (if the project is saved) or on first save (if picked beforehand), UM copies the file into `colorSources/` and sets `relativeFilePath`. Projects are self-contained — the source file travels with the `.umproj` directory.

#### Color map lock (built 2026-06-19)

Cells can be "locked" to the color they currently receive from the color map. Locked colors travel with the cell through any transform (flip, rotate, nudge, stamp, resample), making it possible to infuse an image's spatial color into a grid and then freely rearrange the sprites into patterns that play upon those colors without them snapping to new grid positions.

**Data model** — two optional fields added to `UMGridCell` (with `decodeIfPresent` for full backward compatibility):

```swift
public var lockedFillColor:   UMColor?   // nil = use live color map / style
public var lockedStrokeColor: UMColor?   // nil = use live color map / style
```

**Render priority**: at render time, locked colors are checked before live color map sampling:

```swift
if cell.lockedFillColor != nil || cell.lockedStrokeColor != nil {
    if let fc = cell.lockedFillColor   { motion.fillOverride   = fc }
    if let sc = cell.lockedStrokeColor { motion.strokeOverride = sc }
} else if let src = colorSource, let grid = colorGrid, r < grid.count, c < grid[r].count {
    applyColorMap(grid[r][c], source: src, style: style, to: &motion)
}
```

This applies in all three render paths: live canvas, `FrameCapture` (accumulation), and `UMVideoExporter`.

**`AppController` operations**:
- `lockColorMap()` — samples `colorMapEngine.currentGrid(animationFrame: 0)` and writes each drawn cell's color into `lockedFillColor`/`lockedStrokeColor` using the current `applyTo` and `preserveStyleAlpha` settings. Scoped to `selectedIndices` when non-empty; otherwise operates on all drawn cells.
- `unlockColorMap()` — clears `lockedFillColor` and `lockedStrokeColor` on drawn cells. Also selection-aware.
- `hasColorMapLock: Bool` — true if any drawn cell on the active layer has a locked color; used to enable the Unlock button and show the status indicator.

**UI** — Lock/Unlock row in the COLOR MAP section of Quick Adjust, visible whenever a color map is loaded or locked colors exist. Lock button is disabled when no map is loaded; Unlock button is disabled when no cells are locked. A status line ("⚑ Layer has locked colors") appears below when locks are present, changing to "Selection" when cells are selected. Locking with a selection active scopes the operation to the selected cells only.

#### Per-style color map opt-out (future extension)

Add `var ignoreColorMap: Bool = false` to `CellStyle` (with `decodeIfPresent` for backward compatibility, defaulting to false). When true, cells using this style skip the color map injection and use their explicit style fill/stroke colors. This allows mixing image-colored cells with explicitly-styled foreground cells in the same composition.

#### Scope

Medium-large — roughly 4–5 days:
- `UMColorSource` data model + Codable + document integration: 0.5 days
- `UMColorMapEngine` (sampling, static load, video extraction + caching): 1.5 days
- Rendering loop integration in Canvas + FrameCapture: 0.5 days
- Grid resize hook: 0.25 days
- Quick Adjust COLOR MAP section UI: 1 day
- File copy-on-save, relative path resolution: 0.5 days
- Per-style opt-out flag: 0.25 days (can defer)

**Dependencies:** `AVFoundation` (already available on macOS); the existing `fillOverride`/`strokeOverride` channels on `SpriteMotion` (already built).

---

### 12.3 Features Built (complete inventory)

Everything in this list is implemented and functional in the current build (`main` branch, https://github.com/brogan/UM.git).

**Core grid engine**
- `UMGridDocument`, `UMGridConfig`, `UMGridCell`, `UMGridEngine` with full save/load (`.umproj` JSON)
- All painting tools: Draw, Erase, Select (rubber-band + Shift-extend), Sample, Fill (flood), Nudge
- All grid transforms: flip H/V, rotate L/R, clear, invert — all carry `positionOffset` vectors correctly
- Transform Mode: Move vs Stamp, including Δφ stamp phase offset; stamp operations copy the full `UMGridCell` struct (styleID, motionID, shapeID, pathID, scaleX, scaleY, rotation, positionOffset, phaseOffset) — fixed: previously only `styleID` and `positionOffset` were copied, causing stamped cells to lose their geometry, motion, and path assignments and fall back to default rendering
- Undo/redo (40 steps) covering all painting, transform, nudge, and quick-adjust operations
- Resample Grid sheet with offset and phase policies (Preserve / Scale / Reset; Inherit / Scatter / Reset) and Position Scatter slider (`resizePositionScatter`, 0–1)

**Phase and scatter**
- All five Phase Policies: Synchronized, Random, Sequential, Spatial, Radial
- φ step stepper in Tool Strip (1–240 fr)
- Spatial Scatter slider in Tool Strip (0–1)
- Rescatter Selection in PLACE & TIME

**Four-axis cell model** (built 2026-06-19)
- `CellStyle` is now render-only: `fillColor`, `strokeColor`, `strokeWidth`, `renderMode`, locked hex overrides — all other fields removed
- `UMMotionSet`: new named palette entity carrying `motionPreset`, `motionSpeed`, `motionAmount`, `motionPhase`, `orderChaos`, `framesPerStep`
- `UMGridCell` gains `motionID: UUID?`, `shapeID: UUID?`, `pathID: UUID?` alongside `styleID`
- `UMGridEngine.setCellDrawn` and `floodFill` accept all four axis IDs
- `AppController.projectMotionSets: [UMMotionSet]` — project-level motion palette; `activeMotionID`, `activeShapeID` active selections
- Full CRUD for motion sets: `addMotionSet`, `deleteMotionSet`, `promoteMotionSetToLibrary`, `importMotionSetFromLibrary`
- `UMLibrary.motionSets: [UMMotionSet]` — global library includes motion sets
- Legacy migration: `LegacyCellStyle` decoder extracts old motion fields; `migrateLegacyMotion` builds `UMMotionSet` per old style and patches cells — old projects open seamlessly
- Config format bumped to v3; old v1/v2 files auto-detected and migrated
- Paint call sites (Draw, Fill tools) pass all four active IDs to the engine
- `computeMotion(motionSet:style:path:...)` / `computeParametric(motionSet:style:...)` — function signatures updated
- `resolvePolygons(shapeID:shapeMap:fallback:)` — simplified: direct UUID lookup (no SEQUENCE cycling in renderer for now)
- All render paths (live Canvas, background CG, FrameCapture, UMVideoExporter) updated for 4-axis model
- Style variants (Inverted, Faint, Strong, Swap Colors, Outline Only, Filled Only) operate on render-only fields — unchanged in behaviour

**Styles palette — shape selection updated**
- Clicking a shape row in the palette sets `activeShapeID` (toggle on/off) — newly drawn cells get this shape
- Shape rows no longer toggle into a style's `shapeIDs` list (that list is removed)
- `deleteShape` now clears `shapeID` from any cells that referenced it

**Styles and paths (legacy — still built)**
- Parametric motion presets: Static, Spin, Pulse, Wave, Wander, Jitter, Color Cycle (wired via `UMMotionSet`)
- Keyframe motion paths: `UMMotionPath`, `PathKeyframe`, full PATH EDITOR UI, path overlay on canvas
- Path deselect (click active path row again to draw without path assignment)
- QuickAdjustView updated: ORDER/CHAOS, MOTION, and SEQUENCE sections removed (now belong to motion palette UI — pending §15.9)
- Style variants: Inverted, Faint, Strong, Swap Colors, Outline Only, Filled Only (right-click context menu)

**Style Palette and Library**
- Project tab: STYLES, MOTIONS, PATHS, SHAPES, PALETTES sections with promote (↑), import (↓), delete
- Library tab: global styles/motions/paths/shapes/palettes with promote and import
- Global style/path library at `~/Library/Application Support/UM/library.json`; now also includes `colorPalettes: [UMColorPalette]`
- Shape library manager: `UMShape`, project shapes embedded in `.umproj`, global shapes at `~/Library/Application Support/UM/shapes/`
- Import Loom polygon-set JSON files; shapes survive resave (geometry embedded, not file-referenced)
- Shape rows support multi-select: clicking a row toggles the shape into/out of the active style's `shapeIDs` list; a sequence-position badge shows the order

**Colour palette chooser** (built 2026-06-19 — §15.10)
- `UMColorPalette`: `id: UUID`, `name: String`, `colors: [UMColor]`, `sourceDescription: String`
- Stored in `projectColorPalettes: [UMColorPalette]` in AppController and `[UMColorPalette]` in `UMLibrary`
- Serialised in `ProjectConfig` with `decodeIfPresent` for backward compatibility
- `UMColorMapEngine.buildPaletteColors(rows:cols:)` — samples the stored source image (or first video frame) using the same GPU bilinear path as the live colour map engine; returns flat `[UMColor]`
- `AppController.generateColorPalette(name:rows:cols:)` — builds a palette from the active colour map and appends it to `projectColorPalettes`
- Full CRUD: `deleteColorPalette`, `promoteColorPaletteToLibrary`, `importColorPaletteFromLibrary`, `removeColorPaletteFromLibrary`
- PALETTES section in Project tab: swatch strip preview per palette; rename on double-click; promote (↑) and delete in context menu; "Generate from Color Map…" sheet (name field + 4×4/4×8/8×8 size picker) — visible only when a colour map is loaded
- PALETTES section in Library tab: strip preview, import (↓), remove
- `ColorPalettePickerView` — popover triggered by a `swatchpalette` icon button next to Fill and Stroke `ColorWell`s in the RENDER section; shows a swatch grid (always 8 columns), palette selector when multiple palettes exist, alpha slider at bottom; tapping a swatch applies `color.withAlpha(alpha)` to the bound style property and dismisses

**Canvas and rendering**
- Live animated canvas (SwiftUI Canvas, `@Observable` engine, 24 fps)
- Background draw / accumulation mode (`backgroundDraw` flag, `FrameCapture` struct); accumulation correctly captures path motion trails — fixed: a second `guard !Task.isCancelled` inside `captureTask` was killing every completed render before it could store its result; the guard is removed so completed renders always commit to the frame buffer
- Color map system: `UMColorMapEngine`, static image and video (up to 240 extracted frames) sampling
- **Per-layer color maps** (built 2026-06-19): each layer owns its own `UMColorMapEngine` in `AppController.layerColorMapEngines: [UUID: UMColorMapEngine]`; `colorMapEngine` property always refers to the active layer's engine (no UI changes); `colorMapEngine(forLayerID:)` accessor used by live canvas, accumulation snapshots, `umRenderComposited`, and `UMVideoExporter` for per-layer lookup; layer lifecycle methods (`addLayer`, `removeLayer`, `duplicateLayer`, `selectLayer`, project load/reset) all manage the per-layer engine dict correctly
- **Color map lock** (built 2026-06-19): `lockedFillColor: UMColor?` and `lockedStrokeColor: UMColor?` on `UMGridCell` (Codable, `decodeIfPresent`); locked colors take priority over live sampling in all three render paths; `lockColorMap()` / `unlockColorMap()` in `AppController` (selection-aware); Lock/Unlock row in Quick Adjust COLOR MAP section with `hasColorMapLock` status indicator
- Color map UI in CANVAS section: apply target, style alpha preserve, video loop mode
- Open curves, points, ovals, line polygons imported from Loom — all geometry types rendered
- `buildPolygonPath` handles all five `PolygonType` cases from LoomEngine

**Export**
- PNG still export: NSSavePanel → `renders/stills/`, multiplier (1×/2×/4×/8×), scale-drawing toggle
- Video export: H.264 `.mov` via `AVAssetWriter`, `renders/animations/`, same multiplier/scale options, in-progress bar in Transport Bar
- EXPORT section in Quick Adjust: multiplier, scale drawing, FPS (24/30), frame count, computed output size
- Render directories auto-created alongside saved project file

**Timeline**
- Timeline recording: auto-capture at configurable interval while Record is active
- Timeline state playback (cut-based), state navigation (◀/▶), Timeline Editor sheet (hold durations, delete)

**Quick Adjust**
- PROJECT section: canvas preset picker, width, height
- EXPORT section: multiplier, scale drawing, FPS, frames, computed output
- CANVAS section: background colour, background draw, capture interval, grid lines, Color Map subsection
- ORDER/CHAOS section: slider wired to `CellStyle.orderChaos`; live jitter visible on canvas
- PLACE & TIME section: style, path, offset X/Y, phase, scale X/Y (linkable), rotation, Rescatter
- RENDER section: fill colour, stroke colour, stroke width, render mode
- MOTION section: appears when `controller.activeMotionSet != nil` (a motion set is selected in the left MOTIONS palette); exposes Preset picker, Speed slider, Amount slider, Phase slider, Order/Chaos slider — all bound via UUID-indexed Bindings to `projectMotionSets`; section title shows the motion set name ("MOTION — \(ms.name)")
- PATH EDITOR section: path picker, name, loop toggle, keyframe list, add keyframe, keyframe property editor (frame, dx, dy, rotation, scale X/Y, easing: Linear, Ease In, Ease Out, Ease In/Out, Step, Back In, Back Out, Back In/Out, Bounce Out)
- SEQUENCE section: mode picker (Sequential/All/Random), Frames/Step stepper — fully wired to renderer
- ADVANCED section (placeholder)

**Layer system**
- `UMLayer` (Codable struct in UMEngine) — serialisable layer value type with id, name, isVisible, opacity, document
- `UMLayerState` (@Observable @MainActor class in UMApp) — live in-memory layer wrapping `UMGridEngine` + per-layer UI state
- Layer stack in `AppController`: `layerStates: [UMLayerState]`, `activeLayerIndex`, `selectLayer()`, `addLayer()`, `removeLayer(at:)`, `duplicateLayer(at:)`, `moveLayer(from:to:)`
- The stored `engine` property always points to the active layer's engine — all existing `controller.engine.X` call sites work unchanged
- Playback advances all layer engines in lockstep; timeline recording/navigation is per-active-layer
- Multi-layer live canvas: `ctx.drawLayer { layerCtx in layerCtx.opacity = ... }` per visible layer; each layer computes cell dimensions from its own grid resolution
- Selection highlights apply only to the active layer
- `captureFrameBuffer` composites all visible layers via CoreGraphics into the accumulation buffer
- PNG export: `umRenderComposited()` composites layers at their respective opacities
- Video export: `UMVideoExporter.export(layers: [UMLayer], ...)` renders and composites per-frame
- Save/load: project file encodes `[UMLayer]` JSON array (replaces single `UMGridDocument`)
- LAYERS section at top of Project tab in Style Palette: visibility toggle, active indicator, name, opacity slider + %, add/remove/duplicate via context menu
- Layer rename: double-click the name to edit inline; Return or clicking another row commits; context menu "Rename" also available
- Layer reordering: drag-and-drop within the LAYERS list using SwiftUI `draggable`/`dropDestination` (UUID string payload); accent-colour line overlay marks the drop target row
- Layer opacity slider: mini `Slider` (56 px) in each row bound directly to `ls.opacity`; live percentage label alongside; context-menu presets (100/75/50/25%) remain
- Layer-switch crash fixed: `selectLayer` now nils `activePathID` before swapping `engine` (prevents stale Binding `get` closures firing against the wrong `paths` array); `removeLayer` also nils `activePathID` (was missing entirely); all 9 Binding `get`/`set` closures in `pathSection` and `keyframeEditor` guard against stale `pi`/`ki` indices

**Project and preferences**
- Cmd+N / Cmd+O / Cmd+S / Cmd+Shift+S
- Preferences window: custom projects directory
- Window title tracks saved filename
- Git repository: https://github.com/brogan/UM.git

---

### 12.4 Items from Earlier Spec Now Resolved

These items appeared in the §12.4 "not yet implemented" list in prior revisions and have since been built.

| Feature | Status |
|---|---|
| PNG still export | ✓ Built — multiplier + scale drawing, `renders/stills/` |
| Video export (live animation) | ✓ Built — H.264 AVAssetWriter, `renders/animations/` |
| Spatial scatter UI control | ✓ Built — tool strip slider |
| Phase step frames UI control | ✓ Built — tool strip stepper |
| Image-based color system | ✓ Built — static + video, `UMColorMapEngine`, full CANVAS UI |
| Shape library manager | ✓ Built — see §13 |
| Open curves / points / ovals | ✓ Built — all five `PolygonType` cases rendered |
| Shape rendering via assigned geometry | ✓ Built — `shapePolygonMap: [UUID: [Polygon2D]]`, decoded once per shape, looked up per cell at render time |
| `shapeID: UUID?` → `shapeIDs: [UUID]` | ✓ Built then superseded — `shapeIDs` on `CellStyle` was the multi-shape model; now replaced by direct `cell.shapeID: UUID?` (4-axis model) |
| Order/Chaos jitter | ✓ Built — sine-oscillator position/rotation/scale jitter in `computeMotion`; moved from `CellStyle.orderChaos` to `UMMotionSet.orderChaos`; subdivision-level warp remains pending |
| SEQUENCE shape cycling | ✓ Built in prior iteration then removed from renderer during 4-axis refactor — `resolvePolygons` is now a direct shapeID lookup; SEQUENCE cycling will be re-introduced as a `UMMotionSet` feature (§15.9) |
| Four-axis cell model (style / motion / shape / path) | ✓ Built 2026-06-19 — see §12.3 above |

---

## 13. Geometry Integration

### 13.1 Architecture Decision — File-Based Workflow

**Decision (2026-06-18):** Loom geometry will be integrated into UM via a file-based import workflow rather than by embedding the Loom geometry editor inside UM.

**Rationale:**

- The Loom geometry editor (`GeometryTabView.swift`, ~3500 lines) is tightly coupled to Loom's `AppController` via `@EnvironmentObject`. Embedding it in UM would require a significant refactoring pass to decouple the editor from Loom-specific app state.
- Loom is still under active development. Embedding before stabilisation would create a two-way synchronisation problem: changes to the editor would need to be managed in both applications simultaneously.
- A file-based approach unblocks UM's shape library immediately and yields useful infrastructure regardless of future integration depth.

**Future path — `LoomEditorKit`:** When Loom's geometry editor stabilises, the correct long-term architecture is to extract it as a new Swift Package target (`LoomEditorKit`) within `loom_swift/Package.swift`. The editor views would be refactored to accept `EditableGeometry` as a `Binding` and emit callbacks rather than calling Loom's `AppController`. Both Loom and UM would then declare `LoomEditorKit` as a dependency. All editor changes would be made in one place and both apps would pick them up.

**File format:** Loom geometry is stored as `.json` files using `EditableGeometryJSONLoader` (schema `loom.editableGeometry`, version 2). The `UMShape.geometryJSON` field stores the raw JSON content verbatim. At render time `AppController` decodes it via `EditableGeometryJSONLoader.decode(from:)` to obtain the runtime `[Polygon2D]` polygons.

**Loom project location:** Loom saves projects to `~/.loom_projects/<project>/`, with polygon sets in `<project>/polygonSets/*.json`. The UM import panel defaults to `~/.loom_projects` so users can navigate directly to their Loom projects.

---

### 13.2 Shape Library Manager

#### Data model

```
UMShape                                          (UMEngine/Shape/UMShape.swift)
  id:             UUID
  name:           String                         — display name (defaults to filename stem)
  sourceFilename: String                         — original Loom file name, for reference
  geometryJSON:   String                         — raw Loom polygonSet JSON content

UMGridCell.shapeID: UUID?                        — direct reference to a project shape (4-axis model)
AppController.projectShapes: [UMShape]           — project-level shape palette (shared across layers)
AppController.activeShapeID: UUID?               — the palette selection written into newly drawn cells
AppController.shapePolygonMap: [UUID: [Polygon2D]] — decoded at import/load, looked up per cell per frame
```

#### Storage

- **Project shapes** — stored as individual `.json` files in the `shapes/` subdirectory of the `.umproj` directory package. `config.json` references shapes by UUID filename. Backward-compatible: older single-file projects load shapes from inline JSON or treat missing shapes as empty.
- **Global library shapes** — individual files at `~/Library/Application Support/UM/shapes/<uuid>.json`. Scanned from the directory at startup into `AppController.globalShapes`.

#### Shape–cell assignment (4-axis model)

Shape selection is a **direct per-cell property**, not a per-style list. `cell.shapeID: UUID?` references one `UMShape` from the project palette. At paint time, `activeShapeID` is captured into the cell.

`AppController.shapePolygonMap: [UUID: [Polygon2D]]` caches decoded geometry for every project shape, rebuilt whenever shapes are added, removed, or the project loads. `resolvePolygons(shapeID:shapeMap:fallback:)` is a direct lookup — no iteration, no sequencing.

**SEQUENCE cycling** (shape animation over time) was implemented on the old per-style `shapeIDs` list. In the 4-axis model this will be re-introduced as a property of `UMMotionSet` (§15.9) — a motion set will be able to describe a cycling pattern over multiple shapes. For now, each cell renders one fixed shape.

#### UI — Style Palette SHAPES sections

Both the **Project** and **Library** tabs of the Style Palette contain a SHAPES section below PATHS.

**Project tab SHAPES:**

| Action | Result |
|---|---|
| Click a shape row | Sets `controller.activeShapeID` to this shape (toggle: click again to deselect — newly drawn cells will have no shape). The row highlights with the accent colour when this is the active shape selection. |
| **+ Import Shape…** | Opens `NSOpenPanel` (`.json` files, multiple selection, defaults to `~/.loom_projects`). Each selected file is read and added as a `UMShape` to the project; copied into `shapes/` subdirectory if project is saved. |
| **↑** button | Promotes the shape to the global library (`~/Library/Application Support/UM/shapes/<uuid>.json`). |
| Right-click → Delete Shape | Removes from project; clears `shapeID` on any cells that referenced it; clears `activeShapeID` if it matched. |

**Library tab SHAPES:**

| Action | Result |
|---|---|
| **↓** button | Copies the library shape into the project. Disabled if already present. |
| Right-click → Remove from library | Deletes the file from the shapes directory and removes it from the in-memory list. |

#### Geometry mode (future)

When `LoomEditorKit` is available, UM will gain a **Geometry mode** toggled by a toolbar button (`G`). In Geometry mode:
- The canvas is replaced by the Loom bezier editor focused on the selected shape.
- The right panel is replaced by geometry-specific controls (node properties, curve type, etc.).
- Shapes remain project-local; the promote-to-library flow is unchanged.

Until `LoomEditorKit` is ready, the toolbar Geometry mode button is absent and authoring always happens in standalone Loom.

---

## 15. Outstanding Work — What Remains to Implement

> **This section is the definitive statement of what is not yet done.** Updated 2026-06-19. Items are grouped by the phase of work they naturally belong to, roughly in priority order.

---

### 15.1 Loom Rendering Pipeline Integration

Shape rendering, Order/Chaos jitter, and SEQUENCE cycling are now built (§12.4). What remains here is the deeper Loom pipeline integration: polygon-level subdivision, brushed/stamped render modes, and animated thumbnails.

**Subdivision integration**
- The Order/Chaos jitter built so far operates on the final sprite transform (position, rotation, scale). The deeper materialisation maps `orderChaos` to `SubdivisionParams` and runs `SubdivisionEngine.process(polygons, paramSet)` to warp the polygon vertices themselves — producing organic, distorted shapes at high chaos values rather than just displaced sprites.
- Loom's `SubdivisionEngine` is already available in the linked `LoomEngine` package.
- Required: in `resolvePolygons()` (or a new post-resolve step), run `SubdivisionEngine.process` per cell using the materialised params from `orderChaos`. The existing sine-oscillator jitter in `computeMotion` would remain as the transform-layer chaos; subdivision adds the geometry-layer chaos.
- See §6.5 Phase 2.

**Full Loom rendering modes**
- Current renderer uses SwiftUI Canvas `ctx.fill` / `ctx.stroke` only (render modes: filled, stroked, filledStroked).
- Required: wire `LoomEngine.RenderEngine` for additional modes: brushed (stamp-along-path), stenciled, stamped (bitmap at positions), and path perturbation (noise warp of polygon geometry).
- Also: animated blur, opacity animation, and colour oscillator via `RendererDrivers`.

**Animated style thumbnails**
- Style palette rows show a static coloured dot.
- Required: each style row renders a small live animated preview using the style's actual geometry, motion preset, and Order/Chaos at the current frame.
- The geometry is already available via `shapePolygonMap`; the blocker is that the thumbnail renderer needs a miniature canvas pass per style per frame tick, which has a performance cost that needs careful throttling.

---

### 15.2 Canvas Interaction

**Zoom and pan** ✓ Built 2026-06-20

`AppController.canvasZoom: Double` (default 1.0) and `canvasPan: CGSize` (default .zero) drive a `CGAffineTransform` applied at the start of the `Canvas { ctx, size in }` closure via `ctx.concatenate(translationX:y:).scaledBy(x:y:)`. All canvas-space drawing (grid lines, cells, path overlay, rubber band) is unchanged — only the coordinate system shifts.

Gesture support:
- **Pinch** → `MagnificationGesture` (`.simultaneousGesture`) scales `canvasZoom` relative to `baseZoom` at gesture start.
- **Two-finger scroll / trackpad pan** → `NSEvent.addLocalMonitorForEvents(.scrollWheel)`, fires only when `canvasIsHovered`; no-modifier → pan; Option+scroll → zoom.
- **Cmd+0** → reset zoom=1.0, pan=.zero.
- **Cmd+= / Cmd+−** → zoom ×1.25 / ÷1.25.

Hit-testing: `canvasPoint(_:viewSize:gridW:gridH:)` inverse-transforms all gesture locations before they reach `handleDrag`, `handleNudge`, and `handleSelectEnd`. Rubber-band selection is stored and drawn in canvas space (drawn inside the Canvas body, not as a SwiftUI overlay).

**Hover preview on undrawn cells**
- No visual feedback on undrawn cells before the user commits a draw stroke.
- Required: when hovering in Draw or Fill mode, show a faint preview of the active style's sprite on the cell under the cursor.
- Depends on shape rendering being functional (otherwise only style colours are shown, which is minimally useful).

---

### 15.3 Export

**SVG export**
- The SVG button in the Transport Bar is a stub (no action).
- Required: wire `LoomEngine.SVGExporter` for the current frame, following the same NSSavePanel + `renders/svgs/` directory pattern as PNG.
- Depends on the Loom rendering pipeline (SVGExporter renders via the Loom polygon path, not SwiftUI Canvas).

**Video export from timeline (cut-based)**
- The Video button currently exports live animation (parametric + keyframe motion) as a continuous `.mov`.
- Required: a separate export mode (or option in the export sheet) that renders the recorded timeline states as discrete cuts — each state holds for its configured duration, then cuts to the next.
- This is a different frame-loop structure from the live-animation export.

---

### 15.4 Path Editor

**Bezier tangent handles**
- The PATH EDITOR uses a per-segment easing enum: Linear, Ease In, Ease Out, Ease In/Out, Step, Back In, Back Out, Back In/Out, Bounce Out (9 curves — Robert Penner formulas). The easing enum is retained as the fast-path default when bezier tangent handles are added.
- Required: cubic bezier tangent handles (`inTangent`, `outTangent`) on each keyframe, drawn as draggable handle circles on the canvas path overlay.
- Full design in §12.1. Data model change is backward-compatible (zero-length tangent = current linear interpolation).

---

### 15.5 In-App Geometry Authoring

**Geometry mode (LoomEditorKit)**
- Shapes must currently be authored in standalone Loom and imported via the Style Palette SHAPES section.
- Required: extract Loom's geometry editor as a `LoomEditorKit` Swift Package target; wire it into UM as a canvas overlay entered via a toolbar Geometry (G) button.
- Full design in §13.1. This is a significant extraction effort that depends on Loom's editor stabilising first.
- Until then, the file-based import workflow is the only path.

---

### 15.6 Canvas Overlays and Visual Aids

**Phase heat-map overlay**
- No per-cell phase visualisation on the canvas.
- Required: a toggleable overlay that colours each drawn cell by its `phaseOffset` value (e.g. a heat-map from blue = 0 to red = max), making the temporal structure of the composition visible without playing the animation.

**Background image**
- The CANVAS section supports a solid background colour only.
- Required: an option to load a visible image that is composited behind the grid as a backdrop, distinct from the Color Map (which recolors sprites but never renders the image itself).

---

### 15.7 Compatibility

**Legacy UM XML import**
- No importer for Java UM `.xml` project files.
- Required: read the Java XOM XML format (GridSquare drawn states, DrawSet/Drawer/Animator/KeyFrame trees); map to `UMGridDocument`; all cells get `positionOffset: .zero` and `phaseOffset: 0` as they carry none in the Java format.
- Useful for migrating existing Java UM work but not on the critical path.

---

### 15.8 Camera and Parallax System ✓ Built 2026-06-19

**Architecture**

Six new files ported from Loom into `UMEngine/Sources/UMEngine/Animation/` and `Scene/`:

| File | Contents |
|---|---|
| `UMVec2.swift` | Lightweight 2D vector (avoids name clash with Loom's `Vector2D`) |
| `UMLoopMode.swift` | `loop / once / pingPong` loop modes |
| `DoubleDriver.swift` | `UMDoubleDriver` — 5 modes (constant, oscillator, jitter, noise, keyframe) |
| `VectorDriver.swift` | `UMVectorDriver` — same modes, 2D output |
| `DriverEvaluator.swift` | Stateless evaluator; hash-based jitter/noise; smooth value noise |
| `UMCamera.swift` | `UMCamera(pan:UMVectorDriver, zoom:UMDoubleDriver, rotation:UMDoubleDriver)` + `UMCameraFrame` evaluated snapshot |

`UMLayer` gains three new fields (all backward-compatible `decodeIfPresent`):
- `parallaxFactor: Double` — 0 = background-fixed, 1 = full camera tracking (default 1.0)
- `layerOffset: UMVectorDriver` — independent per-layer positional offset driver
- `opacityDriver: UMDoubleDriver` — animated opacity (wired at Phase 2; constant mode tracks `opacity` slider)

**Parallax convention**

```
layerTranslation = (-camPan.x * parallaxFactor + layerOffset.x,
                    -camPan.y * parallaxFactor + layerOffset.y)
```
Camera zoom and rotation are applied equally to all layers (pivot at canvas centre). Only pan is parallax-weighted per layer.

- `parallaxFactor = 0.0` — background fixed to screen; camera pans over it
- `parallaxFactor = 1.0` — world-space foreground; moves fully with camera

**Per-layer transform helper**

```swift
func umLayerTransform(cameraFrame: UMCameraFrame, parallaxFactor: Double,
                      layerOffset: UMVec2, canvasW: Double, canvasH: Double) -> CGAffineTransform
```
Used in three paths: live canvas `drawLayer`, `umRenderComposited`, `UMVideoExporter.renderLayerCells`.

**AppController**

```swift
var camera: UMCamera = .identity  // project-level
```
`ProjectConfig` gains `camera: UMCamera?` (v4, nil → `.identity`). Layer records gain `parallaxFactor?`, `layerOffset?`, `opacityDriver?` (all optional for v3 backward compat). Camera is reset to `.identity` on `newDocument()` and `readLegacy()`.

**UI**

- CAMERA section in Quick Adjust: Pan X/Y sliders (−500…500), Zoom (0.1–4×), Rotation (−180°–180°), Reset button.
- Parallax slider per layer row (camera icon + compact 0–1 slider).

**Phase 2 (remaining)**
- Expose oscillator / keyframe modes for camera drivers in UI
- Wire `opacityDriver` into live canvas + export when mode ≠ constant
- Layer blend modes

---

### 15.9 Left Panel Restructure and Motion Palette UI ✓ Built 2026-06-20

**What was built (2026-06-19 + 2026-06-20)**

The full 4-axis UI is now implemented across the left panel and the right panel:

**Left panel (StylePaletteView)**

- **LAYERS** section — layer CRUD, visibility, opacity slider, parallax slider, drag-to-reorder, rename ✓
  - Resolution preset chips embedded in section (4×4 through 32×32 + project presets) ✓
- **STYLES** section — full CRUD, variants, library promote/import ✓
- **MOTIONS** section ✓ — lists `projectMotionSets`; click to set `activeMotionID` (highlighted row); click highlighted row again to deselect; double-click name to rename; `+` New Motion; ↑ promote to library; delete via context menu
- **PATHS** section — full CRUD, keyframe count badge, library promote/import ✓
- **SHAPES** section — import, library promote/import, click to set `activeShapeID` ✓
- **PALETTES** section — generate from color map, library promote/import ✓

**Right panel (QuickAdjustView)**

- **MOTION section** (when `activeMotionSet != nil`): Preset, Speed, Amount, Phase, Order/Chaos ✓
  - **SEQUENCE subsection** ✓: Sequence Mode picker (Off / Sequential / Random); Step field (frames per shape, 1–480); shape slot list (per-slot shape picker + − remove button; + Add Shape button)
- **PLACE & TIME section** — all four axis pickers now present ✓:
  - Style, Motion, Shape, Path — each a Picker over the project palette for that axis; shows focused-cell value, writes to all selected cells via `assignXxxToSelection`

**Model changes (2026-06-20)**

`UMMotionSet` gained:
```swift
public enum SequenceMode: String, Codable, CaseIterable, Sendable {
    case off, sequential, random
}
public var sequenceMode: SequenceMode  // default .off
public var shapeIDs: [UUID]            // shapes to cycle through; omitted from JSON when empty
```

`resolveSequenceShapeID(motionSet:cellShapeID:frame:phaseOffset:)` — pure function in `GridScrollUtils.swift` applied at all three render paths (CG accumulation, live canvas, FrameCapture/export) before `resolvePolygons`.

**What remains (still pending)**

- **Full right-panel context-switching** — when a STYLE or SHAPE palette item is active and no cell is selected, the right panel could show a dedicated detail section for that item (currently only MOTION does this). Medium scope.
- **"Nothing active" hint** — a contextual hint row shown when nothing is selected and no palette item is active.
- **Resolution palette Project/Library tabs** — the preset chips exist in the LAYERS section but there is no separate library tab for saving/loading resolution presets globally. Small scope.

---

---

### 15.10 Colour Palette Chooser ✓ Built 2026-06-19

**What was built** differs from the original k-means extraction plan. Rather than deriving a palette algorithmically and creating new `CellStyle` entries, a simpler and more direct approach was taken:

- Palettes are independent `UMColorPalette` entities (not wrappers around `CellStyle`)
- Sampling uses the same GPU bilinear averaging already in `UMColorMapEngine` — no k-means needed
- Colors are applied directly to an existing style's fill or stroke via a popover picker — no new style creation
- Alpha is controllable at the point of picking, not baked into the palette

**Workflow**
1. Load a Color Map source (static image or video) in the CANVAS section.
2. In the PALETTES section of the left panel (Project tab), click **Generate from Color Map…**.
3. Enter a name and choose a size: 4×4 (16 colors), 4×8 (32 colors), or 8×8 (64 colors). UM samples the source image into the selected grid and stores it as a named `UMColorPalette`.
4. The palette appears as a swatch strip in the PALETTES list. Multiple palettes can coexist.
5. In the RENDER section of Quick Adjust, click the `swatchpalette` icon next to Fill or Stroke. A popover shows the palette's swatch grid (8 per row). Adjust the alpha slider, then click any swatch to apply that color + alpha to the active style.
6. Promote a palette to the global library (↑ button) to reuse it across projects.

**What the original plan deferred to future work**
- k-means / median-cut clustering to find representative colors (the bilinear grid average already produces useful, spatially coherent palettes for most use cases)
- Accept/reject per-swatch review step
- Auto-naming heuristics (e.g. "Warm Ochre")
- Style-remapping mode (recolor all existing styles to the nearest palette entry)

---

### 15.11 Keyframe Timeline ✓ Built 2026-06-20

**What was built**

The full keyframe timeline is implemented. Every item in the original phased plan was delivered except the timing-scale % field (item 13 below).

**Model (`UMTimelineTypes.swift`, `UMEngine/Scene/UMCamera.swift`)**

`UMCamera` was built with `pan: UMVectorDriver` from the start — the proposed panX/panY consolidation was never needed. `UMLayer` carries `opacityDriver: UMDoubleDriver`, `layerOffset: UMVectorDriver`, and `gridScrollDriver: UMVectorDriver`; all are evaluated per-frame at every render path.

```swift
enum UMTimelineLane: Int, CaseIterable, Hashable {
    case opacity    = 0   // pink  — UMDoubleDriver keyframes
    case offset     = 1   // blue  — UMVectorDriver keyframes (x, y)
    case gridScroll = 2   // orange — UMVectorDriver keyframes (scroll x, y)
}

enum UMCameraLane: Int, CaseIterable, Hashable {
    case pan      = 0   // teal  — UMVectorDriver
    case zoom     = 1   // green — UMDoubleDriver
    case rotation = 2   // cyan  — UMDoubleDriver
}
```

`UMKFClipboard`, `UMTimelineKFSelection`, `UMCameraKFSelection`, `UMTimelineMarker` — all in `UMTimelineTypes.swift`. The `TLSnapshot` tuple for undo captures all three layer drivers plus the full camera state (50-state stack).

**Panel layout (`UMTimelinePanel.swift`, 1174 lines)**

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  ━━━━━━━━━━━━━━━━  (resize handle — drag to resize, tap to collapse)         │
├──────────────────┬───────────────────────────────────────────────────────────┤
│ HEADER COLUMN    │  CANVAS                                                   │
│  − + ⊕ markers  │  [marker strip — 18 px, named bookmark triangles]         │
│                  │  [ruler — 28 px, adaptive tick marks + frame numbers]     │
│  ▶ Camera        │  camera summary row (all KF diamonds, teal)               │
│    · Pan         │  · Pan lane (teal)                                        │
│    · Zoom        │  · Zoom lane (green)                                      │
│    · Rotation    │  · Rotation lane (cyan)                                   │
│  ▶ Layer 1       │  layer 1 summary row (all KF diamonds, accent)            │
│    · Opacity     │  · Opacity lane (pink)                                    │
│    · Offset      │  · Offset lane (blue)                                     │
│    · Scroll      │  · Grid Scroll lane (orange)                              │
│  ▶ Layer 2 …     │  …                                                        │
└──────────────────┴───────────────────────────────────────────────────────────┘
```

- Resize handle: drag to set panel height; tap to collapse/expand (`isTimelineCollapsed` on `AppController`).
- Header column: zoom −/+ buttons, named-marker jump menu, trash button (when selection non-empty).
- Camera and layer blocks: chevron expand/collapse; lane rows show a coloured KF-present dot and enable checkbox.
- Canvas drawn with SwiftUI `Canvas`. `zoom: Double` (px/frame, default 4.0), `hOffset: Double` (scroll offset in px). Option+scroll zooms; drag pans.
- Playhead: red vertical line + downward triangle cap.

**Interactions**

| Gesture | Effect |
|---|---|
| Click on ruler | Seek playhead to that frame |
| Drag on ruler | Scrub playhead |
| Click on lane row (not on a KF) | Add KF at that frame, capturing current evaluated value; switches driver to keyframe mode |
| Click on KF diamond | Select it; seek playhead to its frame |
| Drag selected KF diamond | Move KF to new frame (live preview while dragging) |
| Shift+click | Additive select |
| Drag on empty area | Rubber-band multi-select |
| Option+drag | Pan timeline horizontally |
| Double-click marker strip | Create named marker (bookmark icon, rename inline) |
| Cmd+C / Cmd+V | Copy / paste selected KFs at playhead (relative offsets preserved) |
| Cmd+Z / Cmd+Shift+Z | Timeline undo / redo (50-state stack) |
| Delete | Delete selected KFs; driver reverts to `.constant` when last KF removed |
| Cmd+A | Select all KFs on all visible lanes |

**Keyframe inspector (Quick Adjust → KEYFRAME section)**

Appears when any KF is selected. Shows: lane label (read-only), Frame stepper, Value fields (scalar or X/Y for vectors), Easing picker (Linear, Ease In, Ease Out, Ease In/Out, Step, Back In, Back Out, Back In/Out, Bounce Out). Edits commit immediately with undo.

**Transport bar additions**

- `isTimelineCollapsed` toggle button — show/hide the timeline panel.
- `showScrubBar` toggle — full-width scrub slider below the transport bar.
- Start frame / End frame fields wired to `controller.startFrame` / `controller.endFrame`.

**Not built from the original plan**

- **Timing-scale % field** — select ≥ 2 KFs, type a percentage, and scale their timing from the earliest-frame pivot. This was item 13 of the phased plan and was not implemented. Everything else was delivered.
- **Start/end drag handles on the ruler** — the spec described draggable orange/red triangles on the ruler for the start/end frame region. Start and end frames are editable via the transport bar fields instead; ruler handles were not added.

---

### Summary Table

| Area | Item | Depends on |
|---|---|---|
| **UI** | Motion palette UI (MOTIONS section in left panel) | ✓ Built 2026-06-20 |
| **UI** | 4-axis cell inspector in PLACE & TIME (Style, Motion, Shape, Path pickers) | ✓ Built 2026-06-20 |
| **UI** | SEQUENCE cycling (motion set shapeIDs + mode + step) | ✓ Built 2026-06-20 |
| **UI** | Full right-panel context-switching (Style/Shape detail when those palette items active) | 4-axis model ✓ |
| **UI** | Resolution palette Project/Library tabs (global presets) | — |
| **Rendering** | Subdivision integration (polygon-level warp) | — |
| **Rendering** | Full Loom render modes (brushed, stamped, perturbation, blur) | — |
| **Rendering** | Animated style thumbnails | — |
| **Canvas** | Zoom and pan | — |
| **Canvas** | Hover preview on undrawn cells | — |
| **Export** | SVG export | Loom pipeline |
| **Export** | Video export from timeline (cut-based) | — |
| **Path editor** | Bezier tangent handles | — |
| **Geometry** | In-app geometry editor (LoomEditorKit) | Loom stabilisation |
| **Overlays** | Phase heat-map overlay | — |
| **Overlays** | Background image | — |
| **Layers** | Camera system (pan, zoom, rotation) | ✓ Built 2026-06-19 |
| **Layers** | Parallax (per-layer depth factor) | ✓ Built 2026-06-19 |
| **Layers** | Per-layer blend modes | — |
| **Layers** | Animated layer opacity / parallax drivers (oscillator UI) | Phase 2 of §15.8 |
| **Timeline** | Keyframe timeline panel (camera + per-layer lanes) | ✓ Built 2026-06-20 |
| **Timeline** | Timing-scale % field (scale selected KF timing from pivot) | — |
| **Layers** | Per-layer color maps | ✓ Built 2026-06-19 |
| **Compat** | Legacy UM XML import | — |
| **Color** | ~~Color map palette extraction → styles~~ → palette chooser | ✓ Built 2026-06-19 |
