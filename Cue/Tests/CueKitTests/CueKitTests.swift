import XCTest
@testable import CueKit

final class FormatterTests: XCTestCase {
    func testUppercaseDetectionNeedsALetter() {
        XCTAssertTrue(Formatter.isUpper("ELIAS"))
        XCTAssertTrue(Formatter.isUpper("INGRID (V.O.)"))
        XCTAssertFalse(Formatter.isUpper("Elias"))
        XCTAssertFalse(Formatter.isUpper("1234 -"))
        XCTAssertFalse(Formatter.isUpper(""))
    }

    func testScenePrefixAcceptsStandardPrefixes() {
        XCTAssertTrue(Formatter.isScenePrefix("INT. APARTMENT - NIGHT"))
        XCTAssertTrue(Formatter.isScenePrefix("ext. street - day"))
        XCTAssertTrue(Formatter.isScenePrefix("I/E CAR - DAY"))
        XCTAssertTrue(Formatter.isScenePrefix("INT/EXT HOUSE - DAY"))
        XCTAssertTrue(Formatter.isScenePrefix("INT ROOM - DAY"))
        XCTAssertFalse(Formatter.isScenePrefix("INTERIOR APARTMENT"))
        XCTAssertFalse(Formatter.isScenePrefix("THE INT. ROOM"))
    }

    func testInferTypeFollowsTheScreenplayConventions() {
        XCTAssertEqual(Formatter.inferType("INT. APARTMENT - NIGHT"), .scene)
        XCTAssertEqual(Formatter.inferType("EXT. STREET - DAY"), .scene)
        XCTAssertEqual(Formatter.inferType("FADE OUT."), .transition)
        XCTAssertEqual(Formatter.inferType("CUT TO:"), .transition)
        XCTAssertEqual(Formatter.inferType("ELIAS"), .character)
        XCTAssertEqual(Formatter.inferType("ELIAS (V.O.)"), .character)
        XCTAssertEqual(Formatter.inferType("He crosses the room."), .action)
        XCTAssertEqual(Formatter.inferType(""), .action)
    }

    func testPlaceKeyDropsExtensionAndTime() {
        XCTAssertEqual(Formatter.placeKey("INT. MARIGOLD - WHEELHOUSE - NIGHT"),
                       "INT. MARIGOLD")
        XCTAssertEqual(Formatter.placeKey("EXT. NORTH SEA - NIGHT"), "EXT. NORTH SEA")
        XCTAssertEqual(Formatter.placeKey("INT. HOUSE (BASEMENT) - DAY"), "INT. HOUSE")
    }

    func testPlaceRemainderIsTheSetAfterThePrefix() {
        XCTAssertEqual(Formatter.placeRemainder("INT. MARIGOLD - WHEELHOUSE - NIGHT"),
                       "MARIGOLD")
        XCTAssertNil(Formatter.placeRemainder("MARIGOLD - WHEELHOUSE"))
    }

    func testSceneTimeSuffix() {
        XCTAssertEqual(Formatter.sceneTimeSuffix("INT. ROOM - NIGHT"), " - NIGHT")
        XCTAssertEqual(Formatter.sceneTimeSuffix("INT. ROOM - CONTINUOUS"), " - CONTINUOUS")
        XCTAssertNil(Formatter.sceneTimeSuffix("INT. ROOM - night"))
        XCTAssertNil(Formatter.sceneTimeSuffix("INT. ROOM"))
    }
}

final class GhostRulesTests: XCTestCase {
    private let rules = GhostRules(names: ["ELIAS", "INGRID"], places: ["INT. ROOM", "EXT. STREET"])

    func testCharacterNameCompletion() {
        let line = Element(type: .character, text: "ELI")
        let ghost = rules.suggest(line: line, lines: [line])
        XCTAssertEqual(ghost, Ghost(text: "AS", kind: .character))
    }

    func testExactNameDoesNotSuggestItself() {
        let line = Element(type: .character, text: "ELIAS")
        XCTAssertNil(rules.suggest(line: line, lines: [line]))
    }

    func testScenePrefixCompletion() {
        var line = Element(type: .new, text: "IN")
        XCTAssertEqual(rules.suggest(line: line, lines: [line]),
                       Ghost(text: "T. ", kind: .scene))
        line.text = "EX"
        XCTAssertEqual(rules.suggest(line: line, lines: [line]),
                       Ghost(text: "T. ", kind: .scene))
    }

    func testPlaceCompletionOnlyOnARepeatedPlace() {
        let first = Element(type: .scene, text: "INT. ROOM - NIGHT")
        let second = Element(type: .scene, text: "INT. ROOM - DAY")
        let third = Element(type: .scene, text: "INT. R")
        XCTAssertEqual(rules.suggest(line: third, lines: [first, second]),
                       Ghost(text: "OOM", kind: .place))
    }

    func testNoPlaceCompletionForANewSet() {
        let first = Element(type: .scene, text: "INT. ROOM - NIGHT")
        let second = Element(type: .scene, text: "INT. HALL - DAY")
        XCTAssertNil(rules.suggest(line: second, lines: [first, second]))
    }
}

