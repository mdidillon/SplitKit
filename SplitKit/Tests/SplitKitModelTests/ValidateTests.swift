import Foundation
import Testing
@testable import SplitKitModel

@Suite("§6.1 validate")
struct ValidateTests {
    @Test func validSessionsHaveNoViolations() {
        #expect(SessionEngine.validate(Session()).isEmpty, "zero windows is valid")
        #expect(SessionEngine.validate(session(mainWindow(1, nil))).isEmpty)
        #expect(SessionEngine.validate(twoWindows).isEmpty)
        #expect(SessionEngine.validate(session(mainWindow(1, h(1, [p(1, 1), v(2, [p(2), p(3, 3)])]), active: 2, focus: 3),
                                               detachedWindow(2, p(4, 4)), detachedWindow(3, p(5, 5)))).isEmpty)
    }

    @Test("Each violation is detected", arguments: ViolationCase.all)
    func detects(c: ViolationCase) {
        #expect(SessionEngine.validate(c.input).contains(c.violation), "\(SessionEngine.validate(c.input))")
        #expect(c.violation.isFatal == c.fatal)
    }

    @Test func violationsAreListedInAFixedOrder() {
        let s = Session(windows: [mainWindow(1, h(1, [p(1, 1), p(1, 1)]), active: 9), mainWindow(1, nil)],
                        contents: [record(cid(1)), record(cid(1)), record(cid(2))])
        #expect(SessionEngine.validate(s) == [
            .multipleMainWindows, .duplicatePaneID(pid(1)), .danglingActivePane(wid(1)), .duplicateWindowID(wid(1)),
            .duplicateContentID(cid(1)), .duplicateRecord(cid(1)), .orphanRecord(cid(2)),
        ])
    }
}

struct ViolationCase: Sendable, CustomTestStringConvertible {
    var violation: InvariantViolation
    var fatal: Bool
    var input: Session
    var testDescription: String { "\(violation)" }

    init(violation: InvariantViolation, fatal: Bool, session: Session) {
        self.violation = violation
        self.fatal = fatal
        input = session
    }

    static let all: [ViolationCase] = [
        ViolationCase(violation: .duplicatePaneID(pid(1)), fatal: true,
                      session: session(mainWindow(1, h(1, [p(1, 1), p(1, 2)])))),
        ViolationCase(violation: .duplicatePaneID(pid(1)), fatal: true,
                      session: session(mainWindow(1, p(1, 1)), detachedWindow(2, p(1, 2)))),
        ViolationCase(violation: .duplicateSplitID(sid(1)), fatal: true,
                      session: session(mainWindow(1, h(1, [p(1, 1), v(1, [p(2, 2), p(3, 3)])])))),
        ViolationCase(violation: .duplicateWindowID(wid(1)), fatal: true,
                      session: session(mainWindow(1, p(1, 1)), detachedWindow(1, p(2, 2)))),
        ViolationCase(violation: .duplicateContentID(cid(1)), fatal: true,
                      session: Session(windows: [mainWindow(1, h(1, [p(1, 1), p(2, 1)]))], contents: [record(cid(1))])),
        ViolationCase(violation: .duplicateRecord(cid(1)), fatal: true,
                      session: Session(windows: [mainWindow(1, p(1, 1))], contents: [record(cid(1)), record(cid(1))])),
        ViolationCase(violation: .missingContentRecord(cid(1)), fatal: true,
                      session: Session(windows: [mainWindow(1, p(1, 1))], contents: [])),
        ViolationCase(violation: .singleChildSplit(sid(1)), fatal: true,
                      session: session(mainWindow(1, .split(id: sid(1), axis: .horizontal, children: [p(1, 1)], fractions: [1])))),
        ViolationCase(violation: .singleChildSplit(sid(1)), fatal: true,
                      session: session(mainWindow(1, .split(id: sid(1), axis: .horizontal, children: [], fractions: [])))),
        ViolationCase(violation: .fractionCountMismatch(sid(1)), fatal: true,
                      session: session(mainWindow(1, h(1, [p(1, 1), p(2, 2)], [1])))),
        ViolationCase(violation: .badFractions(sid(1)), fatal: true,
                      session: session(mainWindow(1, h(1, [p(1, 1), p(2, 2)], [0.5, 0.6])))),
        ViolationCase(violation: .badFractions(sid(1)), fatal: true,
                      session: session(mainWindow(1, h(1, [p(1, 1), p(2, 2)], [1.5, -0.5])))),
        ViolationCase(violation: .badFractions(sid(1)), fatal: true,
                      session: session(mainWindow(1, h(1, [p(1, 1), p(2, 2)], [.nan, 0.5])))),
        ViolationCase(violation: .badFractions(sid(1)), fatal: true,
                      session: session(mainWindow(1, h(1, [p(1, 1), p(2, 2)], [0.5 + 2e-9, 0.5])))),
        ViolationCase(violation: .sameAxisNesting(sid(2)), fatal: true,
                      session: session(mainWindow(1, h(1, [p(1, 1), h(2, [p(2, 2), p(3, 3)])])))),
        ViolationCase(violation: .nilRootInDetachedWindow(wid(2)), fatal: true,
                      session: session(mainWindow(1, p(1, 1)), detachedWindow(2, nil))),
        ViolationCase(violation: .detachedWindowWithoutContent(wid(2)), fatal: true,
                      session: session(mainWindow(1, p(1, 1)), detachedWindow(2, v(2, [p(2), p(3)])))),
        ViolationCase(violation: .multipleMainWindows, fatal: true,
                      session: session(mainWindow(1, p(1, 1)), mainWindow(2, nil))),
        ViolationCase(violation: .orphanRecord(cid(9)), fatal: false,
                      session: Session(windows: [mainWindow(1, p(1, 1))], contents: [record(cid(1)), record(cid(9))])),
        ViolationCase(violation: .danglingActivePane(wid(1)), fatal: false,
                      session: session(mainWindow(1, p(1, 1), active: 2))),
        ViolationCase(violation: .danglingActivePane(wid(1)), fatal: false,
                      session: session(mainWindow(1, nil, active: 1))),
        ViolationCase(violation: .danglingActivePane(wid(1)), fatal: false,
                      session: session(detachedWindow(2, p(2, 2)), mainWindow(1, p(1, 1), active: 2))),  // pane of another window
        ViolationCase(violation: .danglingFocusModePane(wid(1)), fatal: false,
                      session: session(mainWindow(1, p(1, 1), focus: 2))),
    ]
}
