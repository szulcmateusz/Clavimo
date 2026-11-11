import Testing
@testable import ClavimoQuartz

@Suite("Caps Lock mapping")
struct CapsLockMappingTests {
    /// Clavimo 1.2.0 crashed at launch here: the HID client was released
    /// while its keyboard services were still in use. With no Clavimo
    /// entry present this only reads the keyboards' settings.
    @Test func cleaningUpRepeatedlyIsSafe() {
        for _ in 0..<200 {
            CapsLockMapping.removeAll()
        }
    }
}
