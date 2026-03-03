import Foundation
import CoreServices

// MARK: - FileEvent (aligned with FSNotes' FileWatcherEvent)

struct FileEvent {
    let path: String
    let flags: FSEventStreamEventFlags

    var isFile: Bool {
        flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemIsFile
        ) != 0
    }
    var isDirectory: Bool {
        flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemIsDir
        ) != 0
    }
    var isCreated: Bool {
        flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
        ) != 0
    }
    var isRemoved: Bool {
        flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemRemoved
        ) != 0
    }
    var isRenamed: Bool {
        flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemRenamed
        ) != 0
    }
    var isModified: Bool {
        flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemModified
        ) != 0
    }

    // Convenience
    var fileCreated: Bool { isFile && isCreated }
    var fileRemoved: Bool { isFile && isRemoved }
    var fileRenamed: Bool { isFile && isRenamed }
    var fileModified: Bool { isFile && isModified }
    var dirCreated: Bool { isDirectory && isCreated }
    var dirRemoved: Bool { isDirectory && isRemoved }
    var dirRenamed: Bool { isDirectory && isRenamed }

    var url: URL { URL(fileURLWithPath: path) }
}

// MARK: - WorkspaceWatcher

private final class WorkspaceWatcherContext {
    weak var watcher: WorkspaceWatcher?

    init(watcher: WorkspaceWatcher) {
        self.watcher = watcher
    }
}

private let watcherContextRetain: CFAllocatorRetainCallBack = { info in
    guard let info else { return nil }
    let rawPointer = UnsafeMutableRawPointer(mutating: info)
    let context = Unmanaged<WorkspaceWatcherContext>.fromOpaque(rawPointer)
    return UnsafeRawPointer(context.retain().toOpaque())
}

private let watcherContextRelease: CFAllocatorReleaseCallBack = { info in
    guard let info else { return }
    let rawPointer = UnsafeMutableRawPointer(mutating: info)
    Unmanaged<WorkspaceWatcherContext>.fromOpaque(rawPointer).release()
}

/// Watches a workspace directory for file system changes using FSEvents.
@MainActor
final class WorkspaceWatcher {
    private var fileEventStream: FSEventStreamRef?
    private var watcherContext: WorkspaceWatcherContext?
    private var onEvents: (([FileEvent]) -> Void)?

    func start(
        workspace: URL,
        onEvents: @escaping ([FileEvent]) -> Void
    ) {
        stop()
        self.onEvents = onEvents

        let context = WorkspaceWatcherContext(watcher: self)
        watcherContext = context

        var streamContext = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(
                Unmanaged.passRetained(context).toOpaque()
            ),
            retain: watcherContextRetain,
            release: watcherContextRelease,
            copyDescription: nil
        )

        let watchPaths = [workspace.path] as CFArray
        let streamFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &streamContext,
            watchPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            streamFlags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        if FSEventStreamStart(stream) {
            fileEventStream = stream
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            watcherContext = nil
        }
    }

    func stop() {
        guard let stream = fileEventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fileEventStream = nil
        watcherContext = nil
        onEvents = nil
    }

    static func shouldRefreshSidebar(
        forWorkspace workspacePath: String, eventPath: String
    ) -> Bool {
        let normalizedWorkspace = URL(
            fileURLWithPath: workspacePath
        ).standardizedFileURL.path
        let normalizedEvent = URL(
            fileURLWithPath: eventPath
        ).standardizedFileURL.path
        guard normalizedEvent.hasPrefix(normalizedWorkspace)
        else { return false }

        let relativePath = String(
            normalizedEvent.dropFirst(normalizedWorkspace.count)
        )
        if relativePath == "/.kiro"
            || relativePath.hasPrefix("/.kiro/") {
            return false
        }
        if relativePath == "/daily"
            || relativePath.hasPrefix("/daily/") {
            return false
        }
        if relativePath == "/media"
            || relativePath.hasPrefix("/media/") {
            return false
        }
        return true
    }

    private static let eventCallback: FSEventStreamCallback = {
        _, clientInfo, numEvents, eventPathsPointer,
        eventFlags, _ in
        guard let clientInfo else { return }
        let context = Unmanaged<WorkspaceWatcherContext>
            .fromOpaque(clientInfo)
            .takeUnretainedValue()
        guard let watcher = context.watcher else { return }

        let eventPathArray = Unmanaged<CFArray>
            .fromOpaque(eventPathsPointer)
            .takeUnretainedValue() as NSArray
        let paths = eventPathArray.compactMap { $0 as? String }

        var events: [FileEvent] = []
        events.reserveCapacity(numEvents)
        for index in 0..<numEvents {
            guard index < paths.count else { break }
            events.append(
                FileEvent(
                    path: paths[index],
                    flags: eventFlags[index]
                )
            )
        }

        watcher.onEvents?(events)
    }
}
