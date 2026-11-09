// Minimal in-process XCTest runner, used by script/test.sh when
// `swift test` can't launch Xcode's xctest agent (unaccepted Xcode
// license, or an agent AMFI refuses to run). Finds XCTestCase subclasses
// in the bundle's image and runs them, optionally filtered by name.
import Foundation
import ObjectiveC
import XCTest

guard CommandLine.arguments.count >= 2, let bundle = Bundle(path: CommandLine.arguments[1]), bundle.load(),
      let image = bundle.executablePath else {
    FileHandle.standardError.write("usage: testrunner <path/to/Tests.xctest> [filter]\n".data(using: .utf8)!)
    exit(2)
}
let filter = CommandLine.arguments.count >= 3 && !CommandLine.arguments[2].isEmpty ? CommandLine.arguments[2] : nil

var count: UInt32 = 0
let suite = XCTestSuite(name: bundle.bundleURL.lastPathComponent)
if let names = objc_copyClassNamesForImage(image, &count) {
    let classNames = (0..<Int(count)).map { String(cString: names[$0]) }.sorted()
    free(names)
    for name in classNames {
        guard let cls = NSClassFromString(name) as? XCTestCase.Type else { continue }
        let caseSuite = cls.defaultTestSuite
        if let filter {
            let filtered = XCTestSuite(name: caseSuite.name)
            caseSuite.tests.filter { $0.name.contains(filter) }.forEach(filtered.addTest)
            if filtered.testCaseCount > 0 { suite.addTest(filtered) }
        } else {
            suite.addTest(caseSuite)
        }
    }
}
suite.run()
exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
