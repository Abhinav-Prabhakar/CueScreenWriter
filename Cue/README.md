# CueClone — native rebuild

Two macOS apps and one shared framework, generated with XcodeGen:

| Target | Product | Purpose |
| --- | --- | --- |
| `CueKit` | framework | tokens, lamp, copy, script model, formatting, math |
| `CueSite` | `Cue Site.app` | the marketing page, pixel-matched to cuescreenwriter.com |
| `CueApp` | `Cue.app` | the screenwriting app (library, editor, desk) |

## Build

```sh
cd CueClone
xcodegen generate
xcodebuild -project Cue.xcodeproj -scheme CueSite -configuration Debug \
  -derivedDataPath .build build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Cue.xcodeproj -scheme CueApp -configuration Debug \
  -derivedDataPath .build build CODE_SIGNING_ALLOWED=NO
open .build/Build/Products/Debug/Cue\ Site.app
open .build/Build/Products/Debug/Cue.app
```

Resources (fonts, official screenshots, logo) live in `CueShared/Resources` and are copied
into both app bundles flat, so `Bundle.main.url(forResource: "CourierPrime-Regular",
withExtension: "ttf")` and `Bundle.main.url(forResource: "editor-daylight", withExtension:
"jpg")` work.

## Ownership map (do not create files outside your assignment)

```
CueKit/                     shared, already written
CueSite/
  CueSiteApp.swift          already written (SiteModel)
  LandingView.swift         already written (root scroll)
  Design/SiteChrome.swift   already written (logo, section, slug, glass, glow, grain)
  Design/HeaderBar.swift    landing agent
  Sections/FeaturesSection.swift, QuestionsSection.swift, SiteFooter.swift,
  Sections/Illustrations.swift                     landing agent
  Demo/DemoModel.swift, DemoEditor.swift, TrySection.swift   demo agent
  Hero/HeroSection.swift, MacBookView.swift, HeroMock.swift   hero agent
CueApp/
  CueApp.swift, AppModel.swift                     already written
  Views/LibraryView.swift, WritingView.swift, ToolbarView.swift, SidebarView.swift,
  Views/DeskView.swift, MusicCapsule.swift, StickiesPins.swift, TitlePageView.swift
                                                    app-shell agent
  Editor/ScriptEditorView.swift, ScriptTextView.swift, PageFurnitureView.swift
                                                    editor agent
  Document/Exporter.swift, Fountain.swift, PDFExport.swift
                                                    editor agent
```

## Fixed interfaces

```swift
// CueSite root expects exactly these view names:
struct HeaderBar: View
struct HeroSection: View
struct TrySection: View
struct FeaturesSection: View
struct QuestionsSection: View
struct SiteFooter: View

// CueApp shell expects exactly:
struct LibraryView: View
struct WritingView: View
struct ToolbarView: View
struct SidebarView: View
struct DeskView: View
struct MusicCapsule: View
struct TitlePageView: View
struct ScriptEditorView: NSViewRepresentable {
    init(script: Binding<Script>, theme: Theme, isEditable: Bool,
         onPosition: @escaping (EditorPosition) -> Void)
}
enum Exporter {
    static func exportPDF(script: Script, title: String)
    static func exportFountain(script: Script, title: String)
}
```

`SiteModel` is injected with `.environment(model)`; read it with
`@Environment(SiteModel.self) private var model`. It exposes `lamp`, `lit`, `theme`,
`scrollY`, `viewport`, `width`, `typedProgress`, `reduceMotion`, `macBookWidth`.

`AppModel` is injected the same way into `CueApp` views.

## Rules

- Copy is character-exact (curly apostrophes in prose, hyphens in the demo script, em dashes
  in slugs). Take it from `SiteCopy` or the raw source, never retype from memory.
- Colours, type, spacing and motion come from `CueKit`; do not introduce new tokens.
- Official screenshots are only used where the reference page itself uses an image
  (`editor-*.jpg`, `full-*.jpg`). Every other illustration is drawn in SwiftUI.
- Respect Reduce Motion (`model.reduceMotion` / `@Environment(\.accessibilityReduceMotion)`).
- Do not edit files owned by another agent.
