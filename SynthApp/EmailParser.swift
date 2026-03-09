import Foundation

// MARK: - Parsed Email

struct ParsedEmail {
    let subject: String
    let sender: String
    let date: String
    let body: String
}

// MARK: - Email Parser

enum EmailParser {
    static func parse(emlContent: String) -> ParsedEmail {
        let headerBodyParts = splitHeadersAndBody(emlContent)
        let headers = parseHeaders(headerBodyParts.headers)

        let subject = headers["subject"] ?? ""
        let sender = headers["from"] ?? ""
        let date = headers["date"] ?? ""
        let contentType = headers["content-type"] ?? ""

        let rawBody = headerBodyParts.body
        let body = extractPlainTextBody(
            rawBody: rawBody,
            contentType: contentType
        )

        return ParsedEmail(
            subject: subject.trimmingCharacters(in: .whitespaces),
            sender: sender.trimmingCharacters(in: .whitespaces),
            date: date.trimmingCharacters(in: .whitespaces),
            body: body.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }

    // MARK: - Header / Body Splitting

    private static func splitHeadersAndBody(
        _ content: String
    ) -> (headers: String, body: String) {
        // RFC 2822: headers end at the first blank line
        let separators = ["\r\n\r\n", "\n\n"]
        for separator in separators {
            if let range = content.range(of: separator) {
                let headers = String(content[content.startIndex..<range.lowerBound])
                let body = String(content[range.upperBound...])
                return (headers, body)
            }
        }
        // No blank line found means the entire content is headers
        return (content, "")
    }

    // MARK: - Header Parsing

    private static func parseHeaders(
        _ headerBlock: String
    ) -> [String: String] {
        var headers: [String: String] = [:]
        var currentKey = ""
        var currentValue = ""

        let lines = headerBlock.components(separatedBy: .newlines)
        for line in lines {
            if line.isEmpty {
                continue
            }
            // Continuation line: starts with whitespace (folded header)
            let firstChar = line.first
            if firstChar == " " || firstChar == "\t" {
                if !currentKey.isEmpty {
                    currentValue += " " + line.trimmingCharacters(
                        in: .whitespaces
                    )
                }
                continue
            }
            // Save previous header if we have one
            if !currentKey.isEmpty {
                headers[currentKey] = currentValue
            }
            // Parse new header line
            if let colonIndex = line.firstIndex(of: ":") {
                currentKey = String(
                    line[line.startIndex..<colonIndex]
                ).lowercased().trimmingCharacters(in: .whitespaces)
                let valueStart = line.index(after: colonIndex)
                currentValue = String(
                    line[valueStart...]
                ).trimmingCharacters(in: .whitespaces)
            } else {
                currentKey = ""
                currentValue = ""
            }
        }
        // Save last header
        if !currentKey.isEmpty {
            headers[currentKey] = currentValue
        }

        return headers
    }

    // MARK: - Body Extraction

    private static func extractPlainTextBody(
        rawBody: String,
        contentType: String
    ) -> String {
        let boundary = extractBoundary(from: contentType)
        guard let boundary = boundary else {
            // Single-part email: body is the plain text
            return rawBody
        }

        return extractTextPlainFromMultipart(
            rawBody: rawBody,
            boundary: boundary
        )
    }

    private static func extractBoundary(
        from contentType: String
    ) -> String? {
        // Look for boundary="..." or boundary=...
        guard contentType.lowercased().contains("multipart") else {
            return nil
        }
        let components = contentType.components(separatedBy: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("boundary") {
                if let equalsIndex = trimmed.firstIndex(of: "=") {
                    var value = String(
                        trimmed[trimmed.index(after: equalsIndex)...]
                    ).trimmingCharacters(in: .whitespaces)
                    // Remove surrounding quotes if present
                    if value.hasPrefix("\"") && value.hasSuffix("\"") {
                        value = String(value.dropFirst().dropLast())
                    }
                    return value
                }
            }
        }
        return nil
    }

    private static func extractTextPlainFromMultipart(
        rawBody: String,
        boundary: String
    ) -> String {
        let delimiter = "--" + boundary
        let parts = rawBody.components(separatedBy: delimiter)

        for part in parts {
            let partContent = part.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            // Skip the closing boundary marker
            if partContent.hasPrefix("--") {
                continue
            }
            if partContent.isEmpty {
                continue
            }

            let partSplit = splitHeadersAndBody(partContent)
            let partHeaders = parseHeaders(partSplit.headers)
            let partContentType = partHeaders["content-type"] ?? ""

            if partContentType.lowercased().contains("text/plain") {
                return partSplit.body
            }
        }

        // Fallback: if no text/plain part found, return empty
        return ""
    }
}
