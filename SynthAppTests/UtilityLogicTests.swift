import XCTest
import Darwin
import AppKit
@testable import Synth

final class UtilityLogicTests: XCTestCase {
    func testAnyCodableEncodesAndDecodesNestedValues() throws {
        let payload: [String: AnyCodable] = [
            "text": AnyCodable("value"),
            "count": AnyCodable(12),
            "enabled": AnyCodable(true),
            "items": AnyCodable([AnyCodable("first"), AnyCodable(2)]),
            "dict": AnyCodable(["inner": AnyCodable(99)])
        ]

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["text"]?.stringValue, "value")
        XCTAssertEqual(decoded["count"]?.intValue, 12)
        XCTAssertEqual(decoded["enabled"]?.value as? Bool, true)
        XCTAssertEqual(decoded["items"]?.arrayValue?.count, 2)
        XCTAssertEqual(decoded["dict"]?.dictValue?["inner"]?.intValue, 99)
    }

    func testAnyCodableDecodesNullAsNSNull() throws {
        let data = Data("{\"value\":null}".utf8)

        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertTrue(decoded["value"]?.value is NSNull)
    }

    func testJsonRpcRequestInitializerSetsDefaultProtocol() {
        let request = JsonRpcRequest(id: 7, method: "session/new")

        XCTAssertEqual(request.jsonrpc, "2.0")
        XCTAssertEqual(request.id, 7)
        XCTAssertEqual(request.method, "session/new")
        XCTAssertNil(request.params)
    }

    func testStringFuzzyScoreAndTitleCase() {
        XCTAssertEqual("hello world".titleCased, "Hello World")
        XCTAssertEqual("Alpha".fuzzyScore("alpha"), 10000)

        let prefixScore = "alphabet".fuzzyScore("alp")
        let containsScore = "my alphabet".fuzzyScore("alp")

        XCTAssertNotNil(prefixScore)
        XCTAssertNotNil(containsScore)
        XCTAssertTrue((prefixScore ?? 0) > (containsScore ?? 0))
        XCTAssertNil("swift".fuzzyScore("xyz"))
    }

    @MainActor
    func testFlattenFilesReturnsAllNestedFileNodes() {
        let firstFile = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/first.md"),
            isDirectory: false,
            children: nil
        )
        let nestedFile = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/folder/nested.md"),
            isDirectory: false,
            children: nil
        )
        let folderNode = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/folder"),
            isDirectory: true,
            children: [nestedFile]
        )

        let flattened = FileLauncher.flattenFiles([firstFile, folderNode])

        XCTAssertEqual(flattened.map { $0.url.path }, [firstFile.url.path, nestedFile.url.path])
    }

    func testFileTreeNodeEqualityReflectsChildTreeChanges() {
        let firstChild = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/folder/first.md"),
            isDirectory: false,
            children: nil
        )
        let secondChild = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/folder/second.md"),
            isDirectory: false,
            children: nil
        )
        let firstParent = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/folder"),
            isDirectory: true,
            children: [firstChild]
        )
        let secondParent = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/folder"),
            isDirectory: true,
            children: [secondChild]
        )

        XCTAssertNotEqual(firstParent, secondParent)
    }

    @MainActor
    func testFallbackFileResultsIncludesSearchableNoteWhenSemanticMisses() {
        let noteNode = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/Project Roadmap.md"),
            isDirectory: false,
            children: nil
        )
        let imageNode = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/diagram.png"),
            isDirectory: false,
            children: nil
        )
        let recentURLs: Set<URL> = [noteNode.url]

        let results = FileLauncher.fallbackFileResults(
            from: [noteNode, imageNode],
            query: "road",
            noteURLs: [],
            recentFiles: recentURLs
        )

        XCTAssertEqual(results.count, 1)
        guard case .file(let matchedNode, let scoreValue) = results[0] else {
            XCTFail("Expected a file result")
            return
        }
        XCTAssertEqual(matchedNode.url.path, noteNode.url.path)
        XCTAssertGreaterThan(scoreValue, 2000)
    }

    @MainActor
    func testFallbackFileResultsSkipsSemanticNoteURLs() {
        let noteNode = FileTreeNode(
            url: URL(fileURLWithPath: "/tmp/Project Roadmap.md"),
            isDirectory: false,
            children: nil
        )

        let results = FileLauncher.fallbackFileResults(
            from: [noteNode],
            query: "road",
            noteURLs: [noteNode.url],
            recentFiles: []
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testMediaManagerRelativePathAndResolvedURL() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/project/notes/", isDirectory: true)
        let destinationURL = URL(fileURLWithPath: "/tmp/project/media/image.png")

        let relativePath = MediaManager.relativePath(from: baseDirectory, to: destinationURL)

        XCTAssertEqual(relativePath, "../media/image.png")

        let resolvedRelative = MediaManager.resolvedImageURL(
            from: "../media/image.png",
            baseDirectoryURL: baseDirectory
        )
        let resolvedAbsolute = MediaManager.resolvedImageURL(
            from: "https://example.com/image.png",
            baseDirectoryURL: baseDirectory
        )

        XCTAssertEqual(resolvedRelative?.standardizedFileURL.path, destinationURL.standardizedFileURL.path)
        XCTAssertEqual(resolvedAbsolute?.absoluteString, "https://example.com/image.png")
    }

    func testMediaManagerScreenshotURLsFiltersAndSortsByModifiedDate() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let mediaDirectory = rootDirectory.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        let oldFileURL = mediaDirectory.appendingPathComponent("screenshot-old.png")
        let newFileURL = mediaDirectory.appendingPathComponent("screenshot-new.jpg")
        let ignoredFileURL = mediaDirectory.appendingPathComponent("other.png")
        let unsupportedURL = mediaDirectory.appendingPathComponent("screenshot-note.txt")

        try Data("old".utf8).write(to: oldFileURL)
        try Data("new".utf8).write(to: newFileURL)
        try Data("skip".utf8).write(to: ignoredFileURL)
        try Data("text".utf8).write(to: unsupportedURL)

        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldFileURL.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: newFileURL.path)

        let screenshotURLs = MediaManager.screenshotURLs(in: rootDirectory)

        XCTAssertEqual(
            screenshotURLs.map { $0.standardizedFileURL.path },
            [newFileURL, oldFileURL].map { $0.standardizedFileURL.path }
        )
        XCTAssertTrue(MediaManager.isSupportedImageFile(newFileURL))
        XCTAssertFalse(MediaManager.isSupportedImageFile(unsupportedURL))
    }

    func testKiroCliResolverPrefersConfiguredExecutablePath() throws {
        let keyName = "kiroCliPath"
        let originalPath = UserDefaults.standard.string(forKey: keyName)
        defer {
            if let originalPath {
                UserDefaults.standard.set(originalPath, forKey: keyName)
            } else {
                UserDefaults.standard.removeObject(forKey: keyName)
            }
        }

        let executableURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        UserDefaults.standard.set(executableURL.path, forKey: keyName)

        XCTAssertEqual(KiroCliResolver.resolve(), executableURL.path)
    }

    func testSynthMcpResolverDevelopmentBuildCandidatePathsIncludeSourceRoot() {
        let bundleURL = URL(fileURLWithPath: "/tmp/DerivedData/Build/Products/Debug/Synth.app")
        let sourceFilePath = "/tmp/workspace/synth/SynthApp/SynthMcpResolver.swift"
        let currentDirectoryPath = "/tmp/other/location"

        let candidatePaths = SynthMcpResolver.developmentBuildCandidatePaths(
            bundleURL: bundleURL,
            sourceFilePath: sourceFilePath,
            currentDirectoryPath: currentDirectoryPath
        )

        XCTAssertTrue(
            candidatePaths.contains("/tmp/workspace/synth/synth-mcp-server/.build/release/synth-mcp-server")
        )
        XCTAssertTrue(
            candidatePaths.contains("/tmp/workspace/synth/synth-mcp-server/.build/debug/synth-mcp-server")
        )
    }

    func testSynthMcpResolverFirstExecutablePathReturnsFirstMatch() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let firstCandidateURL = rootDirectory.appendingPathComponent("first")
        let secondCandidateURL = rootDirectory.appendingPathComponent("second")

        try "#!/bin/sh\nexit 0\n".write(to: secondCandidateURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: secondCandidateURL.path
        )

        let foundPath = SynthMcpResolver.firstExecutablePath(
            in: [firstCandidateURL.path, secondCandidateURL.path]
        )

        XCTAssertEqual(foundPath, secondCandidateURL.path)
    }

    func testACPClientLocationPathsParsesUniqueFilePaths() {
        let update: [String: AnyCodable] = [
            "locations": AnyCodable([
                AnyCodable([
                    "path": AnyCodable("/tmp/one.md"),
                    "line": AnyCodable(3)
                ]),
                AnyCodable([
                    "path": AnyCodable("/tmp/two.md"),
                    "line": AnyCodable(8)
                ]),
                AnyCodable([
                    "path": AnyCodable("/tmp/one.md"),
                    "line": AnyCodable(12)
                ]),
                AnyCodable([
                    "line": AnyCodable(20)
                ])
            ])
        ]

        let paths = ACPClient.locationPaths(from: update)

        XCTAssertEqual(paths, ["/tmp/one.md", "/tmp/two.md"])
    }

    @MainActor
    func testDocumentChatTrayQuickPromptsFocusOnDocumentEditing() {
        let chatState = DocumentChatState()
        let tray = DocumentChatTray(
            chatState: chatState,
            documentURL: URL(fileURLWithPath: "/tmp/notes.md"),
            documentContent: "Draft content",
            selectedText: nil,
            selectedLineRange: nil
        )

        let reflectedTray = Mirror(reflecting: tray)
        guard let quickPrompts = reflectedTray.children.first(where: { $0.label == "quickPrompts" })?.value
            as? [String] else {
            XCTFail("Failed to inspect quick prompts from DocumentChatTray")
            return
        }

        XCTAssertEqual(quickPrompts, [
            "Summarize this document into key points",
            "Rewrite this section for clarity and flow",
            "Improve headings and overall structure",
            "Find gaps, ambiguities, or inconsistencies"
        ])
    }

    func testDocumentChatTrayPreferredAgentNameSelectsWriter() {
        let agents = [
            AgentInfo(name: "synth-editor", description: nil),
            AgentInfo(name: "synth-writer", description: nil),
            AgentInfo(name: "synth-researcher", description: nil)
        ]

        XCTAssertEqual(DocumentChatTray.preferredAgentName(from: agents), "synth-writer")
    }

    func testDocumentChatTrayPreferredAgentNameReturnsNilWithoutWriter() {
        let agents = [
            AgentInfo(name: "synth-editor", description: nil),
            AgentInfo(name: "synth-researcher", description: nil)
        ]

        XCTAssertNil(DocumentChatTray.preferredAgentName(from: agents))
    }

    func testThinkingAnimationPhaseIndexAdvancesWithTime() {
        let baseTime = Date(timeIntervalSinceReferenceDate: 0)
        let phaseDuration = ThinkingAnimation.phaseDuration

        XCTAssertEqual(ThinkingAnimation.phaseIndex(at: baseTime), 0)
        XCTAssertEqual(
            ThinkingAnimation.phaseIndex(at: baseTime.addingTimeInterval(phaseDuration)),
            1
        )
        XCTAssertEqual(
            ThinkingAnimation.phaseIndex(at: baseTime.addingTimeInterval(phaseDuration * 5)),
            5
        )
        XCTAssertEqual(
            ThinkingAnimation.phaseIndex(at: baseTime.addingTimeInterval(phaseDuration * 6)),
            0
        )
    }

    func testThinkingAnimationActiveDotIndexCycles() {
        XCTAssertEqual(ThinkingAnimation.activeDotIndex(for: 0), 0)
        XCTAssertEqual(ThinkingAnimation.activeDotIndex(for: 1), 1)
        XCTAssertEqual(ThinkingAnimation.activeDotIndex(for: 2), 2)
        XCTAssertEqual(ThinkingAnimation.activeDotIndex(for: 3), 0)
    }

    func testThinkingAnimationStatusTextCycles() {
        XCTAssertEqual(ThinkingAnimation.statusText(for: 0), "Thinking")
        XCTAssertEqual(ThinkingAnimation.statusText(for: 1), "Reviewing")
        XCTAssertEqual(ThinkingAnimation.statusText(for: 2), "Reasoning")
        XCTAssertEqual(ThinkingAnimation.statusText(for: 5), "Reasoning")
    }

    func testThinkingAnimationStatusTextUsesToolCallTitleWhenAvailable() {
        let editCall = ACPToolCall(
            id: "tool-1",
            title: "Editing TESTING NOTE.md",
            kind: "edit",
            status: "in_progress"
        )

        XCTAssertEqual(
            ThinkingAnimation.statusText(for: 0, latestToolCall: editCall),
            "Editing"
        )
    }

    @MainActor
    func testDocumentChatTrayHintsOnlyShownBeforeConversationStarts() {
        XCTAssertTrue(
            DocumentChatTray.shouldShowChatHints(
                messageCount: 0,
                currentResponse: "",
                isLoading: false
            )
        )
        XCTAssertFalse(
            DocumentChatTray.shouldShowChatHints(
                messageCount: 1,
                currentResponse: "",
                isLoading: false
            )
        )
        XCTAssertFalse(
            DocumentChatTray.shouldShowChatHints(
                messageCount: 0,
                currentResponse: "partial",
                isLoading: true
            )
        )
    }

    @MainActor
    func testDocumentChatTrayDisplayedQuickPromptsCapsAtThree() {
        let prompts = [
            "one",
            "two",
            "three",
            "four"
        ]

        let displayed = DocumentChatTray.displayedQuickPrompts(from: prompts)

        XCTAssertEqual(displayed, ["one", "two", "three"])
    }

    func testDocumentChatTrayDisplayedPermissionDiffTextPreservesFullContent() {
        let fullDiffText = String(repeating: "0123456789", count: 80)

        let displayed = DocumentChatTray.displayedPermissionDiffText(fullDiffText)

        XCTAssertEqual(displayed.count, fullDiffText.count)
        XCTAssertEqual(displayed, fullDiffText)
    }

    @MainActor
    func testDocumentChatTrayAgentSymbolFallsBackWhenPreferredUnavailable() {
        let fallbackSymbol = DocumentChatTray.agentSymbolName { _ in false }

        XCTAssertEqual(fallbackSymbol, "person")
    }

    func testShortcutHintRulesUsesOneSecondDelay() {
        XCTAssertEqual(ShortcutHintRules.revealDelaySeconds, 1.0)
    }

    func testShortcutHintRulesRevealStateAfterDelay() {
        let hoverStartDate = Date(timeIntervalSinceReferenceDate: 0)
        let beforeDelayDate = Date(timeIntervalSinceReferenceDate: 0.9)
        let afterDelayDate = Date(timeIntervalSinceReferenceDate: 1.0)

        XCTAssertFalse(
            ShortcutHintRules.shouldRevealHint(
                hoverStartDate: hoverStartDate,
                currentDate: beforeDelayDate
            )
        )
        XCTAssertTrue(
            ShortcutHintRules.shouldRevealHint(
                hoverStartDate: hoverStartDate,
                currentDate: afterDelayDate
            )
        )
    }

    func testSidebarSectionHoverRulesBackgroundOpacity() {
        XCTAssertEqual(
            SidebarSectionHoverRules.backgroundOpacity(isSelected: true, isHovering: false),
            0.15
        )
        XCTAssertEqual(
            SidebarSectionHoverRules.backgroundOpacity(isSelected: false, isHovering: true),
            0.08
        )
        XCTAssertEqual(
            SidebarSectionHoverRules.backgroundOpacity(isSelected: false, isHovering: false),
            0.0
        )
    }

    @MainActor
    func testDocumentStoreShouldRefreshSidebarIgnoresHiddenKiroAndSpecialFolders() {
        let workspacePath = "/tmp/workspace"

        XCTAssertFalse(
            DocumentStore.shouldRefreshSidebar(
                forWorkspace: workspacePath,
                eventPath: "/tmp/workspace/.kiro/settings/mcp.json"
            )
        )
        XCTAssertFalse(
            DocumentStore.shouldRefreshSidebar(
                forWorkspace: workspacePath,
                eventPath: "/tmp/workspace/daily/2026-02-08.md"
            )
        )
        XCTAssertFalse(
            DocumentStore.shouldRefreshSidebar(
                forWorkspace: workspacePath,
                eventPath: "/tmp/workspace/media/screenshot.png"
            )
        )
    }

    @MainActor
    func testDocumentStoreShouldRefreshSidebarForVisibleWorkspaceFiles() {
        let workspacePath = "/tmp/workspace"

        XCTAssertTrue(
            DocumentStore.shouldRefreshSidebar(
                forWorkspace: workspacePath,
                eventPath: "/tmp/workspace/drafts/Untitled.md"
            )
        )
        XCTAssertFalse(
            DocumentStore.shouldRefreshSidebar(
                forWorkspace: workspacePath,
                eventPath: "/tmp/other-workspace/drafts/Untitled.md"
            )
        )
    }

    @MainActor
    func testDocumentStoreShouldApplyFileTreeScanResultRejectsStaleIdentifier() {
        let activeID = UUID()
        let staleID = UUID()
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)

        XCTAssertFalse(
            DocumentStore.shouldApplyFileTreeScanResult(
                activeScanID: activeID,
                scanID: staleID,
                currentWorkspace: workspace,
                scanWorkspace: workspace
            )
        )
    }

    @MainActor
    func testDocumentStoreShouldApplyFileTreeScanResultRequiresMatchingWorkspaceAndIdentifier() {
        let activeID = UUID()
        let workspace = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        let otherWorkspace = URL(fileURLWithPath: "/tmp/other-workspace", isDirectory: true)

        XCTAssertFalse(
            DocumentStore.shouldApplyFileTreeScanResult(
                activeScanID: activeID,
                scanID: activeID,
                currentWorkspace: nil,
                scanWorkspace: workspace
            )
        )
        XCTAssertFalse(
            DocumentStore.shouldApplyFileTreeScanResult(
                activeScanID: activeID,
                scanID: activeID,
                currentWorkspace: workspace,
                scanWorkspace: otherWorkspace
            )
        )
        XCTAssertTrue(
            DocumentStore.shouldApplyFileTreeScanResult(
                activeScanID: activeID,
                scanID: activeID,
                currentWorkspace: workspace,
                scanWorkspace: workspace
            )
        )
    }
}

