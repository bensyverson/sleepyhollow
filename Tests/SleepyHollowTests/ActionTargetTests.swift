import Foundation
@testable import SleepyHollow
import Testing

/// `ActionTarget` and `DocumentPoint`: the addressing decision an act verb
/// makes before any page is touched, so the CLI holds none of it.
struct ActionTargetTests {
    @Test func `a point parses from the x,y form the other verbs report`() throws {
        let point = try DocumentPoint(parsing: " 620 , 180.5 ")
        #expect(point.x == 620)
        #expect(point.y == 180.5)
    }

    @Test func `a malformed point is a usage error naming the shape`() {
        for text in ["620", "620,180,4", "left,top", "", "620,"] {
            #expect(throws: SleepyError.self) {
                _ = try DocumentPoint(parsing: text)
            }
        }
    }

    @Test func `a negative point is a usage error: there is no document above or left of the origin`() {
        #expect(throws: SleepyError.self) {
            _ = try DocumentPoint(parsing: "-1,10")
        }
    }

    @Test func `a selector alone chooses the selector target`() throws {
        let target = try ActionTarget.clicking(selector: "#go", at: nil)
        #expect(target == .selector("#go"))
    }

    @Test func `a point alone chooses the point target`() throws {
        let target = try ActionTarget.clicking(selector: nil, at: "620,180")
        #expect(target == .point(DocumentPoint(x: 620, y: 180)))
    }

    @Test func `naming both is a usage error that says to pick one`() {
        do {
            _ = try ActionTarget.clicking(selector: "#go", at: "620,180")
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.description.contains("--selector"))
            #expect(error.description.contains("--at"))
        } catch {
            Issue.record("expected a SleepyError")
        }
    }

    @Test func `naming neither is a usage error that teaches both`() {
        do {
            _ = try ActionTarget.clicking(selector: nil, at: nil)
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.description.contains("--selector"))
            #expect(error.description.contains("--at"))
        } catch {
            Issue.record("expected a SleepyError")
        }
    }

    @Test func `a target describes itself the way the failure messages read`() {
        #expect(ActionTarget.selector("#go").description == "'#go'")
        #expect(ActionTarget.point(DocumentPoint(x: 620, y: 180)).description == "the point 620,180")
    }

    @Test func `a target at the head of a sentence reads as one`() {
        #expect(ActionTarget.selector("#go").sentenceDescription == "'#go'")
        #expect(ActionTarget.point(DocumentPoint(x: 620, y: 180)).sentenceDescription == "The point 620,180")
    }

    @Test func `a point click round-trips through the operation registry`() throws {
        var registry = OperationRegistry()
        registry.register(ClickOperation.self)
        let operation = ClickOperation(point: DocumentPoint(x: 620, y: 180))
        let decoded = try registry.decode(OperationEnvelope(operation)) as? ClickOperation
        #expect(decoded == operation)
    }
}
