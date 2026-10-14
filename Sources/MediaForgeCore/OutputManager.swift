import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum OutputManager {
    public static func suggestedURL(input: URL, directory: URL, profile: OutputProfile, reserved: Set<URL> = []) -> URL {
        let reservations = Set(reserved.map { $0.standardizedFileURL })
        let sourceStem = input.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let suffix = counter == 1 ? "" : "-" + String(counter)
            let ending = "-converted" + suffix + "." + profile.fileExtension
            let budget = 255 - ending.utf8.count
            var stem = ""
            var byteCount = 0
            for character in sourceStem {
                let size = String(character).utf8.count
                guard byteCount + size <= budget else { break }
                stem.append(character)
                byteCount += size
            }
            if stem.isEmpty { stem = "media" }
            let candidate = directory.appendingPathComponent(stem + ending)
            if !reservations.contains(candidate.standardizedFileURL) && !FileManager.default.fileExists(atPath: candidate.path) && (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) == nil { return candidate }
            counter += 1
        }
    }
    public static func commit(temporary: URL, destination: URL) throws {
        guard temporary.isFileURL, destination.isFileURL, temporary.standardizedFileURL != destination.standardizedFileURL else {
            throw MediaForgeError.fileOperation("Publication requires distinct local file URLs.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
            throw MediaForgeError.fileOperation("Only a nonempty regular staged file can be published.")
        }
        let status = temporary.path.withCString { source in
            destination.path.withCString { target in
                #if canImport(Darwin)
                return renamex_np(source, target, UInt32(RENAME_EXCL))
                #else
                return link(source, target)
                #endif
            }
        }
        guard status == 0 else {
            let code = errno
            if code == EEXIST { throw MediaForgeError.outputExists(destination) }
            throw MediaForgeError.fileOperation("This destination could not safely publish an exclusive output: " + String(cString: strerror(code)))
        }
    }
}
