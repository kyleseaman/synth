import Foundation

/// Parsed HTTP/1.1 request — lightweight replacement for Vapor's Request type.
public struct HTTPRequest {
    public let method: String
    public let path: String
    public let httpVersion: String
    public let headers: HTTPHeaders
    public let body: Data?

    /// Parse raw HTTP/1.1 request data into a structured HTTPRequest.
    /// Returns nil if the data does not contain a valid HTTP request line.
    public static func parse(_ data: Data) -> HTTPRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        return parse(raw)
    }

    public static func parse(_ raw: String) -> HTTPRequest? {
        // Split headers from body at the blank line
        let headerBody = raw.split(
            separator: "\r\n\r\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard let headerSection = headerBody.first else { return nil }

        let headerLines = headerSection.split(separator: "\r\n")
        guard let requestLine = headerLines.first else { return nil }

        // Parse request line: METHOD PATH HTTP/VERSION
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])
        let version = parts.count > 2 ? String(parts[2]) : "HTTP/1.1"

        // Parse headers
        var headers = HTTPHeaders()
        for line in headerLines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                let name = pair[0].trimmingCharacters(in: .whitespaces)
                let value = pair[1].trimmingCharacters(in: .whitespaces)
                headers.add(name: name, value: value)
            }
        }

        // Extract body using Content-Length if available
        var body: Data?
        if headerBody.count > 1 {
            let bodyString = String(headerBody[1])
            if let contentLength = headers.first(name: "content-length"),
               let length = Int(contentLength) {
                // Respect Content-Length to avoid reading past the body
                let bodyData = bodyString.data(using: .utf8) ?? Data()
                body = bodyData.prefix(length)
            } else if !bodyString.isEmpty {
                body = bodyString.data(using: .utf8)
            }
        }

        return HTTPRequest(
            method: method,
            path: path,
            httpVersion: version,
            headers: headers,
            body: body
        )
    }
}

/// Case-insensitive HTTP header storage supporting multiple values per name.
public struct HTTPHeaders {
    private var storage: [(name: String, value: String)] = []

    public init() {}

    public mutating func add(name: String, value: String) {
        storage.append((name: name, value: value))
    }

    /// Returns the first value for the given header name (case-insensitive).
    public func first(name: String) -> String? {
        let lower = name.lowercased()
        return storage.first { $0.name.lowercased() == lower }?.value
    }

    /// Returns all values for the given header name (case-insensitive).
    public func all(name: String) -> [String] {
        let lower = name.lowercased()
        return storage.filter { $0.name.lowercased() == lower }.map(\.value)
    }

    public subscript(name: String) -> String? {
        first(name: name)
    }
}
