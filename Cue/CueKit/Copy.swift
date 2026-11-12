import Foundation

public enum SiteCopy {
    public static let price = "$6.99"
    public static let priceNote = "Launch price. It goes up later, so early writers pay less."
    public static let appStoreURL = URL(string: "https://apps.apple.com/app/cue-screenwriting/id6823013313?mt=12")!
    public static let requires = "macOS 15 Sequoia or later"
    public static let maker = "Daniel Millyard"
    public static let contactEmail = "support@cuescreenwriter.com"
    public static let privacyUpdated = "15 October 2026"

    // Header
    public static let nav = ["Try it", "Price", "Features", "Questions"]

    // Hero
    public static let heroSlug = "FADE IN:"
    public static let heroFixed = "The most beautiful way to write"
    public static let heroTyped = "a screenplay."
    public static let heroLede = "Cue is a screenwriting app for Mac, unlike any other. It formats your script as you type, keeps every scene and character in view, and lights the page like a desk lamp that follows the time of day."
    public static let promiseWords = ["Yours to keep.", "No subscription.", "No ads.", "No AI writing."]
    public static let promiseSmall = "No subscription · No ads · No AI writing"
    public static let download = "Download Cue now"
    public static let tryBelow = "Try the page below ↓"

    // Try
    public static let trySlug = "CUT TO:"
    public static let tryTitle = "Go on. Type something."
    public static let tryNote = "A small demo of Cue’s page, made for the web. The app does a great deal more, but this is how it feels."

    // Features intro
    public static let featuresSlug = "INT. CUE – LATE"
    public static let featuresTitle = "A quiet room for writing."
    public static let featuresNote = "Everything in Cue is there to keep you in the scene: the light, the music, the page. Here’s what you won’t find anywhere else."

    public struct Feature: Identifiable, Sendable {
        public let id: String
        public let slug: String
        public let title: String
        public let body: String
        public let flipped: Bool
        public let wide: Bool
    }

    public static let features: [Feature] = [
        .init(id: "lamp", slug: "EXT. THE LAMP – DAY, EVENING, NIGHT",
              title: "A lamp that keeps your hours.",
              body: "Cue’s light follows the time of day: clean paper in the morning, a warm glow in the evening, a dark desk after midnight. Or pick one and keep it. (This page does the same; try the switch.)",
              flipped: false, wide: true),
        .init(id: "lamp-off", slug: "INT. THE DESK – LIGHTS OUT",
              title: "Or switch it off.",
              body: "When all you want is the words, turn the lamp off. No glow, just the page. In Cue it’s ⌥⌘L; here it’s this switch.",
              flipped: false, wide: true),
        .init(id: "music", slug: "INT. THE DESK – MUSIC PLAYING",
              title: "Your music, beside the page.",
              body: "A small player sits in the corner while you write, showing what’s playing in Apple Music or Spotify. It takes its colours from the album cover, and its waveform moves with the song. Pause or skip without ever leaving your scene.",
              flipped: false, wide: false),
        .init(id: "title", slug: "INT. THE TITLE PAGE – OPENING",
              title: "Your title, the way you see it.",
              body: "Give your script its own title graphic, like a film’s logo on its poster. It takes the place of the typed title on the title page, on your script’s cover in the library, and in the PDF you send out.",
              flipped: true, wide: false),
        .init(id: "pins", slug: "INT. THE DESK – AROUND THE PAGE",
              title: "Pin up what you’re seeing.",
              body: "Drag photos, maps or storyboards onto the desk beside your pages. They stay where you put them, saved with the script, and they never print.",
              flipped: false, wide: false),
        .init(id: "sticky", slug: "INT. THE DESK – LATER",
              title: "Room for the mess.",
              body: "Sticky notes sit on the desk beside the script for the thoughts that don’t belong to one line. Tint them, cross things off, tidy them away. Notes on a line live in the margin.",
              flipped: true, wide: false),
        .init(id: "snippet", slug: "INT. THE PAGE – AS YOU TYPE",
              title: "Formatting that stays out of your way.",
              body: "Press Enter and Cue offers what comes next: action, a character, a new scene. Type a name in capitals and it knows it’s a character. Type I and it offers INT. You never stop to pick a style from a menu.",
              flipped: false, wide: false),
        .init(id: "panel", slug: "INT. SIDE PANEL",
              title: "Every scene and character, a glance away.",
              body: "Scenes with their length in eighths and who’s in them. Characters in their own warm colour, carried down the margin beside every line they speak. Pin your leads to the top.",
              flipped: true, wide: false),
        .init(id: "full-ui", slug: "INT. THE WHOLE DESK – ANY HOUR",
              title: "", body: "", flipped: false, wide: true),
        .init(id: "extras", slug: "ALSO IN THE BAG",
              title: "", body: "", flipped: false, wide: true)
    ]

