import XCTest
@testable import FocusTimer

final class DictationComposerTests: XCTestCase {
    func testStartsFromEmptyField() {
        var composer = DictationComposer()
        composer.begin(current:"")
        XCTAssertEqual(composer.compose("A"),"A")
    }

    func testAppendsToExistingText() {
        var composer = DictationComposer()
        composer.begin(current:"既存")
        XCTAssertEqual(composer.compose("A"),"既存 A")
    }

    func testAfterCommitOnlyNewSpeechIsUsed() {
        var composer = DictationComposer()
        composer.begin(current:"")
        XCTAssertEqual(composer.compose("A"),"A")
        composer.commit(recognized:"A")
        XCTAssertEqual(composer.compose("A"),"")
        XCTAssertEqual(composer.compose("A B"),"B")
        XCTAssertEqual(composer.compose("AB"),"B")
    }

    func testCommitClearsExistingBase() {
        var composer = DictationComposer()
        composer.begin(current:"既存")
        composer.commit(recognized:"A")
        XCTAssertEqual(composer.compose("A B"),"B")
    }

    func testCommitsCanRepeat() {
        var composer = DictationComposer()
        composer.begin(current:"")
        composer.commit(recognized:"A")
        XCTAssertEqual(composer.compose("A B"),"B")
        composer.commit(recognized:"A B")
        XCTAssertEqual(composer.compose("A B C"),"C")
    }

    func testRevisedEarlierTextDropsCommittedLength() {
        var composer = DictationComposer()
        composer.begin(current:"")
        composer.commit(recognized:"あい")
        XCTAssertEqual(composer.compose("愛うえ"),"え")
    }

    func testBeginResetsCommitted() {
        var composer = DictationComposer()
        composer.begin(current:"")
        composer.commit(recognized:"A")
        composer.begin(current:"")
        XCTAssertEqual(composer.compose("C"),"C")
    }
}
