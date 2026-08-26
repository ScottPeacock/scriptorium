import Foundation

/// Grimmory's DTOs are Lombok @Data classes, and Lombok's generated getters
/// change how Jackson names boolean properties:
///
///   private boolean isAdmin;     -> isAdmin()      -> JSON key "admin"
///   private Boolean isPhysical;  -> getIsPhysical() -> JSON key "isPhysical"
///
/// Primitive booleans lose the "is" prefix; boxed ones keep it. Rather than bet
/// on which spelling the server emits for each field, we accept both and let the
/// captured fixtures (Tools/capture-fixtures.sh) settle it. Once fixtures confirm
/// the real keys, this can collapse to plain CodingKeys.
extension KeyedDecodingContainer {
    /// Decodes a boolean that may arrive under either the `isFoo` or `foo` spelling.
    func decodeBoolEitherSpelling(_ key: K, stripped: K) throws -> Bool? {
        if let value = try decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        return try decodeIfPresent(Bool.self, forKey: stripped)
    }
}
