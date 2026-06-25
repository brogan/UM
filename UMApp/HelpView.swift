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
        let url  = task.request.url
        let path = url?.host == "help" ? (url?.lastPathComponent ?? "intro") : "intro"
        let html: String
        if path == "search" {
            let q = URLComponents(url: url ?? URL(string: "um-help://help/search")!,
                                  resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            html = page("Search", searchBody(query: q))
        } else {
            html = helpPages[path] ?? helpPages["intro"]!
        }
        let data = Data(html.utf8)
        let resp = URLResponse(url: url ?? URL(string: "um-help://help/intro")!,
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
    "intro":       page("Introduction",              introBody),
    "layout":      page("Interface Layout",          layoutBody),
    "layers":      page("Working with Layers",       layersBody),
    "painting":    page("Painting Tools",            paintingBody),
    "transforms":  page("Grid Transforms",           transformsBody),
    "phase":       page("Phase Policy & Scatter",    phaseBody),
    "playback":    page("Playback & Recording",      playbackBody),
    "qa-project":  page("PROJECT / CANVAS / CAMERA", qaProjectBody),
    "qa-style":    page("Style (RENDER section)",    qaStyleBody),
    "qa-motion":   page("Motion Palette",            qaMotionBody),
    "qa-path":     page("PATH EDITOR",               qaPathBody),
    "qa-place":    page("PLACE & TIME",              qaPlaceBody),
    "palette":     page("Style Palette",             paletteBody),
    "sprite-sets": page("Sprite Sets",               spriteSetsBody),
    "export":      page("Export",                    exportBody),
    "resample":    page("Resample Grid",             resampleBody),
    "save":        page("Save, Load & Undo",         saveBody),
    "shortcuts":   page("Keyboard Shortcuts",        shortcutsBody),
    "pending":     page("Not Yet Built",             pendingBody),
]

// MARK: - Search helpers

// Body-only content indexed for search (no nav/CSS noise).
private let helpBodies: [String: String] = [
    "intro":       introBody,
    "layout":      layoutBody,
    "layers":      layersBody,
    "painting":    paintingBody,
    "transforms":  transformsBody,
    "phase":       phaseBody,
    "playback":    playbackBody,
    "qa-project":  qaProjectBody,
    "qa-style":    qaStyleBody,
    "qa-motion":   qaMotionBody,
    "qa-path":     qaPathBody,
    "qa-place":    qaPlaceBody,
    "palette":     paletteBody,
    "sprite-sets": spriteSetsBody,
    "export":      exportBody,
    "resample":    resampleBody,
    "save":        saveBody,
    "shortcuts":   shortcutsBody,
    "pending":     pendingBody,
]

private let pageTitles: [String: String] = [
    "sprite-sets": "Sprite Sets",
    "intro":       "Introduction",
    "layout":     "Interface Layout",
    "layers":     "Working with Layers",
    "painting":   "Painting Tools",
    "transforms": "Grid Transforms",
    "phase":      "Phase Policy & Scatter",
    "playback":   "Playback & Recording",
    "qa-project": "PROJECT / CANVAS / CAMERA",
    "qa-style":   "Style (RENDER section)",
    "qa-motion":  "Motion Palette",
    "qa-path":    "PATH EDITOR",
    "qa-place":   "PLACE & TIME",
    "palette":    "Style Palette",
    "export":     "Export",
    "resample":   "Resample Grid",
    "save":       "Save, Load & Undo",
    "shortcuts":  "Keyboard Shortcuts",
    "pending":    "Not Yet Built",
]

private func escapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
}

