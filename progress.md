# Cue — build progress and handoff

> **This file is the working memory for the screenwriting-feature build.**
> Read it first after any context reset. It records what Cue is today, the rules
> the work must follow, the exact build/test/release commands, the architecture
> and its landmines, and the ordered backlog with acceptance criteria.
>
> **Status:** planning only. No feature below has been started. Cue is at
> **v1.1.0 (build 110)**, released and live. All open questions in **§12** are
> now decided; **Phase 0 is next**.

---

## 0. How to use this file

- Pick the first unchecked item in **§9 Backlog**, in the order given.
- Before coding, read that item's **Model / UI / Export / Tests** notes and the
  relevant **§5 Architecture** and **§6 Landmines** entries.
- Every feature must pass **§8 Definition of done** before it is marked done.
- Update this file at the end of every work session: move the item's status,
  add a dated line to **§11 Work log**, and record any decision in **§12**.
- Status markers: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked.
- Never commit copyrighted produced screenplays or PDFs. The examples in the
  backlog are for **manual comparison only**; see **§10**.

---

## 1. Project snapshot

| | |
|---|---|
| Product | **Cue** — a native Mac screenwriting app. Free, no App Store, no account, no AI writing. |
| Repo | `Abhinav-Prabhakar/CueScreenWriter` (public, `main`) |
| App version | `1.1.0` / build `110` (`Cue/project.yml`) |
| Bundle id | `com.abhinavprabhakar.cue` |
| Platform | macOS 15+, universal (arm64 + x86_64), Swift 5 / SwiftUI + AppKit |
| Tests | **39 passing**: CueKit 20, CueApp 19 |
| Release | <https://github.com/Abhinav-Prabhakar/CueScreenWriter/releases/tag/v1.1.0> |
| Asset | **must be named `Cue.zip`** — every site download link is `releases/latest/download/Cue.zip` |
| Site | <https://abhinav-prabhakar.github.io/CueScreenWriter/> — static, served from `main` / `/docs`, no Actions |
| Data | `~/Library/Application Support/Cue/library.json` + `Attachments/`; override with `CUE_DATA_DIR` |
| Fonts | Courier Prime (Regular/Bold/Italic/BoldItalic) for script; Geist for UI; both bundled |

**Product rules already decided (do not revisit):** free, no App Store, no
subscriptions, no analytics, no accounts, distribution via GitHub Releases,
site static in `docs/`, no GitHub Actions, no web views inside the app.

---

## 2. Ground rules for every feature

### 2.1 Native first, never web-like

- Prefer real AppKit/SwiftUI controls: `List`, `Form`, `Section`, `Picker`,
  `Toggle`, `Slider`, `Menu`, `NSMenu`, sheets, `Settings` scene,
  `NSTouchBar`. A custom control is justified only when the stock one cannot
  express the screenplay semantics (the desk, the page, the sticky).
- If you build a custom control, it must have hover, pressed, focus, disabled
  and keyboard states, plus an accessibility label/value/action.
- No floating panels made of rectangles with fake shadows. Use the established
  materials: paper, glass, hairline, lamp pool.
- Context menus are AppKit (`NSMenu`) when the click location matters; SwiftUI
  `.contextMenu` is fine elsewhere.
- Inline editing over modal dialogs. Sheets are for tools (sound library,
  settings, updates, title page). Alerts only for destructive failure.

### 2.2 Design system (the only allowed source)

Everything comes from `CueKit/Tokens.swift` and `CueKit/Fonts.swift`.

- Colours: `Hex.*` and `Theme.daylight / evening / night`. **Never** add a raw
  hex outside `Tokens.swift`. Every new surface must be defined in all three
  lamps (`Theme.of(lamp)`), including new marks, chips and revision colours.
- Type: `Fonts.ui(size, weight:)` for chrome (10–21 pt); `Fonts.script(size)`
  for the page. Courier Prime italic/bold already exist and are the foundation
  for styled runs.
- Geometry: paper radius **6**; controls radius **5–8**; primary actions are
  capsules. Page metrics live in `PageMetrics` (`CueKit/SiteMath.swift`) and
  the shared paragraph geometry in `ScreenplayTypography`
  (`CueApp/Editor/ScriptTextView.swift`).
- Spacing: 4 pt grid; common paddings 8 / 12 / 16 / 22 / 26. Toolbar: 32 pt tall,
  46 pt top padding, title centred.
- Shadows: `theme.shadow` at the established radii; never a coloured glow.
- Motion: `Animation.cue`, `.cueLamp`, `.cueHover`, `.cueFade`, `.cueMenu`.
  Always respect `accessibilityReduceMotion`.
- Sliders/pickers in custom surfaces tint with `Color(hex: Hex.orange)`.
- Dark mode is the **Night** lamp, not the system appearance; test all three.

### 2.3 Keyboard, menu and Touch Bar parity

Every new command needs: a menu item in the right menu, a keyboard shortcut
listed in `HelpView`, and — if it is a writing action — a Touch Bar item where
it fits. Shortcut collisions must be checked against `CueApp.swift` and
`HelpView`.

### 2.4 Data safety is non-negotiable

- `CueDocument`, `Script` and `Element` are persisted as JSON and decoded with
  **synthesised `Codable`**. Adding a non-optional property with a default
  still breaks old files, because the synthesised `init(from:)` requires the
  key. Every new persisted field must be optional **or** decoded with
  `decodeIfPresent` in a hand-written initialiser. See **§6.1**.
- Autosave is debounced (`AppModel.scheduleSave`) and atomic. Import, export and
  migration must never be able to destroy the only copy.
