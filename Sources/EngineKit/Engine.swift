import CEngine
import Darwin
import FrameKit
import Foundation
import InputKit

public enum EngineError: Error, Equatable {
    case dylibMissing(String)
    case dylibOpen(String)
    case symbolMissing(String)
    case abiMismatch(found: UInt32)
    case code(Int32)
}

public struct EngineConfig: Sendable {
    public var bindHost: String
    public var bindPort: UInt16
    public var desktopWidth: UInt16
    public var desktopHeight: UInt16

    public init(
        bindHost: String = "127.0.0.1",
        bindPort: UInt16 = 0,
        desktopWidth: UInt16 = 64,
        desktopHeight: UInt16 = 64
    ) {
        self.bindHost = bindHost
        self.bindPort = bindPort
        self.desktopWidth = desktopWidth
        self.desktopHeight = desktopHeight
    }
}

/// Thin `dlopen` wrapper around ABI v1. Engine callbacks hop onto `callbackQueue` before `InputSink`.
public final class Engine: @unchecked Sendable {
    public static let expectedAbiVersion: UInt32 = 1

    private let handle: UnsafeMutableRawPointer
    private let abiVersionFn: @convention(c) () -> UInt32
    private let startFn:
        @convention(c) (UnsafePointer<MrdpdEngineConfig>?, UnsafePointer<MrdpdCallbacks>?) -> Int32
    private let stopFn: @convention(c) () -> Int32
    private let pushFn: @convention(c) (UnsafePointer<MrdpdFrame>?) -> Int32
    private let scriptMouseFn: (@convention(c) (UnsafePointer<MrdpdMouseEvent>?) -> Int32)?
    private let copyLastFrameFn:
        (@convention(c) (UnsafeMutablePointer<UInt8>?, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32)?

    private let callbackQueue: DispatchQueue
    private var sink: InputSink?
    private var started = false

    public init(
        dylibPath: String,
        callbackQueue: DispatchQueue = DispatchQueue(label: "mrdpd.engine.callbacks")
    ) throws {
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            throw EngineError.dylibMissing(dylibPath)
        }
        guard let handle = dylibPath.withCString({ dlopen($0, RTLD_NOW | RTLD_LOCAL) }) else {
            throw EngineError.dylibOpen(String(cString: dlerror()))
        }
        self.handle = handle
        self.callbackQueue = callbackQueue

        func require<T>(_ name: String) throws -> T {
            dlerror()
            guard let sym = dlsym(handle, name) else {
                dlclose(handle)
                throw EngineError.symbolMissing(name)
            }
            return unsafeBitCast(sym, to: T.self)
        }

        abiVersionFn = try require("mrdpd_engine_abi_version")
        let found = abiVersionFn()
        guard found == Self.expectedAbiVersion else {
            dlclose(handle)
            throw EngineError.abiMismatch(found: found)
        }
        startFn = try require("mrdpd_engine_start")
        stopFn = try require("mrdpd_engine_stop")
        pushFn = try require("mrdpd_engine_push_frame")

        dlerror()
        if let raw = dlsym(handle, "mrdpd_stub_script_mouse") {
            scriptMouseFn = unsafeBitCast(
                raw,
                to: (@convention(c) (UnsafePointer<MrdpdMouseEvent>?) -> Int32).self
            )
        } else {
            scriptMouseFn = nil
        }
        dlerror()
        if let raw = dlsym(handle, "mrdpd_stub_copy_last_frame") {
            copyLastFrameFn = unsafeBitCast(
                raw,
                to: (@convention(c) (UnsafeMutablePointer<UInt8>?, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32)
                    .self
            )
        } else {
            copyLastFrameFn = nil
        }
    }

    deinit {
        if started {
            _ = stopFn()
        }
        dlclose(handle)
    }

    public var abiVersion: UInt32 { abiVersionFn() }

    public func start(config: EngineConfig = EngineConfig(), sink: InputSink) throws {
        self.sink = sink
        let rc = config.bindHost.withCString { hostPtr in
            var cfg = MrdpdEngineConfig()
            cfg.bind_host = hostPtr
            cfg.bind_port = config.bindPort
            cfg.desktop_width = config.desktopWidth
            cfg.desktop_height = config.desktopHeight
            var cb = MrdpdCallbacks()
            cb.userdata = Unmanaged.passUnretained(self).toOpaque()
            cb.on_mouse = Engine.onMouseTrampoline
            cb.on_key = Engine.onKeyTrampoline
            return withUnsafePointer(to: &cfg) { cfgPtr in
                withUnsafePointer(to: &cb) { cbPtr in
                    startFn(cfgPtr, cbPtr)
                }
            }
        }
        try throwIfNeeded(rc)
        started = true
    }

    public func stop() {
        _ = stopFn()
        started = false
        sink = nil
    }

    public func push(_ frame: Frame) throws {
        try frame.pixels.withUnsafeBufferPointer { pixels in
            guard let base = pixels.baseAddress else {
                throw EngineError.code(MRDPD_ERR_INVAL)
            }
            let dirty = frame.dirtyRects.map { rect in
                MrdpdRect(x: rect.x, y: rect.y, w: rect.width, h: rect.height)
            }
            try dirty.withUnsafeBufferPointer { dirtyBuf in
                var cFrame = MrdpdFrame()
                cFrame.width = frame.width
                cFrame.height = frame.height
                cFrame.stride = frame.stride
                cFrame.format = MRDP_PIXEL_BGRA8888
                cFrame.pixels = base
                if dirty.isEmpty {
                    cFrame.dirty_rects = nil
                    cFrame.dirty_rect_count = 0
                } else {
                    cFrame.dirty_rects = dirtyBuf.baseAddress
                    cFrame.dirty_rect_count = UInt32(dirty.count)
                }
                try throwIfNeeded(withUnsafePointer(to: &cFrame, pushFn))
            }
        }
    }

    public func scriptMouseForTests(x: Int32, y: Int32, buttons: UInt32 = 0, wheel: Int16 = 0) throws {
        guard let scriptMouseFn else {
            throw EngineError.symbolMissing("mrdpd_stub_script_mouse")
        }
        var event = MrdpdMouseEvent(x: x, y: y, buttons: buttons, wheel: wheel)
        try throwIfNeeded(withUnsafePointer(to: &event, scriptMouseFn))
    }

    public func copyLastFramePixelsForTests(capacity: Int = 4096) throws -> [UInt8] {
        guard let copyLastFrameFn else {
            throw EngineError.symbolMissing("mrdpd_stub_copy_last_frame")
        }
        var buf = [UInt8](repeating: 0, count: capacity)
        var len: UInt32 = 0
        try buf.withUnsafeMutableBufferPointer { dest in
            try throwIfNeeded(copyLastFrameFn(dest.baseAddress, UInt32(dest.count), &len))
        }
        return Array(buf.prefix(Int(len)))
    }

    private func throwIfNeeded(_ rc: Int32) throws {
        if rc != MRDPD_OK {
            throw EngineError.code(rc)
        }
    }

    private static let onMouseTrampoline:
        @convention(c) (UnsafeMutableRawPointer?, MrdpdMouseEvent) -> Void = { userdata, event in
            guard let userdata else { return }
            let engine = Unmanaged<Engine>.fromOpaque(userdata).takeUnretainedValue()
            let input = InputEvent.mouse(
                x: event.x,
                y: event.y,
                buttons: event.buttons,
                wheel: event.wheel
            )
            engine.callbackQueue.async {
                engine.sink?.handle(input)
            }
        }

    private static let onKeyTrampoline:
        @convention(c) (UnsafeMutableRawPointer?, MrdpdKeyEvent) -> Void = { userdata, event in
            guard let userdata else { return }
            let engine = Unmanaged<Engine>.fromOpaque(userdata).takeUnretainedValue()
            let input = InputEvent.key(
                scancode: event.scancode,
                isExtended: event.extended != 0,
                isPressed: event.pressed != 0
            )
            engine.callbackQueue.async {
                engine.sink?.handle(input)
            }
        }
}

public enum StubEngineDylib {
    public static func path() throws -> String {
        if let env = ProcessInfo.processInfo.environment["MRDP_STUB_DYLIB"], !env.isEmpty {
            return env
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let names = [
                "engine/target/debug/libmrdpd_stub_engine.dylib",
                "engine/target/debug/deps/libmrdpd_stub_engine.dylib",
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
            "/engine/target/debug/libmrdpd_stub_engine.dylib",
            "/engine/target/debug/deps/libmrdpd_stub_engine.dylib",
        ] {
            let path = cwd + suffix
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        throw EngineError.dylibMissing("engine/target/debug/libmrdpd_stub_engine.dylib")
    }
}
