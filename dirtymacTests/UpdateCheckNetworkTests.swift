import XCTest
@testable import dirtymac

/// Answers every request from a closure instead of the network.
nonisolated final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        handler = nil
        seen = []
    }
}

/// The one request dirtymac can make, run against a stand-in server.
final class UpdateCheckNetworkTests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func respond(status: Int, body: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    // MARK: Replies

    func testReadsTheVersionFromAGoodReply() async throws {
        respond(status: 200, body: #"{"tag_name":"v1.5.0"}"#)
        let version = try await UpdateCheck.fetchLatestVersion(session: session())
        XCTAssertEqual(version, "1.5.0")
    }

    func testAnythingButOKIsAFailure() async {
        for status in [301, 304, 403, 404, 429, 500, 503] {
            respond(status: status, body: #"{"tag_name":"v9.9.9"}"#)
            do {
                _ = try await UpdateCheck.fetchLatestVersion(session: session())
                XCTFail("status \(status) should fail")
            } catch let error as UpdateCheck.CheckError {
                XCTAssertEqual(error, .badStatus, "status \(status)")
            } catch {
                XCTFail("status \(status): \(error)")
            }
        }
    }

    func testAnUnreadableReplyIsAFailure() async {
        for body in ["", "<html>captive portal</html>", #"{"tag_name":"latest"}"#, #"{"tag_name":"v1.5.0-beta"}"#, "{}"] {
            respond(status: 200, body: body)
            do {
                _ = try await UpdateCheck.fetchLatestVersion(session: session())
                XCTFail("\(body.debugDescription) should fail")
            } catch let error as UpdateCheck.CheckError {
                XCTAssertEqual(error, .badBody, body.debugDescription)
            } catch {
                XCTFail("\(body.debugDescription): \(error)")
            }
        }
    }

    func testNoConnectionIsAFailure() async {
        StubURLProtocol.handler = nil   // the stub then reports "not connected"
        do {
            _ = try await UpdateCheck.fetchLatestVersion(session: session())
            XCTFail("should fail offline")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("\(error)")
        }
    }

    // MARK: What goes out

    func testTheRequestCarriesNothingAboutTheUser() async throws {
        respond(status: 200, body: #"{"tag_name":"v1.5.0"}"#)
        _ = try await UpdateCheck.fetchLatestVersion(session: session())

        XCTAssertEqual(StubURLProtocol.seen.count, 1, "exactly one request")
        let request = try XCTUnwrap(StubURLProtocol.seen.first)
        XCTAssertEqual(request.url, UpdateCheck.latestReleaseAPI)
        XCTAssertNil(request.url?.query)
        XCTAssertTrue(request.httpMethod == nil || request.httpMethod == "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
        XCTAssertEqual(request.timeoutInterval, 10)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "dirtymac-update-check")
        let headers = request.allHTTPHeaderFields ?? [:]
        for forbidden in ["Cookie", "Authorization", "Referer", "X-Forwarded-For", "X-Client-Id", "X-Device-Id"] {
            XCTAssertNil(headers[forbidden], "\(forbidden) must not be sent")
        }
        // The User-Agent must not leak the version or the Mac either.
        let agent = headers["User-Agent"] ?? ""
        XCTAssertFalse(agent.contains(WhatsNew.currentVersion))
        XCTAssertFalse(agent.lowercased().contains("macos"))
        XCTAssertFalse(agent.lowercased().contains("darwin"))
    }

    func testTheSessionKeepsNothingBetweenRequests() {
        let session = UpdateCheck.makeSession()
        let configuration = session.configuration
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    // MARK: Through the model

    @MainActor
    func testTheModelWorksEndToEndOnTheRealRequestCode() async throws {
        respond(status: 200, body: #"{"tag_name":"v7.0.0"}"#)
        let defaults = try TestDefaults.make(self)
        let session = session()
        let checker = UpdateChecker(
            defaults: defaults,
            currentVersion: "1.4.0",
            fetch: { try await UpdateCheck.fetchLatestVersion(session: session) }
        )
        checker.setEnabled(true)
        await checker.pendingCheck?.value
        XCTAssertEqual(checker.notice, .available("7.0.0"))
        XCTAssertEqual(StubURLProtocol.seen.count, 1)
    }

    @MainActor
    func testTheModelStaysOffTheNetworkWhileChecksAreOff() async throws {
        respond(status: 200, body: #"{"tag_name":"v7.0.0"}"#)
        let session = session()
        let checker = UpdateChecker(
            defaults: try TestDefaults.make(self),
            currentVersion: "1.4.0",
            fetch: { try await UpdateCheck.fetchLatestVersion(session: session) }
        )
        checker.start()
        checker.tick()
        await checker.check()
        XCTAssertEqual(StubURLProtocol.seen.count, 0)
    }

    // MARK: The promise, enforced

    /// "No network access unless you turn on update checks": the only
    /// source file allowed to speak to the network is UpdateCheck.swift,
    /// where every request is gated by the user's consent. A new file
    /// that opens a connection fails this test until it is reviewed.
    func testOnlyTheUpdateCheckTouchesTheNetwork() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dirtymac")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 10, "found the sources")

        let networkTokens = [
            "URLSession", "URLRequest", "NSURLConnection", "NWConnection", "NWPathMonitor",
            "CFSocket", "CFStream", "WKWebView", "WebKit", "Network.framework", "import Network",
            "URLSessionWebSocketTask", "MultipeerConnectivity", "NetService",
        ]
        var offenders: [String] = []
        for file in files where file.lastPathComponent != "UpdateCheck.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in networkTokens where text.contains(token) {
                offenders.append("\(file.lastPathComponent): \(token)")
            }
        }
        XCTAssertEqual(offenders, [], "network use outside UpdateCheck.swift")
    }

    /// Everything inside UpdateCheck.swift that could send a request is
    /// the one function the model calls only after consent.
    func testTheRequestFunctionIsCalledOnlyFromTheModel() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dirtymac")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        var callers: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("fetchLatestVersion(") { callers.append(file.lastPathComponent) }
        }
        XCTAssertEqual(callers.sorted(), ["UpdateCheck.swift", "UpdateChecker.swift"])
    }
}
