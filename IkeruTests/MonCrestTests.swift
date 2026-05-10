import Testing
import SwiftUI
@testable import Ikeru

@Suite("MonCrest")
struct MonCrestTests {
    @Test("All four mon kinds render a non-empty path inside the bounds")
    func allKindsRender() {
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        for kind in MonKind.allCases {
            let path = MonCrestShape(kind: kind).path(in: rect)
            #expect(!path.isEmpty, "Mon \(kind) produced an empty path")
            #expect(rect.insetBy(dx: -1, dy: -1).contains(path.boundingRect),
                    "Mon \(kind) escapes its bounds")
        }
    }
}