private func stripHTML(_ html: String) -> String {
    var s = html
    for pattern in ["<script[^>]*>[\\s\\S]*?</script>", "<style[^>]*>[\\s\\S]*?</style>"] {
        if let rx = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            s = rx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
    }
    if let rx = try? NSRegularExpression(pattern: "<[^>]+>") {
        s = rx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
    }
    s = s.replacingOccurrences(of: "&amp;",  with: "&")
         .replacingOccurrences(of: "&lt;",   with: "<")
         .replacingOccurrences(of: "&gt;",   with: ">")
         .replacingOccurrences(of: "&nbsp;", with: " ")
         .replacingOccurrences(of: "&#39;",  with: "'")
         .replacingOccurrences(of: "&quot;", with: "\"")
    return s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

private func searchBody(query: String) -> String {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else {
        return """
        <h1>Search</h1>
        <p class="subtitle">Type a term in the search box to find help topics.</p>
        """
    }
    let qLower = q.lowercased()

    struct Hit { var key: String; var title: String; var count: Int; var snippet: String }
    var hits: [Hit] = []

    for (key, body) in helpBodies {
        let text     = stripHTML(body)
        let textLow  = text.lowercased()
        var count    = 0
        var pos      = textLow.startIndex
        while let r = textLow.range(of: qLower, range: pos..<textLow.endIndex) {
            count += 1
            pos = r.upperBound
            if count >= 15 { break }
        }
        guard count > 0,
              let firstR = textLow.range(of: qLower) else { continue }

        let matchOffset = text.distance(from: text.startIndex, to: firstR.lowerBound)
        let lo  = max(0, matchOffset - 80)
        let hi  = min(text.count, matchOffset + q.count + 120)
        let s0  = text.index(text.startIndex, offsetBy: lo)
        let s1  = text.index(text.startIndex, offsetBy: hi)
        var snip = escapeHTML(String(text[s0..<s1]))
        if lo > 0 { snip = "…" + snip }
        if hi < text.count { snip += "…" }
        // highlight (q is plain text so safe to inject wrapped in <mark>)
        let qEsc  = escapeHTML(q)
        let snipHL = snip.replacingOccurrences(of: qEsc, with: "<mark>\(qEsc)</mark>",
                                               options: .caseInsensitive)
        hits.append(Hit(key: key, title: pageTitles[key] ?? key, count: count, snippet: snipHL))
    }

    hits.sort { $0.count > $1.count }

    guard !hits.isEmpty else {
        return """
        <h1>Search: &ldquo;\(escapeHTML(q))&rdquo;</h1>
        <p>No results found. Try a shorter or different term, or browse the navigation on the left.</p>
        """
    }

    let cards = hits.map { h in
        """
        <div class="search-result">
          <span class="result-count">\(h.count) match\(h.count == 1 ? "" : "es")</span>
          <a href="um-help://help/\(h.key)">\(escapeHTML(h.title))</a>
          <p class="snippet">\(h.snippet)</p>
        </div>
        """
    }.joined()

    let n = hits.count
    return """
    <h1>Search: &ldquo;\(escapeHTML(q))&rdquo;</h1>
    <p class="subtitle">\(n) page\(n == 1 ? "" : "s") matched</p>
    \(cards)
    """
}

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
.search-form{padding:8px 10px 6px}
.search-form input[type=search]{width:100%;padding:5px 9px;font-size:12px;border-radius:7px;
  border:1px solid var(--border);background:var(--bg);color:var(--text);outline:none;
  -webkit-appearance:none}
.search-form input[type=search]:focus{border-color:var(--accent);box-shadow:0 0 0 2px rgba(0,113,227,.18)}
.search-result{background:var(--bg);border:1px solid var(--border);border-radius:9px;
  padding:11px 14px;margin-bottom:9px;overflow:hidden}
.search-result a{font-size:13px;font-weight:600;display:block;margin-bottom:2px}
.result-count{font-size:10px;color:var(--sub);float:right;margin-top:2px}
.snippet{font-size:12px;color:var(--sub);margin-top:5px;line-height:1.5;clear:both}
mark{background:rgba(255,210,0,.38);border-radius:2px;padding:0 1px;color:inherit}
@media(prefers-color-scheme:dark){
  mark{background:rgba(255,210,0,.22)}
  .search-form input[type=search]:focus{box-shadow:0 0 0 2px rgba(10,132,255,.25)}
}
"""#

// MARK: - Navigation HTML

private let nav = #"""
<a class="nav-logo" href="um-help://help/intro">UM Help</a>
<form class="search-form" action="um-help://help/search" method="GET">
  <input type="search" name="q" placeholder="Search help…" autocomplete="off" autocorrect="off" spellcheck="false">
</form>
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
  <li>Click <strong>+ New Layer</strong> below the layer list — a small menu appears. Choose <strong>Grid Layer</strong> for a standard grid layer or <strong>Open Layer</strong> for free-placement (see Open Layers below). The new layer becomes active.</li>
  <li>Right-click a layer row → <strong>Duplicate</strong> to copy the layer including all its cells, styles, and paths.</li>
  <li>Right-click → <strong>Delete Layer</strong> to remove it. Disabled when only one layer remains.</li>
</ul>

<h2>Layers and export</h2>
<p>PNG and video exports composite all visible layers at their configured opacities. Hidden layers are excluded. Each layer uses its own grid resolution when rendering — a 4×4 foreground layer and an 8×8 background layer both occupy the full canvas area, each drawn at their respective cell sizes.</p>

<h2>Layers and the timeline</h2>
<p>Timeline recording and state navigation operate on the <em>active layer</em> only. Other layers are unaffected by loading a recorded state.</p>
<div class="tip"><strong>Typical workflow</strong> — build a background layer (large cells, slow motion, low opacity), add a foreground layer (smaller cells, faster motion), and adjust the balance with the opacity sliders. Each layer can have its own color map source for complex image-driven color effects.</div>

<h2>Camera and parallax</h2>
<p>The <strong>CAMERA</strong> section in Quick Adjust lets you position and animate a virtual camera over the entire composition. All layers render through the camera. Each of the three camera properties — <strong>PAN</strong>, <strong>ZOOM</strong>, and <strong>ROTATION</strong> — has an independent <strong>Mode</strong> picker, so you can mix constant positioning with animated oscillation or noise on a per-axis basis.</p>
<table>
  <tr><th>Mode</th><th>Controls shown</th><th>Effect</th></tr>
  <tr><td><strong>Constant</strong></td><td>Slider or value field</td><td>Static camera position — no animation.</td></tr>
  <tr><td><strong>Oscillator</strong></td><td>Amplitude (and X/Y for Pan), Period (s), Phase (0–1), Offset (Pan only)</td><td>Sinusoidal back-and-forth drift around the centre value.</td></tr>
  <tr><td><strong>Jitter</strong></td><td>Range (and X/Y for Pan), Duration (frames)</td><td>Stepped random jumps held for the given number of frames.</td></tr>
  <tr><td><strong>Noise</strong></td><td>Amplitude (and X/Y for Pan), Frequency (cyc/s)</td><td>Smooth Perlin-style wander.</td></tr>
  <tr><td><strong>Keyframe</strong></td><td>—</td><td>Driven by keyframes in the timeline. Add keyframes using the Pan / Zoom / Rotation lane in the Keyframe Timeline panel.</td></tr>
</table>
<p>The <strong>Reset Camera</strong> button (bottom of the section) returns all three drivers to their identity defaults (Pan 0, Zoom 1×, Rotation 0°, mode Constant). It is greyed out when the camera is already at identity.</p>

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

<h2>LAYER DRIVERS — blend mode, animated opacity and offset</h2>
<p>The <strong>LAYER DRIVERS</strong> section in Quick Adjust (collapsed by default) controls how a layer composites and moves independently of the camera. <strong>All three controls — Blend, Opacity, and Offset — apply to both grid layers and open layers.</strong> The DISTORTION subsection is grid-only and does not appear when an open layer is active.</p>

<h3>Blend mode</h3>
<p>The <strong>Blend</strong> picker at the top of LAYER DRIVERS sets how this layer composites with all layers below it:</p>
<table>
  <tr><th>Mode</th><th>Effect</th></tr>
  <tr><td><strong>Normal</strong></td><td>Standard alpha compositing. Default.</td></tr>
  <tr><td><strong>Multiply</strong></td><td>Darkens by multiplying colours. Black stays black; white is transparent.</td></tr>
  <tr><td><strong>Screen</strong></td><td>Lightens by inverting, multiplying, and inverting again. Opposite of Multiply.</td></tr>
  <tr><td><strong>Overlay</strong></td><td>Multiply on darks, Screen on lights. Increases contrast while preserving highlights and shadows.</td></tr>
  <tr><td><strong>Dodge</strong></td><td>Brightens the result by reducing contrast. Useful for glow effects.</td></tr>
  <tr><td><strong>Burn</strong></td><td>Darkens by increasing contrast. Deepens shadows.</td></tr>
  <tr><td><strong>Soft Light</strong></td><td>Gentle Overlay variant. Subtle contrast boost.</td></tr>
  <tr><td><strong>Hard Light</strong></td><td>Strong contrast, similar to Overlay with layer roles reversed.</td></tr>
  <tr><td><strong>Difference</strong></td><td>Subtracts darker from lighter. Creates inversion-like effects.</td></tr>
  <tr><td><strong>Exclusion</strong></td><td>Lower-contrast version of Difference.</td></tr>
  <tr><td><strong>Add</strong></td><td>Additive compositing (Plus Lighter). Values above 1 clip to white. Good for light, fire, or energy overlays.</td></tr>
</table>
<div class="tip">Put a dark, textured grid layer in <strong>Multiply</strong> over a bright background to darken only where cells are drawn, leaving empty cells transparent.</div>

<h3>Opacity driver</h3>
<p>Animates the layer's opacity over time, overriding the layer-row slider when any non-constant mode is active.</p>
<table>
  <tr><th>Mode</th><th>Description</th></tr>
  <tr><td><strong>Constant</strong></td><td>Static opacity. Controlled by the layer-row slider.</td></tr>
  <tr><td><strong>Oscillator</strong></td><td>Sinusoidal pulse between (centre − amplitude) and (centre + amplitude). Set Centre (the midpoint, 0–1), Amplitude (deviation amount), Period (seconds per cycle), and Phase (starting offset, 0–1).</td></tr>
  <tr><td><strong>Jitter</strong></td><td>Random step changes on a fixed interval. Set Range (±maximum jump) and Duration (frames between steps).</td></tr>
  <tr><td><strong>Noise</strong></td><td>Smooth Perlin-style drift. Set Amplitude (±range) and Frequency (cycles/s).</td></tr>
  <tr><td><strong>Keyframe</strong></td><td>Driven by keyframes in the timeline's <strong>Opacity</strong> lane. Set keyframes directly on the timeline.</td></tr>
</table>

<h3>Offset driver</h3>
<p>Adds a canvas-pixel positional shift to the entire layer, independent of the parallax camera pan.</p>
<table>
  <tr><th>Mode</th><th>Description</th></tr>
  <tr><td><strong>Constant</strong></td><td>Fixed X/Y offset in canvas pixels (default 0, 0).</td></tr>
  <tr><td><strong>Oscillator</strong></td><td>Sinusoidal back-and-forth. Set Amp X / Amp Y (peak displacement in px), Period (s), and Phase (0–1).</td></tr>
  <tr><td><strong>Jitter</strong></td><td>Random step jumps. Set Range X / Range Y (px) and Duration (frames).</td></tr>
  <tr><td><strong>Noise</strong></td><td>Smooth drift. Set Amp X / Amp Y (px) and Frequency (cyc/s).</td></tr>
  <tr><td><strong>Keyframe</strong></td><td>Driven by keyframes in the timeline's <strong>Offset</strong> lane.</td></tr>
</table>
<div class="tip">Use oscillator offset on a background layer to create a subtle breathing or drifting effect without touching the camera.</div>
<div class="tip"><strong>Fading up a morph target animation</strong> — place your morph-target sprites on their own open layer, then open LAYER DRIVERS → Opacity. Use <strong>Keyframe</strong> mode to draw a fade-in curve on the timeline Opacity lane, or <strong>Oscillator</strong> mode to pulse the whole layer in and out. The morph continues to interpolate underneath regardless of layer opacity.</div>

<h2>Right-panel context sections</h2>
<p>The Quick Adjust right panel shows context sections that reflect the active palette item:</p>
<ul>
  <li>When a <strong>style</strong> is active, the section header reads <strong>STYLE — [name]</strong> instead of the generic RENDER label.</li>
  <li>When a <strong>shape</strong> is active, a <strong>SHAPE — [name]</strong> section appears below MOTION, showing the shape's polygon counts (visible and total) and how many cells in the active layer use it.</li>
  <li>When a <strong>motion set</strong> is active, the <strong>MOTION — [name]</strong> section appears as before.</li>
</ul>

<h2>Open Layers</h2>
<p>An <strong>open layer</strong> is a special layer type where you freely place individual shapes anywhere on the canvas, rather than filling a grid. Use open layers for accent elements, floating logos, or any shape that shouldn't follow a regular grid rhythm.</p>

<h3>Creating an open layer</h3>
<ol class="steps">
  <li>Click the <strong>+ New Layer</strong> button below the layer list — it opens a small menu.</li>
  <li>Choose <strong>Open Layer</strong>. The new layer appears in the list with a <strong>✦</strong> icon to distinguish it from grid layers.</li>
  <li>Click the open layer row to make it active.</li>
</ol>

<h3>Placing sprites</h3>
<ol class="steps">
  <li>With an open layer active, click anywhere on the canvas. A new sprite appears at that position, using the currently selected style, shape, and motion.</li>
  <li>Alternatively, open <strong>Quick Adjust</strong> and click <strong>+ Place at Centre</strong> in the SPRITES section to place a sprite at the canvas midpoint.</li>
</ol>
<div class="note">To control which style, shape, and motion a new sprite gets, select those items in the left palette before clicking to place.</div>

<h3>Selecting a sprite</h3>
<p>Click any existing sprite on the canvas to select it. The selected sprite gets an accent outline. Its properties appear in the <strong>SPRITES</strong> inspector in Quick Adjust.</p>

<h3>Moving a sprite</h3>
<p>Drag any sprite to reposition it. The sprite moves in real time. Alternatively, edit the <strong>Position X</strong> and <strong>Position Y</strong> fields in the SPRITES inspector (values shown as a percentage of canvas width/height).</p>
<p>Drag behaviour depends on the sprite's <strong>Position Driver</strong> mode:</p>
<ul>
  <li><strong>Constant / other modes</strong> — drag updates the sprite's base position. This is the normal way to place a sprite.</li>
  <li><strong>Keyframe mode</strong> — drag writes (or overwrites) a position keyframe at the current playhead frame. The sprite's base position stays fixed; the keyframe records an offset from it. Move the playhead to a different frame and drag again to add another keyframe, building up a motion path entirely by dragging.</li>
</ul>

<h3>Deleting a sprite</h3>
<ul>
  <li>Select the sprite (click it on the canvas), then press <kbd>Delete</kbd>.</li>
  <li>Or click the <strong>&times;</strong> button next to the sprite&apos;s name in the SPRITES list in Quick Adjust.</li>
</ul>

<h3>The SPRITES inspector (Quick Adjust)</h3>
<p>When an open layer is active, Quick Adjust shows the <strong>SPRITES section</strong> in place of the usual grid controls. At the top is a list of all sprites on that layer. Click a row to select a sprite; click <strong>&times;</strong> to remove it.</p>
<p>When a sprite is selected, the inspector below the list shows:</p>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td>Name</td><td>Editable label for the sprite. Shown in the sprite list.</td></tr>
  <tr><td>Position X / Y</td><td>Canvas position as a percentage (0% = left/top edge, 100% = right/bottom edge).</td></tr>
  <tr><td>Rotation</td><td>Rotation in degrees.</td></tr>
  <tr><td>Scale X / Y</td><td>Size multiplier relative to the default sprite reference size (one-eighth of the shorter canvas dimension).</td></tr>
  <tr><td>Style</td><td>Fill and stroke style. Picks from the project&apos;s style palette.</td></tr>
  <tr><td>Shape</td><td>Loom shape. Picks from the project&apos;s shape library.</td></tr>
  <tr><td>Motion</td><td>Motion set driving animated offset, rotation, and scale. Picks from the project&apos;s motion palette.</td></tr>
  <tr><td>Phase offset</td><td>Frame offset into the motion cycle, same as grid cells. Lets sprites animate out of phase with each other.</td></tr>
  <tr><td>Sprite Set</td><td>Optional animated geometry cycle. When assigned, the sprite steps through a sequence of shapes (and optional per-state style overrides) on a per-frame schedule, overriding its static Shape assignment and any SEQUENCE cycling from the motion set. See <a href="um-help://help/sprite-sets">Sprite Sets</a>.</td></tr>
</table>

<h3>Animated position (Position Driver)</h3>
<p>Below the Phase field, the <strong>POSITION DRIVER</strong> section adds an independent animated offset on top of the sprite&apos;s static position. The offset is expressed in canvas pixels and is summed with the motion set&apos;s own position offset.</p>
<table>
  <tr><th>Mode</th><th>Controls</th><th>Result</th></tr>
  <tr><td><strong>Constant</strong> (default)</td><td>Offset X, Offset Y (px)</td><td>A fixed pixel offset. Default is 0, 0 — no extra motion. Useful for nudging a sprite by a precise pixel amount without changing its normalised position.</td></tr>
  <tr><td><strong>Oscillator</strong></td><td>Amp X/Y (px), Period (s), Phase (0–1)</td><td>Sinusoidal back-and-forth drift. The sprite oscillates symmetrically around its base position.</td></tr>
  <tr><td><strong>Jitter</strong></td><td>Range X/Y (px), Duration (frames)</td><td>Step-change jitter: the offset jumps to a new random value within ±Range every Duration frames, then holds.</td></tr>
  <tr><td><strong>Noise</strong></td><td>Amp X/Y (px), Frequency (cyc/s)</td><td>Smooth Perlin-style noise drift. Organic, non-repeating position wander.</td></tr>
  <tr><td><strong>Keyframe</strong></td><td>Frame, Pos X, Pos Y, Easing (in KF inspector)</td><td>Keyframe-driven position. Expand the sprite's layer in the timeline — each sprite shows a purple <strong>↑ [name]</strong> lane. Click the lane to add the first keyframe and switch to Keyframe mode. Once in Keyframe mode, <strong>dragging the sprite on the canvas</strong> records a position keyframe at the current playhead frame — move the playhead and drag to build a motion path by hand. Keyframes can also be dragged left/right in the timeline; Delete removes selected ones. The KF inspector in Quick Adjust shows Frame, Pos X, Pos Y (canvas pixels), and Easing. All standard timeline operations apply: rubber-band select, Cmd+C/V, timing-scale, Cmd+Z undo.</td></tr>
</table>
<div class="tip"><strong>Drag-to-keyframe workflow</strong> — click the purple lane in the timeline once to plant the first keyframe, then drag the sprite to each position at the appropriate frame. No need to touch the KF inspector unless you want to fine-tune values or easing.</div>
<div class="tip"><strong>Position Driver + Motion Set</strong> — both contribute independently. The motion set&apos;s oscillation is driven by its preset and speed/amount parameters; the Position Driver runs its own separate waveform. Stacking an Oscillator motion set (slow, large arc) with a Noise Position Driver (fast, small amplitude) gives organic floating motion with a directional bias.</div>

<h3>Shape cycling on sprites</h3>
<p>There are two ways to cycle shapes on a sprite over time:</p>
<ul>
  <li><strong>Sprite Sets (recommended)</strong> — assign a Sprite Set via the <strong>Sprite Set</strong> picker in the inspector. A Sprite Set is a dedicated animation cycle that specifies an ordered list of shapes, a hold-frame count per shape, a loop mode, and optional per-state style overrides. It is self-contained and completely independent of the motion set. This is the preferred method for any multi-state shape animation (walking cycles, swimming poses, etc.). See <a href="um-help://help/sprite-sets">Sprite Sets</a>.</li>
  <li><strong>SEQUENCE (motion set)</strong> — sprites also honour the SEQUENCE setting on their assigned motion set, exactly like grid cells. When a motion set has SEQUENCE mode set to Sequential or Random and a list of shapes, the sprite cycles through those shapes at the configured frames-per-step rate. A Sprite Set assignment overrides SEQUENCE — both cannot be active at once.</li>
</ul>
<div class="note">SEQUENCE settings appear in the MOTION section in Quick Adjust. Select the sprite to bring up its motion set, then scroll down to the Sequence row.</div>

<h3>Per-polygon colour overrides</h3>
<p>When a sprite has a shape assigned, the <strong>POLYGON OVERRIDES</strong> section appears at the bottom of the inspector. It lists every visible polygon in that shape, numbered from #0.</p>
<p>For each polygon you can independently override the <strong>fill</strong> colour and the <strong>stroke</strong> colour:</p>
<ul>
  <li>Click <strong>set</strong> next to F (fill) or S (stroke) to activate an override and open the colour picker.</li>
  <li>Click the colour well to change the override colour.</li>
  <li>Click <strong>&times;</strong> to remove the override and revert that polygon to the style&apos;s colour.</li>
</ul>
<div class="note">Polygon indices are positional. If you re-import a shape from Loom with a different polygon ordering, existing overrides will shift to different polygons. Clear all overrides before re-importing if you want a clean slate.</div>

<h3>Open layers and LAYER DRIVERS</h3>
<p>The full <strong>LAYER DRIVERS</strong> section is available for open layers. When an open layer is active, LAYER DRIVERS shows:</p>
<ul>
  <li><strong>Blend</strong> — composite mode for the whole open layer against layers below it.</li>
  <li><strong>Opacity</strong> — animate the entire layer's opacity via Constant, Oscillator, Jitter, Noise, or Keyframe mode. The Keyframe Opacity lane in the timeline is the most direct way to fade an open layer up or down at a specific moment.</li>
  <li><strong>Offset</strong> — shift the entire open layer (all sprites together) by an animated canvas-pixel amount, independent of individual sprite positions or the camera.</li>
</ul>
<p>DISTORTION does not appear for open layers — it has no effect on free-placed shapes.</p>
<div class="note">These are <em>layer-level</em> controls — they apply uniformly to every sprite in the layer. To animate an individual sprite's position, use the sprite's own Position Driver instead.</div>

<h3>Open layers and export</h3>
<p>Open layers export identically to grid layers — they composite into the PNG or video output with the layer's configured opacity, offset, blend mode, and parallax factor all applied. Sprite positions are stored as canvas fractions, so they remain correctly placed regardless of export resolution. The Position Driver animation, SEQUENCE shape cycling, Sprite Set morph/cross-fade, and all LAYER DRIVERS values are applied at export time.</p>

<h3>Limitations in this version</h3>
<ul>
  <li><strong>Motion controls</strong> — when a sprite is selected and has a motion set assigned, the <strong>MOTION — [name]</strong> section appears below SPRITES in Quick Adjust, showing all motion parameters for that motion set. If no sprite is selected, the section shows the palette&apos;s active motion set (if any).</li>
  <li><strong>No path animation on sprites</strong> — sprites support a motion set and a Position Driver for animated movement, but not keyframe paths.</li>
  <li><strong>Polygon override index stability</strong> — polygon overrides are keyed by positional index. Re-importing a shape from Loom with a different polygon ordering will shift overrides to different polygons.</li>
</ul>

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

<h2>Grid Distortion</h2>
<p>The <strong>DISTORTION</strong> subsection inside <strong>LAYER DRIVERS</strong> applies a geometric warp to the active grid layer at render time. The underlying cell data is unchanged — distortion is purely a display and export transform.</p>
<p>Open <strong>LAYER DRIVERS</strong> in Quick Adjust and use the <strong>Mode</strong> picker to choose a distortion type.</p>

<h3>None</h3>
<p>Default. Cells are positioned on a uniform rectangular grid. No distortion applied.</p>

<h3>Perspective</h3>
<p>Simulates a receding surface by varying row heights and column widths exponentially. Use it to make a grid appear to tilt away from the viewer — rows becoming smaller toward one edge — or to create a floor, ceiling, or sidewall perspective.</p>
<table>
  <tr><th>Control</th><th>Range</th><th>Effect</th></tr>
  <tr><td><strong>Vertical</strong></td><td>−1 to +1</td><td>+1: top rows compressed, bottom rows expanded (floor receding away at top). −1: the reverse (floor receding toward bottom, or ceiling effect).</td></tr>
  <tr><td><strong>Horizontal</strong></td><td>−1 to +1</td><td>+1: left columns compressed, right columns expanded. −1: the reverse. Set both to zero for a uniform grid.</td></tr>
  <tr><td><strong>Converge</strong></td><td>0 to 1</td><td>Links each row's horizontal width to its vertical scale factor. At 1, compressed rows are proportionally narrower — distant rows taper in from the sides as they would on a true receding plane. An automatic zoom is applied so the most-foreshortened row always fills the full canvas width; wider rows extend beyond the canvas edge and are clipped.</td></tr>
</table>
<p>When perspective is active, the grid lines in the canvas redraw at the correct variable-pitch positions so they match the distorted cell boundaries.</p>
<div class="tip">Set Vertical to 0.6, Converge to 0.8 for a strong one-point floor perspective. Combine with a Grid Scroll oscillator to animate tiles travelling away across the receding surface.</div>
<div class="note">Click-to-draw accuracy is reduced when perspective is strong, because the hit-test still uses the uniform grid to find which cell was clicked. For detailed painting, reduce the distortion while drawing and restore it for playback.</div>

<h3>Barrel / Cone</h3>
<p>A radial size modulation centred on the canvas. Cell <em>positions</em> remain at their uniform grid locations; only the drawn size of each cell's content changes.</p>
<table>
  <tr><th>Amount</th><th>Effect</th></tr>
  <tr><td><strong>&gt; 0 (Barrel / Spherical)</strong></td><td>Centre cells drawn larger than normal; corner cells drawn at normal size. The composition appears to bulge outward from the centre — a lens or balloon effect. Maximum at +1.</td></tr>
  <tr><td><strong>0</strong></td><td>Uniform — no distortion.</td></tr>
  <tr><td><strong>&lt; 0 (Cone / Pincushion)</strong></td><td>Centre cells drawn smaller than normal; corner cells drawn at normal size. The composition appears to pinch inward — a spotlight or cone effect. Maximum at −1.</td></tr>
</table>
<p>The scale formula is <em>s = 1 + amount × (1 − r²)</em> where r is the normalised radial distance from the canvas centre (0 at centre, 1 at corners). The drawn size scales smoothly from the midpoint outward.</p>
<div class="tip">A high positive amount on a dense grid of circles creates an organic bubble or soap-foam texture where inner cells appear larger and more prominent.</div>

<h3>Fractured</h3>
<p>Each cell's drawn position is shifted by a stable random offset in X and Y. Cell sizes remain uniform; only centres move. The randomisation is deterministic — the same <strong>Seed</strong> always produces the same jitter pattern — so the result is stable across frames and exports.</p>
<table>
  <tr><th>Control</th><th>Description</th></tr>
  <tr><td><strong>Amount</strong></td><td>Maximum jitter as a fraction of cell size. 0 = no jitter. 1 = each cell can shift by up to ±50% of its width and height in each axis. At high values cells overlap neighbours.</td></tr>
  <tr><td><strong>Seed</strong></td><td>Integer that selects the random stream. Different seeds give completely different patterns at the same amount. Click <strong>↺</strong> to randomise to a new seed instantly.</td></tr>
</table>
<div class="tip">Use Fractured at a low amount (0.1–0.2) on a dense grid to break the mechanical regularity of the layout without visually displacing cells far from their natural positions. At higher amounts it produces a scattered mosaic effect.</div>
<div class="note">Fractured distortion is most effective on grid layers with shapes assigned. On plain rectangle cells, the shifted positions may create visible gaps between cells at the edges of the canvas.</div>

<h3>Combining distortion with other layer features</h3>
<ul>
  <li><strong>Grid Scroll + Perspective</strong>: As cells scroll across the layer, each one is placed at the distorted position of its current display slot, so cells visually grow or shrink as they travel across the receding surface.</li>
  <li><strong>Blend modes + Barrel</strong>: A Screen or Add barrel layer over a uniform base can create a natural vignette where the composition emphasises the centre.</li>
  <li><strong>Multiple layers with different distortions</strong>: Distortion is per-layer, so you can stack a Perspective grid below a Fractured grid for complex spatial arrangements.</li>
</ul>
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
  <tr><td>↺ Loop</td><td>—</td><td>Toggle loop playback. When on (accent colour), playback wraps from the End frame back to the Start frame automatically. Loop mode and the Start/End fields together define both the playback loop and the export render range — set them once and both uses follow.</td></tr>
  <tr><td>● / ■ Record/Stop</td><td>—</td><td>Begin or end timeline recording. See below.</td></tr>
  <tr><td>Frame counter</td><td>—</td><td>Shows the current frame. Animation cycles because styles loop. The counter is unbounded.</td></tr>
  <tr><td>S / E fields</td><td>—</td><td>Start and End frame of the playback/render region. These fields are shared with the Export panel — changing either updates both places. <strong>⌘-drag in the timeline ruler</strong> is the fastest way to sweep both fields at once: the anchor frame fixes Start and the cursor sets End (or vice versa if you drag left).</td></tr>
  <tr><td>PNG</td><td>—</td><td>Export the current frame as a PNG still. See <a href="um-help://help/export">Export</a>.</td></tr>
  <tr><td>SVG</td><td>—</td><td>SVG export — not yet implemented.</td></tr>
  <tr><td>Video</td><td>—</td><td>Export an animation as a .mov video. See <a href="um-help://help/export">Export</a>.</td></tr>
</table>
<div class="tip"><strong>Workflow: set region, loop, export.</strong> ⌘-drag in the ruler to sweep a region, toggle Loop on, press Play to audition it, then export — the S/E values already define the export range so no re-entry needed.</div>

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

<h2>Keyframe Timeline panel</h2>
<p>The <strong>Keyframe Timeline</strong> panel sits below the canvas. Drag the handle at the top edge to resize — a full-width accent line previews where the new boundary will land without reflowing the canvas. Tap the handle to collapse or expand the panel. It controls <em>driver-based</em> animation — smooth interpolated motion that uses the same frame clock as parametric animation, distinct from the cut-based recording timeline above.</p>

<h3>Lanes</h3>
<p>Each <strong>grid layer</strong> has three driver lanes. <strong>Sprite layers</strong> have two layer-level lanes plus one per-sprite position lane. The camera has three additional lanes:</p>
<table>
  <tr><th>Lane</th><th>Colour</th><th>Controls</th></tr>
  <tr><td>Opacity</td><td>Pink</td><td>Layer opacity over time (0–1). Grid and open layers.</td></tr>
  <tr><td>Offset</td><td>Blue</td><td>Layer canvas-pixel position offset (X, Y). Grid and open layers.</td></tr>
  <tr><td>Grid Scroll</td><td>Orange</td><td>Per-layer grid scroll amount (X, Y in cell units). Grid layers only.</td></tr>
  <tr><td>↑ [Sprite name]</td><td>Purple</td><td>Position Driver offset for that sprite (X, Y in canvas pixels). One lane per sprite; open layers only.</td></tr>
  <tr><td>Camera Pan</td><td>Teal</td><td>Camera pan offset (X, Y in pixels)</td></tr>
  <tr><td>Camera Zoom</td><td>Green</td><td>Camera zoom factor</td></tr>
  <tr><td>Camera Rotation</td><td>Cyan</td><td>Camera rotation in degrees</td></tr>
</table>
<div class="note">Setting a keyframe on any lane automatically switches that driver to Keyframe mode. Deleting the last keyframe on a lane reverts it to Constant mode.</div>

<h3>Showing and hiding lanes</h3>
<p>Each lane header has an <strong>eye.slash</strong> button (far right) that hides the lane from view. Hidden lanes still animate normally — hiding is purely a workspace declutter. To restore hidden lanes, look at the <strong>layer row</strong> (or Camera row) in the header column: when any of its lanes are hidden, an <strong>eye</strong> icon appears on the right side of that row. Click it to show all hidden lanes for that layer at once.</p>

<h3>Selecting and deleting keyframes</h3>
<p>Keyframes are shown as diamond shapes on each lane. To select them:</p>
<ul>
  <li><strong>Click</strong> a diamond to select it (and seek the playhead to its frame).</li>
  <li><strong>Shift+click</strong> a diamond to add it to the current selection.</li>
  <li><strong>Drag</strong> on any empty lane area to rubber-band multi-select.</li>
  <li><strong>⌘A</strong> to select all keyframes on all visible lanes.</li>
</ul>
<p>Once keyframes are selected, delete them with the <strong>Delete</strong> key, or with the trash icon that appears in the header toolbar. A <strong>trash icon</strong> also appears in the lane header area whenever there is a selection.</p>

<h3>Interactions</h3>
<table>
  <tr><th>Action</th><th>Effect</th></tr>
  <tr><td>Click ruler</td><td>Seek playhead to that frame</td></tr>
  <tr><td>Drag ruler</td><td>Scrub playhead continuously</td></tr>
  <tr><td>⌘-drag ruler</td><td>Sweep render/loop region — sets Start and End simultaneously. Anchor frame stays fixed; cursor frame moves the other boundary. Release to commit.</td></tr>
  <tr><td>Click on lane (not on a KF)</td><td>Add a keyframe at that frame, capturing the current evaluated value</td></tr>
  <tr><td>Click a KF diamond</td><td>Select it; seek playhead to its frame</td></tr>
  <tr><td>Drag a KF diamond</td><td>Move keyframe to a new frame (live preview while dragging)</td></tr>
  <tr><td>Shift+click</td><td>Additive selection</td></tr>
  <tr><td>Drag on empty area</td><td>Rubber-band multi-select</td></tr>
  <tr><td>Option+drag</td><td>Pan timeline horizontally</td></tr>
  <tr><td>Option+scroll</td><td>Zoom timeline (px/frame)</td></tr>
  <tr><td>Delete</td><td>Delete selected keyframes</td></tr>
  <tr><td>⌘C / ⌘V</td><td>Copy / paste selected KFs at playhead (relative offsets preserved)</td></tr>
  <tr><td>⌘Z / ⌘⇧Z</td><td>Undo / redo (50-state stack)</td></tr>
  <tr><td>⌘A</td><td>Select all keyframes on all visible lanes</td></tr>
</table>

<h3>Timing scale</h3>
<p>When <strong>two or more keyframes</strong> are selected, a <strong>Scale [n]% ↔</strong> row appears in the header column. Enter a percentage and click <strong>↔</strong> to stretch or compress the selected keyframes in time:</p>
<ul>
  <li>The <strong>earliest selected frame</strong> is the pivot — it stays fixed.</li>
  <li>All other selected frames are moved proportionally: <code>newFrame = pivot + (oldFrame − pivot) × (scale / 100)</code>.</li>
  <li><strong>200%</strong> doubles the spacing between keyframes (slower animation).</li>
  <li><strong>50%</strong> halves it (faster animation).</li>
</ul>
<div class="tip">To tighten a slow camera move, rubber-band select all its KFs, type 50 in the Scale field, and click ↔.</div>

<h3>Keyframe inspector</h3>
<p>When any keyframe is selected, the <strong>KEYFRAME</strong> section appears at the top of Quick Adjust. Edit the frame number, value (scalar or X/Y), and easing curve (Linear, Ease In, Ease Out, Ease In/Out, Step, Back In, Back Out, Back In/Out, Bounce Out). Changes commit immediately with undo.</p>
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

<h3>Phase heat-map overlay</h3>
<p>The <strong>Phase map</strong> checkbox (below the Grid row in the CANVAS section) overlays a colour tint on each drawn cell of the <em>active grid layer</em>, colouring it by its <code>phaseOffset</code> value:</p>
<ul>
  <li><strong>Blue</strong> — phaseOffset = 0 (earliest-starting cells)</li>
  <li><strong>Red</strong> — phaseOffset = max in the layer (latest-starting cells)</li>
  <li>Intermediate offsets are linearly interpolated through the hue spectrum.</li>
</ul>
<p>The overlay is drawn at 50% opacity and is view-only — it does not appear in PNG or video export. Use it to verify that your phase policy produced the expected timing structure, or to diagnose unexpected clusters of cells that are in sync.</p>
<div class="note">The phase heat-map only draws when the active layer is a <strong>grid</strong> layer. Switching to an open layer hides the overlay automatically.</div>

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
<p>The CAMERA section sits below CANVAS in the Quick Adjust panel. It positions and animates a virtual camera over the entire composition — all layers render through it. Camera state is saved in the project and applied to all PNG and video exports.</p>
<p>The section is divided into three subsections — <strong>PAN</strong>, <strong>ZOOM</strong>, and <strong>ROTATION</strong> — each with its own <strong>Mode</strong> picker. This lets you mix animation modes independently: for example, a noise-driven pan with a constant zoom.</p>

<h3>PAN</h3>
<table>
  <tr><th>Mode</th><th>Controls</th><th>Effect</th></tr>
  <tr><td><strong>Constant</strong></td><td>Pan X slider (−500…500 px), Pan Y slider</td><td>Static camera position.</td></tr>
  <tr><td><strong>Oscillator</strong></td><td>Amp X / Amp Y (px), Period (s), Phase (0–1), Offset X / Offset Y (px)</td><td>Sinusoidal back-and-forth drift. Amplitude controls the half-range; Offset shifts the centre.</td></tr>
  <tr><td><strong>Jitter</strong></td><td>Range X / Range Y (px), Duration (frames)</td><td>Stepped random jumps at the given frame interval.</td></tr>
  <tr><td><strong>Noise</strong></td><td>Amp X / Amp Y (px), Frequency (cyc/s)</td><td>Smooth independent noise on each axis.</td></tr>
  <tr><td><strong>Keyframe</strong></td><td>—</td><td>Driven by the <strong>Camera Pan</strong> lane in the Keyframe Timeline.</td></tr>
</table>

<h3>ZOOM</h3>
<table>
  <tr><th>Mode</th><th>Controls</th><th>Effect</th></tr>
  <tr><td><strong>Constant</strong></td><td>Zoom slider (0.1 – 4.0×)</td><td>Static zoom level. 1.0 = native size.</td></tr>
  <tr><td><strong>Oscillator</strong></td><td>Centre (×), Amplitude (×), Period (s), Phase (0–1)</td><td>Sinusoidal breathing zoom.</td></tr>
  <tr><td><strong>Jitter</strong></td><td>Range (×), Duration (frames)</td><td>Stepped random zoom jumps.</td></tr>
  <tr><td><strong>Noise</strong></td><td>Amplitude (×), Frequency (cyc/s)</td><td>Smooth zoom wander.</td></tr>
  <tr><td><strong>Keyframe</strong></td><td>—</td><td>Driven by the <strong>Camera Zoom</strong> lane in the Keyframe Timeline.</td></tr>
</table>

<h3>ROTATION</h3>
<table>
  <tr><th>Mode</th><th>Controls</th><th>Effect</th></tr>
  <tr><td><strong>Constant</strong></td><td>Rotation slider (−180° … 180°)</td><td>Static rotation around the canvas centre.</td></tr>
  <tr><td><strong>Oscillator</strong></td><td>Centre (°), Amplitude (°), Period (s), Phase (0–1)</td><td>Sinusoidal rock.</td></tr>
  <tr><td><strong>Jitter</strong></td><td>Range (°), Duration (frames)</td><td>Stepped random rotation jumps.</td></tr>
  <tr><td><strong>Noise</strong></td><td>Amplitude (°), Frequency (cyc/s)</td><td>Smooth rotation wander.</td></tr>
  <tr><td><strong>Keyframe</strong></td><td>—</td><td>Driven by the <strong>Camera Rotation</strong> lane in the Keyframe Timeline.</td></tr>
</table>

<p>The <strong>Reset Camera</strong> button (bottom of the section) returns all three drivers to identity (Pan 0, Zoom 1×, Rotation 0°, mode Constant). It is greyed out when already at identity.</p>
<p>Parallax per layer is controlled by the small slider (camera icon) in each layer row — see <a href="um-help://help/layers">Working with Layers</a> for details on how parallax interacts with camera pan.</p>
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
  <tr><td><strong>Easing</strong></td><td>—</td><td>—</td><td>Interpolation curve from this keyframe to the next <em>(used only when both tangents are zero)</em>.</td></tr>
  <tr><td><strong>Smooth</strong></td><td>—</td><td>—</td><td>When checked, dragging one tangent handle automatically mirrors the opposite one (C1 continuity — smooth arc through the keyframe).</td></tr>
  <tr><td><strong>Out X / Out Y</strong></td><td>−5 – 5</td><td>c</td><td>Out tangent — the control point that shapes the exit curve from this keyframe. In cell-fraction units.</td></tr>
  <tr><td><strong>In X / In Y</strong></td><td>−5 – 5</td><td>c</td><td>In tangent — the control point that shapes the arrival curve at this keyframe. In cell-fraction units.</td></tr>
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

<h2>Bezier tangent handles</h2>
<p>Each keyframe has two tangent handles that shape the cubic Bezier curve through that point. When all tangents are zero (default), the path falls back to linear interpolation with the Easing curve applied. As soon as any tangent is non-zero, Bezier interpolation takes over for position — the Easing picker is then ignored for that segment.</p>

<table>
  <tr><th>Handle</th><th>Colour</th><th>Controls</th></tr>
  <tr><td><strong>Out handle</strong></td><td>Accent-coloured ring</td><td>Direction and curvature of the <em>exit</em> from this keyframe.</td></tr>
  <tr><td><strong>In handle</strong></td><td>Grey ring</td><td>Direction and curvature of the <em>arrival</em> at this keyframe.</td></tr>
</table>

<h3>Using handles on the canvas</h3>
<ol class="steps">
  <li>Select a path in the Style Palette to make it active and show the overlay on the canvas.</li>
  <li>Click a keyframe dot on the canvas to select it — the dot grows and the two tangent handle circles appear connected by thin lines.</li>
  <li>Drag an out (accent) or in (grey) handle to shape the curve. The path trajectory updates in real time.</li>
  <li>To make a smooth arc through the keyframe, enable <strong>Smooth</strong> in the property editor — dragging one handle mirrors the other automatically.</li>
  <li>To remove tangent influence (revert to Easing-based interpolation), reset the Out/In X/Y sliders to 0 (double-click each to snap to zero).</li>
</ol>

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
<p>Lists everything owned by the current document. Organised into seven sections: LAYERS, STYLES, MOTIONS, PATHS, SHAPES, PALETTES, and SPRITE SETS.</p>

<h3>LAYERS</h3>
<p>See <a href="um-help://help/layers">Working with Layers</a> for the full guide to layers.</p>
<p>Below the layer list, the LAYERS section also shows <strong>resolution preset chips</strong> — click any chip to instantly resample the active layer to that grid size. Built-in sizes (4×4 through 32×32) are always present. To save the current resolution as a project preset, click the <strong>+</strong> button at the end of the chip row. To save a project preset to your global library, right-click it and choose <strong>Save to Library</strong>. To remove a project preset, right-click → <strong>Remove</strong>.</p>

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

<h3>SPRITE SETS</h3>
<p>Sprite Sets are reusable shape-animation cycles that can be assigned to sprites on open layers <strong>and to individual grid cells on grid layers</strong>. Each set holds an ordered list of <em>states</em>: a shape, an optional style override, and a hold-frame count. The set steps through those states at playback time, independently of the motion set.</p>
<ul>
  <li><strong>+ New Sprite Set</strong> — creates an empty set ready to be filled with states in the editor.</li>
  <li><strong>+ Import Layers as Shapes…</strong> — in the SHAPES section above. Select a multi-layer Loom geometry file; each visible, non-empty layer becomes a separate shape and a Sprite Set containing all of them in layer order is created automatically.</li>
  <li><strong>Pencil icon</strong> — opens the Sprite Set editor for that set.</li>
  <li><strong>Right-click</strong> — Edit…, Rename, Duplicate, Delete.</li>
  <li><strong>Double-click the name</strong> — inline rename field. Press Return to confirm.</li>
</ul>
<h4>Direct drawing with a Sprite Set</h4>
<p><strong>Tap a Sprite Set row</strong> to make it the active drawing instrument (the row highlights in accent colour; tap again to deselect). While a Sprite Set is active:</p>
<ul>
  <li><strong>On an open layer</strong> — clicking the canvas or using <strong>+ Place at Centre</strong> places a sprite that is automatically assigned the active Sprite Set. No need to place first and assign afterwards.</li>
  <li><strong>On a grid layer</strong> — drawing or flood-filling cells automatically assigns the active Sprite Set to each cell. The cells animate through the Sprite Set's states independently (each cell's phase offset staggers the cycle). Morph and cross-fade transitions are supported exactly as on open-layer sprites.</li>