    public static let extras: [(String, String)] = [
        ("Bring your scripts.", "Import a screenplay PDF or a Fountain file, from any app."),
        ("Send them anywhere.", "Export a standard screenplay PDF, or Fountain."),
        ("A proper title page.", "Title, credit, contact and draft date, set the standard way."),
        ("Notes on any line.", "Select words, press Tab, write the note."),
        ("Find anything.", "Search the whole script and jump straight there."),
        ("Soft sounds.", "Quiet keys and a gentle room tone, or silence. Your choice."),
        ("Covers for your scripts.", "Give each one a picture in your library."),
        ("Never lose a word.", "Saves as you go, always."),
        ("Hands on the keys.", "Everything has a shortcut. The mouse is optional.")
    ]

    // Questions
    public static let questionsSlug = "INT. QUESTIONS – CONTINUOUS"
    public static let questionsTitle = "Questions"
    public static let qa: [(String, String)] = [
        ("Where can I get it?",
         "On the Mac App Store, for \(price). Pay once and it’s yours, with updates through the App Store, free."),
        ("Which Macs does it run on?",
         "Any Mac running \(requires)."),
        ("Can I bring my scripts from Final Draft or another app?",
         "Yes, as a PDF or a Fountain file. Cue reads the page and rebuilds the scenes, characters and dialogue. Final Draft’s own .fdx files aren’t supported yet, so export a PDF from Final Draft and import that."),
        ("Can I send my script to someone who doesn’t use Cue?",
         "Yes. Cue exports a standard screenplay PDF that anyone can read, print or submit, and Fountain, which most screenwriting apps can open."),
        ("Is there an iPad version?",
         "Not yet. The Mac comes first. An iPad version is planned."),
        ("Why is it so cheap?",
         "Because a place to write shouldn’t cost more than the coffee you drink while using it. Cue has no servers to run and no subscription to justify, so the price can be small and stay that way."),
        ("Is Cue made with AI?",
         "Partly, and we’d rather say so. Cue is designed by \(maker), a designer and writer, and built with Claude, an AI coding assistant. The app itself has no AI in it: it doesn’t write for you, read your script or send it anywhere. It only ever suggests words you’ve already written, like a character’s name."),
        ("What isn’t Cue?",
         "Cue is for writing. It doesn’t do live collaboration, revision colours or production breakdowns. If your production needs those, draft in Cue and finish there.")
    ]

    // Footer
    public static let fadeOut = "FADE OUT."
    public static let signOff = "Written, by you."
    public static let footerTitle = "Cue · Screenwriting for Mac"
    public static let footerLinks = ["Support", "Privacy"]
    public static let copyright = "© 2026 \(maker)"

    // Titles for the lamp screenshots
    public static let lampTitles: [Lamp: String] = [
        .daylight: "Daylight", .evening: "Evening", .night: "Night"
    ]

    // Demo
    public static let demoInitial: [(ElementType, String)] = [
        (.scene, "INT. KITCHEN TABLE - 2 AM"),
        (.action, "A laptop glows. MAYA (30s) stares at a blinking cursor. Her tea went cold an hour ago."),
        (.character, "MAYA"),
        (.paren, "(to the cat)"),
        (.dialogue, "One page. Then bed."),
        (.action, "The cat does not believe her."),
        (.new, "")
    ]
}
