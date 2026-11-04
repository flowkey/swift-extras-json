import ExtrasJSON
import XCTest

class JSONValueConversionTests: XCTestCase {
    private enum Hand: String, JSONValueCodable {
        case left, right
    }

    private struct Note: JSONValueCodable, Equatable {
        var pitch: UInt8
        var duration: Double
        var hand: Hand?

        init(pitch: UInt8, duration: Double, hand: Hand?) {
            self.pitch = pitch
            self.duration = duration
            self.hand = hand
        }

        init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
            pitch = try jsonValue.member("pitch")
            duration = try jsonValue.member("duration")
            hand = try jsonValue.memberIfPresent("hand")
        }

        var jsonValue: JSONValue {
            ["pitch": pitch.jsonValue, "duration": duration.jsonValue, "hand": hand.jsonValue]
        }
    }

    func testDecodesNestedMembers() throws {
        let notes = try [Note](jsonData: Array(#"[{"pitch": 60, "duration": 0.5, "hand": "left"}, {"pitch": 62, "duration": 1}]"#.utf8))
        XCTAssertEqual(notes, [Note(pitch: 60, duration: 0.5, hand: .left), Note(pitch: 62, duration: 1, hand: nil)])
    }

    func testRoundTripsThroughJSONValue() throws {
        let note = Note(pitch: 64, duration: 0.25, hand: .right)
        XCTAssertEqual(try Note(jsonValue: note.jsonValue), note)
    }

    func testFailureNamesThePathOfTheBadValue() {
        let json: JSONValue = ["notes": [["pitch": 60, "duration": 1], ["pitch": "C4", "duration": 1]]]
        XCTAssertThrowsError(try json.member("notes", as: [Note].self)) { error in
            XCTAssertEqual(error as? JSONValueDecodingFailure, .typeMismatch(expected: "a number", path: ".notes[1].pitch"))
        }
    }

    func testMissingMemberAndUnknownRawValue() {
        let json: JSONValue = ["pitch": 60, "hand": "both"]
        XCTAssertThrowsError(try Note(jsonValue: json)) { error in
            XCTAssertEqual(error as? JSONValueDecodingFailure, .missingMember(path: ".duration"))
        }
        XCTAssertThrowsError(try json.member("hand", as: Hand.self)) { error in
            XCTAssertEqual(error as? JSONValueDecodingFailure, .unknownRawValue(path: ".hand"))
        }
    }

    func testIntegersRejectFractions() {
        XCTAssertThrowsError(try Int(jsonValue: 1.5))
        XCTAssertEqual(try Int(jsonValue: 3), 3)
    }
}