final class ScriptModelTests: XCTestCase {
    func testScriptCodableRoundTrip() throws {
        let script = Script(title: "Harrow Light", elements: [
            Element(type: .scene, text: "INT. MARIGOLD - WHEELHOUSE - NIGHT"),
            Element(type: .character, text: "ELIAS"),
            Element(type: .paren, text: "(quietly)"),
            Element(type: .dialogue, text: "Who else would be daft enough?"),
            Element(type: .transition, text: "CUT TO:")
        ])
        let data = try JSONEncoder().encode(script)
        let decoded = try JSONDecoder().decode(Script.self, from: data)
        XCTAssertEqual(decoded, script)
    }

    func testAnalysisCollectsCastPlacesAndSceneNumbers() {
        let elements = [
            Element(type: .scene, text: "INT. ROOM - NIGHT"),
            Element(type: .character, text: "ELIAS (V.O.)"),
            Element(type: .dialogue, text: "One."),
            Element(type: .scene, text: "EXT. STREET - DAY"),
            Element(type: .character, text: "INGRID"),
            Element(type: .dialogue, text: "Two."),
            Element(type: .character, text: "ELIAS"),
            Element(type: .dialogue, text: "Three.")
        ]
        let derived = ScriptAnalysis.derive(elements)
        XCTAssertEqual(derived.names, ["ELIAS", "INGRID"])
        XCTAssertEqual(derived.places, ["INT. ROOM", "EXT. STREET"])
        XCTAssertEqual(derived.sceneNo[elements[0].id], 1)
        XCTAssertEqual(derived.sceneNo[elements[3].id], 2)
        XCTAssertEqual(derived.speakerOf[elements[2].id], "ELIAS")
        XCTAssertEqual(derived.colours["ELIAS"], 0)
        XCTAssertEqual(derived.colours["INGRID"], 1)
        XCTAssertEqual(ScriptAnalysis.cueName("INGRID (V.O.)"), "INGRID")
    }

    func testNextElementJumpsFromCharacterToDialogueAndSceneToAction() {
        XCTAssertEqual(ElementType.character.next, .dialogue)
        XCTAssertEqual(ElementType.dialogue.next, .new)
        XCTAssertEqual(ElementType.scene.next, .action)
        XCTAssertEqual(ElementType.transition.next, .scene)
    }
}

final class PageMetricsTests: XCTestCase {
    func testLetterPageGeometry() {
        let metrics = PageMetrics(pageWidth: 850)
        XCTAssertEqual(metrics.inch, 100, accuracy: 0.001)
        XCTAssertEqual(metrics.scriptSize, 16.666, accuracy: 0.01)
        XCTAssertEqual(metrics.characterIndent, 369.75, accuracy: 0.01)
        XCTAssertEqual(metrics.dialogueIndent, 249.9, accuracy: 0.01)
        XCTAssertEqual(metrics.topPadding, 97.5, accuracy: 0.01)
    }

    func testScriptSizeHasAPracticalFloor() {
        XCTAssertEqual(PageMetrics(pageWidth: 400).scriptSize, 12.5, accuracy: 0.001)
    }

    func testLayoutBreaksAtTheDocumentedWidths() {
        XCTAssertTrue(SiteMath.isSingleColumn(860))
        XCTAssertFalse(SiteMath.isSingleColumn(861))
        XCTAssertTrue(SiteMath.isPhone(640))
        XCTAssertFalse(SiteMath.isPhone(641))
        XCTAssertEqual(SiteMath.content(1440), 1120)
        XCTAssertEqual(SiteMath.gutter(390), 16)
    }
}

final class UpdateVersionTests: XCTestCase {
    func testVersionParsingAcceptsTagsAndShortForms() {
        XCTAssertEqual(SemanticVersion("v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("1.2")?.description, "1.2.0")
        XCTAssertEqual(SemanticVersion("2")?.description, "2.0.0")
        XCTAssertEqual(SemanticVersion("v1.0.0-beta.2")?.description, "1.0.0-beta.2")
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("release"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
    }

    func testVersionOrdering() {
        XCTAssertTrue(UpdateSchedule.isNewer("v1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateSchedule.isNewer("v2.0.0", than: "1.99.99"))
        XCTAssertFalse(UpdateSchedule.isNewer("v1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateSchedule.isNewer("v1.0.0", than: "1.0.1"))
        XCTAssertTrue(UpdateSchedule.isNewer("v1.0.0", than: "1.0.0-beta.4"))
        XCTAssertTrue(UpdateSchedule.isNewer("v1.0.0-beta.4", than: "1.0.0-beta.2"))
    }

    func testAutomaticChecksAreMonthly() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(UpdateSchedule.shouldCheck(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateSchedule.shouldCheck(lastCheck: now.addingTimeInterval(-29 * 86_400), now: now))
        XCTAssertFalse(UpdateSchedule.shouldCheck(lastCheck: now.addingTimeInterval(-30 * 86_400 + 60), now: now))
        XCTAssertTrue(UpdateSchedule.shouldCheck(lastCheck: now.addingTimeInterval(-31 * 86_400), now: now))
    }
}
