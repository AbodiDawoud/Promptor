import Foundation
import CoreServices

final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void
    private let path: String // Store the path to ensure it's valid during deinit

    init?(url: URL, latency: TimeInterval = 0.3, callback: @escaping () -> Void) {
        guard url.isFileURL else {
            print("Error: FolderWatcher can only watch file URLs.")
            return nil
        }
        self.callback = callback
        // Ensure the path string remains valid for the C callback context.
        // Using fileSystemRepresentation ensures correct encoding.
        var pathChars = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard (url as NSURL).getFileSystemRepresentation(&pathChars, maxLength: pathChars.count) else {
             print("Error: Could not get file system representation for URL: \(url)")
             return nil
        }
        self.path = String(cString: pathChars)


        // Pass `self` as context info. `unsafeBitCast` is necessary for C interop.
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                // Check if clientCallBackInfo is non-nil before proceeding
                guard let clientCallBackInfo = clientCallBackInfo else { return }
                // Safely cast context info back to FolderWatcher instance.
                let handler = Unmanaged<FolderWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
                // Callback on the main thread for UI updates.
                DispatchQueue.main.async { handler.callback() }
            },
            &context,
            [self.path] as CFArray, // Use the stored path string
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes) // Added UseCFTypes for safety with CFArray
        )

        guard let stream = stream else {
             print("Error: Failed to create FSEventStream.")
             return nil
         }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        guard FSEventStreamStart(stream) else {
            print("Error: Failed to start FSEventStream.")
            FSEventStreamInvalidate(stream) // Clean up if start fails
            FSEventStreamRelease(stream)
            self.stream = nil // Ensure stream is nil if start failed
            return nil
        }
         print("FolderWatcher started for path: \(self.path)")
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        print("FolderWatcher stopped for path: \(path)")
    }


    deinit {
        stop() // Ensure stream is stopped and released on deinit
    }
} 