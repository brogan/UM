import SwiftUI
@preconcurrency import WebKit

// MARK: - Public surface

struct HelpView: View {
    var body: some View {
        HelpWebView()
            .frame(minWidth: 780, minHeight: 540)
    }
}

struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("UM Help") { openWindow(id: "umhelp") }
            .keyboardShortcut("/", modifiers: .command)
    }
}

// MARK: - WKWebView wrapper

private struct HelpWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(HelpSchemeHandler(), forURLScheme: "um-help")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: URL(string: "um-help://help/intro")!))
        return wv
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ wv: WKWebView,
                     decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let scheme = action.request.url?.scheme else { return .allow }
            return scheme == "um-help" ? .allow : .cancel
        }
    }
}

// MARK: - URL scheme handler

private class HelpSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let path = task.request.url?.host == "help"
            ? (task.request.url?.lastPathComponent ?? "intro")
            : "intro"
        let html = helpPages[path] ?? helpPages["intro"]!
        let data = Data(html.utf8)
        let resp = URLResponse(url: task.request.url!,
                               mimeType: "text/html",
                               expectedContentLength: data.count,
                               textEncodingName: "utf-8")
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

// MARK: - Page template

private func page(_ title: String, _ body: String) -> String { """
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8">
<title>\(title) — UM Help</title>
<style>\(css)</style>
</head>
<body>
<div class="layout">
<nav>\(nav)</nav>
<main id="main">\(body)</main>
</div>
<script>
document.querySelectorAll('nav a[href]').forEach(function(a){
  if(a.href===window.location.href) a.classList.add('active');
});
</script>
</body></html>
""" }

// MARK: - Pages registry

private let helpPages: [String: String] = [
    "intro":      page("Introduction",            introBody),
    "layout":     page("Interface Layout",        layoutBody),
    "layers":     page("Working with Layers",     layersBody),
    "painting":   page("Painting Tools",          paintingBody),
    "transforms": page("Grid Transforms",         transformsBody),
    "phase":      page("Phase Policy & Scatter",  phaseBody),
    "playback":   page("Playback & Recording",    playbackBody),
    "qa-project": page("PROJECT / CANVAS / CAMERA", qaProjectBody),
    "qa-style":   page("Style (RENDER section)",    qaStyleBody),
    "qa-motion":  page("Motion Palette",           qaMotionBody),
    "qa-path":    page("PATH EDITOR",             qaPathBody),
    "qa-place":   page("PLACE & TIME",            qaPlaceBody),
    "palette":    page("Style Palette",           paletteBody),
    "export":     page("Export",                  exportBody),
    "resample":   page("Resample Grid",           resampleBody),
    "save":       page("Save, Load & Undo",       saveBody),
    "shortcuts":  page("Keyboard Shortcuts",      shortcutsBody),
    "pending":    page("Not Yet Built",           pendingBody),
]

// MARK: - Shared CSS

private let css = #"""
:root{
  --bg:#f2f2f7;--nav:#fff;--surface:#fff;--text:#1c1c1e;
  --sub:#636366;--accent:#0071e3;--border:rgba(0,0,0,.1);
  --code:rgba(0,0,0,.05);--note-bg:rgba(0,113,227,.07);
  --note-br:rgba(0,113,227,.35);--tip-bg:rgba(52,199,89,.07);
  --tip-br:rgba(52,199,89,.35);--warn-bg:rgba(255,159,10,.08);
  --warn-br:rgba(255,159,10,.4);
}
@media(prefers-color-scheme:dark){
  :root{--bg:#000;--nav:#1c1c1e;--surface:#1c1c1e;--text:#f5f5f7;
    --sub:#98989d;--accent:#0a84ff;--border:rgba(255,255,255,.1);
    --code:rgba(255,255,255,.07);--note-bg:rgba(10,132,255,.1);
    --note-br:rgba(10,132,255,.35);--tip-bg:rgba(52,199,89,.1);
    --tip-br:rgba(52,199,89,.35);--warn-bg:rgba(255,159,10,.1);
    --warn-br:rgba(255,159,10,.4);}
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif;
  font-size:13px;line-height:1.56;color:var(--text);background:var(--bg)}
.layout{display:flex;height:100vh;overflow:hidden}
nav{width:196px;flex-shrink:0;background:var(--nav);border-right:1px solid var(--border);
  overflow-y:auto;padding:10px 0 20px}
.nav-logo{display:block;font-size:15px;font-weight:700;color:var(--text);padding:8px 14px 12px;
  text-decoration:none;letter-spacing:-.01em}
.nav-group{font-size:10px;font-weight:700;letter-spacing:.07em;text-transform:uppercase;
  color:var(--sub);padding:10px 14px 3px}
nav a{display:block;padding:4px 10px;text-decoration:none;color:var(--text);font-size:12px;
  border-radius:5px;margin:1px 4px}
