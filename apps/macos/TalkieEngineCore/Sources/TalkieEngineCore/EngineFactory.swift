import Foundation
import TalkieKit

public enum TalkieEngineCoreFactory {
    @MainActor
    public static func makeEmbeddedEngine() -> any EmbeddedEngineRuntime {
        EngineService()
    }
}