- `CUE_DATA_DIR` must keep working for QA and tests.

### 2.5 Performance and scale

- A feature film script is 90–140 pages, ~3,000 paragraphs. Any per-keystroke
  work must stay O(visible paragraphs) or be debounced. The editor already
  repairs paragraph types incrementally — follow that pattern.
- PDF generation is synchronous on the main actor today. Keep it under a second
  for a 120-page script; move to a background task if a feature makes it slower
  (measure first).

### 2.6 The writer never manages the page

Cue's editor is a continuous scroll. The writer focuses on the words; the page
is computed, not administered. This is a product decision, not a temporary
shortcut:

- **No manual page breaks, no page-stack view, no “fit to page” fiddling in the
  editor.** Pagination exists in the PDF renderer and in the read-only furniture
  (page numbers, scene numbers), never as something the writer has to maintain.
- Every feature must degrade to nothing when unused. A writer who never touches
  dual dialogue, revisions or act breaks sees exactly today's editor.
- If a feature would require the writer to think about the page (forcing a
  break, choosing a page colour to type on, managing A/B pages by hand), the
  feature is wrong — redesign it to be derived or automatic.
- Optional production output (coloured revision pages, headers) is a **PDF
  setting**, never an editing mode.

---

## 3. Build, test, run

All commands from `CueScreenWriter/Cue/`.

```sh
# Generate the Xcode project after adding/removing files
xcodegen generate

# Debug build
xcodebuild -project Cue.xcodeproj -scheme CueApp \
  -configuration Debug -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO build

# Tests
xcodebuild test -project Cue.xcodeproj -scheme CueKit \
  -configuration Debug -derivedDataPath .build CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Cue.xcodeproj -scheme CueApp \
  -configuration Debug -derivedDataPath .build CODE_SIGNING_ALLOWED=NO

# Run against a throwaway library (never risk the writer's real data)
CUE_DATA_DIR=/tmp/cue-qa .build/Build/Products/Debug/Cue.app/Contents/MacOS/Cue
```

`xcodebuild` prints a harmless `DVTPlugInErrorDomain` / CoreSimulator warning on
this machine; ignore it. Look for `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **`.

---

## 4. Architecture map

```
Cue/
├── CueKit/                  pure model + design language (no AppKit UI)
│   ├── Script.swift         ElementType, Element, Script, Formatter, GhostRules,
│   │                        ScriptAnalysis, EditorPosition
│   ├── Tokens.swift         Hex, NoteTint, Lamp + LampController, Theme, Motion
│   ├── Fonts.swift          Courier Prime + Geist registration and helpers
│   ├── SiteMath.swift       PageMetrics, MacBookMetrics, site copy helpers
│   ├── Copy.swift           site/demo copy
│   └── UpdateVersion.swift  SemanticVersion, UpdateSchedule
├── CueApp/
│   ├── AppModel.swift       CueDocument, CueNote, CueSticky, CuePin, CueTitlePage,
│   │                        AppModel (document CRUD, desk objects, audio sync,
│   │                        updates, persistence)
│   ├── Editor/
│   │   ├── ScriptTextView.swift   NSTextView subclass: typing, element inference,
│   │   │                          chooser/time menus, paragraph styles, placeholders
│   │   ├── ScriptEditorView.swift SwiftUI wrapper, scroll, position reporting
│   │   └── PageFurnitureView.swift page numbers, rails, scene numbers
│   ├── Document/
│   │   ├── Fountain.swift         Fountain import/export
│   │   ├── PDFExport.swift        print renderer (NSTextStorage → page containers)
│   │   ├── PDFImport.swift        text extraction + element inference
│   │   ├── Exporter.swift         save panels, PDF/Fountain orchestration
│   │   └── LibraryStore.swift     JSON manifest, attachments, quarantine
│   ├── Views/               WritingView, DeskView, SidebarView, ToolbarView,
│   │                        LibraryView, TitlePageView, NoteComposerView+HelpView,
│   │                        MusicCapsule, SoundLibraryView, SettingsView,
│   │                        StickiesPins, StickyEditorView, DeskInteractionLayer
│   ├── Audio/AmbientPlayer.swift  14 synthesized rooms, lazy render, volume
│   ├── Update/UpdateController.swift, UpdateViews.swift
│   ├── TouchBar/CueTouchBar.swift
│   └── CueApp.swift         WindowGroup, commands, Settings, MenuBarExtra, AppRoot
├── CueSite/                 native SwiftUI rendering of the marketing page (and the
│                            demo editor); it mirrors ElementType and must keep compiling
├── CueShared/Resources      fonts + app screenshots
└── Tests/CueKitTests, Tests/CueAppTests
```

### Key symbols

- `ElementType`: `scene, action, character, paren, dialogue, transition, new`.
  `.new` is transient: it is persisted, but is resolved by `Formatter.inferType`
  when rendering/exporting. **Any new persistent element type must be added to
  every exhaustive switch listed in §4.1.**
- `ScreenplayTypography.paragraphStyle(for:width:line:spacingBefore:)` — the one
  place the page's indents live for the editor. PDF has its own
  `attributes(for:index:elements:)` but calls the same paragraph style.
- `PDFExport.makeLayout` — one `NSTextStorage` flowed into `NSTextContainer`s,
  one container per page. This is the pagination engine today.
- `ScriptAnalysis.derive` — cast, places, scene numbers, speaker map, speech
  ranges. Drives sidebar, colours and page furniture.
- `AppModel.currentScript` is a live copy; `AppModel.current` is the document.
  Editing goes through the script binding → `scriptChanged()` → debounce save.

### 4.1 Touchpoints when `ElementType` grows

