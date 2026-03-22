import Testing
@testable import DexBar

@Suite("KeychainHelper", .serialized)
struct KeychainHelperTests {

    private let key = "test.keychain.unit"

    init() {
        // Clean up before each test
        KeychainHelper.delete(for: key)
    }

    @Test func saveAndLoad() {
        KeychainHelper.save("hello", for: key)
        #expect(KeychainHelper.load(for: key) == "hello")
    }

    @Test func loadMissingKeyReturnsNil() {
        #expect(KeychainHelper.load(for: key) == nil)
    }

    @Test func overwriteUpdatesValue() {
        KeychainHelper.save("first", for: key)
        KeychainHelper.save("second", for: key)
        #expect(KeychainHelper.load(for: key) == "second")
    }

    @Test func deleteRemovesValue() {
        KeychainHelper.save("value", for: key)
        KeychainHelper.delete(for: key)
        #expect(KeychainHelper.load(for: key) == nil)
    }

    @Test func deleteMissingKeyDoesNotCrash() {
        // Should complete without throwing or crashing
        KeychainHelper.delete(for: key)
    }

    @Test func saveEmptyString() {
        KeychainHelper.save("", for: key)
        #expect(KeychainHelper.load(for: key) == "")
    }

    @Test func saveUnicodeValue() {
        KeychainHelper.save("pässwörd✓", for: key)
        #expect(KeychainHelper.load(for: key) == "pässwörd✓")
    }
}