final class NoteIndexTests: XCTestCase {
    func testRebuildSearchAndFindExactBehavior() {
        let workspaceURL = URL(fileURLWithPath: "/tmp/workspace-notes", isDirectory: true)
        let firstNote = FileTreeNode(
            url: workspaceURL.appendingPathComponent("First Note.md"),
            isDirectory: false,
            children: nil
        )
        let secondNote = FileTreeNode(
            url: workspaceURL.appendingPathComponent("folder/Meeting Notes.txt"),
            isDirectory: false,
            children: nil
        )
        let imageFile = FileTreeNode(
            url: workspaceURL.appendingPathComponent("diagram.png"),
            isDirectory: false,
            children: nil
        )
        let nestedFolder = FileTreeNode(
            url: workspaceURL.appendingPathComponent("folder"),
            isDirectory: true,
            children: [secondNote, imageFile]
        )

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: [firstNote, nestedFolder], workspace: workspaceURL)

        XCTAssertTrue(noteIndex.isPopulated)
        XCTAssertEqual(noteIndex.notes.count, 2)
        XCTAssertEqual(noteIndex.search("").count, 2)
        XCTAssertNotNil(noteIndex.findExact("first note"))
        XCTAssertNil(noteIndex.findExact("missing note"))

        let queryResults = noteIndex.search("meeting")
        XCTAssertTrue(queryResults.contains { $0.title == "Meeting Notes" })
        XCTAssertFalse(queryResults.contains { $0.title == "diagram" })
    }

    func testEmptyQueryReturnsAtMostTwentyNotes() {
        let workspaceURL = URL(fileURLWithPath: "/tmp/workspace-limit", isDirectory: true)
        let allNodes = (1...25).map { number in
            FileTreeNode(
                url: workspaceURL.appendingPathComponent("Note \(number).md"),
                isDirectory: false,
                children: nil
            )
        }

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: allNodes, workspace: workspaceURL)

        XCTAssertEqual(noteIndex.notes.count, 25)
        XCTAssertEqual(noteIndex.search("").count, 20)
    }

    func testUpdateFileReindexesUpdatedTokenMatches() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let firstNoteURL = workspaceURL.appendingPathComponent("First.md")
        let secondNoteURL = workspaceURL.appendingPathComponent("Second.md")
        try "alpha alpha signal".write(to: firstNoteURL, atomically: true, encoding: .utf8)
        try "alpha report".write(to: secondNoteURL, atomically: true, encoding: .utf8)

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: FileTreeNode.scan(workspaceURL), workspace: workspaceURL)
        guard let indexedFirstURL = noteIndex.findExact("First")?.url else {
            XCTFail("Missing indexed first note")
            return
        }

        XCTAssertEqual(noteIndex.search("alpha").count, 2)

        let updatedText = "beta planning memo"
        try updatedText.write(to: firstNoteURL, atomically: true, encoding: .utf8)
        noteIndex.updateFile(indexedFirstURL, content: updatedText)

        let alphaResults = noteIndex.search("alpha")
        XCTAssertEqual(alphaResults.count, 1)
        XCTAssertEqual(alphaResults.first?.title, "Second")

        let betaResults = noteIndex.search("beta")
        XCTAssertEqual(betaResults.count, 1)
        XCTAssertEqual(betaResults.first?.title, "First")
    }
}

