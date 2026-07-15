import Security
import XCTest
@testable import Talkie_iOS

@MainActor
final class ComposeProviderCredentialStoreTests: XCTestCase {
    func testExactLookupDoesNotReturnLastProviderWithRequestedModel() {
        var storage: [String: Data] = [:]
        let store = ComposeProviderCredentialStore(
            readData: { storage[$0] },
            writeData: { data, account in
                storage[account] = data
                return errSecSuccess
            },
            removeData: { account in
                storage.removeValue(forKey: account)
                return errSecSuccess
            }
        )

        let anthropic = ComposeBorrowedProvider(
            providerId: "anthropic",
            providerName: "Anthropic",
            modelId: "claude-sonnet-4-6",
            apiKey: "sk-ant-test",
            assistantPrompt: "Test",
            fallbackReason: nil
        )
        XCTAssertTrue(store.save(anthropic))

        XCTAssertNil(
            store.load(providerId: "openai", modelId: "gpt-5.5"),
            "An exact OpenAI lookup must not return the last Anthropic credential"
        )
        XCTAssertEqual(store.load()?.providerId, "anthropic")
        XCTAssertEqual(store.load()?.modelId, "claude-sonnet-4-6")
    }
}
