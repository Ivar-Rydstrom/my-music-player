import XCTest
@testable import PlayerCore

final class ArtworkRetryTests: XCTestCase {
    actor Responses {
        var calls = 0
        var remainingMisses: Int
        init(misses: Int) { remainingMisses = misses }
        func next() -> Data? {
            calls += 1
            if remainingMisses > 0 { remainingMisses -= 1; return nil }
            return Data("artwork".utf8)
        }
    }

    func testVisibleRequestRecoversWithoutChangingURLOrRecreatingRow() async {
        let responses = Responses(misses: 2)
        let data = await ArtworkRetry.load(delays: [.seconds(1), .seconds(3)],
            attempt: { await responses.next() }, sleep: { _ in })
        XCTAssertEqual(data, Data("artwork".utf8))
        let calls = await responses.calls
        XCTAssertEqual(calls, 3)
    }

    func testSuccessfulRequestDoesNotRetry() async {
        let responses = Responses(misses: 0)
        _ = await ArtworkRetry.load(attempt: { await responses.next() }, sleep: { _ in
            XCTFail("A successful request must not delay")
        })
        let calls = await responses.calls
        XCTAssertEqual(calls, 1)
    }

    func testMissingArtworkHasBoundedRetries() async {
        let responses = Responses(misses: 100)
        let data = await ArtworkRetry.load(delays: [.seconds(1)],
            attempt: { await responses.next() }, sleep: { _ in })
        XCTAssertNil(data)
        let calls = await responses.calls
        XCTAssertEqual(calls, 2)
    }

    func testCancelledRowStopsRetrying() async {
        let responses = Responses(misses: 100)
        let started = expectation(description: "First attempt started")
        let task = Task {
            await ArtworkRetry.load(delays: [.seconds(60)], attempt: {
                let data = await responses.next()
                started.fulfill()
                return data
            })
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        let data = await task.value
        XCTAssertNil(data)
        let calls = await responses.calls
        XCTAssertEqual(calls, 1)
    }
}