final class DocumentModelTests: XCTestCase {
    func testLoadAndSavePlainTextDocument() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let textFileURL = rootDirectory.appendingPathComponent("sample.txt")
        try "Hello".write(to: textFileURL, atomically: true, encoding: .utf8)

        guard let loadedDocument = Document.load(from: textFileURL) else {
            XCTFail("Failed to load text document")
            return
        }
        XCTAssertEqual(loadedDocument.content.string, "Hello")

        let updatedContent = NSAttributedString(string: "Updated")
        try loadedDocument.save(updatedContent)
        let savedText = try String(contentsOf: textFileURL, encoding: .utf8)
        XCTAssertEqual(savedText, "Updated")
    }

    func testLoadMarkdownDocumentContainsRenderedText() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let markdownFileURL = rootDirectory.appendingPathComponent("sample.md")
        try "# Heading\n\nBody content".write(to: markdownFileURL, atomically: true, encoding: .utf8)

        guard let loadedDocument = Document.load(from: markdownFileURL) else {
            XCTFail("Failed to load markdown document")
            return
        }

        XCTAssertTrue(loadedDocument.content.string.contains("Heading"))
        XCTAssertTrue(loadedDocument.content.string.contains("Body content"))
    }

    func testLoadReturnsNilForOversizedFile() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let largeFileURL = rootDirectory.appendingPathComponent("large.txt")
        FileManager.default.createFile(atPath: largeFileURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: largeFileURL)
        defer { try? fileHandle.close() }
        try fileHandle.truncate(atOffset: 51 * 1024 * 1024)

        XCTAssertNil(Document.load(from: largeFileURL))
    }
}

