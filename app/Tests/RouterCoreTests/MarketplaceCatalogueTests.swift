import Foundation
import Testing
@testable import RouterCore

/// F6 — reading a marketplace descriptor into the offers it makes.
@Suite("F6 — the catalogue")
struct MarketplaceCatalogueTests {
    @Test("C1 — offers are read with their versions, and the versionless ones are counted")
    func reads() {
        let catalogue = MarketplaceCatalogue.read(text: """
        {"name":"mkt","plugins":[
          {"name":"a","version":"1.0.0"},
          {"name":"b"},
          {"name":"c","version":""}
        ]}
        """)
        #expect(catalogue?.offers.count == 3)
        #expect(catalogue?.offer(named: "a")?.version == "1.0.0")
        // An empty string is not a version. Left as-is it would compare unequal to everything and
        // report an update against a catalogue that declared nothing.
        #expect(catalogue?.offer(named: "c")?.version == nil)
        #expect(catalogue?.declaredNoVersion == 2)
        #expect(catalogue?.offer(named: "missing") == nil)
    }

    /// One malformed offer among 291 must not take the other 290 with it. The skipped offer
    /// surfaces as `notOffered` for whatever names it, which is a stated verdict rather than a
    /// silent absence.
    @Test("C2 — an offer with no name is skipped and the rest survive")
    func skipsNameless() {
        let catalogue = MarketplaceCatalogue.read(text: """
        {"name":"mkt","plugins":[{"version":"1.0.0"},{"name":"","version":"2.0.0"},{"name":"c"}]}
        """)
        #expect(catalogue?.offers.count == 1)
        #expect(catalogue?.offer(named: "c") != nil)
    }

    @Test(
        "C3 — what is not a catalogue",
        arguments: [
            "", "not json", "[]", "\"string\"", "{\"name\":\"mkt\"}",
            "{\"name\":\"mkt\",\"plugins\":{}}", "{\"name\":\"mkt\",\"plugins\":\"none\"}"
        ]
    )
    func refused(text: String) {
        #expect(MarketplaceCatalogue.read(text: text) == nil)
    }

    /// The shape measured on this machine: the largest catalogue declares 291 plugins and versions
    /// 14 of them. A catalogue of 291 that reads as a catalogue of 14 is the failure the count
    /// exists to prevent.
    @Test("C4 — an empty plugins array is a catalogue of zero, not a failure to read one")
    func emptyIsACatalogue() {
        let catalogue = MarketplaceCatalogue.read(text: #"{"name":"mkt","plugins":[]}"#)
        #expect(catalogue != nil)
        #expect(catalogue?.offers.isEmpty == true)
        #expect(catalogue?.declaredNoVersion == 0)
    }
}
