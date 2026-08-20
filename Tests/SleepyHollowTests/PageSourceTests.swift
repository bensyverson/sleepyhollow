import Foundation
@testable import SleepyHollow
import Testing

/// Every page verb takes exactly one page source: a URL or a named session.
struct PageSourceTests {
    @Test func `url source survives JSON transport`() throws {
        let source = try PageSource.url(#require(URL(string: "http://localhost:8080/fixture.html")))
        let data: Data = try JSONEncoder().encode(source)
        let decoded: PageSource = try JSONDecoder().decode(PageSource.self, from: data)
        #expect(decoded == source)
    }

    @Test func `session source survives JSON transport`() throws {
        let name = try #require(SessionName("login-flow"))
        let source = PageSource.session(name)
        let data: Data = try JSONEncoder().encode(source)
        let decoded: PageSource = try JSONDecoder().decode(PageSource.self, from: data)
        #expect(decoded == source)
    }
}