final class MCPServerManagerTests: XCTestCase {
    func testStartWritesConfigAndStopTerminates() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let workspaceURL = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let binaryDirectory = rootDirectory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)

        let executableURL = binaryDirectory.appendingPathComponent("synth-mcp-server")
        let scriptContents = """
        #!/bin/sh
        trap 'exit 0' TERM INT
        while true; do
          sleep 1
        done
        """
        try scriptContents.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        let originalPathEnv = getenv("PATH").map { String(cString: $0) } ?? ""
        setenv("PATH", "\(binaryDirectory.path):\(originalPathEnv)", 1)
        defer { setenv("PATH", originalPathEnv, 1) }

        let manager = MCPServerManager()
        manager.enableHTTPBridge = true
        manager.healthProbe = { _ in true }
        manager.httpPort = 9823
        manager.start(workspace: workspaceURL)
        defer { manager.stop() }

        XCTAssertTrue(manager.isRunning)

        let configURL = workspaceURL
            .appendingPathComponent(".kiro")
            .appendingPathComponent("settings")
            .appendingPathComponent("mcp.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))

        let configData = try Data(contentsOf: configURL)
        let configJSON = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        let servers = configJSON?["mcpServers"] as? [String: Any]
        let synthServer = servers?["synth-mcp"] as? [String: Any]
        let synthArgs = synthServer?["args"] as? [String]
        let configuredCommand = synthServer?["command"] as? String

        XCTAssertNotNil(configuredCommand)
        XCTAssertTrue(configuredCommand?.hasSuffix("/synth-mcp-server") == true)
        XCTAssertEqual(synthArgs ?? [], ["--workspace", workspaceURL.path, "--stdio"])
        XCTAssertEqual(synthServer?["disabled"] as? Bool, false)

        let runtimeConfig = manager.mcpServerConfig(workspace: workspaceURL.path)
        let runtimeEntry = runtimeConfig?.first
        let runtimeArgs = runtimeEntry?["args"]?.arrayValue?.compactMap { $0.stringValue }
        let runtimeCommand = runtimeEntry?["command"]?.stringValue
        let runtimeEnvironment = runtimeEntry?["env"]?.arrayValue ?? []
        XCTAssertEqual(runtimeEntry?["name"]?.stringValue, "synth-mcp")
        XCTAssertEqual(runtimeCommand, configuredCommand)
        XCTAssertEqual(runtimeArgs ?? [], ["--workspace", workspaceURL.path, "--stdio"])
        XCTAssertEqual(runtimeEnvironment.count, 0)
        XCTAssertNil(runtimeEntry?["transport"])

        manager.stop()
        XCTAssertFalse(manager.isRunning)
    }

    func testStartPreservesExistingMcpServerEntries() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let workspaceURL = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let settingsDirectory = workspaceURL
            .appendingPathComponent(".kiro")
            .appendingPathComponent("settings", isDirectory: true)
        try FileManager.default.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)

        let configURL = settingsDirectory.appendingPathComponent("mcp.json")
        let existingConfig: [String: Any] = [
            "mcpServers": [
                "custom-server": [
                    "command": "/tmp/custom-binary",
                    "args": ["--flag"],
                    "disabled": false
                ]
            ]
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existingConfig, options: [.prettyPrinted])
        try existingData.write(to: configURL)

        let binaryDirectory = rootDirectory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        let executableURL = binaryDirectory.appendingPathComponent("synth-mcp-server")
        try "#!/bin/sh\nsleep 10\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        let originalPathEnv = getenv("PATH").map { String(cString: $0) } ?? ""
        setenv("PATH", "\(binaryDirectory.path):\(originalPathEnv)", 1)
        defer { setenv("PATH", originalPathEnv, 1) }

        let manager = MCPServerManager()
        manager.enableHTTPBridge = false
        manager.start(workspace: workspaceURL)
        defer { manager.stop() }

        let mergedData = try Data(contentsOf: configURL)
        let mergedJSON = try JSONSerialization.jsonObject(with: mergedData) as? [String: Any]
        let mergedServers = mergedJSON?["mcpServers"] as? [String: Any]

        XCTAssertNotNil(mergedServers?["custom-server"])
        XCTAssertNotNil(mergedServers?["synth-mcp"])
    }

    func testStartWithHttpBridgeDisabledWritesConfigWithoutLaunchingProcess() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let workspaceURL = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let binaryDirectory = rootDirectory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        let executableURL = binaryDirectory.appendingPathComponent("synth-mcp-server")
        try "#!/bin/sh\nsleep 10\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        let originalPathEnv = getenv("PATH").map { String(cString: $0) } ?? ""
        setenv("PATH", "\(binaryDirectory.path):\(originalPathEnv)", 1)
        defer { setenv("PATH", originalPathEnv, 1) }

        let manager = MCPServerManager()
        manager.enableHTTPBridge = false
        manager.start(workspace: workspaceURL)
        defer { manager.stop() }

        let configURL = workspaceURL
            .appendingPathComponent(".kiro")
            .appendingPathComponent("settings")
            .appendingPathComponent("mcp.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertFalse(manager.isRunning)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: manager.runtimeLeaseURL(workspace: workspaceURL).path
            )
        )
    }

    func testRuntimeLeaseRoundTripAndRemoval() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let workspaceURL = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let manager = MCPServerManager()
        manager.writeRuntimeLease(
            workspace: workspaceURL,
            pid: 123,
            port: 9731,
            commandPath: "/tmp/synth-mcp-server"
        )

        let lease = manager.readRuntimeLease(workspace: workspaceURL)
        XCTAssertEqual(lease?.pid, 123)
        XCTAssertEqual(lease?.port, 9731)
        XCTAssertEqual(lease?.workspacePath, workspaceURL.path)
        XCTAssertEqual(lease?.commandPath, "/tmp/synth-mcp-server")

        manager.removeRuntimeLease(workspace: workspaceURL)
        XCTAssertNil(manager.readRuntimeLease(workspace: workspaceURL))
    }

    func testRuntimeLeaseURLIsOutsideWorkspaceBoundary() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )

        let manager = MCPServerManager()
        let leaseURL = manager.runtimeLeaseURL(workspace: workspaceURL)

        XCTAssertFalse(leaseURL.path.hasPrefix(workspaceURL.path))
    }

    func testStartDoesNotSignalProcessFromRuntimeLease() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let workspaceURL = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let binaryDirectory = rootDirectory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        let executableURL = binaryDirectory.appendingPathComponent("synth-mcp-server")
        try "#!/bin/sh\nsleep 10\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        let originalPathEnv = getenv("PATH").map { String(cString: $0) } ?? ""
        setenv("PATH", "\(binaryDirectory.path):\(originalPathEnv)", 1)
        defer { setenv("PATH", originalPathEnv, 1) }

        let manager = MCPServerManager()
        manager.enableHTTPBridge = true
        manager.healthProbe = { _ in false }
        manager.portAvailabilityProbe = { _ in false }
        manager.processAliveProbe = { _ in true }

        var signalCount = 0
        manager.signalProbe = { _, _ in
            signalCount += 1
            return 0
        }

        manager.writeRuntimeLease(
            workspace: workspaceURL,
            pid: 4242,
            port: 9766,
            commandPath: executableURL.path
        )

        manager.start(workspace: workspaceURL)
        defer { manager.stop() }

        XCTAssertEqual(signalCount, 0)
    }

    func testSelectAvailablePortFallsBackFromPreferredPort() {
        let manager = MCPServerManager()
        manager.portAvailabilityProbe = { portValue in
            portValue == 9724
        }

        let selectedPort = manager.selectAvailablePort(
            preferredPort: 9722,
            searchWindow: 3
        )

        XCTAssertEqual(selectedPort, 9724)
    }

    func testSelectAvailablePortSkipsOccupiedPreferredPort() {
        let preferredPort: UInt16 = 9732
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertTrue(socketDescriptor >= 0)
        defer { close(socketDescriptor) }

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = preferredPort.bigEndian
        socketAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                Darwin.bind(
                    socketDescriptor,
                    reboundPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        XCTAssertEqual(bindResult, 0)
        XCTAssertEqual(Darwin.listen(socketDescriptor, 8), 0)

        let manager = MCPServerManager()
        let selected = manager.selectAvailablePort(
            preferredPort: preferredPort,
            searchWindow: 3
        )

        XCTAssertNotNil(selected)
        XCTAssertNotEqual(selected, preferredPort)
    }

    func testThemeResolveFontUsesCandidateOrder() {
        var requestedNames: [String] = []
        let targetSize: CGFloat = 15
        let resolvedFont = Theme.resolveFont(
            candidates: ["Missing-Regular", "MesloLGS-Regular", "Fallback-Regular"],
            size: targetSize
        ) { fontName, fontSize in
            requestedNames.append(fontName)
            guard fontName == "MesloLGS-Regular" else { return nil }
            return NSFont.systemFont(ofSize: fontSize)
        }

        XCTAssertEqual(requestedNames, ["Missing-Regular", "MesloLGS-Regular"])
        XCTAssertEqual(resolvedFont?.pointSize, targetSize)
    }

    func testThemeResolveFontReturnsNilWhenNoCandidateExists() {
        let resolvedFont = Theme.resolveFont(
            candidates: ["Unavailable-Regular", "Unavailable-Bold"],
            size: 14
        ) { _, _ in nil }

        XCTAssertNil(resolvedFont)
    }

    func testThemeMesloCandidatesPreferBoldWhenRequested() {
        let candidateNames = Theme.mesloCandidates(for: .bold)

        XCTAssertEqual(candidateNames.first, "MesloLGS-Bold")
        XCTAssertTrue(candidateNames.contains("MesloLGS-Regular"))
    }

    func testThemeParseCandidateListTrimsAndDeduplicates() {
        let parsedCandidates = Theme.parseCandidateList(
            " MesloLGS-Regular, , FiraCode-Regular , MesloLGS-Regular "
        )

        XCTAssertEqual(
            parsedCandidates,
            ["MesloLGS-Regular", "FiraCode-Regular"]
        )
    }

    func testThemeEditorCandidateNamesPrependsUserConfiguredFonts() {
        let suiteName = "ThemeEditorCandidates-\(UUID().uuidString)"
        guard let defaultsStore = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }
        defer { defaultsStore.removePersistentDomain(forName: suiteName) }
        defaultsStore.set(
            "FiraCode-Regular, Iosevka-Regular",
            forKey: Theme.editorFontCandidatesKey
        )

        let candidateNames = Theme.editorCandidateNames(
            weight: .regular,
            defaults: defaultsStore
        )

        XCTAssertEqual(
            Array(candidateNames.prefix(2)),
            ["FiraCode-Regular", "Iosevka-Regular"]
        )
        XCTAssertTrue(candidateNames.contains("MesloLGS-Regular"))
    }

    func testThemeEditorCandidateNamesDeduplicatesAgainstFallbacks() {
        let suiteName = "ThemeEditorDedup-\(UUID().uuidString)"
        guard let defaultsStore = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }
        defer { defaultsStore.removePersistentDomain(forName: suiteName) }
        defaultsStore.set(
            "MesloLGS-Regular, FiraCode-Regular",
            forKey: Theme.editorFontCandidatesKey
        )

        let candidateNames = Theme.editorCandidateNames(
            weight: .regular,
            defaults: defaultsStore
        )
        let mesloOccurrences = candidateNames.filter { $0 == "MesloLGS-Regular" }.count

        XCTAssertEqual(mesloOccurrences, 1)
        XCTAssertEqual(
            Array(candidateNames.prefix(2)),
            ["MesloLGS-Regular", "FiraCode-Regular"]
        )
    }

    func testThemeSourceSerifCandidatesPreferSourceSerifFour() {
        let candidateNames = Theme.sourceSerifCandidates(for: .regular)

        XCTAssertEqual(candidateNames.first, "SourceSerif4-Regular")
        XCTAssertTrue(candidateNames.contains("Source Serif 4"))
    }

    func testThemePublicSansCandidatesPreferPublicSans() {
        let candidateNames = Theme.publicSansCandidates(for: .regular)

        XCTAssertEqual(candidateNames.first, "PublicSans-Regular")
        XCTAssertTrue(candidateNames.contains("Public Sans"))
    }

    func testThemeEditorNSFontFallsBackToSystemFontWhenCandidatesMiss() {
        let expectedFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let resolvedFont = Theme.editorNSFont(ofSize: 13, weight: .regular) { _, _ in nil }

        XCTAssertEqual(resolvedFont.fontName, expectedFont.fontName)
        XCTAssertEqual(resolvedFont.pointSize, expectedFont.pointSize)
    }

    func testThemeBundledFontFileNamesIncludeRequiredFamilies() {
        let bundledFontFiles = Set(Theme.bundledFontFileNames)

        XCTAssertTrue(bundledFontFiles.contains("mesloLGS_NF_regular.ttf"))
        XCTAssertTrue(bundledFontFiles.contains("PublicSans-Regular.ttf"))
        XCTAssertTrue(bundledFontFiles.contains("SourceSerif4-Regular.ttf"))
    }

    func testThemeRegisterFontsAttemptsEachURLAndCountsSuccesses() {
        let fontURLs = [
            URL(fileURLWithPath: "/tmp/font-a.ttf"),
            URL(fileURLWithPath: "/tmp/font-b.ttf"),
            URL(fileURLWithPath: "/tmp/font-c.ttf")
        ]
        var attemptedPaths: [String] = []

        let successCount = Theme.registerFonts(at: fontURLs) { fontURL, _, _ in
            attemptedPaths.append((fontURL as URL).path)
            return (fontURL as URL).lastPathComponent != "font-b.ttf"
        }

        XCTAssertEqual(attemptedPaths, fontURLs.map(\.path))
        XCTAssertEqual(successCount, 2)
    }
}
