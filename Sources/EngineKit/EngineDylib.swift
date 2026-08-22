import Foundation

/// Path to the real IronRDP engine dylib (`libmrdpd_engine.dylib`).
public enum EngineDylib {
    public static func path() throws -> String {
        if let env = ProcessInfo.processInfo.environment["MRDP_ENGINE_DYLIB"], !env.isEmpty {
            return env
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let names = [
                "engine/target/debug/libmrdpd_engine.dylib",
                "engine/target/debug/deps/libmrdpd_engine.dylib",
            ]
            for name in names {
                let candidate = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate.path
                }
            }
            dir.deleteLastPathComponent()
        }
        let cwd = FileManager.default.currentDirectoryPath
        for suffix in [
            "/engine/target/debug/libmrdpd_engine.dylib",
            "/engine/target/debug/deps/libmrdpd_engine.dylib",
        ] {
            let path = cwd + suffix
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        throw EngineError.dylibMissing("engine/target/debug/libmrdpd_engine.dylib")
    }
}