</ul>
<div class="tip">Select a Sprite Set in the palette, then draw across a grid to scatter many cells that all share the same animation cycle. Each cell inherits the active style, shape, and motion — the Sprite Set adds the shape-animation layer on top, with per-cell phase staggering for variety.</div>
<p>To assign a Sprite Set to an <strong>existing sprite</strong>, select the sprite and use the <strong>Sprite Set</strong> picker in the SPRITES inspector in Quick Adjust.</p>
<p>To assign a Sprite Set to <strong>existing grid cells</strong>, select the cells and use the <strong>Anim. Set</strong> picker in the <strong>PLACE &amp; TIME</strong> section of Quick Adjust. Choose <strong>—</strong> to remove the assignment and revert the cell to its static shape.</p>

<h2>Library tab</h2>
<p>Shows your global user library — resolution presets, styles, motion sets, paths, shapes, and colour palettes saved across all projects.</p>
<ul>
  <li>Each section shows whether the item is already in the current project. If not, a <strong>↓</strong> button (or chip) imports it.</li>
  <li>The <strong>RESOLUTION</strong> section lists global resolution presets as chips. Click ↓ on a chip to import it into the current project (greyed when already present). Right-click a chip to remove it from the library.</li>
  <li>Library is stored at <code>~/Library/Application Support/UM/library.json</code> (styles/paths/motions/palettes), <code>~/Library/Application Support/UM/shapes/</code> (shapes), and <code>~/Library/Application Support/UM/resolutionPresets.json</code> (resolution presets).</li>
  <li>Right-click any library row or chip to remove it from the library.</li>