nav a:hover{background:rgba(0,0,0,.05)}
nav a.active{background:var(--accent);color:#fff}
@media(prefers-color-scheme:dark){nav a:hover{background:rgba(255,255,255,.08)}}
main{flex:1;overflow-y:auto;padding:28px 34px 40px;background:var(--surface)}
h1{font-size:22px;font-weight:700;margin-bottom:6px;letter-spacing:-.02em}
.subtitle{color:var(--sub);font-size:13.5px;margin-bottom:20px}
h2{font-size:15px;font-weight:600;margin:26px 0 8px;border-bottom:1px solid var(--border);padding-bottom:5px}
h3{font-size:13.5px;font-weight:600;margin:18px 0 6px}
h4{font-size:12px;font-weight:600;margin:14px 0 4px;color:var(--sub);text-transform:uppercase;letter-spacing:.05em}
p{margin-bottom:10px}
ul,ol{margin:6px 0 10px 20px}
li{margin-bottom:4px}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
table{width:100%;border-collapse:collapse;margin:8px 0 14px;font-size:12px}
th{text-align:left;padding:6px 10px;background:var(--code);border-bottom:2px solid var(--border);font-weight:600}
td{padding:5px 10px;border-bottom:1px solid var(--border);vertical-align:top}
tr:last-child td{border-bottom:none}
pre{background:var(--code);border:1px solid var(--border);border-radius:7px;
  padding:12px 14px;font-family:'SF Mono','Menlo',monospace;font-size:11.5px;
  line-height:1.45;overflow-x:auto;margin:10px 0;white-space:pre}
code{font-family:'SF Mono','Menlo',monospace;font-size:11.5px;background:var(--code);
  border:1px solid var(--border);border-radius:3px;padding:1px 5px}
kbd{display:inline-block;font-family:-apple-system,sans-serif;font-size:11px;font-weight:500;
  background:var(--code);border:1px solid var(--border);border-radius:4px;padding:1px 6px;
  box-shadow:0 1px 0 var(--border)}
.note{background:var(--note-bg);border-left:3px solid var(--note-br);border-radius:0 6px 6px 0;
  padding:9px 13px;margin:12px 0;font-size:12.5px}
.tip{background:var(--tip-bg);border-left:3px solid var(--tip-br);border-radius:0 6px 6px 0;
  padding:9px 13px;margin:12px 0;font-size:12.5px}
.warn{background:var(--warn-bg);border-left:3px solid var(--warn-br);border-radius:0 6px 6px 0;
  padding:9px 13px;margin:12px 0;font-size:12.5px}
.note strong,.tip strong,.warn strong{display:block;margin-bottom:2px}
ol.steps{list-style:none;counter-reset:step;margin-left:0}
ol.steps li{counter-increment:step;position:relative;padding-left:32px;margin-bottom:10px}
ol.steps li::before{content:counter(step);position:absolute;left:0;top:1px;width:22px;height:22px;
  background:var(--accent);color:#fff;border-radius:50%;font-size:11px;font-weight:700;
  display:flex;align-items:center;justify-content:center}
"""#

// MARK: - Navigation HTML

private let nav = #"""
<a class="nav-logo" href="um-help://help/intro">UM Help</a>
<div class="nav-group">Getting Started</div>
<a href="um-help://help/intro">Introduction</a>
<a href="um-help://help/layout">Interface Layout</a>
<div class="nav-group">Layers</div>
<a href="um-help://help/layers">Working with Layers</a>
<div class="nav-group">Tools &amp; Canvas</div>
<a href="um-help://help/painting">Painting Tools</a>
<a href="um-help://help/transforms">Grid Transforms</a>
<a href="um-help://help/phase">Phase Policy &amp; Scatter</a>
<div class="nav-group">Playback</div>
<a href="um-help://help/playback">Playback &amp; Recording</a>
<div class="nav-group">Quick Adjust</div>
<a href="um-help://help/qa-project">PROJECT / CANVAS</a>
<a href="um-help://help/qa-style">Style (RENDER)</a>
<a href="um-help://help/qa-motion">Motion Palette</a>
<a href="um-help://help/qa-path">PATH EDITOR</a>
<a href="um-help://help/qa-place">PLACE &amp; TIME</a>
<div class="nav-group">Assets &amp; Files</div>
<a href="um-help://help/palette">Style Palette</a>
<a href="um-help://help/export">Export</a>
<a href="um-help://help/resample">Resample Grid</a>
<a href="um-help://help/save">Save, Load &amp; Undo</a>
<div class="nav-group">Reference</div>
<a href="um-help://help/shortcuts">Keyboard Shortcuts</a>
<a href="um-help://help/pending">Not Yet Built</a>
"""#

// MARK: - Page content

private let introBody = #"""
<h1>UM</h1>
<p class="subtitle">A grid-based drawing and animation program for macOS.</p>

<h2>What UM is</h2>
<p>UM is built around a simple idea: paint cells on a grid, and watch the result play back as a live animation. Every cell you mark can carry its own shape, colour, render mode, and motion — and the whole composition plays continuously as you work.</p>
<p>The grid is UM's greatest strength. It gives your composition structure: you can flip it, rotate it, change its resolution, flood-fill it, and build symmetrical patterns in seconds. But grids also have a reputation for looking mechanical and lock-stepped. UM resolves this through two ideas.</p>

<h2>The central insight: grid as topology, not geometry</h2>
<p>The grid determines <em>structure</em> — which cells are adjacent, what flipping and rotating means, how resolution change maps cells to new cells. It does <strong>not</strong> determine where the sprite actually sits on screen, and it does not determine when each cell's animation begins.</p>
<p>Those are independent per-cell properties:</p>
<ul>
  <li><strong>Position offset</strong> — a nudge from the cell's nominal centre, in absolute pixels. A sprite displaced 12 px to the right remains 12 px to the right after a resolution change, a flip, or a rotation. The visual arrangement you built is preserved exactly.</li>
  <li><strong>Phase offset</strong> — a frame-count shift that controls where each cell enters the animation cycle. A cell with phase offset 24 is always 24 frames ahead of a cell at offset 0. Painting with the Spatial or Sequential phase policy fills the grid with a wave of staggered timing automatically.</li>
</ul>
<p>The practical result: you can work quickly with the grid's structural tools and still end up with compositions that feel organic and hand-placed rather than mechanical.</p>

<h2>Four independent creative axes</h2>
<p>Every drawn cell carries four independent axis assignments that are combined at render time:</p>
<ul>
  <li><strong>Style</strong> — the visual character: fill colour, stroke colour, stroke width, and render mode (filled, stroked, or both). Styles are palette items shared across all layers.</li>
  <li><strong>Motion</strong> — the animation behaviour: a named <em>motion set</em> that carries a parametric preset (Spin, Wave, Jitter…), speed, amount, phase, Order/Chaos, and per-axis mix controls. Motion sets are palette items; changing the active motion set before painting affects newly drawn cells only.</li>
  <li><strong>Shape</strong> — the geometry: a named Loom polygon file imported into the project. One shape per cell; changing the active shape affects newly drawn cells only.</li>
  <li><strong>Path</strong> — a keyframe motion path: a named, reusable sequence of position/rotation/scale keyframes that loops at a set rate.</li>
</ul>
<p>Motion and path are <strong>additive</strong>: a cell with the Spin motion preset and an Orbit path will spin in place <em>while</em> following the orbit.</p>

<h2>ORDER / CHAOS</h2>
<p>A single slider per <em>motion set</em> controls the amount of organic irregularity. At full <strong>Order</strong>, sprites behave precisely. At full <strong>Chaos</strong>, layered sine-wave jitter displaces each sprite's position (±30% of cell size), rotation (±90°), and scale (±40%) — each cell getting a unique seed so no two are ever in sync.</p>

<h2>Multiple layers</h2>
<p>Compositions can stack multiple independent layers, each with its own grid, styles, and opacity. Layers composite bottom-to-top in real time, and each layer exports at its configured opacity.</p>

<h2>Color maps</h2>
<p>A static image or video file can drive the fill and/or stroke color of every sprite in the composition. UM samples the average color of each grid cell's region from the image and applies it at render time. The image is never shown directly — it exists purely as a color source. Combined with motion paths and the ORDER/CHAOS jitter, even a simple single-style composition can produce rich, image-sourced color variation.</p>

<h2>The creative loop</h2>
<p>The canvas is always live. You paint cells, watch the animated result, adjust the style or phase policy or ORDER/CHAOS slider, paint more. The tool strip, style palette, and quick-adjust panel keep everything in one view — no tab switching, no separate windows.</p>
<div class="tip"><strong>Where to go next</strong> — <a href="um-help://help/layout">Interface Layout</a> gives you the full map of the screen. <a href="um-help://help/painting">Painting Tools</a> explains how to draw and the keyboard shortcuts.</div>
"""#

private let layoutBody = #"""
<h1>Interface Layout</h1>
<p class="subtitle">Four panels, always visible, always live.</p>

<pre>
┌─────────────────────────────────────────────────────────────────────┐
│  TOOL STRIP                                                         │
│  [D][E][S][A][F][N]  [↔][↕][↺][↻][⊡][⊟]  Move│Stamp  Δφ:+0       │
│  φ:[Spatial ▼] step: 4fr   Scatter:──●──  ☐Stretch  [6×6 ▾]       │
├───────────────┬─────────────────────────────┬───────────────────────┤
│               │                             │                       │
│  STYLE        │  GRID CANVAS                │  QUICK ADJUST         │
│  PALETTE      │  (live, always animated)    │                       │
│               │                             │  ▶ PROJECT            │
│  Project  Lib │  ·  ·  ■  ·  ·  ·          │  ▶ EXPORT             │
│               │  ·  ■  ■  ■  ·  ·          │  ▶ CANVAS             │
│  ● LAYERS     │  ·  ·  ■  ·  ·  ·          │  ▶ PLACE & TIME       │
│  ● STYLES     │                             │  ▶ RENDER             │
│  ● MOTIONS    │                             │  ▶ PATH EDITOR        │
│  ● PATHS      │                             │  ▶ ADVANCED           │
│  ● SHAPES     │                             │                       │
│               │                             │  (Motion palette      │
│               │                             │   detail — pending)   │
├───────────────┴─────────────────────────────┴───────────────────────┤
│  TRANSPORT BAR  ⏮  ▶  ●  frame 0 / 120  [PNG] [SVG] [Video]       │
└─────────────────────────────────────────────────────────────────────┘
</pre>

<h2>Tool Strip</h2>
<p>Runs across the top of the window. Always visible. Three groups left to right:</p>
<ul>
  <li><strong>Painting tools</strong> — Draw, Erase, Select, Sample, Fill, Nudge. See <a href="um-help://help/painting">Painting Tools</a>.</li>
  <li><strong>Grid transforms</strong> — flip, rotate, clear, invert, with Move/Stamp toggle. See <a href="um-help://help/transforms">Grid Transforms</a>.</li>
  <li><strong>Phase policy, step, scatter, stretch, resolution</strong> — controls that apply at paint time. See <a href="um-help://help/phase">Phase Policy &amp; Scatter</a>.</li>
</ul>

<h2>Style Palette</h2>
<p>The left panel. Two tabs: <strong>Project</strong> and <strong>Library</strong>.</p>
<p>The Project tab lists everything belonging to the current document — layers, styles, motion sets, motion paths, and imported shapes. Click a style to make it the active painting style. Click a motion set to make it the active motion. Click a shape to make it the active shape. Click a path to start editing its keyframes in the PATH EDITOR panel.</p>
<p>The Library tab shows your global user library of saved styles, paths, and shapes — shared across all projects.</p>
<p>See <a href="um-help://help/layers">Working with Layers</a> and <a href="um-help://help/palette">Style Palette</a> for full details.</p>

<h2>Grid Canvas</h2>
<p>The live, always-animated centre panel. This is where you paint. The canvas is letterboxed to maintain the output aspect ratio set in the PROJECT section — the neutral border outside the canvas area is not part of the output.</p>
<p>All painting tools operate directly on the canvas. The motion path overlay appears here when a path is active.</p>
<p><strong>Zoom and pan:</strong> Pinch to zoom, scroll (two-finger trackpad) to pan, <kbd>⌥</kbd>+scroll to zoom. <kbd>⌘0</kbd> resets to fit. <kbd>⌘=</kbd> / <kbd>⌘−</kbd> step zoom. Zoom and pan are view-only — they do not affect export or the project file.</p>

<h2>Quick Adjust</h2>
<p>The right panel. A stack of collapsible sections — click any section header to expand or collapse it. The upper three sections (PROJECT, EXPORT, CANVAS) are project-wide. All sections below them operate on the currently active style or selected cells.</p>
<p>See the <a href="um-help://help/qa-project">Quick Adjust</a> pages for full details on each section.</p>

<h2>Transport Bar</h2>
<p>Runs across the bottom. Controls playback, recording, frame navigation, and export. See <a href="um-help://help/playback">Playback &amp; Recording</a> and <a href="um-help://help/export">Export</a>.</p>
"""#

private let layersBody = #"""
<h1>Working with Layers</h1>
<p class="subtitle">Stack independent grids and composite them at configurable opacities.</p>

<p>Layers let you build up a composition from separate, independently configurable grids. Each layer has its own cells, styles, shapes, and paths. All visible layers composite bottom-to-top in real time on the shared canvas. Layers can have different grid resolutions occupying the same canvas area.</p>

<h2>The LAYERS section</h2>
<p>Open the Style Palette's <strong>Project</strong> tab. The <strong>LAYERS</strong> section sits at the top. Each row shows:</p>
<table>
  <tr><th>Element</th><th>Description</th></tr>
  <tr><td>Eye icon</td><td>Click to toggle the layer's visibility on and off. Hidden layers are excluded from the canvas and from exports.</td></tr>
  <tr><td>Accent dot</td><td>Filled with the accent colour when this is the active layer; faint otherwise.</td></tr>
  <tr><td>Layer name</td><td>The editable name. Double-click to rename inline.</td></tr>
  <tr><td>Opacity slider</td><td>A mini slider (0–100%) that adjusts the layer's compositing opacity continuously.</td></tr>
  <tr><td>Opacity %</td><td>Live readout alongside the slider.</td></tr>
  <tr><td>Camera icon + parallax slider</td><td>A compact 0–1 slider controlling how much camera movement this layer responds to. See Camera &amp; Parallax below.</td></tr>
</table>

<h2>Selecting the active layer</h2>
<p>Click any layer row to make it active. All painting, style editing, path editing, and Quick Adjust operations apply to the active layer only. The selection highlight on the canvas applies only to the active layer's cells.</p>

<h2>Renaming a layer</h2>
<ol class="steps">
  <li>Double-click the layer name in the palette row. The name turns into an editable text field.</li>
  <li>Type the new name.</li>
  <li>Press <kbd>Return</kbd> or click anywhere else to commit. The name updates immediately.</li>
</ol>
<p>Alternatively, right-click the layer row and choose <strong>Rename</strong> from the context menu.</p>

<h2>Adjusting opacity</h2>
<p>Drag the mini slider in the layer row left (more transparent) or right (more opaque). The canvas updates live as you drag. The percentage label shows the current value.</p>
<p>Right-clicking the row also gives quick opacity presets: 100%, 75%, 50%, 25%.</p>

<h2>Reordering layers</h2>
<ol class="steps">
  <li>Click and hold a layer row.</li>
  <li>Drag it up or down. A blue accent line appears between rows showing where the layer will land.</li>
  <li>Release to drop. The layer moves to that position and the canvas recomposes immediately.</li>
</ol>
<div class="note"><strong>Layer order</strong> — layers are composited bottom-to-top. A layer at the top of the list renders in front of layers below it.</div>

<h2>Adding and removing layers</h2>
<ul>
  <li>Click <strong>+ New Layer</strong> below the layer list to add a new layer. It inherits the active layer's grid resolution and becomes the active layer.</li>
  <li>Right-click a layer row → <strong>Duplicate</strong> to copy the layer including all its cells, styles, and paths.</li>
  <li>Right-click → <strong>Delete Layer</strong> to remove it. Disabled when only one layer remains.</li>
</ul>

<h2>Layers and export</h2>
<p>PNG and video exports composite all visible layers at their configured opacities. Hidden layers are excluded. Each layer uses its own grid resolution when rendering — a 4×4 foreground layer and an 8×8 background layer both occupy the full canvas area, each drawn at their respective cell sizes.</p>

<h2>Layers and the timeline</h2>
<p>Timeline recording and state navigation operate on the <em>active layer</em> only. Other layers are unaffected by loading a recorded state.</p>
<div class="tip"><strong>Typical workflow</strong> — build a background layer (large cells, slow motion, low opacity), add a foreground layer (smaller cells, faster motion), and adjust the balance with the opacity sliders. Each layer can have its own color map source for complex image-driven color effects.</div>

<h2>Camera and parallax</h2>
<p>The <strong>CAMERA</strong> section in Quick Adjust lets you position a virtual camera over the entire composition. All layers render through the camera:</p>
<table>
  <tr><th>Control</th><th>Range</th><th>Description</th></tr>
  <tr><td>Pan X / Y</td><td>−500 … 500 px</td><td>Shift the camera horizontally and vertically in canvas pixels.</td></tr>
  <tr><td>Zoom</td><td>0.1 – 4.0×</td><td>Scale the canvas from its centre. 1.0 = no zoom.</td></tr>
  <tr><td>Rotation</td><td>−180° … 180°</td><td>Rotate the canvas around its centre.</td></tr>
  <tr><td>Reset</td><td>—</td><td>Return all camera values to neutral (pan 0, zoom 1, rotation 0).</td></tr>
</table>

<p>Each layer row has a <strong>parallax slider</strong> (the camera icon) that controls how much of the camera pan this layer absorbs:</p>
<table>
  <tr><th>Value</th><th>Effect</th></tr>
  <tr><td>0.0</td><td>Background-fixed — the layer stays anchored to the screen. Camera panning has no effect on it. Use for distant backgrounds, skies, or HUD overlays.</td></tr>
  <tr><td>1.0 (default)</td><td>World-space — the layer moves fully with the camera. Use for foreground objects that should appear to be "in the world".</td></tr>
  <tr><td>0.1 – 0.9</td><td>Intermediate parallax — the layer moves at a fraction of the camera speed. Lower values read as further away; higher values as closer.</td></tr>
</table>

<div class="note"><strong>Parallax only applies to Pan X / Y.</strong> Camera zoom and rotation affect all layers equally regardless of their parallax factor.</div>
<div class="tip"><strong>Layered depth example</strong> — three layers: sky (factor 0.0), mid-ground (factor 0.3), foreground (factor 1.0). Pan the camera left — the sky stays still, the mid-ground drifts slowly, and the foreground moves fastest, producing natural depth.</div>

<p>Camera pan, zoom, and rotation are saved as part of the project file and applied consistently in all renders and video exports.</p>

<h2>Grid Scroll</h2>
<p>The <strong>GRID SCROLL</strong> section in Quick Adjust (below CAMERA) slides the active layer's cells across the canvas by remapping which source cell appears at each display position. Unlike nudging individual cells, grid scroll moves the entire layer's content as a unit — and wraps, clamps, or consumes cells at the edges.</p>

<h3>Edge Mode</h3>
<table>
  <tr><th>Mode</th><th>Effect</th></tr>
  <tr><td><strong>Wrap</strong></td><td>Cells that scroll off one edge reappear at the opposite edge. The layer tiles seamlessly.</td></tr>
  <tr><td><strong>Clamp</strong></td><td>Edge cells stretch to fill the gap — the last column or row repeats rather than wrapping.</td></tr>
  <tr><td><strong>Consume</strong></td><td>Cells that scroll off the edge simply vanish — no wrapping or repeating.</td></tr>
</table>

<h3>Driver Mode</h3>
<p>The <strong>Mode</strong> picker controls how the scroll offset is generated over time:</p>
<table>
  <tr><th>Mode</th><th>Controls</th><th>Result</th></tr>
  <tr><td><strong>Constant</strong></td><td>Scroll X, Scroll Y (cells)</td><td>A fixed offset, set in cell units. Useful for repositioning a layer or creating a static tiled repeat.</td></tr>
  <tr><td><strong>Oscillator</strong></td><td>Amp X/Y (cells), Period (s), Phase (0–1), Offset X/Y (cells)</td><td>Sinusoidal back-and-forth scrolling. Amplitude sets the peak swing, period the cycle length, phase the starting point in the cycle, offset a constant bias added on top.</td></tr>
  <tr><td><strong>Jitter</strong></td><td>Range X/Y (cells), Duration (frames)</td><td>Random step-change offset that holds for Duration frames then jumps to a new random value within ±Range. Produces staccato, nervous texture.</td></tr>
  <tr><td><strong>Noise</strong></td><td>Amp X/Y (cells), Freq (cyc/s)</td><td>Smooth Perlin-style noise scrolling. Amplitude sets the maximum swing; frequency how rapidly it changes. Produces organic, drifting motion.</td></tr>
  <tr><td><strong>Keyframe</strong></td><td>—</td><td>Offset driven by keyframes set in the timeline's Grid Scroll lane. Edit the curve in the Timeline panel.</td></tr>
</table>

<h3>Step-by-step: infinite horizontal scroll</h3>
<ol class="steps">
  <li>Select the layer you want to scroll.</li>
  <li>Open <strong>GRID SCROLL</strong> in Quick Adjust. Set <strong>Edge Mode</strong> to <strong>Wrap</strong>.</li>
  <li>Set <strong>Mode</strong> to <strong>Oscillator</strong>.</li>
  <li>Set <strong>Amp X</strong> to half the number of columns (e.g. 4 for an 8-column grid). Leave <strong>Amp Y</strong> at 0.</li>
  <li>Set <strong>Period</strong> to the number of seconds you want for one full back-and-forth cycle.</li>
  <li>Press <kbd>Space</kbd> to play — the layer's cells scroll left then right, wrapping at the edges.</li>
</ol>
<div class="tip">For a continuous scroll in one direction rather than back-and-forth, use <strong>Keyframe</strong> mode and draw a steadily-increasing ramp in the timeline's Grid Scroll lane.</div>
<p>Click <strong>Reset</strong> to return Scroll X and Y to zero and Edge Mode to Wrap.</p>
"""#

private let paintingBody = #"""
<h1>Painting Tools</h1>
<p class="subtitle">Six tools for drawing, erasing, selecting, sampling, filling, and nudging.</p>

<table>
  <tr><th>Button</th><th>Key</th><th>Tool</th><th>What it does</th></tr>
  <tr><td><strong>Draw</strong></td><td><kbd>D</kbd></td><td>Draw</td><td>Click or drag to mark cells as drawn with the active style.</td></tr>
  <tr><td><strong>Erase</strong></td><td><kbd>E</kbd></td><td>Erase</td><td>Click or drag to mark cells as undrawn.</td></tr>
  <tr><td><strong>Select</strong></td><td><kbd>S</kbd></td><td>Select</td><td>Click a drawn cell to select or deselect it. Shift-click to add/remove. Drag on an empty area to rubber-band select. Shift-drag extends the selection.</td></tr>
  <tr><td><strong>Sample</strong></td><td><kbd>A</kbd></td><td>Sample</td><td>Click a drawn cell to load its style as the active painting style.</td></tr>
  <tr><td><strong>Fill</strong></td><td><kbd>F</kbd></td><td>Fill</td><td>Flood-fill contiguous undrawn cells from the clicked cell with the active style. Propagates to 4-connected undrawn neighbours only.</td></tr>
  <tr><td><strong>Nudge</strong></td><td><kbd>N</kbd></td><td>Nudge</td><td>Click a drawn cell to select it; drag to move its visual position offset. See below.</td></tr>
</table>

<div class="note"><strong>Keyboard shortcuts</strong> are suppressed while a text field has focus. They're also blocked when Command, Option, or Control is held, so they won't conflict with menu shortcuts.</div>

<h2>Drawing cells</h2>
<p>When a cell is drawn with the Draw tool, all four active palette selections are captured simultaneously:</p>
<ul>
  <li><strong>Style</strong> — the active style (fill, stroke, mode) from the STYLES section.</li>
  <li><strong>Motion</strong> — the active motion set (preset, speed, Order/Chaos) from the MOTIONS section. If none is selected, the cell has no motion (Static).</li>
  <li><strong>Shape</strong> — the active shape from the SHAPES section. If none is selected, the cell uses the default built-in polygon.</li>
  <li><strong>Path</strong> — the active keyframe path from the PATHS section. If none is selected, the cell has no path.</li>
  <li><strong>Position offset</strong> — set by the <strong>Scatter</strong> slider in the Tool Strip.</li>
  <li><strong>Phase offset</strong> — set by the current <strong>Phase Policy</strong> and <strong>φ step</strong> values. See <a href="um-help://help/phase">Phase Policy &amp; Scatter</a>.</li>
</ul>
<p>A paint stroke — from first touch to release — is a single undo operation regardless of how many cells it crosses.</p>

<h2>The Nudge tool</h2>
<p>The Nudge tool moves a cell's visual position without changing its grid position. Use it to place sprites organically after drawing, or to fine-tune the spatial composition.</p>
<ol class="steps">
  <li>Switch to the Nudge tool (<kbd>N</kbd>). Click a drawn cell — it is selected and highlighted.</li>
  <li>Drag in any direction. The sprite moves continuously, tracked in pixels. The cell's grid outline remains as a faint reference square showing the nominal position.</li>
  <li>The <strong>PLACE &amp; TIME</strong> panel in Quick Adjust shows the resulting Offset X / Offset Y values live.</li>
  <li>Multiple cells can be selected first (using the Select tool) and then nudged together — all selected cells move by the same delta simultaneously.</li>
</ol>
<div class="tip"><strong>Pixel-perfect nudging</strong> — while any cells are selected, arrow keys nudge the position offset by 1 px per press. Hold Shift for 10 px per press. This works regardless of which tool is active.</div>

<h2>Arrow-key nudge</h2>
<table>
  <tr><th>Key</th><th>Movement</th><th>Distance</th></tr>
  <tr><td><kbd>←</kbd> <kbd>→</kbd></td><td>Left / right</td><td>1 px</td></tr>
  <tr><td><kbd>↑</kbd> <kbd>↓</kbd></td><td>Up / down</td><td>1 px</td></tr>
  <tr><td><kbd>Shift</kbd>+<kbd>←</kbd> <kbd>→</kbd></td><td>Left / right</td><td>10 px</td></tr>
  <tr><td><kbd>Shift</kbd>+<kbd>↑</kbd> <kbd>↓</kbd></td><td>Up / down</td><td>10 px</td></tr>
</table>
<p>The first press in a sequence pushes an undo snapshot. Held-key repeats continue without additional snapshots. One <kbd>⌘Z</kbd> undoes the entire sequence.</p>
"""#

private let transformsBody = #"""
<h1>Grid Transforms &amp; Transform Mode</h1>
<p class="subtitle">Six one-click operations that restructure the grid — plus Stamp mode for additive symmetry.</p>

<h2>Grid Transforms</h2>
<table>
  <tr><th>Button</th><th>Transform</th><th>Notes</th></tr>
  <tr><td><strong>↔</strong></td><td>Flip horizontal</td><td>Mirrors cells left–right. Position offset dx is negated on each cell.</td></tr>
  <tr><td><strong>↕</strong></td><td>Flip vertical</td><td>Mirrors cells top–bottom. Position offset dy is negated.</td></tr>
  <tr><td><strong>↺</strong></td><td>Rotate left 90°</td><td>Requires a square grid (rows = cols). Offset vector rotated 90° left: (dx,dy)→(dy,−dx).</td></tr>
  <tr><td><strong>↻</strong></td><td>Rotate right 90°</td><td>Requires a square grid. Offset vector rotated 90° right: (dx,dy)→(−dy,dx).</td></tr>
  <tr><td><strong>⊡</strong></td><td>Clear all</td><td>Marks all cells undrawn. Position and phase offsets are preserved — the cells are still there, just undrawn.</td></tr>
  <tr><td><strong>⊟</strong></td><td>Invert</td><td>Toggles every cell's drawn state. Drawn → undrawn; undrawn → drawn.</td></tr>
</table>

<p>Every transform records a single undo snapshot — one <kbd>⌘Z</kbd> reverses the entire operation.</p>

<h3>How position offsets survive transforms</h3>
<p>When you flip or rotate the grid, each cell's position offset vector is transformed geometrically alongside the cell. A sprite nudged 10 px to the right of its nominal centre will, after a horizontal flip, be 10 px to the <em>left</em> of the (now mirrored) nominal centre. The spatial arrangement the user built is preserved.</p>
<p>Phase offsets are not modified by flip or rotate — timing does not mirror geometrically.</p>

<h2>Transform Mode: Move vs Stamp</h2>
<p>A <strong>Move | Stamp</strong> toggle sits in the Tool Strip between the painting tools and the transform buttons.</p>

<h3>Move mode (default)</h3>
<p>Standard behaviour: cells relocate to their transformed positions. The grid "turns over". Cells at position A are now at position B.</p>

<h3>Stamp mode</h3>
<p>Originals stay in place. The transform deposits a copy of all drawn cells at their transformed positions, layered on top of whatever is already there. This is the fastest way to build symmetrical patterns.</p>

<h4>Step-by-step: 4-way symmetry with Stamp</h4>
<ol class="steps">
  <li>Draw a pattern in one quadrant of the grid using the Draw tool.</li>
  <li>Switch to <strong>Stamp</strong> mode in the Tool Strip.</li>
  <li>Click <strong>↔</strong> (flip horizontal). The original cells remain and a mirrored copy appears — you now have 2-way horizontal symmetry.</li>
  <li>Click <strong>↕</strong> (flip vertical). Another copy is deposited — you now have 4-way symmetry.</li>
</ol>

<pre>
Step 1: one quadrant     Step 2+3: after ↔        Step 4: after ↕

·  ·  ·  ·  ·           ·  ·  ·  ·  ·            ·  ■  ·  ■  ·
·  ■  ■  ·  ·           ·  ■  ■  ■  ■  ·         ■  ■  ·  ■  ■
·  ■  ·  ·  ·     →     ·  ■  ·  ·  ■  ·    →    ■  ·  ·  ·  ■
·  ·  ·  ·  ·           ·  ·  ·  ·  ·  ·         ·  ■  ·  ■  ·
</pre>

<p>Each subsequent stamp application layers on top, so you can keep adding rotations or flips to build complex symmetry quickly. Switch back to Move mode when you want normal transform behaviour.</p>

<h3>Phase offset in Stamp mode (Δφ)</h3>
<p>When Stamp mode is active, a <strong>Δφ</strong> control appears next to the toggle. Use the − and + buttons to set a signed frame offset value (e.g. +12 or −8).</p>
<p>When a stamp transform is applied, the <em>copied</em> cells receive their existing phase offset plus this Δφ value. The originals are unchanged. This lets stamped copies animate at a deliberate offset from the originals — mirrored copies that beat at a different phase, or rotated copies that create a pinwheel timing effect.</p>
<div class="tip"><strong>Example</strong> — paint a ring of cells with Sequential phase policy (phases 0, 8, 16, 24…), set Δφ to +48, then flip horizontal in Stamp mode. The mirrored ring has phases 48, 56, 64, 72… — the two halves animate in counterpoint.</div>
"""#

private let phaseBody = #"""
<h1>Phase Policy &amp; Scatter</h1>
<p class="subtitle">Control how newly painted cells get their temporal and spatial offset at paint time.</p>

<p>These controls appear in the Tool Strip to the right of the transform buttons. They affect <em>newly painted cells only</em> — existing cells keep their current offsets. This is intentional: you can deliberately mix policies within one layer by painting in multiple passes.</p>

<h2>Phase Policy</h2>
<p>Controls the <code>phaseOffset</code> assigned to each cell when it is drawn. A cell with phase offset <em>N</em> evaluates its animation at frame <code>currentFrame + N</code> — it is always N frames ahead of a cell at offset 0.</p>

<table>
  <tr><th>Policy</th><th>Effect on new cells</th></tr>
  <tr><td><strong>Synchronized</strong></td><td>phaseOffset = 0. All cells animate in lock-step.</td></tr>
  <tr><td><strong>Random</strong></td><td>phaseOffset = random value 0–119. Each cell gets a unique, independent starting point. Produces an organic, uncorrelated feel.</td></tr>
  <tr><td><strong>Sequential</strong></td><td>phaseOffset increments by φ step with each cell painted in stroke order. Creates a travelling wave as you drag across the grid.</td></tr>
  <tr><td><strong>Spatial</strong></td><td>phaseOffset = (row + col) × φ step. Produces a diagonal wave across the entire grid regardless of paint order.</td></tr>
  <tr><td><strong>Radial</strong></td><td>phaseOffset = distance-from-centre × φ step. Rings ripple outward from the grid centre.</td></tr>
</table>

<h3>φ step (phase step frames)</h3>
<p>The stepper immediately after the policy picker sets how many frames separate each phase increment in Sequential, Spatial, and Radial modes. Range: 1–240 frames. Default: 4.</p>
<ul>
  <li>Larger values spread cells further around the animation cycle — a wide, slow wave.</li>
  <li>Smaller values cluster cells close together — a tight, fast ripple.</li>
  <li>Synchronized and Random ignore this value entirely.</li>
</ul>

<h3>Phase offset and keyframe paths</h3>
<p>phaseOffset also controls where each cell enters its keyframe path loop. Cells sharing a single path but painted with Sequential policy will distribute themselves evenly around the loop — a field of cells all following the same orbit path, each at a different point in the orbit, with zero additional setup.</p>

<h4>Step-by-step: creating a radial wave</h4>
<ol class="steps">
  <li>Set Phase Policy to <strong>Radial</strong>.</li>
  <li>Set φ step to <strong>6</strong>.</li>
  <li>Use the Fill tool (<kbd>F</kbd>) to flood the entire grid. Every cell is drawn simultaneously, each receiving phaseOffset = distanceFromCentre × 6.</li>
  <li>Press <kbd>Space</kbd> to play. The cells near the centre animate first; those at the corners lag behind — a wave rings outward continuously.</li>
  <li>Increase φ step to stretch the wave out, or reduce it to make the rings more tightly bunched.</li>
</ol>

<h2>Spatial Scatter</h2>
<p>The <strong>Scatter</strong> slider (0.0–1.0) controls how much random <code>positionOffset</code> is injected at paint time.</p>
<ul>
  <li><strong>0 (default)</strong> — sprites land exactly at cell centres. Precise, gridded.</li>
  <li><strong>0.25</strong> — gentle organic displacement; the composition feels hand-placed rather than mechanical.</li>
  <li><strong>1.0</strong> — offsets randomised up to ±1 full cell size on each axis. Compositions become loose and open.</li>
</ul>
<p>Scatter is applied once when each cell is drawn. Moving the slider does not retroactively affect existing cells. Use <strong>Rescatter</strong> in PLACE &amp; TIME to re-scatter a selection with the current setting.</p>
<div class="tip"><strong>Combining scatter and phase</strong> — paint a composition with Spatial phase policy and moderate scatter. The result has both spatial irregularity (sprites drift off their centres) and temporal irregularity (each cell enters the animation at a different frame). The grid structure remains — you can still flip, rotate, or resample the result and both offsets are carried correctly.</div>
"""#

private let playbackBody = #"""
<h1>Playback &amp; Recording</h1>
<p class="subtitle">Animate, capture state sequences, and navigate a recorded timeline.</p>

<h2>Transport Bar controls</h2>
<table>
  <tr><th>Control</th><th>Key</th><th>Function</th></tr>
  <tr><td>⏮ Rewind</td><td>—</td><td>Stop playback, return to frame 0, and exit timeline navigation (returns to live mode).</td></tr>
  <tr><td>▶ / ⏸ Play/Pause</td><td><kbd>Space</kbd></td><td>Toggle animation at 24 fps. Pausing holds the current frame.</td></tr>
  <tr><td>● / ■ Record/Stop</td><td>—</td><td>Begin or end timeline recording. See below.</td></tr>
  <tr><td>Frame counter</td><td>—</td><td>Shows the current frame. Animation cycles because styles loop. The counter is unbounded.</td></tr>
  <tr><td>PNG</td><td>—</td><td>Export the current frame as a PNG still. See <a href="um-help://help/export">Export</a>.</td></tr>
  <tr><td>SVG</td><td>—</td><td>SVG export — not yet implemented.</td></tr>
  <tr><td>Video</td><td>—</td><td>Export an animation as a .mov video. See <a href="um-help://help/export">Export</a>.</td></tr>
</table>

<h2>Recording a timeline</h2>
<p>UM can capture a sequence of grid-state snapshots as you paint — forming a <strong>timeline</strong> that drives cut-based animation, where the composition changes over time.</p>

<ol class="steps">
  <li>Press <strong>●</strong> (Record) in the Transport Bar. Playback starts automatically; the button turns red.</li>
  <li>Paint, erase, and modify the canvas freely. Every <em>N</em> seconds (set by <strong>Capture</strong> in the CANVAS section), the current state of the grid is automatically snapped into the timeline.</li>
  <li>The timeline is capped at 500 states. When full, the oldest state is discarded to make room.</li>
  <li>Press <strong>■</strong> (Stop) when done. The recorded states remain.</li>
</ol>
<div class="note"><strong>Capture interval</strong> — default is 2.0 s (48 frames at 24 fps). Painting for 10 seconds at this setting produces roughly 5 states. Adjust in CANVAS → Capture before recording.</div>

<h2>Navigating recorded states</h2>
<p>Once states have been recorded, navigation controls appear in the Transport Bar:</p>
<table>
  <tr><th>Control</th><th>Function</th></tr>
  <tr><td>◀</td><td>Load the previous state into the live canvas.</td></tr>
  <tr><td><strong>N/M</strong> (e.g. 3/7)</td><td>Current position — state 3 of 7. Click to open the Timeline Editor.</td></tr>
  <tr><td>▶</td><td>Load the next state.</td></tr>
  <tr><td>⏮</td><td>Return to live mode (frame 0, exits state navigation).</td></tr>
</table>
<p>Loading a state replaces the live canvas with that state's cells and styles. You can paint over it and continue recording — new captures start from whatever is on canvas at that moment.</p>

<h2>Timeline playback</h2>
<p>When you have navigated to a recorded state (current position ≥ 0) and press Play, UM enters timeline playback: each state holds for its configured duration, then cuts to the next. After the last state it loops back to state 1. Press ⏮ to exit timeline playback and return to live mode.</p>

<h2>Timeline Editor</h2>
<p>Click the position indicator (e.g. <strong>3/7</strong>) to open the Timeline Editor sheet.</p>
<table>
  <tr><th>Column</th><th>Description</th></tr>
  <tr><td>Number</td><td>State index. The currently loaded state is highlighted.</td></tr>
  <tr><td>→</td><td>Load this state into the live canvas.</td></tr>
  <tr><td>Sprites</td><td>Count of drawn cells in this state.</td></tr>
  <tr><td>Hold slider</td><td>Drag to change how long this state holds before cutting to the next (0.25 s – 10 s).</td></tr>
  <tr><td>×</td><td>Delete this state from the timeline.</td></tr>
</table>
<p><strong>Clear All</strong> removes all states and closes the editor. States are saved in the .umproj file.</p>
"""#

private let qaProjectBody = #"""
<h1>Quick Adjust: PROJECT / CANVAS / CAMERA</h1>
<p class="subtitle">Project-wide settings for output dimensions, canvas appearance, and the virtual camera.</p>
<p>These sections affect the whole document. They sit at the top of the Quick Adjust panel and are always accessible regardless of which style is active.</p>

<h2>PROJECT</h2>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Canvas preset</strong></td><td>Quick picker for common output sizes. Choosing a preset sets Width and Height immediately.</td></tr>
  <tr><td><strong>Width / Height</strong></td><td>Output canvas dimensions in pixels. Edit directly for any custom size.</td></tr>
</table>
<table>
  <tr><th>Preset</th><th>Dimensions</th></tr>
  <tr><td>HD 1920×1080</td><td>1920 × 1080 px</td></tr>
  <tr><td>4K 3840×2160</td><td>3840 × 2160 px</td></tr>
  <tr><td>Square 1080×1080</td><td>1080 × 1080 px (default)</td></tr>
  <tr><td>A4 Portrait</td><td>2480 × 3508 px (300 dpi)</td></tr>
  <tr><td>A4 Landscape</td><td>3508 × 2480 px (300 dpi)</td></tr>
</table>
<p>The canvas is <strong>letterboxed</strong> on screen — the drawing area always preserves the output aspect ratio. The neutral grey border outside is not part of any export.</p>

<h2>EXPORT</h2>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Multiplier</strong></td><td>Scale factor at export time. 1× = native canvas size. 2× = double resolution. Up to 8×.</td></tr>
  <tr><td><strong>Scale drawing</strong></td><td>When checked (default), stroke widths scale with the multiplier so lines look identical to screen at any output size.</td></tr>
  <tr><td><strong>Output</strong></td><td>Read-only display of the actual pixel dimensions that will be written.</td></tr>
  <tr><td><strong>FPS</strong></td><td>Frames per second for video export — 24 or 30.</td></tr>
  <tr><td><strong>From / To</strong></td><td>Start and end frame of the export range. These are the same values as the <strong>Start / End</strong> fields in the Transport Bar — changing either updates both places. Duration in seconds is shown alongside.</td></tr>
</table>
<div class="note"><strong>From / To is shared with the transport bar.</strong> Set your playback range in the timeline and the export range follows automatically — no need to enter the same numbers twice. Non-zero start frames are fully supported: a From of 60, To of 180 exports a 120-frame clip starting at animation frame 60.</div>

<h2>CANVAS</h2>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Background</strong></td><td>Canvas background colour. Click the swatch to open the colour panel. Default: white.</td></tr>
  <tr><td><strong>Bg Image</strong></td><td>Background image composited behind all layers, on top of the background colour. Click <strong>Choose…</strong> to pick any image file (JPEG, PNG, TIFF, HEIC…). The image fills the full canvas area. Click ✕ to remove it. Saved with the project.</td></tr>
  <tr><td><strong>Draw</strong></td><td>Background draw checkbox. When checked (default) the canvas clears to the background colour before each frame — a fresh render each tick. When unchecked, frames accumulate: each new frame's sprites layer on top of the previous frame's content without clearing. Rewinding to frame 0 clears the accumulation.</td></tr>
  <tr><td><strong>Capture</strong></td><td>Auto-capture interval during recording (0.5 s – 8.0 s, default 2.0 s).</td></tr>
  <tr><td><strong>Grid</strong></td><td>Show grid checkbox. When on, lines divide the canvas into cells. Off by default.</td></tr>
  <tr><td><strong>Grid colour / width</strong></td><td>Colour, opacity, and stroke width of the grid lines. Dimmed when Show grid is off.</td></tr>
</table>
<div class="note"><strong>Background image vs Color Map</strong> — the background image is drawn as a visible backdrop behind sprites. The Color Map is an invisible sampling source that drives sprite colours. They serve entirely different purposes and can be used simultaneously.</div>

<h3>Accumulation mode</h3>
<p>Turning <strong>Background draw</strong> off is the primary way to create time-based build-up effects. Earlier frames remain visible as new sprites are drawn on top. Combined with motion paths or the Wander/Wave presets, this traces visible motion trajectories across the canvas. The accumulation persists until you press ⏮ (rewind) or turn Background draw back on.</p>

<h2>Canvas Zoom &amp; Pan</h2>
<p>The canvas can be zoomed and panned independently of the project's output resolution. Zoom and pan are view-only — they do not affect PNG or video export.</p>
<table>
  <tr><th>Gesture / Key</th><th>Action</th></tr>
  <tr><td>Pinch (trackpad)</td><td>Zoom in or out around the canvas centre.</td></tr>
  <tr><td>Scroll / two-finger drag</td><td>Pan the canvas.</td></tr>
  <tr><td><kbd>⌥</kbd> + scroll</td><td>Zoom in or out (scroll-wheel zoom).</td></tr>
  <tr><td><kbd>⌘0</kbd></td><td>Reset — fit the canvas to the window at 100%, pan centred.</td></tr>
  <tr><td><kbd>⌘=</kbd></td><td>Zoom in 25%.</td></tr>
  <tr><td><kbd>⌘−</kbd></td><td>Zoom out 25%.</td></tr>
</table>
<p>All painting tools — Draw, Erase, Select, Fill, Sample, Nudge — remain fully functional at any zoom level. Hit-testing is computed in canvas space, so brush strokes always land on the correct cell regardless of view zoom or pan offset.</p>

<h2>Color Map</h2>
<p>Below a divider at the bottom of the CANVAS section. A color map is an image or video whose pixel colors drive sprite fill and/or stroke colors, overriding the style's explicit colors. The image is never shown on the canvas — it is used purely as a color source.</p>

<h3>Loading a color source</h3>
<ol class="steps">
  <li>Click <strong>Choose…</strong>. A file picker opens. Accept any image format (JPEG, PNG, TIFF, HEIC…) or video (MP4, MOV, M4V).</li>
  <li>For a <strong>static image</strong>, UM samples it once at load time. The color grid is fixed for the entire animation.</li>
  <li>For a <strong>video</strong>, up to 240 frames are extracted at load time (shown as <em>N fr extracted</em>). During playback, each animation frame maps to the corresponding extracted video frame.</li>
  <li>A photo icon (static) or film icon (video) confirms the source type. A spinner shows while video is being extracted — the canvas continues rendering normally during this time.</li>
  <li>Click <strong>✕</strong> to remove the color source and revert to style colors.</li>
</ol>

<h3>Color Map settings</h3>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Apply to</strong></td><td>Fill — sampled colour replaces fill only. Stroke — replaces stroke only. Both — replaces fill and stroke simultaneously.</td></tr>
  <tr><td><strong>Style α</strong></td><td>When checked (default), the sprite keeps its style's fill opacity; only the RGB values come from the image. Uncheck to also use the image's alpha channel.</td></tr>
  <tr><td><strong>Loop</strong></td><td>Video only. Loop (default) wraps back to the start when animation frames exceed the extracted frame count. Clamp holds the last frame.</td></tr>
</table>

<h3>How sampling works</h3>
<p>UM draws the source image into a tiny <em>rows × cols</em> pixel buffer using GPU-accelerated bilinear downscaling — one pixel per grid cell. The resulting pixel value is the average colour of all source pixels in that cell's region. A 4K source image sampled into a 6×6 grid takes microseconds.</p>
<p>When the grid is resampled (resolution change), the colour source is automatically re-sampled at the new grid dimensions — no reload needed.</p>
<div class="tip"><strong>Projects are self-contained</strong> — when you choose a color source, UM copies the file into a <code>colorSources/</code> folder inside the .umproj package. The project can be moved, renamed, or shared and the color source travels with it automatically.</div>

<h2>Color map lock</h2>
<p>By default, a cell's color map color depends on its position in the grid — move or transform a cell and it picks up whatever color lives at its new grid coordinates. <strong>Lock</strong> breaks that dependency: each drawn cell bakes its current color map sample into the cell itself, so the color travels with it through any transform (flip, rotate, nudge, stamp, resample).</p>
<p>This enables a workflow that is otherwise impossible:</p>
<ol class="steps">
  <li>Load a color source and watch your grid take on the image's colors spatially.</li>
  <li>Click <strong>Lock</strong>. UM reads the current color from each drawn cell's grid position and stores it directly on the cell.</li>
  <li>Clear the color source or ignore it — the locked colors are now independent data on the cells.</li>
  <li>Freely rotate, flip, nudge, stamp, or otherwise transform the grid. Each cell keeps the color it had at lock time.</li>
  <li>Click <strong>Unlock</strong> at any point to return all cells to live color map sampling.</li>
</ol>

<h3>Lock settings</h3>
<table>
  <tr><th>Control</th><th>Description</th></tr>
  <tr><td><strong>Lock</strong></td><td>Bakes the current color map into all drawn cells (or selected cells only, if a selection exists). Respects the current <em>Apply to</em> and <em>Style α</em> settings. Disabled when no color source is loaded.</td></tr>
  <tr><td><strong>Unlock</strong></td><td>Removes locked colors from drawn cells (or selected cells). Cells revert to live color map sampling — or to style colors if no map is loaded. Available even after the color source has been cleared.</td></tr>
</table>
<div class="tip"><strong>Selection-aware</strong> — when cells are selected (rubber-band or Shift-click), Lock and Unlock operate only on the selection. Use this to lock one region of the grid while leaving another region free to track the live color map.</div>
<p>A status line <em>"⚑ Layer has locked colors"</em> appears below the Lock row whenever any drawn cell on the active layer has a baked color. This is a reminder that those cells are no longer tracking the live color map.</p>

<h2>Color map palette extraction</h2>
<p>When a Color Map source is loaded, UM can sample it to build a named <strong>colour palette</strong> — a set of swatches you can use to hand-pick fill and stroke colours for your styles. See <a href="um-help://help/palette">Style Palette &amp; Library → PALETTES</a> for how to generate and manage palettes, and <a href="um-help://help/qa-style">Style (RENDER)</a> for how to apply palette colours to a style's fill or stroke.</p>

<h2>CAMERA</h2>
<p>The CAMERA section sits below CANVAS in the Quick Adjust panel. It positions a virtual camera over the entire composition — all layers render through it. Camera state is saved in the project and applied to all PNG and video exports.</p>
<table>
  <tr><th>Control</th><th>Range</th><th>Description</th></tr>
  <tr><td><strong>Pan X</strong></td><td>−500 … 500 px</td><td>Shift the viewport left (negative) or right (positive) in canvas pixels.</td></tr>
  <tr><td><strong>Pan Y</strong></td><td>−500 … 500 px</td><td>Shift the viewport up (negative) or down (positive) in canvas pixels.</td></tr>
  <tr><td><strong>Zoom</strong></td><td>0.1 – 4.0×</td><td>Scale the canvas around its centre point. 1.0 = native size.</td></tr>
  <tr><td><strong>Rotation</strong></td><td>−180° … 180°</td><td>Rotate the canvas clockwise (positive) or counter-clockwise (negative) around its centre.</td></tr>
  <tr><td><strong>Reset</strong></td><td>—</td><td>Return all values to neutral (Pan 0, Zoom 1×, Rotation 0°). Greyed out when already at identity.</td></tr>
</table>
<p>Parallax per layer is controlled by the small slider (camera icon) in each layer row — see <a href="um-help://help/layers">Working with Layers</a> for details on how parallax interacts with camera pan.</p>
<div class="note"><strong>Phase 1 — constant values only.</strong> The camera currently supports static positioning (constant mode). Oscillator and keyframe animation of camera movement (camera moves over the timeline) will be added in a future release.</div>
"""#

private let qaStyleBody = #"""
<h1>Quick Adjust: RENDER</h1>
<p class="subtitle">Visual rendering properties for the active style — fill, stroke, and render mode.</p>

<h2>The four-axis model</h2>
<p>Each drawn cell has four independent creative axes that are combined at render time:</p>
<table>
  <tr><th>Axis</th><th>What it controls</th><th>Palette section</th></tr>
  <tr><td><strong>Style</strong></td><td>Fill colour, stroke colour, stroke width, render mode</td><td>STYLES (left panel)</td></tr>
  <tr><td><strong>Motion</strong></td><td>Parametric preset, speed, amount, phase, Order/Chaos, axis mix</td><td>MOTIONS (left panel) — <em>pending UI</em></td></tr>
  <tr><td><strong>Shape</strong></td><td>Polygon geometry (imported from Loom)</td><td>SHAPES (left panel)</td></tr>
  <tr><td><strong>Path</strong></td><td>Keyframe motion path</td><td>PATHS (left panel)</td></tr>
</table>
<p>Changing the active style in the STYLES section only affects newly drawn cells — existing cells keep the axis values they had when they were painted.</p>

<h2>RENDER section</h2>
<p>Edits the <strong>active style</strong> (highlighted in the STYLES section of the Style Palette). Changes are reflected immediately on every cell that uses this style.</p>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Fill</strong></td><td>Fill colour and opacity. Click the colour well to open the system colour panel. Click the palette icon (🎨) to pick from a colour palette instead — see below.</td></tr>
  <tr><td><strong>Stroke</strong></td><td>Stroke colour and opacity. Same palette icon available.</td></tr>
  <tr><td><strong>Width</strong></td><td>Stroke width in pixels. Double-click to reset to 1.5.</td></tr>
  <tr><td><strong>Mode</strong></td><td>Filled (fill only), Stroked (outline only), or Fill &amp; Stroke (both, default).</td></tr>
</table>

<h2>Colour palette picker</h2>
<p>The palette icon (swatchpalette) next to Fill and Stroke opens a popover showing your project's colour palettes as swatch grids. Palettes are generated from a loaded Color Map — see <a href="um-help://help/palette">Style Palette → PALETTES</a> and <a href="um-help://help/qa-project">PROJECT / CANVAS → Color map palette extraction</a>.</p>
<ul>
  <li>If multiple palettes exist, a menu at the top of the popover lets you switch between them.</li>
  <li>Adjust the <strong>Alpha</strong> slider before clicking a swatch to control opacity. The slider default is 1.0 (fully opaque).</li>
  <li>Click any swatch to apply that colour (with the current alpha) to the active style's fill or stroke and close the popover.</li>
  <li>The palette icon is greyed out when no palettes exist in the project.</li>
</ul>
<div class="tip">The colour well and palette picker work together — use the colour well for fine-tuned colour editing (hue wheel, sliders) and the palette picker to stay within a coherent image-sourced colour range.</div>

<h2>Style variants</h2>
<p>Right-click any style row in the palette to create a derived variant:</p>
<table>
  <tr><th>Variant</th><th>Effect</th></tr>
  <tr><td>Inverted</td><td>Fill and stroke RGB values inverted; alpha preserved.</td></tr>
  <tr><td>Faint</td><td>Fill alpha 0.15, stroke alpha 0.25.</td></tr>
  <tr><td>Strong</td><td>Fill and stroke alpha set to 1.0.</td></tr>
  <tr><td>Swap Colors</td><td>Fill and stroke colours exchanged.</td></tr>
  <tr><td>Outline Only</td><td>Stroked mode; fill alpha 0.</td></tr>
  <tr><td>Filled Only</td><td>Filled mode; stroke alpha 0.</td></tr>
</table>

<div class="note"><strong>Motion, Order/Chaos, and Sequence controls</strong> have moved out of Quick Adjust and will be accessible via the MOTIONS palette section in the left panel (currently being built — see <a href="um-help://help/qa-motion">Motion Palette</a> and <a href="um-help://help/pending">Not Yet Built</a>).</div>
"""#

private let qaMotionBody = #"""
<h1>Motion Palette</h1>
<p class="subtitle">Named motion sets — the animation axis of the four-axis cell model.</p>

<h2>What a motion set is</h2>
<p>A <strong>motion set</strong> is a named, saveable entity that controls how a cell animates. It is one of the four independent creative axes — decoupled from the style (rendering), shape (geometry), and path (keyframe trajectory).</p>
<p>Each motion set stores:</p>
<table>
  <tr><th>Property</th><th>Description</th></tr>
  <tr><td><strong>Preset</strong></td><td>The parametric animation pattern. See below.</td></tr>
  <tr><td><strong>Speed</strong></td><td>Cycle rate multiplier (0–2, default 1).</td></tr>
  <tr><td><strong>Amount</strong></td><td>Amplitude of the effect (0–1, default 0.5).</td></tr>
  <tr><td><strong>Phase</strong></td><td>Starting phase within the oscillation cycle (0–1). Distinct from the per-cell phase offset in PLACE &amp; TIME — this shifts the waveform shape, not when the cell starts animating.</td></tr>
  <tr><td><strong>Order/Chaos</strong></td><td>A 0–1 scalar that adds layered sine-wave jitter on top of the preset. See below.</td></tr>
  <tr><td><strong>Axis mix</strong></td><td>Per-axis multipliers (0–1) that attenuate or suppress individual channels of the preset's output. Which axes appear depends on the preset — see below.</td></tr>
</table>

<h2>Motion presets</h2>
<table>
  <tr><th>Preset</th><th>What it does</th><th>Axis mix controls</th></tr>
  <tr><td><strong>Static</strong></td><td>No motion. Default for cells with no motion set assigned.</td><td>—</td></tr>
  <tr><td><strong>Spin</strong></td><td>Continuous rotation. At Speed 1, Amount 1: roughly one full rotation every 3 seconds.</td><td>Rotation</td></tr>
  <tr><td><strong>Pulse</strong></td><td>Sine-wave scale oscillation on both axes simultaneously. Sprites breathe in and out.</td><td>Scale</td></tr>
  <tr><td><strong>Wave</strong></td><td>Sine displacement. Default axis: horizontal. Use Axis mix to suppress X, add Y, or blend both.</td><td>X, Y</td></tr>
  <tr><td><strong>Wander</strong></td><td>Slow 2D drift using two sine waves at a golden-ratio frequency ratio. Each cell follows a unique Lissajous figure.</td><td>X, Y</td></tr>
  <tr><td><strong>Jitter</strong></td><td>High-frequency small-amplitude noise on both axes plus rotation. Fast, twitchy character.</td><td>X, Y, Rotation</td></tr>
  <tr><td><strong>Color Cycle</strong></td><td>Continuously rotates fill and stroke hues. Achromatic colours (grey, white, black) are unaffected.</td><td>—</td></tr>
  <tr><td><strong>Custom</strong></td><td>Reserved — no effect in the current build.</td><td>—</td></tr>
</table>

<h2>ORDER / CHAOS</h2>
<p>Every motion set carries an Order/Chaos value (0–1). At <strong>0</strong> — sprites behave exactly as the preset dictates. At <strong>1</strong> — layered sine-wave jitter is added on top, each cell getting a unique seed derived from its grid index:</p>
<ul>
  <li>Position drift: ±30% of cell size on each axis</li>
  <li>Rotation jitter: ±90°</li>
  <li>Scale jitter: ±40% (X) / ±32% (Y)</li>
</ul>
<p>All jitter is smooth (sinusoidal) — no per-frame random. The chaos feels organic rather than flickery.</p>
<p>Motion and chaos are <strong>additive with keyframe path motion</strong>: position offsets add, rotations add, scale multiplies.</p>
<div class="tip"><strong>Order/Chaos around 0.3</strong> gives subtle aliveness — sprites breathe and drift slightly while still reading as a coherent composition. 0.8–1.0 gives maximum turbulence.</div>

<h2>Axis mix</h2>
<p>Each preset drives a specific set of animation channels. The <strong>Axis mix</strong> sliders (visible in Quick Adjust for the active motion set) let you attenuate or completely suppress individual channels:</p>
<table>
  <tr><th>Slider</th><th>Range</th><th>Effect</th></tr>
  <tr><td><strong>X</strong></td><td>0–1</td><td>Scales the horizontal position displacement. Set to 0 for vertical-only motion on Wave or Wander.</td></tr>
  <tr><td><strong>Y</strong></td><td>0–1</td><td>Scales the vertical position displacement. Set to 0 to restrict Wander or Jitter to horizontal.</td></tr>
  <tr><td><strong>Rotation</strong></td><td>0–1</td><td>Scales the rotation output. Set to 0 on Jitter for position-only twitching with no angle change. Set to 0 on Spin to cancel rotation while Order/Chaos can still add some chaos.</td></tr>
  <tr><td><strong>Scale</strong></td><td>0–1</td><td>Scales the deviation from 1.0 on Pulse. At 0 the sprite stays at its natural size; at 1 it breathes at full Amount.</td></tr>
</table>
<p>Only the sliders relevant to the current preset are shown. Axis mix operates on the preset's parametric output only — Order/Chaos jitter and keyframe path offsets are unaffected.</p>
<div class="tip"><strong>Jitter position-only:</strong> set Rotation to 0. <strong>Y-only wave:</strong> set X to 0 and Y to 1. <strong>X-only wander:</strong> set Y to 0.</div>

<h2>Using motion sets</h2>
<p>Motion sets work like the other three palette axes:</p>
<ol class="steps">
  <li>Open the <strong>MOTIONS</strong> section in the Style Palette (Project tab).</li>
  <li>Click <strong>+ New Motion</strong> to create a motion set. It becomes the active motion — highlighted in the palette.</li>
  <li>Click the motion set row in the MOTIONS section to select it. The <strong>MOTION</strong> section appears in Quick Adjust on the right, showing Preset, Speed, Amount, Phase, and Order/Chaos controls.</li>
  <li>Edit the parameters. Changes take effect immediately on all cells that carry this motion set.</li>
  <li>Paint cells with the Draw or Fill tool. Each new cell captures the active motion set.</li>
  <li>To assign an existing motion set to already-drawn cells, select those cells and choose the motion set from the <strong>Motion</strong> picker in PLACE &amp; TIME.</li>
  <li>Click the highlighted row again to deselect — new cells will be painted with no motion (Static).</li>
</ol>

<h2>SEQUENCE cycling</h2>
<p>A motion set can cycle through a list of shapes over time, so each cell that carries this motion set automatically switches geometry on a schedule. This replaces the old per-style SEQUENCE mode with a more flexible, palette-based version.</p>

<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Sequence</strong></td><td>Off (default), Sequential, or Random. Off means each cell uses its own assigned shape. Sequential steps through the list in order. Random picks deterministically from the list each step.</td></tr>
  <tr><td><strong>Step</strong></td><td>How many frames each shape holds before advancing. Range: 1–480 fr. Works with the cell's phaseOffset so cells staggered by phase appear to be at different points in the sequence.</td></tr>
  <tr><td><strong>Shape slots</strong></td><td>The ordered list of shapes the sequence cycles through. Each slot has a shape picker; use − to remove a slot and + Add Shape to append one.</td></tr>
</table>

<h3>Step-by-step: shape cycling on a motion set</h3>
<ol class="steps">
  <li>Import at least two shapes via the SHAPES section of the Style Palette (+ Import Shape…).</li>
  <li>Select the motion set you want to add cycling to by clicking its row in MOTIONS. The MOTION section appears in Quick Adjust.</li>
  <li>Scroll down to the <strong>Sequence</strong> picker inside MOTION and choose <strong>Sequential</strong>.</li>
  <li>Set <strong>Step</strong> to the number of frames each shape should hold (e.g. 12 for half a second at 24 fps).</li>
  <li>Click <strong>+ Add Shape</strong> (appears below Sequence and Step). A new shape slot appears — pick a shape from the dropdown.</li>
  <li>Click <strong>+ Add Shape</strong> again and pick the second shape. Repeat for as many shapes as needed.</li>
  <li>Press <kbd>Space</kbd> to play. Cells carrying this motion set will cycle through the shapes on schedule. Cells with different phase offsets will be at different points in the cycle simultaneously.</li>
</ol>
<div class="note"><strong>Sequence overrides per-cell shape</strong> — when Sequence mode is not Off, the motion set's shape list takes priority over whatever shape is assigned to each cell individually. To disable cycling, set Sequence back to Off.</div>
"""#

private let qaPathBody = #"""
<h1>Quick Adjust: PATH EDITOR</h1>
<p class="subtitle">Create and edit keyframe motion paths — reusable named sequences of transforms that play back on cells.</p>

<h2>Concepts</h2>
<p>A <strong>motion path</strong> is a named sequence of keyframes. Each keyframe specifies a frame number and a set of transforms: position offset, rotation, and scale. At render time, the path is evaluated at <code>currentFrame + cell.phaseOffset</code> to produce a transform that is <em>added</em> to the cell's parametric motion output.</p>
<p>Position offsets in keyframes are stored in <strong>cell-fraction units</strong>: <code>1.0</code> = shift by one full cell width (X) or height (Y). This keeps paths resolution-independent — the same path looks proportionally identical on a 4×4 and a 20×20 grid.</p>
<p>Paths <strong>loop by default</strong>. When evaluation passes the last keyframe, it wraps back to the start. Toggle Loop off to clamp at the last keyframe instead.</p>

<h2>Creating a path</h2>
<ol class="steps">
  <li>In the Style Palette (Project tab), click <strong>+ New Path</strong>. A new path is created with two identity keyframes at frames 0 and 48, and it becomes the active path for editing.</li>
  <li>Alternatively, click the <strong>+</strong> button inside the PATH EDITOR section of Quick Adjust.</li>
  <li>The path overlay appears on the canvas — a dot at each keyframe's position, connected by a line showing the interpolated trajectory.</li>
</ol>

<h2>PATH EDITOR controls</h2>
<table>
  <tr><th>Control</th><th>Description</th></tr>
  <tr><td><strong>Path picker</strong></td><td>Select which path is being edited from all paths in the project.</td></tr>
  <tr><td><strong>+</strong></td><td>Create a new empty path.</td></tr>
  <tr><td><strong>Trash</strong></td><td>Delete the active path. Removes its reference from all assigned cells.</td></tr>
  <tr><td><strong>Name</strong></td><td>Editable text field for the path name.</td></tr>
  <tr><td><strong>Loop</strong></td><td>When checked (default), the path loops continuously. When off, evaluation clamps at the last keyframe.</td></tr>
  <tr><td><strong>Duration</strong></td><td>Read-only. Frame number of the last keyframe = the loop length.</td></tr>
</table>

<h2>Keyframe list</h2>
<p>Each row in the list shows the frame number, dx, dy, rotation, and a − delete button. Click a row to select it and expand the property editor below. Click again to collapse. The − button removes that keyframe (disabled when only 2 keyframes remain).</p>

<h2>Adding a keyframe</h2>
<p>Below the list, set the target frame in the <strong>Add at [N] fr</strong> stepper, then click <strong>+</strong>. The new keyframe is initialised with interpolated values from the path's current state at that frame — inserting is non-destructive. Edit the values to diverge from the interpolated baseline.</p>

<h2>Keyframe property editor</h2>
<table>
  <tr><th>Field</th><th>Range</th><th>Unit</th><th>Description</th></tr>
  <tr><td><strong>Frame</strong></td><td>0 – 9999</td><td>fr</td><td>Frame number. Stepper; list re-sorts automatically.</td></tr>
  <tr><td><strong>Offset X</strong></td><td>−3 – 3</td><td>c</td><td>Horizontal offset in cell-width fractions. 0 = cell centre.</td></tr>
  <tr><td><strong>Offset Y</strong></td><td>−3 – 3</td><td>c</td><td>Vertical offset in cell-height fractions.</td></tr>
  <tr><td><strong>Rotation</strong></td><td>−360 – 360</td><td>°</td><td>Rotation added to the cell's base rotation and any parametric rotation.</td></tr>
  <tr><td><strong>Scale X / Y</strong></td><td>0.1 – 3</td><td>×</td><td>Scale multiplier, combined with cell scale and parametric scale.</td></tr>
  <tr><td><strong>Easing</strong></td><td>—</td><td>—</td><td>Interpolation curve from this keyframe to the next.</td></tr>
</table>
<table>
  <tr><th>Easing</th><th>Shape</th></tr>
  <tr><td>Linear</td><td>Constant rate throughout the segment.</td></tr>
  <tr><td>Ease In</td><td>Starts slow, accelerates into the next keyframe.</td></tr>
  <tr><td>Ease Out</td><td>Arrives fast, decelerates at the next keyframe.</td></tr>
  <tr><td>Ease In/Out</td><td>Slow at both ends, fastest through the middle. Default.</td></tr>
  <tr><td>Step</td><td>Holds the current keyframe's values and jumps instantly to the next.</td></tr>
</table>
<p>Double-click any slider in the property editor to reset it to its default value.</p>

<h2>Step-by-step: a simple orbit path</h2>
<ol class="steps">
  <li>Create a new path via <strong>+ New Path</strong> in the Style Palette. Rename it "Orbit" in the Name field.</li>
  <li>Select <strong>keyframe 0</strong>. Set Offset X to <strong>−1.0</strong>, Offset Y to <strong>0</strong>. This is the leftmost point of the orbit.</li>
  <li>Select <strong>keyframe 48</strong>. Set Offset X to <strong>−1.0</strong>, Offset Y to <strong>0</strong> (same as frame 0 — the loop closes smoothly). This is a placeholder we'll add intermediate points to.</li>
  <li>Click <strong>Add at 12 fr</strong>. Set Offset X to <strong>0</strong>, Offset Y to <strong>−1.0</strong>. Top of the orbit.</li>
  <li>Click <strong>Add at 24 fr</strong>. Set Offset X to <strong>1.0</strong>, Offset Y to <strong>0</strong>. Right of the orbit.</li>
  <li>Click <strong>Add at 36 fr</strong>. Set Offset X to <strong>0</strong>, Offset Y to <strong>1.0</strong>. Bottom of the orbit.</li>
  <li>The path overlay on the canvas now shows a rough circular trajectory. Press <kbd>Space</kbd> to play — any cells assigned to this path will orbit.</li>
  <li>Select cells with the Select tool, then in PLACE &amp; TIME set their <strong>Path</strong> to "Orbit". Paint more cells with Sequential phase policy — they'll distribute evenly around the orbit.</li>
</ol>

<h2>Assigning and deselecting paths</h2>
<p>Click a path row in the Style Palette to make it the active path — newly drawn cells will be assigned to it. <strong>Click the highlighted row again to deselect it</strong> — the active path becomes nil and newly drawn cells are painted with no path assignment. You can also assign a path to already-drawn cells via PLACE &amp; TIME → Path.</p>

<h2>Path deselect on canvas</h2>
<p>The path overlay (dots and connecting line) only appears when a path is active. Deselecting the path in the palette hides the overlay.</p>
"""#

private let qaPlaceBody = #"""
<h1>Quick Adjust: PLACE &amp; TIME</h1>
<p class="subtitle">Edit all four axis assignments and the spatial, temporal, scale, and rotation properties of selected cells.</p>

<p>All PLACE &amp; TIME controls apply simultaneously to every <strong>selected cell</strong>. Select cells first using the Select tool or Nudge tool, then edit here. When multiple cells with different values are selected, each control shows the value of the first selected cell — editing applies to all.</p>

<h2>Four-axis assignment pickers</h2>
<p>The top of PLACE &amp; TIME contains a picker for each of the four creative axes. These let you reassign any axis on selected cells after they have been painted:</p>

<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Style</strong></td><td>Reassigns every selected cell to the chosen style. Affects rendering: fill, stroke, mode.</td></tr>
  <tr><td><strong>Motion</strong></td><td>Assigns a motion set to the selected cells. Choose — to remove the motion assignment (cells revert to Static). Affects parametric animation: preset, speed, amount, Order/Chaos, SEQUENCE cycling.</td></tr>
  <tr><td><strong>Shape</strong></td><td>Assigns a shape (Loom polygon set) to the selected cells. Choose — to remove it (cells revert to the default built-in shape). Note: when the assigned motion set has Sequence mode active, the motion set's shape list takes precedence over this per-cell assignment.</td></tr>
  <tr><td><strong>Path</strong></td><td>Assigns a keyframe motion path to the selected cells. Choose None to remove the path assignment.</td></tr>
</table>

<h3>Step-by-step: reassigning an axis on existing cells</h3>
<ol class="steps">
  <li>Switch to the <strong>Select</strong> tool (<kbd>S</kbd>) and rubber-band or click to select the cells you want to change.</li>
  <li>In PLACE &amp; TIME, open the picker for the axis you want to change (Style, Motion, Shape, or Path).</li>
  <li>Choose the new value. All selected cells update immediately — the change is undoable with <kbd>⌘Z</kbd>.</li>
</ol>

<h2>Spatial and temporal properties</h2>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Offset X / Y</strong></td><td>Position offset in reference pixels. Positive X = right; positive Y = down.</td></tr>
  <tr><td><strong>Phase</strong></td><td>The phaseOffset in frames. The cell evaluates its animation at currentFrame + phaseOffset. Applies to the parametric motion preset, the keyframe path, and SEQUENCE cycling — cells with higher phase are further along in every cycle.</td></tr>
  <tr><td><strong>Scale X / Y</strong></td><td>Resting-pose size (0.1 – 3.0, double-click to reset to 1.0). Multiplicative with animated scale from the motion preset and path. X and Y are linked by default — click the link icon to unlock.</td></tr>
  <tr><td><strong>Rotation</strong></td><td>Resting-pose rotation (−180° to +180°, double-click to reset to 0°). Animated rotation from MOTION and PATH EDITOR adds on top.</td></tr>
  <tr><td><strong>Rescatter</strong></td><td>Re-randomises positionOffset and re-assigns phaseOffset using the current Scatter and Phase Policy settings.</td></tr>
</table>

<h3>Phase offset vs motion phase</h3>
<p>These are two different things that are easy to confuse:</p>
<ul>
  <li><strong>Phase offset</strong> (here in PLACE &amp; TIME) — shifts <em>when</em> a cell's animation begins. Cell A at offset 0 and Cell B at offset 24 are always 24 frames apart in every cycle — the parametric preset, the path loop, and the SEQUENCE shape cycle.</li>
  <li><strong>Motion phase</strong> (in the MOTION section) — shifts the starting point <em>within</em> the oscillation waveform of the parametric preset. It is a per-motion-set design parameter that affects all cells using that motion set equally.</li>
</ul>

<h3>Rescatter workflow</h3>
<ol class="steps">
  <li>Select the cells you want to re-randomise (rubber-band with Select, or <kbd>⌘A</kbd> for all).</li>
  <li>Set the Scatter slider in the Tool Strip to the desired scatter amount.</li>
  <li>Set the Phase Policy to the desired policy.</li>
  <li>Click <strong>Rescatter</strong>. Position offsets and phase offsets are re-randomised immediately.</li>
</ol>
"""#

private let paletteBody = #"""
<h1>Style Palette &amp; Library</h1>
<p class="subtitle">Manage layers, styles, paths, and shapes for the current project and your global library.</p>

<p>The Style Palette sits on the left side of the window. It has two tabs: <strong>Project</strong> and <strong>Library</strong>.</p>

<h2>Project tab</h2>
<p>Lists everything owned by the current document. Organised into six sections: LAYERS, STYLES, MOTIONS, PATHS, SHAPES, and PALETTES.</p>

<h3>LAYERS</h3>
<p>See <a href="um-help://help/layers">Working with Layers</a> for the full guide to layers.</p>

<h3>STYLES</h3>
<p>A style controls rendering only: fill colour, stroke colour, stroke width, and render mode. Click a style row to make it the <strong>active style</strong> — new cells you draw will carry this style. The active style is highlighted with an accent indicator.</p>
<ul>
  <li><strong>+ New Style</strong> — adds a blank style to the project.</li>
  <li><strong>↑ button</strong> — saves a copy to the global library.</li>
  <li><strong>Double-click the name</strong> — rename inline.</li>
</ul>
<p>Right-click a style row for the context menu:</p>
<table>
  <tr><th>Item</th><th>Effect</th></tr>
  <tr><td>Create Variant → Inverted</td><td>New style with fill and stroke RGB values inverted; alpha preserved.</td></tr>
  <tr><td>Create Variant → Faint</td><td>New style with fill alpha 0.15, stroke alpha 0.25.</td></tr>
  <tr><td>Create Variant → Strong</td><td>New style with fill and stroke alpha set to 1.0.</td></tr>
  <tr><td>Create Variant → Swap Colors</td><td>New style with fill and stroke colours exchanged.</td></tr>
  <tr><td>Create Variant → Outline Only</td><td>New style in Stroked mode; fill alpha 0.</td></tr>
  <tr><td>Create Variant → Filled Only</td><td>New style in Filled mode; stroke alpha 0.</td></tr>
  <tr><td>Save to Library</td><td>Promotes the style to the global library.</td></tr>
  <tr><td>Delete Style</td><td>Removes the style. Cells using it are reassigned to the first remaining style. Disabled when only one style exists.</td></tr>
</table>

<h3>MOTIONS</h3>
<p>Motion sets control animation: parametric preset, speed, amount, phase, Order/Chaos, axis mix, and SEQUENCE shape cycling. Click a motion set row to make it the <strong>active motion</strong> — new cells you draw will carry this motion. The <strong>MOTION</strong> section in Quick Adjust (right panel) shows its parameters immediately.</p>
<ul>
  <li><strong>+ New Motion</strong> — adds a blank motion set (Static preset, all defaults).</li>
  <li><strong>↑ button</strong> — saves a copy to the global library.</li>
  <li><strong>Double-click the name</strong> — rename inline.</li>
  <li><strong>Right-click</strong> — Rename, Save to Library, Delete Motion.</li>
</ul>
<div class="tip"><strong>Editing a motion set</strong> — click the motion set row to select it, then adjust Preset, Speed, Amount, Phase, Order/Chaos, and SEQUENCE settings in the <strong>MOTION</strong> section of Quick Adjust on the right. Changes apply immediately to all cells that carry this motion set. See <a href="um-help://help/qa-motion">Motion Palette</a> for the full guide.</div>

<h3>PATHS</h3>
<p>Click a path row to make it the <strong>active path</strong> for editing — its keyframes appear in the PATH EDITOR section of Quick Adjust, and the path overlay appears on the canvas. Click the highlighted row again to deselect it (newly drawn cells will have no path assignment).</p>
<ul>
  <li><strong>+ New Path</strong> — creates a path with two identity keyframes (frames 0 and 48) and selects it.</li>
  <li>Each row shows a keyframe count badge (e.g. <code>4 kf</code>) and a <strong>↑</strong> button to promote to the library.</li>
  <li><strong>Double-click the name</strong> — rename inline.</li>
</ul>
<p>Right-click a path row: <strong>Save to Library</strong> or <strong>Delete Path</strong> (removes from project and clears its reference from all cells).</p>

<h3>SHAPES</h3>
<p>Shapes are Loom polygon-set geometry files imported into the project. Each shape is a named set of bezier polygons. Clicking a shape sets it as the <strong>active shape</strong> — new cells you draw will be rendered with this geometry. Click the highlighted row again to deselect (new cells will use the default built-in polygon).</p>
<ul>
  <li><strong>+ Import Shape…</strong> — opens a file picker (defaults to ~/.loom_projects). Select one or more Loom .json polygon-set files.</li>
  <li><strong>↑ button</strong> — saves the shape to the global library.</li>
  <li><strong>Double-click the name</strong> — rename inline.</li>
</ul>
<p>Right-click: <strong>Delete Shape</strong> removes it from the project. Any cells that referenced this shape fall back to the default geometry.</p>

<div class="tip"><strong>Shape cycling over time</strong> — to cycle through multiple shapes on a schedule, use the SEQUENCE feature in the <strong>MOTION</strong> section: add shape slots to a motion set, set a step interval, and choose Sequential or Random mode. The motion set's shape list overrides the per-cell shape during playback. See <a href="um-help://help/qa-motion">Motion Palette → SEQUENCE cycling</a>.</div>

<h3>PALETTES</h3>
<p>Colour palettes are sets of swatches sampled from a Color Map source. They provide a way to apply coherent, image-sourced colours to your styles through the palette picker in the RENDER section.</p>
<ul>
  <li><strong>Generate from Color Map…</strong> — opens a sheet to name the palette and choose a size. Available only when a Color Map source is loaded. Sizes:
    <ul>
      <li><strong>4×4</strong> — 16 colours (4 horizontal bands × 4 vertical bands of the source image)</li>
      <li><strong>4×8</strong> — 32 colours</li>
      <li><strong>8×8</strong> — 64 colours</li>
    </ul>
  </li>
  <li>Each palette row shows the name and a <strong>swatch strip preview</strong> of the first 32 colours.</li>
  <li><strong>↑ button</strong> — saves the palette to the global library for reuse across projects.</li>
  <li><strong>Double-click the name</strong> — rename inline.</li>
</ul>
<p>Right-click a palette row: <strong>Save to Library</strong> or <strong>Delete Palette</strong>.</p>
<p>To use a palette colour in a style, click the palette icon (🎨) next to Fill or Stroke in the RENDER section — see <a href="um-help://help/qa-style">Style (RENDER)</a>.</p>

<div class="tip"><strong>Workflow tip</strong> — generate several palettes at different sizes from the same source to give yourself a coarse (4×4) and a fine (8×8) set of options. Palettes from different color sources can coexist — name them by source to keep track.</div>

<h2>Library tab</h2>
<p>Shows your global user library — styles, motion sets, paths, shapes, and colour palettes saved across all projects.</p>
<ul>
  <li>Style, motion, shape, and palette rows show whether the item is already in the current project. If not, a <strong>↓</strong> button imports it.</li>
  <li>Library is stored at <code>~/Library/Application Support/UM/library.json</code> (styles/paths/motions/palettes) and <code>~/Library/Application Support/UM/shapes/</code> (shapes).</li>
  <li>Right-click any library row to remove it from the library.</li>
</ul>
"""#

private let exportBody = #"""
<h1>Export</h1>
<p class="subtitle">PNG stills and H.264 video from the Transport Bar.</p>
<p>Export settings are configured in the <strong>EXPORT</strong> section of Quick Adjust. See <a href="um-help://help/qa-project">PROJECT / CANVAS</a> for those controls.</p>

<h2>PNG export</h2>
<ol class="steps">
  <li>Navigate to the frame you want — pause playback and scrub the frame counter, or leave at frame 0 for the start.</li>
  <li>Set <strong>Multiplier</strong> and <strong>Scale drawing</strong> in the EXPORT section if needed.</li>
  <li>Click <strong>PNG</strong> in the Transport Bar.</li>
  <li>A save panel opens. The default location is <code>renders/stills/</code> inside your project package. The suggested filename is <code>&lt;projectname&gt;_YYYYMMDD_HHmmss.png</code>.</li>
  <li>Choose a location and click Save. The image is written immediately.</li>
</ol>
<p>The export renders at <code>canvasWidth × multiplier</code> × <code>canvasHeight × multiplier</code>. In accumulation mode (Background draw off), the current accumulation buffer is composited as the background before rendering the current frame. All visible layers are composited at their configured opacities.</p>

<h2>Video export</h2>
<ol class="steps">
  <li>Set the export range using <strong>From / To</strong> in the EXPORT section (or the Start / End fields in the Transport Bar — they are the same values).</li>
  <li>Set <strong>Multiplier</strong>, <strong>Scale drawing</strong>, and <strong>FPS</strong> as needed.</li>
  <li>Click <strong>Video</strong> in the Transport Bar.</li>
  <li>A save panel opens. Default location: <code>renders/animations/</code> inside your project package.</li>
  <li>Choose a location and click Save. The panel closes and export begins in the background.</li>
  <li>A progress bar replaces the Video button showing <em>N%</em>. The UI remains responsive during export.</li>
  <li>When complete, the Video button returns.</li>
</ol>
<p>Format: H.264 in a .mov container. The exported clip spans animation frames <em>From</em> through <em>To − 1</em>, output as a clip starting at time zero. All layers composite per-frame at their configured opacities. In accumulation mode, each exported frame correctly shows the accumulated build-up, exactly as it appears on screen during live playback.</p>

<h2>Render directories</h2>
<p>Render directories live <strong>inside</strong> the project package and are created automatically when the project is saved:</p>
<pre>
MyProject.umproj/
    renders/
        stills/       ← PNG exports
        animations/   ← Video exports
</pre>
<p>The save panel defaults to the correct subdirectory — you can accept the default or navigate elsewhere. If the project has not been saved yet, the save panel defaults to <code>~/Documents/UM Projects/renders/</code> instead.</p>

<div class="warn"><strong>SVG export</strong> — the SVG button in the Transport Bar is present but not yet implemented.</div>
"""#

private let resampleBody = #"""
<h1>Resample Grid</h1>
<p class="subtitle">Change the grid resolution while preserving the composition's spatial and temporal nuance.</p>

<p>Click the <strong>resolution label</strong> (e.g. <strong>6×6</strong>) at the far right of the Tool Strip to open the Resample Grid sheet.</p>
<p>The grid always fills the full output canvas — columns divide the canvas width equally, rows divide the canvas height equally. Changing resolution changes cell size, not canvas size.</p>

<h2>Setting the target size</h2>
<ul>
  <li><strong>Rows / Cols</strong> fields — type directly to set the destination dimensions.</li>
  <li><strong>Scale Factor</strong> — type a multiplier (e.g. <code>2</code> to double, <code>0.5</code> to halve) and click Apply. Can be used repeatedly.</li>
</ul>

<h2>Resize policies</h2>
<p>These control what happens to position offsets and phase offsets during the resample.</p>

<h3>Offset policy (position offsets)</h3>
<table>
  <tr><th>Option</th><th>Effect</th></tr>
  <tr><td><strong>Preserve</strong> (default)</td><td>Position offsets copy unchanged in absolute pixels. A sprite displaced 12 px rightward remains 12 px rightward in the new grid — sprites stay visually where you placed them.</td></tr>
  <tr><td><strong>Scale</strong></td><td>Offsets scale proportionally with the change in cell size. A sprite at 50% of the old cell width remains at 50% of the new (larger or smaller) cell width.</td></tr>
  <tr><td><strong>Reset</strong></td><td>All position offsets are zeroed. Sprites re-centre on their new cell centres.</td></tr>
</table>

<h3>Phase policy (phase offsets)</h3>
<table>
  <tr><th>Option</th><th>Effect</th></tr>
  <tr><td><strong>Inherit</strong> (default)</td><td>Child cells inherit the parent's phaseOffset unchanged.</td></tr>
  <tr><td><strong>Scatter</strong></td><td>Each child inherits its parent's phaseOffset plus a bounded random perturbation. The Scatter slider controls the magnitude. Prevents a mechanical look when subdividing.</td></tr>
  <tr><td><strong>Reset</strong></td><td>All phase offsets are zeroed.</td></tr>
</table>

<p>Path assignments are preserved across all resize policies — if a cell was assigned to a path, it remains assigned after resampling.</p>
<p>Click <strong>Resample</strong> to apply. Click <strong>Cancel</strong> (or press Escape) to close without changes. Both resample and cancel are fully undoable.</p>

<div class="tip"><strong>Going coarser</strong> — when going from a finer to a coarser grid (e.g. 16×16 → 8×8), merged cells adopt the position and phase offset of the child closest to the merged area's centre. Choose Preserve + Inherit to carry the composition faithfully to the lower-resolution version.</div>
"""#

private let saveBody = #"""
<h1>Save, Load &amp; Undo</h1>

<h2>Saving and loading</h2>
<p>UM projects are saved as <code>.umproj</code> files — plain JSON containing the full document: grid configuration, all cells (including position offsets, phase offsets, path assignments), styles, paths, shapes (including full geometry), canvas size, timeline states, and color source settings. Files are human-readable in any text editor.</p>
<p>Projects saved by earlier builds load correctly — missing fields default to sensible values automatically.</p>
<p><strong>Shape geometry is embedded</strong> in the .umproj file. You do not need to keep the original Loom .json files alongside the project. Once imported, shapes are self-contained.</p>
<p><strong>Color source files</strong> are referenced by absolute path, not embedded. Copy the image or video file alongside the project when sharing it across machines.</p>

<h3>Keyboard shortcuts</h3>
<table>
  <tr><th>Shortcut</th><th>Action</th></tr>
  <tr><td><kbd>⌘N</kbd></td><td>New — resets to a blank 8×8 grid</td></tr>
  <tr><td><kbd>⌘O</kbd></td><td>Open — shows a file chooser</td></tr>
  <tr><td><kbd>⌘S</kbd></td><td>Save — writes to the current file; opens Save As for unsaved documents</td></tr>
  <tr><td><kbd>⌘⇧S</kbd></td><td>Save As — always shows the save panel</td></tr>
</table>

<h3>Default projects folder</h3>
<p>New documents save to <code>~/Documents/UM Projects/</code> (created automatically on first launch). To change it: <strong>UM → Preferences…</strong> (<kbd>⌘,</kbd>) → Choose… → Reset to revert.</p>
<p>The window title shows <em>UM — Untitled</em> until saved; <em>UM — FileName</em> after.</p>

<h2>Undo and Redo</h2>
<table>
  <tr><th>Shortcut</th><th>Action</th></tr>
  <tr><td><kbd>⌘Z</kbd></td><td>Undo</td></tr>
  <tr><td><kbd>⌘⇧Z</kbd></td><td>Redo</td></tr>
</table>
<p>The undo stack holds up to 40 snapshots.</p>

<h3>What is recorded as a single undo step</h3>
<ul>
  <li>Each paint stroke (first touch to release)</li>
  <li>Each grid transform (flip, rotate, clear, invert)</li>
  <li>Each stamp transform</li>
  <li>Each resample</li>
  <li>Each nudge drag (first touch to release)</li>
  <li>Each arrow-key nudge sequence</li>
  <li>Each Rescatter operation</li>
  <li>Path assignment to selected cells (PLACE &amp; TIME → Path)</li>
  <li>Quick Adjust field edits (committed on Return or focus-loss)</li>
</ul>

<h3>What is not recorded</h3>
<ul>
  <li>Phase policy changes in the Tool Strip</li>
  <li>Resize policy selections in the Resample sheet</li>
  <li>Keyframe edits in PATH EDITOR (these update the path immediately but undo for keyframe editing is not yet implemented)</li>
</ul>
<p>Timeline states accumulate independently and are managed via the Timeline Editor — they are not part of the undo stack.</p>
"""#

private let shortcutsBody = #"""
<h1>Keyboard Shortcuts</h1>

<h2>Tools</h2>
<table>
  <tr><th>Key</th><th>Tool</th></tr>
  <tr><td><kbd>D</kbd></td><td>Draw</td></tr>
  <tr><td><kbd>E</kbd></td><td>Erase</td></tr>
  <tr><td><kbd>S</kbd></td><td>Select</td></tr>
  <tr><td><kbd>A</kbd></td><td>Sample</td></tr>
  <tr><td><kbd>F</kbd></td><td>Fill</td></tr>
  <tr><td><kbd>N</kbd></td><td>Nudge</td></tr>
</table>

<h2>Playback</h2>
<table>
  <tr><th>Key</th><th>Action</th></tr>
  <tr><td><kbd>Space</kbd></td><td>Play / Pause</td></tr>
</table>

<h2>Nudge (cells selected)</h2>
<table>
  <tr><th>Key</th><th>Action</th></tr>
  <tr><td><kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd></td><td>Move position offset 1 px</td></tr>
  <tr><td><kbd>⇧←</kbd> <kbd>⇧→</kbd> <kbd>⇧↑</kbd> <kbd>⇧↓</kbd></td><td>Move position offset 10 px</td></tr>
</table>

<h2>File</h2>
<table>
  <tr><th>Key</th><th>Action</th></tr>
  <tr><td><kbd>⌘N</kbd></td><td>New document</td></tr>
  <tr><td><kbd>⌘O</kbd></td><td>Open…</td></tr>
  <tr><td><kbd>⌘S</kbd></td><td>Save</td></tr>
  <tr><td><kbd>⌘⇧S</kbd></td><td>Save As…</td></tr>
  <tr><td><kbd>⌘,</kbd></td><td>Preferences</td></tr>
</table>

<h2>Edit</h2>
<table>
  <tr><th>Key</th><th>Action</th></tr>
  <tr><td><kbd>⌘Z</kbd></td><td>Undo</td></tr>
  <tr><td><kbd>⌘⇧Z</kbd></td><td>Redo</td></tr>
</table>

<h2>Canvas Zoom</h2>
<table>
  <tr><th>Key / Gesture</th><th>Action</th></tr>
  <tr><td>Pinch</td><td>Zoom in / out</td></tr>
  <tr><td>Scroll (no modifier)</td><td>Pan</td></tr>
  <tr><td><kbd>⌥</kbd> + scroll</td><td>Zoom in / out</td></tr>
  <tr><td><kbd>⌘0</kbd></td><td>Reset zoom &amp; pan</td></tr>
  <tr><td><kbd>⌘=</kbd></td><td>Zoom in 25%</td></tr>
  <tr><td><kbd>⌘−</kbd></td><td>Zoom out 25%</td></tr>
</table>

<h2>Help</h2>
<table>
  <tr><th>Key</th><th>Action</th></tr>
  <tr><td><kbd>⌘/</kbd></td><td>Open this help window</td></tr>
</table>

<div class="note"><strong>Suppressed shortcuts</strong> — single-key tool shortcuts (D, E, S, A, F, N) are suppressed while a text field has keyboard focus, and when Command, Option, or Control is held, so they never conflict with menu shortcuts or text editing.</div>
"""#

private let pendingBody = #"""
<h1>Not Yet Built</h1>
<p class="subtitle">Features designed and planned, but not yet implemented in the current build.</p>

<table>
  <tr><th>Area</th><th>Feature</th><th>Notes</th></tr>
  <tr><td>Right panel</td><td>Full palette-context right panel (Style / Shape detail sections)</td><td>When a STYLE or SHAPE palette item is active and no cell is selected, the right panel could show a dedicated detail section for that item. Currently only the MOTION section appears when a motion set is active. Style detail (RENDER) and Shape detail are not yet context-switched in — you must select cells and edit via PLACE &amp; TIME instead.</td></tr>
  <tr><td>Left panel</td><td>Resolution preset library (global tabs)</td><td>The LAYERS section already shows preset resolution chips (4×4 through 32×32) and project-saved presets. What's missing is a Library tab to save resolution presets globally across projects.</td></tr>
  <tr><td>Rendering</td><td>Subdivision-level polygon warp</td><td>ORDER/CHAOS currently produces sine-oscillator jitter on sprite transforms. The deeper materialisation — warping polygon vertices via SubdivisionEngine based on the chaos value — is designed but not yet wired.</td></tr>
  <tr><td>Rendering</td><td>Full Loom render modes</td><td>Brushed (stamp-along-path), stenciled, stamped (bitmap at positions), and path perturbation (noise warp of geometry). Current build: Filled, Stroked, Fill &amp; Stroke only.</td></tr>
  <tr><td>Rendering</td><td>Animated style thumbnails</td><td>Style rows in the palette show a static coloured dot. Live animated miniature previews are planned.</td></tr>
  <tr><td>Canvas</td><td>Hover preview</td><td>No visual feedback on undrawn cells before committing a stroke. A faint style preview on hover is planned.</td></tr>
  <tr><td>Export</td><td>SVG export</td><td>The SVG button in the Transport Bar is present but has no action yet.</td></tr>
  <tr><td>Export</td><td>Timeline video export</td><td>The Video button exports live animation (parametric + keyframe motion). A separate mode that renders the recorded timeline states as discrete cuts is planned.</td></tr>
  <tr><td>Path Editor</td><td>Bezier tangent handles</td><td>The PATH EDITOR uses per-segment easing (Linear, Ease In/Out, Step). Cubic bezier tangent handles (in/out per keyframe, drawn on the canvas as draggable circles) are designed but not yet built.</td></tr>
  <tr><td>Geometry</td><td>In-app geometry editor</td><td>Shapes must currently be authored in standalone Loom and imported as .json files. An in-app geometry mode (toolbar button G) is planned once Loom's editor is extractable as a standalone Swift Package.</td></tr>
  <tr><td>Canvas overlays</td><td>Phase heat-map overlay</td><td>A toggleable overlay colouring each cell by its phaseOffset value (blue = 0, red = max) to make temporal structure visible without playing the animation.</td></tr>
  <tr><td>Canvas overlays</td><td>Background image backdrop</td><td>✓ Built — "Bg Image" row in CANVAS section. Image fills canvas behind all layers; saved in project package.</td></tr>
  <tr><td>Layers</td><td>Animated opacity &amp; parallax drivers</td><td>Camera pan, zoom, and rotation support constant values today. Oscillator and keyframe modes (driving camera motion over time) and the per-layer opacity/offset drivers are Phase 2.</td></tr>
  <tr><td>Layers</td><td>Blend modes</td><td>Layer compositing currently uses Normal (opacity) only. Additional CGBlendMode options are planned.</td></tr>
  <tr><td>Undo</td><td>Keyframe edit undo</td><td>Keyframe edits in PATH EDITOR update the path immediately but are not tracked in the undo stack.</td></tr>
  <tr><td>Compatibility</td><td>Legacy UM XML import</td><td>No importer for Java UM .xml project files. Old Swift .umproj files (pre-4-axis model) are automatically migrated on open.</td></tr>
</table>
"""#