Every one of these must be updated, and the compiler will catch most of them:

| File | What it owns |
|---|---|
| `CueKit/Script.swift` | enum cases, `isUppercase`, `accessibilityName`, `next`, `Formatter.choices`, inference, analysis |
| `CueApp/Editor/ScriptTextView.swift` | paragraph geometry, placeholder text, chooser labels, Tab/Return rules |
| `CueApp/Document/PDFExport.swift` | attributes, spacing, scene marks, page furniture |
| `CueApp/Document/Fountain.swift` | parse + serialise mappings |
| `CueApp/Document/PDFImport.swift` | inference from extracted text |
| `CueApp/Views/SidebarView.swift`, `PageFurnitureView.swift` | scene/character lists, rails |
| `CueSite/Demo/DemoEditor.swift`, `DemoModel.swift`, `HeroMock.swift` | site demo compiles against the model |

---

## 5. Current baseline (v1.1.0)

### Shipped

- Real screenplay engine: scene/action/character/paren/dialogue/transition,
  Tab/Return flow, INT./EXT. and character autocomplete (`GhostRules`),
  scene and page numbers drawn by the furniture, title page.
- Desk: stickies (created at the pointer, edited inline, tint/strike/delete),
  pinned photos, title-page strip, music capsule, lamp pool.
- Library with covers, search, rename, delete; JSON storage with attachments.
- Import/export: Fountain both ways, screenplay PDF import, PDF export.
- Three lamps + Auto, persisted; reduce-motion respected.
- 14-room synthesized sound library with lazy rendering and volume.
- Updates: monthly gate, manual check, background download, staged install on
  quit, native sheet + banner, Markdown release notes.
- Native Settings (General/Sound/Updates), menu bar extra, Touch Bar, AppKit
  desk menus.

### Known limitations (the backlog)