</ul>
"""#

private let spriteSetsBody = #"""
<h1>Sprite Sets</h1>
<p class="subtitle">Reusable shape-animation cycles for sprites and grid cells — independent of motion sets.</p>

<p>A <strong>Sprite Set</strong> is an ordered list of <em>states</em>. Each state specifies a shape, an optional style override, a hold-frame count, and an optional cross-fade into the next state. When a sprite or grid cell has a Sprite Set assigned, UM steps through those states as the animation plays, cycling the shape (and optionally its fill/stroke colours) on a per-frame schedule. Between states, an opacity blend — or smooth colour interpolation when <strong>Style Tween</strong> is on — can play over a configurable number of frames with a chosen easing curve. The cycle runs independently of the element's motion set.</p>

<h2>Concepts</h2>

<h3>States</h3>
<p>Each state in a Sprite Set represents one phase of the animation cycle:</p>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td>Shape</td><td>The Loom shape to display during this state. Picked from the project's shape library.</td></tr>
  <tr><td>Style override</td><td>Optional. When set, this style is used instead of the sprite's own style for the duration of this state. Set to – (dash) to use the sprite's global style.</td></tr>
  <tr><td>Hold frames</td><td>How many animation frames to stay on this state before advancing to the next. Minimum 1.</td></tr>
  <tr><td>Trans</td><td>Transition frames. After the Hold period ends, the sprite cross-fades from this state to the next over this many frames. Set to 0 (default) for an instant hard cut. See <strong>Cross-fade</strong> below.</td></tr>
  <tr><td>Ease</td><td>Easing curve applied to the cross-fade progress. Only relevant when Trans &gt; 0. Options include Linear, Ease In/Out, Back In/Out, Bounce Out, and others. The picker is dimmed when Trans is 0.</td></tr>
  <tr><td>Style Tween</td><td>When enabled (and Trans &gt; 0), the fill and stroke colours are linearly interpolated between this state's style and the next state's style over the transition window, instead of cross-fading two separate shapes at their own colours. Works with both cross-fade and morph transitions. Dimmed when Trans is 0.</td></tr>
