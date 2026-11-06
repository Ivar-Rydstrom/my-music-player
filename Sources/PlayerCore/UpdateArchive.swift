import Foundation

/// Reads a zip's central directory so an update archive can be vetted before anything is extracted.
public enum UpdateArchive {
    public struct Entry: Equatable, Sendable {
        public let path: String
        /// Unix mode bits, when the archive was made on a Unix host.
        public let unixMode: UInt32?

        public init(path: String, unixMode: UInt32?) {
            self.path = path
            self.unixMode = unixMode
        }

        var isSymlink: Bool { unixMode.map { $0 & 0o170000 == 0o120000 } ?? false }
    }

    public enum Problem: LocalizedError, Equatable {
        case unreadable(String)
        case unsafePath(String)
        case symlink(String)
        case unexpectedLayout

        public var errorDescription: String? {
            switch self {
            case .unreadable(let reason): return "The update archive couldn't be read (\(reason))."
            case .unsafePath(let path): return "The update archive contains an unsafe path: \(path)"
            case .symlink(let path): return "The update archive contains a symbolic link: \(path)"
            case .unexpectedLayout: return "The update archive doesn't contain exactly one app."
            }
        }
    }

    /// Lists entries from the central directory. Zip64 and multi-disk archives are rejected.
    public static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }

        guard bytes.count >= 22 else { throw Problem.unreadable("too short") }
        var end = -1
        var offset = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        while offset >= lowest {
            if u32(offset) == 0x06054b50 { end = offset; break }
            offset -= 1
        }
        guard end >= 0 else { throw Problem.unreadable("no end of central directory") }
        guard u16(end + 4) == 0, u16(end + 6) == 0 else { throw Problem.unreadable("multi-disk archive") }
        let count = u16(end + 10), size = u32(end + 12), start = u32(end + 16)
        guard count != 0xFFFF, size != 0xFFFFFFFF, start != 0xFFFFFFFF else { throw Problem.unreadable("zip64 archive") }
        guard start + size <= end else { throw Problem.unreadable("central directory out of bounds") }

        var entries: [Entry] = []
        var cursor = start
        for _ in 0..<count {
            guard cursor + 46 <= start + size, u32(cursor) == 0x02014b50 else { throw Problem.unreadable("bad central directory entry") }
            let host = bytes[cursor + 5]
            let nameLength = u16(cursor + 28), extraLength = u16(cursor + 30), commentLength = u16(cursor + 32)
            let external = UInt32(u32(cursor + 38))
            let nameEnd = cursor + 46 + nameLength
            guard nameEnd <= start + size else { throw Problem.unreadable("name out of bounds") }
            guard let path = String(bytes: bytes[(cursor + 46)..<nameEnd], encoding: .utf8) else {
                throw Problem.unreadable("non-UTF-8 name")
            }
            entries.append(Entry(path: path, unixMode: host == 3 ? external >> 16 : nil))
            cursor = nameEnd + extraLength + commentLength
        }
        return entries
    }

    /// Accepts only relative paths inside one top-level `.app` folder, plus ditto's `__MACOSX` metadata,
    /// with no symbolic links. Returns the app folder's name.
    @discardableResult
    public static func validate(_ entries: [Entry]) throws -> String {
        var apps = Set<String>()
        for entry in entries {
            let path = entry.path
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
                  !components.contains(".."), !components.contains("."),
                  !components.dropLast().contains("") else { throw Problem.unsafePath(path) }
            guard !entry.isSymlink else { throw Problem.symlink(path) }
            let top = String(components[0])
            if top == "__MACOSX" { continue }
            guard top.hasSuffix(".app"), top.count > 4 else { throw Problem.unexpectedLayout }
            apps.insert(top)
        }
        guard apps.count == 1, let app = apps.first else { throw Problem.unexpectedLayout }
        return app
    }
}
