#if os(Windows)
import WinSDK

internal struct Thread: ~Copyable {
    private var handle: HANDLE?

    private final class Box {
        let body: () -> Void

        init(_ body: @escaping () -> Void) {
            self.body = body
        }
    }

    public init(_ body: @escaping () -> Void) {
        let box = Unmanaged.passRetained(Box(body))
        self.handle = CreateThread(
            nil,
            0,
            { rawArg in
                let box = Unmanaged<Box>.fromOpaque(rawArg!).takeRetainedValue()
                box.body()
                return 0
            },
            box.toOpaque(),
            0,
            nil
        )
    }

    public mutating func join() {
        if let handle {
            _ = WaitForSingleObject(handle, DWORD(INFINITE))
            _ = CloseHandle(handle)
            self.handle = nil
        }
    }

    public mutating func detach() {
        if let handle {
            _ = CloseHandle(handle)
            self.handle = nil
        }
    }

    deinit {
        if let handle {
            _ = CloseHandle(handle)
        }
    }
}
#endif