// GamehubMockCore - Phase 1 skeleton
// Mock core for launcher builds on iOS Simulator

public struct GamehubMockCore {
    public init() {}

    public var version: String {
        "mock-0.1.0"
    }

    public func launchGame() {
        print("[MockCore] launchGame called (no-op)")
    }
}