</table>

<h3>Per-state transforms</h3>
<p>Click the <strong>▸ chevron</strong> on any state row to expand a transform sub-row with two lines of controls:</p>
<p><strong>Row 1 — position, rotation, scale</strong> (applied on top of the sprite's own transform while this state is active):</p>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Δx</strong></td><td>Horizontal position offset in canvas pixels. Positive shifts the sprite right.</td></tr>
  <tr><td><strong>Δy</strong></td><td>Vertical position offset in canvas pixels. Positive shifts the sprite down.</td></tr>
  <tr><td><strong>°</strong></td><td>Rotation offset in degrees, added to the sprite's own rotation.</td></tr>
  <tr><td><strong>Sx</strong></td><td>Horizontal scale multiplier (1.0 = no change). Applied on top of the sprite's own scale.</td></tr>
  <tr><td><strong>Sy</strong></td><td>Vertical scale multiplier (1.0 = no change). Applied on top of the sprite's own scale.</td></tr>
</table>
<p><strong>Row 2 — transition</strong>:</p>
<table>
  <tr><th>Field</th><th>Description</th></tr>
  <tr><td><strong>Trans</strong></td><td>Number of cross-fade frames after this state's Hold period. 0 = instant cut to next state.</td></tr>
  <tr><td><strong>Ease</strong></td><td>Easing curve for the cross-fade (dimmed when Trans = 0).</td></tr>
  <tr><td><strong>Style↔</strong></td><td>Style Tween checkbox. When checked and Trans &gt; 0, fill and stroke colours are lerped between this state's style and the next state's style over the transition window. See <strong>Style tweening</strong> below.</td></tr>
</table>
<p>All transform fields default to identity (0 / 0 / 0 / 1 / 1). Trans defaults to 0. The preview canvas updates immediately and shows the cross-fade or style tween live when scrubbing through a transition window.</p>

<h3>Transitions: cross-fade and morph</h3>
<p>When <strong>Trans</strong> is greater than 0, UM transitions between states over the specified number of frames. The method it uses depends on whether the two shapes are topology-compatible:</p>
<ul>
  <li><strong>Vertex morph</strong> (automatic when shapes match) — if both states have the same number of polygons and the same number of vertices per polygon, UM interpolates the actual vertex positions. The shape smoothly deforms from one configuration to the other. Position, rotation, and scale also interpolate simultaneously. This produces the smoothest possible animation and is the intended path for shapes authored as morph targets in Loom.</li>
  <li><strong>Cross-fade</strong> (fallback) — if the shapes have different topology, UM draws both shapes simultaneously: the outgoing shape fades out while the incoming shape fades in. Works across any two shapes regardless of vertex count.</li>
</ul>
<p>UM automatically picks the right method — no configuration needed. Shape your morph targets in Loom's geometry editor (which validates topology parity) and import them via <strong>Import Layers as Shapes</strong>; the morph will work automatically.</p>
<p>The <strong>Ease</strong> curve controls the feel of either transition type:</p>
<ul>
  <li><strong>Linear</strong> — constant rate throughout.</li>
  <li><strong>Ease In/Out</strong> (default) — slow start and end, fast in the middle. Usually the most natural.</li>
  <li><strong>Back In/Out</strong> — briefly overshoots before settling, giving a snappy elastic feel.</li>
  <li><strong>Bounce Out</strong> — incoming shape bounces into position at the end of the transition.</li>
  <li><strong>Step</strong> — hard cut at exactly the midpoint.</li>
</ul>
<div class="note">Trans frames extend the state's total on-screen time. A state with Hold = 4 and Trans = 2 occupies 6 frames in the cycle before the next state begins its Hold period.</div>
<div class="tip">For Ping-Pong loop mode, transitions only play during the forward pass. The reverse pass is hold-only, so the cycle length is shorter on the way back.</div>

<h3>Style tweening</h3>
<p>By default, when a state transition has a style override, the colour changes abruptly at the boundary even during a cross-fade or morph — the shape blends but the colour is drawn from each state's own style. <strong>Style Tween</strong> replaces this with true colour interpolation:</p>
<ul>
  <li>Enable <strong>Style↔</strong> in the expand sub-row for a state (requires Trans &gt; 0).</li>
  <li>During the transition window, UM linearly interpolates the <strong>fill colour</strong> and <strong>stroke colour</strong> between the FROM state's style and the TO state's style at the eased progress value.</li>
  <li>The interpolated colour is applied to both the outgoing and incoming shapes during a cross-fade, and to the single morphed shape during a morph transition. In both cases the result is a smooth colour shift that tracks exactly with the shape transition.</li>
  <li>If a state has no style override (the — dash option), the element's own global style colour is used as that end of the interpolation.</li>
</ul>
<div class="note">Style Tween is per-state: it applies to the transition out of that state, not to the state itself. A 3-state cycle could have tween on state 0 → 1 but a hard cut on state 1 → 2, for example.</div>
<div class="tip">Combining Style Tween with morph gives the smoothest possible animation: the shape vertices physically deform between poses while the fill and stroke colours flow simultaneously from one palette to another — all in a single pass.</div>

<h3>Loop modes</h3>
<table>
  <tr><th>Mode</th><th>Behaviour</th></tr>
  <tr><td><strong>Loop</strong></td><td>Cycles forward through all states continuously. After the last state, wraps back to the first.</td></tr>
  <tr><td><strong>Ping Pong</strong></td><td>Plays forward through all states, then backward through the intermediate states (not repeating the endpoints), and repeats. Gives a smooth back-and-forth without a hard jump.</td></tr>
  <tr><td><strong>Once</strong></td><td>Plays through all states once, then stops and shows nothing (sprite becomes invisible after the cycle ends).</td></tr>
  <tr><td><strong>Hold Last</strong></td><td>Plays through all states once, then holds on the final state indefinitely.</td></tr>
</table>

<h3>Phase offset</h3>
<p>The sprite's <strong>Phase offset</strong> (set in the SPRITES inspector) is added to the current frame before resolving which state is active. This means two sprites sharing the same Sprite Set but with different phase offsets will be at different points in the cycle — useful for staggering an animated crowd or making repeated elements feel less mechanical.</p>

<h2>Creating Sprite Sets</h2>

<h3>From scratch</h3>
<ol class="steps">
  <li>In the left palette → Project tab → <strong>SPRITE SETS</strong> section, click <strong>+ New Sprite Set</strong>.</li>
  <li>The new set appears in the list. Click the <strong>pencil icon</strong> to open the editor.</li>
  <li>Give the set a name and choose a loop mode in the header.</li>
  <li>Click <strong>Add State</strong> and choose a shape from the menu. Repeat for each phase of the animation.</li>
  <li>For each state, set the <strong>Hold</strong> value (frames to stay on this shape at full opacity) and optionally pick a style override. To add a cross-fade into the next state, expand the ▸ chevron and set <strong>Trans</strong> &gt; 0.</li>
  <li>Use the up/down chevrons to reorder states. The minus (−) button removes a state.</li>
  <li>Use the <strong>preview scrubber</strong> at the bottom to step through the cycle and verify the active state indicator moves as expected.</li>
</ol>

<h3>From a multi-layer Loom geometry file (Import Layers as Shapes)</h3>
<p>If your animation states are separate layers inside one Loom geometry file (e.g. a swimming cycle spread across layers named Swim01, Swim02, Swim03), UM can extract them automatically:</p>
<ol class="steps">
  <li>In the left palette → SHAPES section, click <strong>+ Import Layers as Shapes…</strong></li>
  <li>Select the Loom .json geometry file. UM reads every layer that is both <strong>visible</strong> and <strong>non-empty</strong>.</li>
  <li>Each qualifying layer is saved as an individual shape (named after the layer) and added to the project shape library.</li>
  <li>A new Sprite Set named after the geometry file is created automatically, containing all the extracted shapes in layer order with a default hold of 2 frames each.</li>
  <li>Open the Sprite Set editor to adjust hold-frame counts, loop mode, or style overrides.</li>
</ol>
<div class="note">Hidden layers and layers with no polygons are skipped. If a layer was a reference or guide in Loom, it will not produce a shape.</div>
<div class="tip">If the source file is a morph-target geometry file from Loom (topology-locked with the lock icon), all extracted shapes have the same vertex count and will automatically morph — no cross-fade fallback — when Trans &gt; 0 in the Sprite Set editor.</div>

<h2>Morph target animation (Loom → UM workflow)</h2>
<p>Morph target animation smoothly deforms a shape's vertices from one configuration to another — like a character's body moving between a rest pose and a walk pose. Unlike a cross-fade (which blends two shapes by opacity), a morph physically moves each vertex, producing fluid organic motion.</p>
<p>UM detects morph compatibility automatically: if two adjacent Sprite Set states have the same number of polygons and the same number of vertices per polygon, UM morphs them. Otherwise it cross-fades. Topology is authored and locked in Loom — UM trusts it without re-checking.</p>

<h3>Step 1 — Author the morph targets in Loom</h3>
<ol class="steps">
  <li>Open Loom and create or open a geometry file. Add one layer per animation pose (e.g. Rest, MidSwing, FullSwing). All layers must share the same polygon count and vertex count per polygon — Loom shows a vertex-mismatch warning in the layer list if they diverge.</li>
  <li>Once all poses are drawn and the vertex counts match, click the <strong>lock icon</strong> in the geometry editor toolbar to designate the file as a morph target. The icon turns orange and the file becomes topology-locked: vertex positions can still be tweaked, but adding or removing vertices or polygons is blocked.</li>
  <li>Save the file. The lock is stored in the file; it persists across sessions. To unlock (and break morph identity), click the lock icon again.</li>
</ol>
<div class="note">Each layer in a locked morph target file is a valid morph destination. A single file can hold many poses — you do not need separate files per target.</div>

<h3>Step 2 — Import into UM</h3>
<ol class="steps">
  <li>In the UM left palette → Project tab → <strong>SHAPES</strong> section, click <strong>+ Import Layers as Shapes…</strong></li>
  <li>Select the locked Loom geometry file. UM extracts each visible, non-empty layer as an individual shape and adds them all to the project shape library.</li>
  <li>A Sprite Set named after the geometry file is created automatically, containing all the extracted shapes in layer order with Hold = 2 frames and Trans = 0.</li>
</ol>

<h3>Step 3 — Set up transitions in the Sprite Set editor</h3>
<ol class="steps">
  <li>Click the <strong>pencil icon</strong> next to the Sprite Set to open the editor.</li>
  <li>Confirm the states are in the correct order (use ↑↓ to reorder).</li>
  <li>Expand the <strong>▸ chevron</strong> on each state to show the transform sub-row.</li>
  <li>Set <strong>Trans</strong> to the number of frames you want the morph to take (e.g. 4). Set <strong>Ease</strong> to your preferred curve (Ease In/Out is a good default).</li>
  <li>Scrub the preview slider through the transition window (the frames immediately after the Hold period). You should see the shape physically deforming — if you see two overlapping shapes fading instead, the topology doesn't match (check vertex counts in Loom).</li>
  <li>Adjust Hold and Trans values per state to control the rhythm of the animation.</li>
</ol>

<h3>Step 4 — Assign and play back</h3>
<ol class="steps">
  <li><strong>On an open layer</strong> — select the sprite on the canvas. In the <strong>SPRITES inspector</strong> (right panel), set the <strong>Sprite Set</strong> picker to the imported set.</li>
  <li><strong>On a grid layer</strong> — select one or more cells, then use the <strong>Anim. Set</strong> picker in PLACE &amp; TIME (Quick Adjust) to assign the Sprite Set.</li>
  <li>Press play in the Transport Bar. The shape deforms smoothly between poses on schedule.</li>
  <li>Use the element's <strong>Phase offset</strong> to stagger multiple sprites or cells sharing the same Sprite Set so they are at different points in the cycle.</li>
</ol>
<div class="tip">Position, rotation, and scale also interpolate smoothly during a morph transition — set per-state Δx/Δy/°/Sx/Sy values on each state to combine shape morphing with positional animation in a single pass.</div>

<h2>Assigning a Sprite Set to a sprite (open layer)</h2>
<ol class="steps">
  <li>Select the open layer in the left palette, then click the sprite on the canvas to select it.</li>
  <li>In the <strong>SPRITES inspector</strong> in Quick Adjust (right panel), find the <strong>Sprite Set</strong> picker between Motion and Phase offset.</li>
  <li>Choose the Sprite Set from the list. The picker shows <em>None</em> when no set is assigned.</li>
  <li>Play back the animation — the sprite's shape changes on schedule.</li>
</ol>
<div class="tip">Set <strong>None</strong> to restore the sprite's static shape (or SEQUENCE cycling from its motion set).</div>

<h2>Assigning a Sprite Set to grid cells</h2>
<ol class="steps">
  <li>Select one or more drawn cells on a grid layer (click or rubber-band select).</li>
  <li>In the <strong>PLACE &amp; TIME</strong> section of Quick Adjust (right panel), find the <strong>Anim. Set</strong> picker — it appears after the Shape picker.</li>
  <li>Choose the Sprite Set from the list. Choose <strong>—</strong> to remove any existing assignment.</li>
  <li>Play back the animation — each selected cell animates through the Sprite Set's states. Each cell's phase offset staggers the cycle for natural variety.</li>
</ol>
<div class="note">When a Sprite Set is assigned to a grid cell, the cell's static Shape assignment is ignored at render time. The Sprite Set drives the shape. To revert to the static shape, set Anim. Set to —.</div>

<h2>Priority and overrides</h2>
<p>When a Sprite Set is assigned, it takes priority over the element's static <strong>Shape</strong> field and over any SEQUENCE cycling from the motion set. Both cannot be active simultaneously — the Sprite Set wins. Remove the Sprite Set assignment (set to None / —) to revert to SEQUENCE-driven or static shape behaviour.</p>
<p>Style overrides work similarly: if the active state has a style override set, that style is used for the entire frame including motion parameters derived from the style. If the state's style is set to – (dash), the sprite's own global style is used as normal.</p>

<h2>Editing a Sprite Set</h2>
<p>Click the <strong>pencil icon</strong> next to a Sprite Set row in the palette (or choose <strong>Edit…</strong> from the right-click context menu) to open the editor sheet. The sheet has four areas top to bottom:</p>
<table>
  <tr><th>Area / Control</th><th>Action</th></tr>
  <tr><td><strong>Header</strong>: Name field</td><td>Rename the set. Changes apply immediately.</td></tr>
  <tr><td><strong>Header</strong>: Loop mode picker</td><td>Switch between Loop, Ping Pong, Once, Hold Last.</td></tr>
  <tr><td><strong>Header</strong>: ✕ button</td><td>Close the editor. Escape also works.</td></tr>
  <tr><td><strong>State list</strong>: ▸ chevron</td><td>Expand two transform rows: row 1 = Δx, Δy, °, Sx, Sy; row 2 = Trans (cross-fade frames) + Ease (easing curve) + Style↔ (style tween toggle).</td></tr>
  <tr><td><strong>State list</strong>: shape picker</td><td>Which shape from the project library this state displays.</td></tr>
  <tr><td><strong>State list</strong>: style picker</td><td>Optional style override for this state. – means use the sprite's own style.</td></tr>
  <tr><td><strong>State list</strong>: Hold field</td><td>How many frames to stay on this state (at full opacity) before any transition begins.</td></tr>
  <tr><td><strong>State list</strong>: Trans field</td><td>Cross-fade frames after Hold. 0 = instant cut. See <strong>Cross-fade between states</strong> above.</td></tr>
  <tr><td><strong>State list</strong>: Ease picker</td><td>Easing curve applied to the cross-fade. Dimmed when Trans = 0.</td></tr>
  <tr><td><strong>State list</strong>: Style↔ checkbox</td><td>Style Tween toggle. When checked, fill/stroke colours are linearly interpolated during the transition. Dimmed when Trans = 0. See <strong>Style tweening</strong>.</td></tr>
  <tr><td><strong>State list</strong>: − button</td><td>Remove this state.</td></tr>
  <tr><td><strong>State list</strong>: ↑ / ↓ buttons</td><td>Reorder states. The coloured dot indicates which state is active at the current preview frame.</td></tr>
  <tr><td><strong>State list</strong>: Add State menu</td><td>Append a new state using a shape from the project library.</td></tr>
  <tr><td><strong>Preview canvas</strong></td><td>Dark 160px canvas. Renders via the same cross-fade engine as the main canvas — scrub through a transition window (after the Hold period, before the next state) to see the two shapes blended live. Drag the sprite to adjust Δx/Δy for the focused state; ghost states at ±1 are shown at 22% opacity as onion skins.</td></tr>
  <tr><td><strong>Scrubber</strong>: ▶ / ⏸ button</td><td>Play or pause the animation preview at 24fps. Dragging the slider pauses playback automatically.</td></tr>
  <tr><td><strong>Scrubber</strong>: slider</td><td>Step to a specific frame across the full cycle (including the reverse pass for Ping Pong).</td></tr>
  <tr><td><strong>Scrubber</strong>: shape name</td><td>Shows the name of the shape currently active at the scrubber position.</td></tr>
</table>

<h2>Renaming a Sprite Set</h2>
<p>Two ways:</p>
<ul>
  <li><strong>Double-click</strong> the Sprite Set name in the palette. An inline text field appears — edit and press Return.</li>
  <li><strong>Right-click</strong> the row → <strong>Rename</strong>. Same inline field.</li>
  <li>The <strong>name field</strong> in the Sprite Set editor sheet also renames the set.</li>
</ul>

<h2>Duplicating a Sprite Set</h2>
<p>Right-click the Sprite Set row → <strong>Duplicate</strong>. A copy is inserted directly below the original, named <em>Copy of [name]</em>. The copy is fully independent — editing one does not affect the other. Use this to create variations with different style overrides, shape sequences, or morph target configurations without rebuilding from scratch.</p>

<h2>Deleting a Sprite Set</h2>
<p>Right-click the Sprite Set row in the palette → <strong>Delete</strong>. Any sprites or grid cells that had this set assigned revert to their static shape (or SEQUENCE cycling). The deletion cannot be undone.</p>
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

<h2>Video export — live animation</h2>
<ol class="steps">
  <li>Set the export range using <strong>From / To</strong> in the EXPORT section (or the Start / End fields in the Transport Bar — they are the same values).</li>
  <li>Set <strong>Multiplier</strong>, <strong>Scale drawing</strong>, and <strong>FPS</strong> as needed.</li>
  <li>Click <strong>Video</strong> in the Transport Bar (or <strong>Video ▾ → Live animation…</strong> if the timeline has recorded cuts).</li>
  <li>A save panel opens. Default location: <code>renders/animations/</code> inside your project package.</li>
  <li>Choose a location and click Save. The panel closes and export begins in the background.</li>
  <li>A progress bar replaces the Video button showing <em>N%</em>. The UI remains responsive during export.</li>
  <li>When complete, the Video button returns.</li>
</ol>
<p>Format: H.264 in a .mov container. The exported clip spans animation frames <em>From</em> through <em>To − 1</em>, output as a clip starting at time zero. All layers composite per-frame at their configured opacities. In accumulation mode, each exported frame correctly shows the accumulated build-up, exactly as it appears on screen during live playback.</p>

<h2>Video export — cut sequence</h2>
<p>When the active layer has at least one recorded timeline state, the Transport Bar shows <strong>Video ▾</strong> instead of a plain Video button. Choose <strong>Cut sequence…</strong> to export each recorded state as a discrete cut.</p>
<ol class="steps">
  <li>Record a few states using the recording workflow (see <a href="um-help://help/timeline">Timeline &amp; Recording</a>).</li>
  <li>Click <strong>Video ▾ → Cut sequence (N cuts)…</strong> in the Transport Bar.</li>
  <li>A save panel opens with a <code>_cuts_</code> filename. Choose a location and click Save.</li>
  <li>The exporter renders each timeline state for its configured hold duration (in frames), stitching all cuts into a single .mov. The animation frame counter runs continuously so parametric and keyframe motion plays uninterrupted across cuts.</li>
  <li>Total clip length = sum of all state hold durations ÷ FPS.</li>
</ol>
<p>Multiplier, Scale drawing, FPS, and Camera settings from the EXPORT / CAMERA sections apply to the cut sequence export exactly as they do to live animation export. The cut sequence does not use the From / To frame range — that range only applies to live animation.</p>

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
  <tr><td>Right panel</td><td>Full palette-context right panel (Style / Shape detail sections)</td><td>✓ Built — the RENDER section header now reads <strong>STYLE — [name]</strong> when a style is active. A <strong>SHAPE — [name]</strong> section appears below MOTION when a shape is active. A <strong>LAYER DRIVERS</strong> section (collapsed by default) exposes oscillator, jitter, and noise modes for layer opacity and layer offset.</td></tr>
  <tr><td>Left panel</td><td>Resolution preset library (global tabs)</td><td>✓ Built — the Library tab now shows a <strong>RESOLUTION</strong> section with global presets. Right-click a project preset chip (↑ Save to Library); in the Library tab, click ↓ to import a preset into the current project. See <a href="um-help://help/palette">Style Palette</a>.</td></tr>
  <tr><td>Rendering</td><td>Subdivision-level polygon warp</td><td>ORDER/CHAOS currently produces sine-oscillator jitter on sprite transforms. The deeper materialisation — warping polygon vertices via SubdivisionEngine based on the chaos value — is designed but not yet wired.</td></tr>
  <tr><td>Rendering</td><td>Full Loom render modes</td><td>Brushed (stamp-along-path), stenciled, stamped (bitmap at positions), and path perturbation (noise warp of geometry). Current build: Filled, Stroked, Fill &amp; Stroke only.</td></tr>
  <tr><td>Rendering</td><td>Animated style thumbnails</td><td>Style rows in the palette show a static coloured dot. Live animated miniature previews are planned.</td></tr>
  <tr><td>Canvas</td><td>Hover preview</td><td>No visual feedback on undrawn cells before committing a stroke. A faint style preview on hover is planned.</td></tr>
  <tr><td>Export</td><td>SVG export</td><td>The SVG button in the Transport Bar is present but has no action yet.</td></tr>
  <tr><td>Export</td><td>Timeline video export</td><td>The Video button exports live animation (parametric + keyframe motion). A separate mode that renders the recorded timeline states as discrete cuts is planned.</td></tr>
  <tr><td>Sprites</td><td>Animated geometry / Sprite Sets (Phase 1 + Phase 2a)</td><td>✓ Built — <strong>Sprite Sets</strong> are reusable shape-animation cycles assignable to any sprite. Each set holds an ordered list of states (shape + optional style override + hold frames + per-state transforms). The editor sheet includes a live preview canvas with play/pause. Multi-layer Loom geometry files can be split into individual per-layer shapes automatically via <strong>+ Import Layers as Shapes…</strong>. See <a href="um-help://help/sprite-sets">Sprite Sets</a>.</td></tr>
  <tr><td>Sprites</td><td>Sprite Set Phase 2b: transition frames (cross-fade / opacity blend between states)</td><td><code>transitionFrames</code> and <code>easing</code> are stored in the data model but not yet rendered. When built, states with <code>transitionFrames &gt; 0</code> will blend between the outgoing and incoming shape using interpolated opacity over the transition window. No data migration needed — existing projects will gain the effect automatically.</td></tr>
  <tr><td>Geometry</td><td>In-app geometry editor</td><td>Shapes must currently be authored in standalone Loom and imported as .json files. An in-app geometry mode (toolbar button G) is planned once Loom's editor is extractable as a standalone Swift Package.</td></tr>
  <tr><td>Canvas overlays</td><td>Phase heat-map overlay</td><td>✓ Built — <strong>Phase map</strong> checkbox in the CANVAS section of Quick Adjust. Colours each drawn cell in the active grid layer by phaseOffset: blue (0) → red (max), 50% opacity. See <a href="um-help://help/layers">Layers</a>.</td></tr>
  <tr><td>Canvas overlays</td><td>Background image backdrop</td><td>✓ Built — "Bg Image" row in CANVAS section. Image fills canvas behind all layers; saved in project package.</td></tr>
  <tr><td>Layers</td><td>Animated opacity &amp; parallax drivers</td><td>✓ Built — <strong>LAYER DRIVERS</strong> section in Quick Adjust exposes oscillator, jitter, and noise modes for layer opacity and layer offset. See <a href="um-help://help/layers">Layers</a> for details.</td></tr>
  <tr><td>Layers</td><td>Blend modes</td><td>✓ Built — <strong>Blend</strong> picker at the top of the <strong>LAYER DRIVERS</strong> section: Normal, Multiply, Screen, Overlay, Dodge, Burn, Soft Light, Hard Light, Difference, Exclusion, Add. Applied in all render paths.</td></tr>
  <tr><td>Layers</td><td>Grid distortion</td><td>✓ Built — <strong>DISTORTION</strong> subsection in LAYER DRIVERS. Three modes: <strong>Perspective</strong> (exponential row/column taper, ±1 strength per axis; grid lines follow distorted boundaries); <strong>Barrel/Cone</strong> (radial size modulation, +1 = centre cells larger, −1 = centre cells smaller); <strong>Fractured</strong> (stable per-cell random position jitter with seed control and ↺ randomise button).</td></tr>
  <tr><td>Undo</td><td>Keyframe edit undo</td><td>Keyframe edits in PATH EDITOR update the path immediately but are not tracked in the undo stack.</td></tr>
  <tr><td>Compatibility</td><td>Legacy UM XML import</td><td>No importer for Java UM .xml project files. Old Swift .umproj files (pre-4-axis model) are automatically migrated on open.</td></tr>
</table>
"""#
