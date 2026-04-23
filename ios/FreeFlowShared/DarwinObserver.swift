import Foundation

public final class DarwinObserver {
    private var tokens: [(name: String, callback: () -> Void)] = []
    private var observerHandle: UnsafeMutableRawPointer?

    public init() {
        self.observerHandle = UnsafeMutableRawPointer(bitPattern: UInt(ObjectIdentifier(self).hashValue) | 1)
    }

    deinit { removeAll() }

    public func add(name: String, callback: @escaping () -> Void) {
        tokens.append((name: name, callback: callback))
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let nameRef = CFNotificationName(name as CFString)
        let context = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            context,
            { _, observer, cfName, _, _ in
                guard let observer, let cfName else { return }
                let receiver = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
                let received = cfName.rawValue as String
                DispatchQueue.main.async {
                    for token in receiver.tokens where token.name == received {
                        token.callback()
                    }
                }
            },
            nameRef.rawValue,
            nil,
            .deliverImmediately
        )
    }

    public func removeAll() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let context = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(center, context)
        tokens.removeAll()
    }
}