Dual dialogue; revision colours / locking / A-B pages; act breaks; SUPER and
centred text; bilingual and sign-language dialogue; non-linear timeline labels;
(CONT'D)/(MORE) and page-break conventions; song cues; document inserts; split
screens / multi-column action; character aliases; camera/continuous-take notes;
production metadata and breakdowns. Details and order in **§9**.

---

## 6. Landmines and gotchas (learned the hard way)

### 6.1 Codable migration will destroy libraries if done naively
`CueDocument`, `Script`, `Element` use synthesised `Codable`. A new non-optional
property — even with a default value — makes existing `library.json` fail to
decode, and `LibraryStore.load()` **quarantines the manifest and returns nil**,
showing the writer an empty library. So:

- New persisted fields are `Optional` **or** the type gets a hand-written
  `init(from:)` using `decodeIfPresent`.
- Add a fixture test that decodes a **v1.1 manifest** (copy the current
  `library.json` shape into `Tests/CueAppTests/Fixtures/`) before changing any
  persisted model.
- `Script` is nested inside documents; both layers need the same care.
- `LibraryStore` quarantines on *any* decode error, so migration bugs are
  destructive-looking. Test the migration path explicitly.

### 6.2 The desk is AppKit and **not flipped**
`DeskInteractionLayer.DeskSurface` receives events in bottom-left coordinates
(`isFlipped == false`), so the desk fraction is `local.y / height`, not
`1 - local.y / height`. The toolbar band (top 86 pt) is deliberately excluded so
clicks on the title don't create stickies. If the toolbar height changes,
update `toolbarBand`.

### 6.3 Sheets can hold `NSApp.terminate`
The updater calls `NSApp.terminate`, but a presented sheet kept the app alive
while the installer waited for the PID. `installAndRelaunch()` now schedules
`exit(0)` after 1.2 s. Keep that fallback for any future quit-time work.

### 6.4 QA screenshots
- `screencapture -l <windowID>`; get IDs with the helper below.
- Sheets are **separate windows** with their own IDs.
- Always `osascript -e 'tell application id "com.abhinavprabhakar.cue" to activate'`
  before clicking, and do the click + capture in the **same** shell command:
  other apps steal focus between commands.
- The image reader renders at different scales. Never infer coordinates from
  the displayed image. Use the window frame from the helper and known layout
  constants, or crop around the expected screen point to confirm.
- `screencapture` dismisses native menus, so menu items are driven by keyboard
  (Down + Return) or by clicking immediately after opening.
- Death by a thousand instances: two copies of `Cue.app` (same bundle id) can
  run at once during QA. `pkill -f "Cue.app/Contents/MacOS/Cue"` before every
  run; check `ps` if focus behaves strangely.

### 6.5 Update testing
To exercise the updater for real you need an older running build. Build one
without touching `project.yml`:

```sh
xcodebuild -project Cue.xcodeproj -scheme CueApp -configuration Debug \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION=1.0 CURRENT_PROJECT_VERSION=1 build
```

Copy that bundle elsewhere (`/tmp/cue-inst/Cue.app`), run it with
`CUE_DATA_DIR`, press ⌘U, wait for “ready”, click **Restart Now**. Verify the
copy's `Info.plist` becomes the new version and a new PID appears. Clean up
`~/Library/Application Support/Cue/Updates` afterwards. Do not test against the
real library.

The release **asset must be uploaded as `Cue.zip`**; `gh release upload` uses the
local filename, so copy/rename first. The site's download links and the updater
both depend on it.

### 6.6 Selection and inline editing
The sticky editor commits on outside click via a local `NSEvent` monitor. The
title rename uses `@FocusState`. When adding new inline editors, make sure the
`NSTextView` does not steal focus on the mouse-up that opened the editor, and
commit on `onExitCommand`/outside click/done.

### 6.7 Fountain is lossy today
Sections, synopses, notes and boneyards are **discarded** on import, and the
exporter never writes them. Act breaks (backlog item 4) will change that
decision; when it does, update the Fountain tests and README.

### 6.8 The site demo is a second implementation
`CueSite/Demo/DemoEditor.swift` duplicates a lot of the editor's layout and
switch statements. It exists to render the landing page and the interactive
demo. New element types will break its build; update it rather than deleting it,
and re-capture `docs/preview/` if the demo's look changes.

### 6.9 Screenshot regeneration
`tools/capture*.py` capture the **web** site (Playwright/Chrome). App screenshots
in `screenshots/` were captured from the running app; recapture them when a
shipped surface changes, then update the README and `docs/preview/` if the
marketing page shows the same surface.

---

## 7. QA terminal helpers (recreate after a reboot)

They live in `/tmp` and may vanish. Sources:

```swift
// /tmp/winid.swift — print Cue windows: owner | title | id | bounds
import Cocoa
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                      kCGNullWindowID) as! [[String: Any]]
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    if owner == "Cue" || owner == "Cue Site" {
        print(owner, "|", name, "|", w[kCGWindowNumber as String] as? Int ?? 0,
              "|", w[kCGWindowBounds as String] as? [String: Any] ?? [:])
    }
}
```

```swift
// /tmp/click.swift — one left click at global screen points
import CoreGraphics
import Foundation
let p = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
    .post(tap: .cghidEventTap)
usleep(40_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?
    .post(tap: .cghidEventTap)
usleep(40_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?
    .post(tap: .cghidEventTap)
```

```swift
// /tmp/rightclick.swift — move, then right down/up
import CoreGraphics
import Foundation
let p = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .right)?
    .post(tap: .cghidEventTap)
usleep(80_000)
CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: p, mouseButton: .right)?
    .post(tap: .cghidEventTap)
usleep(60_000)
CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: p, mouseButton: .right)?
    .post(tap: .cghidEventTap)
```

```swift
// /tmp/dblclick.swift — two clicks with clickState 1 then 2
import CoreGraphics
import Foundation
let p = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
for i in 1...2 {
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                       mouseCursorPosition: p, mouseButton: .left)
    down?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
    down?.post(tap: .cghidEventTap)
    usleep(40_000)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                     mouseCursorPosition: p, mouseButton: .left)
    up?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
    up?.post(tap: .cghidEventTap)
    usleep(60_000)
}
```

Compile with `swiftc -O /tmp/winid.swift -o /tmp/winid`, etc.

Keyboard: `osascript -e 'tell application "System Events" to keystroke "u" using command down'`.
Some System Events automation needs Accessibility permission for the agent.

---

## 8. Definition of done (apply to every item)

A feature is only `[x]` when all of these are true.

1. **Model** — the data model expresses the feature without string hacks; the
   model has unit tests for its happy path, edge cases and Codable round trip.
2. **Migration** — an existing v1.1 `library.json` still opens, and there is a
   test proving it (§6.1).
3. **Editor** — typing, Tab/Return flow, the element chooser, placeholders,
   copy/paste, undo/redo, find, and selection all behave; the page redraws
   correctly during edits.
4. **PDF** — export preserves the feature on the page, with page breaks and
   numbers still correct; check the PDF text with PDFKit (tests) and by eye.
5. **Fountain** — import and export either round-trip the feature or
   deliberately document the loss in `Fountain.swift` and the README.
6. **PDF import** — the extractor does something sensible with the construct
   (or explicitly ignores it without corrupting neighbouring paragraphs).
7. **Sidebar/furniture** — scene list, character roster, page/scene counts and
   rails remain correct.
8. **Three lamps** — Daylight, Evening and Night all read well; no raw colours
   outside `Tokens.swift`.
9. **Native behaviour** — menu item, shortcut in `HelpView`, focus, hover,
   disabled state, accessibility labels/values, and Touch Bar where it belongs.
10. **Keyboard-only** — the whole feature can be used without the mouse.
11. **Performance** — a 120-page script still types without lag; PDF export
    stays under ~1s (measure).
12. **Regression** — the §8.1 checklist passes; tests still all green.
13. **Docs** — README bullets/shortcuts and the relevant `docs/*.html` copy are
    updated; screenshots refreshed if the look changed.
14. **Progress** — this file updated with status and a work-log line.

### 8.1 Regression checklist (run before every release)

- [ ] Right-click the desk → Add Sticky Note lands at the pointer; inline tint,
      strike, delete, done all work; outside click commits.
- [ ] Double-click the desk adds a sticky; double-click the toolbar title renames
      (Enter commits, Escape cancels).
- [ ] Sound library lists 14 rooms, selecting plays, volume persists, capsule
      reflects the room.
- [ ] Lamp cycles Daylight → Evening → Night → Auto; the page, toolbar, sidebar
      and desk all follow; Reduce Motion respected.
- [ ] Sidebar scenes/characters/notes counts match the script; clicking a scene
      jumps to it.
- [ ] Fountain round trip preserves every element; PDF export opens and is
      paginated; exported PDF re-imports.
- [ ] Library create/rename/delete/search/cover; attachments survive a relaunch.
- [ ] Settings, menu bar extra, Touch Bar install on a new window.
- [ ] Update check reports the current version correctly; a staged update still
      installs on quit.
- [ ] No crashes in Console; no “Cue: could not save” logs.

---

## 9. Backlog (ordered)

Sizes: **S** ≈ half a day, **M** ≈ 1–2 days, **L** ≈ 3–5 days of focused work
(including tests and QA).

Dependencies are explicit; do not jump ahead of a dependency.

---

### Phase 0 — foundations (do these first)

#### F0.1 `[ ]` Model version and safe migration — S
- Add `schemaVersion` to the manifest envelope **without breaking the current
  array format** (`[CueDocument]` today). Simplest safe route: keep the array,
  version each document (`CueDocument.schemaVersion: Int = 1` decoded with
  `decodeIfPresent`), and write a `CueDocument.init(from:)` that tolerates
  missing/new keys.
- Add `Tests/CueAppTests/Fixtures/library-v1.1.json` (copy the current shape)
  and a test that decodes it, then re-encodes and compares.
- Introduce `CueDocument.migrated()` or a `LibraryStore.migrate` step for future
  versions.
- Acceptance: no existing library is quarantined; corrupt manifests still are.

#### F0.2 `[ ]` Inline text runs (bold / italic / underline) — M
- Why first: foreign dialogue, revision emphasis, underlined scene directions
  and title cards all need it. Without runs, half the backlog becomes string
  conventions.
- Model: `Element.runs: [TextRun]` (`TextRun { location, length, bold, italic,
  underline }`, UTF-16 offsets), `text` stays the source of truth. Default empty.
  Decode with `decodeIfPresent`; drop runs whose ranges exceed the text.
- UI: ⌘B / ⌘I / ⌘U in `ScriptTextView`; format menu + toolbar affordance only
  if it does not clutter the page; typing after a styled run inherits it.
- Export: PDF applies traits through `ScreenplayTypography.font`; Fountain maps
  `**bold**`, `*italic*`, `_underline_`; PDF import maps bold/italic runs.
- Editing: inserting/deleting text must shift or clip runs (unit-tested).
- Tests: round trip, overlapping/adjacent runs, editing offsets, Fountain.
- Acceptance: an italicised foreign line survives edit → save → reload → PDF →
  Fountain → re-import.

#### F0.3 `[ ]` Shared layout contract for new element types — S
- `ScreenplayTypography` is used by editor and PDF; keep it the single source
  for indents/alignment. Move any alignment/leading rules that PDF duplicates
  into it.
- Add a small `ScreenplayElementStyle` enum/struct in CueKit if it removes the
  duplicated switches in `ScriptTextView` and `PDFExport`.
- Acceptance: both renderers derive geometry from one function; no visual change
  to existing elements (compare PDFs pixel-wise or by text frames).

#### F0.4 `[ ]` Test fixtures and golden PDF helpers — S
- `Tests/CueAppTests/Fixtures/` for scripts and manifests.
- Helper: build a script → `PDFExport.data` → `PDFDocument` → page count and
  text per page, so features can assert marks/positions.
- Acceptance: at least one fixture per feature can be asserted without macOS UI.

---

### Phase 1 — page vocabulary (highest value, foundation for the rest)

#### 1. `[ ]` Centred and right-aligned text: SUPER, title cards, chyrons — M
- Produced examples: *The Big Short* (definition cards, direct address),
  *Vice*, *Chernobyl* (“SUPER: 1:23:45 A.M.”), *Oppenheimer* (date/location
  cards), *The French Dispatch* (section headers).
- Model: new persisted `ElementType.centered` and `.right`, **or** an
  `alignment` attribute on `.action`. Prefer the new types: they are explicit,
  exportable and searchable. Add to every switch (§4.1).
- UI: element chooser entries (“Centred”, “Right”), Tab/Return flow (both go to
  action), placeholder text, shortcut in the Desk/Format menu.
- Export: centre/right with the action indents; no bold by default.
- Fountain: `>centred<` is Fountain's existing centred syntax; right-aligned has
  no standard, use a documented extension (`>>right<<`) or lossy note.
- Tests: layout frames, PDF alignment, Fountain.
- Acceptance: a SUPER line and a right-aligned “CUT TO:” look correct in all
  lamps and in the PDF.

#### 2. `[ ]` Act breaks and TV structure — M
- Produced examples: *Breaking Bad* (COLD OPEN / TEASER / ACT ONE / END ACT),
  *Mad Men*, *The West Wing*, *Succession*.
- Model: `ElementType.section` with `SectionKind` (`coldOpen`, `teaser`,
  `act(Int)`, `tag`, `endOfAct(Int)`, `episodeTitle`). Acts must be numbered in
  analysis.
- UI: insert via menu (“Insert Act Break”), styled as a centred bold line with
  space above; the sidebar gains an acts summary (scenes per act, page range).
- Export: act headings centred, page/scene numbering continues; optional
  “END OF ACT” auto-line.
- Fountain: sections currently discarded — map `## Act One` ↔ `.section` and
  document the round-trip.
- Tests: numbering, Fountain, PDF page range, sidebar.
- Acceptance: a 5-act TV draft shows act structure and correct per-act scene
  counts.

#### 3. `[ ]` Revision mode: colours, asterisks, locked numbers, A/B pages, OMITTED — L
- Produced examples: every production draft — *Succession* (blue revisions),
  *Breaking Bad*, *Mad Men*; WGA/studio practice.
- Model: per document: `revisionColour` (white/blue/pink/yellow/green/goldenrod),
  `revisionDate`, `revisionRound`, `lockedSceneNumbers`, `sceneNumberOverrides:
  [UUID: String]`, `omittedScenes: Set<UUID>`, `revisedParagraphs: Set<UUID>`.
  Per page: colour + date (needed for A/B pages).
- UI: a **Revision** menu (Start New Revision, Next Colour, Lock Scene Numbers,
  Mark This Scene Omitted, Insert A-Scene, Mark Paragraph Revised). Toolbar
  gets a small colour chip + round, opening a native menu. Scene numbers are
  drawn by `PageFurnitureView`; lock them and allow `12A`/`12B`.
- Editor: changed paragraphs get the margin `*`; scene numbers stop renumbering
  when locked; OMITTED keeps the number in place.
- PDF: page header (“BLUE — REVISED 11/12/26”) by default on **white** paper;
  `*` in the left margin; locked numbers; A-pages must not cascade. A
  “Print revision colours” option renders coloured page backgrounds for
  production. White is the default because Cue is a writing app and the printed
  script should read cleanly; colour is a deliberate production choice.
- Fountain: no standard; document loss (or a `[[cue:revision]]` comment that is
  ignored on import).
- Tests: numbering with locks/inserts/omitted, asterisk placement, PDF headers,
  page numbering with A/B pages.
- Risk: **this touches pagination**, the most fragile part. Do it after F0.3/4
  and keep the current layout as a regression baseline.
- Acceptance: a locked 34-scene script can take a new scene as 12A without
  renumbering 13+, and a blue revision prints with dates and asterisks.

#### 4. `[ ]` Page-break conventions: (CONT'D), (MORE), CONTINUED: — S
- Produced examples: *The Social Network*, *The West Wing*, most drafts.
- Model: derived, not stored — a pagination pass produces page breaks and
  continuation metadata from the PDF layout engine.
- **Decided:** the editor keeps its continuous scroll and gains no page breaks
  (§2.6). Markers appear only in the PDF. The layout pass is factored out of
  `PDFExport` so a future reading view can reuse it, but no editor work is
  scoped.
- Rules: dialogue that breaks adds `(MORE)` at the bottom and `(CONT'D)` on the
  character cue after the break; `CONTINUED:` top/bottom if enabled; never
  break a scene heading from its first action line; widows controlled.
- Tests: fixtures that force a break at each element type; assert marker
  placement and that page count is stable.
- Acceptance: exporting a long dialogue matches Final Draft/Fade In behaviour
  for the same page geometry, and the editor still scrolls seamlessly.

---

### Phase 2 — dialogue and voices

#### 5. `[ ]` Dual dialogue — M/L
- **Priority over item 6:** dual dialogue needs the column engine first;
  bilingual dialogue's core (a language/delivery attribute plus italic runs)
  does not. Build the engine here, reuse it for subtitles and split screens.
- Produced examples: *Step Brothers*, *Anchorman*, *30 Rock* (overlapping
  comedy). Verify against a real draft before implementation.
- Model: a `DualDialogue` group referencing two speeches (left/right), or two
  `Element`s flagged `dualSide: .left/.right` with a group id. The latter keeps
  the flat list; both must survive Codable and editing.
- UI: select a speech → “Make Dual Dialogue” (⌘D), right column appears with the
  caret; Tab moves between columns; “Break Dual” restores linear order.
- Editor: side-by-side containers with the existing dialogue indents; the
  chooser and Tab/Return must be column-aware.
- PDF: two columns for that block only; pagination must not split the pair
  across pages if avoidable.
- Fountain: `^` caret on the second line (Fountain's dual-dialogue syntax); test
  round trip.
- Tests: insertion/removal, caret movement, Fountain, PDF columns, page breaks.
- Acceptance: two overlapping speeches print side by side and remain editable
  as normal speeches after breaking the pair.

#### 6. `[ ]` Bilingual dialogue and sign language — M
- **Does not require the column engine** except for the optional subtitle
  track; the core is a per-speech attribute plus italic runs (F0.2). It follows
  dual dialogue only because that item lands the shared column layout first.
- Produced examples: *Parasite*, *Minari*, *Roma*, *Drive My Car*, *Anatomy of a
  Fall*, *Past Lives*; sign language: *CODA*, *A Quiet Place*.
- Model: per-dialogue `language: String?` and `delivery: Delivery`
  (`spoken`, `subtitled`, `signing`, `voiceOver`, `offScreen`). The character
  cue already carries `(V.O.)`/`(O.S.)` in text; formalise for analysis.
- UI: a small language/delivery control in the element chooser or a context
  menu (“Dialogue Language…”, “Signed Dialogue”); italicise foreign lines by
  default (uses F0.2).
- PDF: italic foreign dialogue; optional subtitle track (a second rendering of
  the same speech, smaller, in brackets); a “SUBTITLES:” convention block.
- Fountain: no standard; document loss or use inline notes.
- Tests: language round trip, italic rendering, PDF bilingual export.
- Acceptance: a scene with Korean and English dialogue prints both clearly and
  the roster/scene cast are unaffected.

#### 7. `[ ]` Character aliases and non-person cues — S
- Produced examples: *The Usual Suspects* (VERBAL/KEYSER SÖZE), *Fight Club*
  (NARRATOR/TYLER), *Psycho* (MOTHER), plus “MAN #2”, “VOICE”, “RADIO”.
- Model: `CueDocument.castAliases: [String: String]` (cue → roster name) plus
  `isVoice` derived from `(V.O.)`/`(O.S.)`/`(FILTERED)`.
- UI: merge/split in the Characters tab (“Merge into…”), with undo.
- Analysis: scene cast, counts, colours, `declaredCharacterLines`.
- Tests: alias merge, colour stability, scene cast, declared counts.
- Acceptance: “YOUNG ELIAS” and “ELIAS” share one colour and one roster row,
  while “VOICE” can be marked non-physical.

---

### Phase 3 — structure and production

#### 8. `[ ]` Non-linear and multi-timeline labels — S
- Produced examples: *Dunkirk* (THE MOLE / THE SEA / THE AIR), *Memento*
  (BLACK AND WHITE / COLOR), *Oppenheimer* (FISSION / FUSION), *Cloud Atlas*.
- Model: `Element.timeline: String?` or a document-level `timelines: [String]`
  with a scene tag; analysis groups by timeline.
- UI: a timeline picker on the scene heading (context menu), a coloured dot in
  the scene list and a filter.
- PDF: optional timeline label in the scene heading or a running header.
- Tests: grouping, filter, PDF label, colours across lamps.
- Acceptance: a three-timeline script can be filtered to one strand and exported
  with its labels.

#### 9. `[ ]` Scene metadata and breakdown export — M
- Produced examples: production drafts (Final Draft/Fade In breakdowns);
  *Dunkirk*'s three timelines; any TV schedule.
- Model: parse `INT/EXT`, location, day/night, cast, page eighths into a
  `SceneMeta` derived from the heading, with manual overrides; do **not**
  duplicate the text.
- UI: a Breakdown tab or inspector with editable fields; scene cards linking to
  the heading.
- Export: CSV/JSON breakdown; optional “sides” export by scene selection.
- Tests: parser against real headings (INT./EXT., I/E, CONTINUOUS, LATER,
  date-stamped, “MONTAGE”), overrides, CSV columns.
- Acceptance: export a correct breakdown for a 60-scene script and select two
  scenes to print as sides.

#### 10. `[ ]` Production header, footer and watermarks — S
- Produced examples: every production draft (“BLUE REVISED 11/12/26”, page
  numbers with scene numbers, WGA info); reading drafts (“FOR YOUR
  CONSIDERATION”).
- Model: `CueDocument.pageHeader`, `pageFooter`, `watermark`, `showTitleOnPages`.
- UI: in the title page editor (already a sheet) or Settings → Document.
- PDF: drawn by page furniture; keep the current page number and scene-number
  marks.
- Tests: header on every page, first page suppression, watermark opacity.
- Acceptance: a “BLUE REVISED” draft prints with the right header on every page.

#### 11. `[ ]` Song cues, lyrics and musical numbers — S
- Produced examples: *Baby Driver* (song + lyric cues), *La La Land*,
  *Barbie*, *West Side Story*.
- Model: `.song` element with title/artist and lyric lines, or a styled action
  block. Prefer a structured element so the sidebar can list numbers.
- UI: insert song cue; lyrics as indented italic lines (F0.2).
- PDF: centred/bold cue, lyrics indented.
- Fountain: documented extension only.
- Tests: round trip, PDF styling, numbering.
- Acceptance: a musical sequence prints with numbered numbers and clear cues.

#### 12. `[ ]` Inserts: letters, articles, screens, ciphers — M
- Produced examples: *Zodiac*, *All the President's Men*, *The Social Network*
  (depositions), *The Big Short*.
- Model: `.insert` block referencing an attachment id (image) or typeset text,
  with caption, fit mode and optional full-page.
- UI: drop/paste an image into the page (not only the desk), choose fit, caption.
- PDF: draw the image within the text block; never split awkwardly.
- Tests: attachment lifecycle, PDF page fit, deletion cleanup.
- Acceptance: a letter insert prints in place, survives save/reload, and leaves
  no orphan attachment when deleted.

#### 13. `[ ]` Continuous take and camera notes — S
- Produced examples: *1917* (one take), *Birdman*, *Rope*, *Gravity*.
- Model: `.camera` element (right/left small caps) or a scene attribute
  (“ONE CONTINUOUS TAKE”).
- UI: insert camera note; optional running time stamp.
- PDF: aligned as production notes; must not affect scene numbering.
- Tests: no effect on counts; PDF placement.
- Acceptance: a continuous-take script prints camera notes without polluting
  action or dialogue.

#### 14. `[ ]` Split screens and multi-column action — L
- Produced examples: *The Big Short*, *Requiem for a Dream*, *Scott Pilgrim*,
  *24*.
- Model: a `Columns` block of 2–3 action/dialogue streams with a shared start
  and end; reuse the dual-dialogue column engine.
- UI: select action lines → “Make Columns”, edit each column, break back.
- PDF: side-by-side containers with aligned baselines; do not break mid-block.
- Tests: PDF frames, editing order, Fountain loss documented.
- Acceptance: a three-column sequence prints legibly in one block.

---

### Phase 4 — finishing touches

#### 15. `[ ]` Dialogue continuation polish and reading modes — S
- “Hide page furniture while typing”, “Focus mode”, and a clean reading PDF
  without revision marks. No page-stack view in the editor (§2.6). Only after
  the page engine is stable.

#### 16. `[ ]` Accessibility and localisation sweep — M
- VoiceOver pass over every new control; keyboard-only pass; Dynamic Type is
  not a macOS app concern, but larger UI text in Settings should not clip.
- Copy review for consistency and typography (curly quotes, en dashes).

---

## 10. Produced-script reference list (manual comparison only)

Do **not** commit these files. Use them to check a feature by eye, then delete
them. Prefer the officially published screenplays/books where available.

- *The Big Short* (2015) — SUPER, direct address, split screens, montage.
- *Vice* (2018) — asides, direct address, on-screen text.
- *Chernobyl* (2019, TV) — SUPER time stamps, title cards, act structure.
- *Oppenheimer* (2023) — FISSION/FUSION sections, date cards.
- *Dunkirk* (2017) — three timelines, title cards.
- *Memento* (2000) — black-and-white/colour sequence labels.
- *The French Dispatch* (2021) — magazine headers/columns.
- *Parasite* (2019), *Minari* (2020), *Roma* (2018), *Drive My Car* (2021),
  *Anatomy of a Fall* (2023), *Past Lives* (2023) — bilingual dialogue.
- *CODA* (2021), *A Quiet Place* (2018) — sign language.
- *Succession* (TV) — revision colours, act breaks.
- *Breaking Bad* “Pilot” (TV) — cold open/teaser/acts, scene numbering.
- *Mad Men* “Smoke Gets in Your Eyes” (TV) — act breaks, CONT’D.
- *The West Wing* “Pilot” (TV) — act breaks, (CONT’D), (MORE).
- *Step Brothers* / *Anchorman* — dual dialogue (verify before relying on it).
- *Baby Driver* (2017), *La La Land* (2016), *Barbie* (2023) — song cues/lyrics.
- *Zodiac* (2007), *All the President's Men* (1976) — inserts.
- *Requiem for a Dream* (2000), *Scott Pilgrim* (2010), *24* (TV) — split screens.
- *The Usual Suspects* (1995), *Fight Club* (1999), *Psycho* (1960) — aliases.
- *1917* (2019), *Birdman* (2014), *Rope* (1948) — continuous takes.
- *The Social Network* (2010) — modern dialogue and page breaks.

If a claim about a specific script is uncertain, check the draft first; do not
write a feature spec from memory alone.

---

## 11. Work log

### 2026-11-12 — v1.1.0
- Shipped background updates (monthly gate, manual check, staged install on
  quit, native sheet/banner, Markdown notes, exit fallback).
- Stickies: created at the pointer, inline editor (tint/strike/delete/done),
  sidebar clearing, toolbar-band guard.
- Title rename inline; mute button removed.
- 14-room synthesized sound library with lazy render and volume.
- Native Settings, menu bar extra, Touch Bar.
- Tests 39/39. Release v1.1.0 (`Cue.zip`), site updated.
- Commits: `6fce298`, `bd3e256`.
- Verified: update 1.0 → 1.1.0 end to end on a copied bundle; Pages live with
  the new copy.
- This progress file created (untracked at time of writing).

### 2026-11-12 — decisions locked, tracker published
- Resolved every open question in §12 with the writer:
  - editor stays a continuous scroll; no page breaks in the editor (item 4 → S);
  - revision PDFs default to white with a header, colour is opt-in;
  - dual dialogue precedes bilingual dialogue; the column engine is shared;
  - lossy Fountain export allowed for production-only constructs, never silent;
  - reference drafts are available on request, never committed.
- Added **§2.6 The writer never manages the page** as a standing product rule.
- Updated items 3, 4, 5, 6 and 15 to match; removed the page-stack idea.
- `progress.md` is now tracked in the public repo.
- No code changed; tests remain 39/39 at v1.1.0.

### Template for the next entry
```
### YYYY-MM-DD — <feature / version>
- What changed:
- Files:
- Tests added:
- QA evidence (screenshots, PDFs, scripts):
- Regressions checked:
- Decisions / follow-ups:
```

---

## 12. Decisions

### Product and platform
- Free, no App Store, no analytics, GitHub Releases, static site in `docs/`,
  no CI.
- Native-first UI; the desk is the only bespoke canvas; sheets for tools.
- Light is a product concept: every surface must be designed for all three
  lamps.
- Persistence is a human-readable JSON manifest; attachments beside it.
- Updates are dependency-free and GitHub-only.

### Writing experience
- **No true page breaks in the editor.** The editor is a continuous scroll;
  the writer should never manage the page (§2.6). PDF is the only paginator.
  Item 4 is therefore **S**, not M/L.
- **Revision PDFs default to white paper** with a revision header and margin
  asterisks; “Print revision colours” is an opt-in PDF setting for production.
- **Dual dialogue is built before bilingual dialogue** (item 5 → item 6). The
  column engine lands once and is reused for subtitles and split screens;
  bilingual dialogue needs only a per-speech attribute and italic runs.
- Every feature must be invisible when unused.

### Data and interoperability
- **Lossy Fountain export is acceptable for production-only concepts**
  (revision marks, inserts, columns, aliases, timeline tags, camera notes), but
  it must never be silent: each loss is listed in `Fountain.swift`, in a README
  “Fountain support” table, and ideally emitted as an ignored `[[cue:…]]`
  comment. Anything that maps cleanly (sections/acts, centred `>text<`, bold,
  italic, underline, dual dialogue `^`) must round-trip and be tested.
- Import must always be non-destructive to neighbouring paragraphs, even when a
  construct is dropped.
- Persisted-model changes follow §6.1 without exception.

### Reference material
- The writer has legal access to produced drafts. Ask for the specific script
  needed for a feature (and delete it after verification); never commit a draft
  or a derived PDF. All comparisons in §10 are visual, not golden fixtures.

### Still open (ask when the item starts)
- Exact colour palette for the six revision colours (must be defined in
  `Tokens.swift` for all three lamps).
- Whether act breaks should appear in the scene list as collapsible groups or
  as a separate summary.
- Whether a subtitle track for bilingual dialogue belongs in v1 or after the
  core attribute ships.

---

## 13. Resume protocol (first 15 minutes after a context reset)

1. `cd CueScreenWriter && git status --short && git log --oneline -3` — confirm
   the tree and the last commit.
2. Read this file's **§6** landmines and the first unchecked item in **§9**.
3. Run the two test schemes; expect 39 passing at the v1.1.0 baseline.
4. Launch the app with `CUE_DATA_DIR=/tmp/cue-qa` and smoke-test the §8.1
   sticky/title/sound/update items.
5. Open the files listed in the item's notes, write the model test first, then
   the implementation, then the export path.
6. End the session by updating **§9**, **§11** and any new **§12** decisions.
