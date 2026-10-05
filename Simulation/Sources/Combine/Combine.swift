// Minimal Combine stand-in: @Published, AnyCancellable and a manually fired
// Timer publisher (tests call FakeTimers.fire() to advance the app's ticker).
import Foundation

public protocol ObservableObject: AnyObject {}

public final class AnyCancellable: Hashable {
    private var cancelAction: (() -> Void)?
    public init(_ cancel: @escaping () -> Void) { cancelAction = cancel }
    deinit { cancel() }
    public func cancel() { cancelAction?(); cancelAction = nil }
    public func store(in set: inout Set<AnyCancellable>) { set.insert(self) }
    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

@propertyWrapper
public struct Published<Value> {
    final class Box {
        var value: Value
        var subscribers: [UUID: (Value) -> Void] = [:]
        init(_ value: Value) { self.value = value }
    }

    let box: Box

    public init(wrappedValue: Value) { box = Box(wrappedValue) }

    public var wrappedValue: Value {
        get { box.value }
        nonmutating set {
            // Like Combine, subscribers hear about the change as it happens (willSet).
            for subscriber in box.subscribers.values { subscriber(newValue) }
            box.value = newValue
        }
    }

    public var projectedValue: Publisher { Publisher(box: box) }

    public struct Publisher {
        let box: Box
        public func receive<S>(on scheduler: S) -> Publisher { self }
        public func sink(receiveValue: @escaping (Value) -> Void) -> AnyCancellable {
            let id = UUID()
            box.subscribers[id] = receiveValue
            receiveValue(box.value)
            let box = self.box
            return AnyCancellable { box.subscribers[id] = nil }
        }
    }
}

public enum FakeTimers {
    public static var handlers: [UUID: (Date) -> Void] = [:]
    public static var activeCount: Int { handlers.count }
    public static func fire() {
        for handler in Array(handlers.values) { handler(Date()) }
    }
}

public struct TimerPublisher {
    public func autoconnect() -> TimerPublisher { self }
    public func sink(receiveValue: @escaping (Date) -> Void) -> AnyCancellable {
        let id = UUID()
        FakeTimers.handlers[id] = receiveValue
        return AnyCancellable { FakeTimers.handlers[id] = nil }
    }
}

extension Timer {
    public static func publish(every interval: TimeInterval, on runLoop: RunLoop, in mode: RunLoop.Mode) -> TimerPublisher {
        TimerPublisher()
    }
}
