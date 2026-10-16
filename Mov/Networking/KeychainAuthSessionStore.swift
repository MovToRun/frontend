import Foundation
import Security

enum AuthSessionKeychainAccessibility: Equatable, Sendable {
    case afterFirstUnlockThisDeviceOnly
}

protocol AuthSessionKeychainAccess: Sendable {
    func readData(service: String, account: String, synchronizable: Bool) throws -> Data?
    func replaceData(
        _ data: Data,
        service: String,
        account: String,
        accessibility: AuthSessionKeychainAccessibility,
        synchronizable: Bool
    ) throws
    func deleteData(service: String, account: String, synchronizable: Bool) throws
}

enum AuthSessionKeychainStoreError: Error, Equatable {
    case keychainUnavailable
    case invalidStoredSnapshot
    case encodingFailure
}

/// The app session and any refresh recovery request ID are stored as one Keychain item.
/// Share `shared` with every auth client in the app so they also share one mutation actor.
final class KeychainAuthSessionStore: AuthSessionStoring, @unchecked Sendable {
    static let shared = KeychainAuthSessionStore()

    let mutationCoordinator: AuthSessionMutationCoordinator

    private let keychain: any AuthSessionKeychainAccess
    private let service: String
    private let account: String
    private let lock = NSLock()

    init(
        service: String = KeychainAuthSessionStore.defaultService,
        account: String = "current-session-v1",
        keychain: any AuthSessionKeychainAccess = SecurityAuthSessionKeychainAccess()
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
        self.mutationCoordinator = AuthSessionKeychainCoordinatorRegistry.shared.coordinator(service: service, account: account)
    }

    func loadSnapshot() throws -> AuthSessionSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        let data: Data?
        do {
            data = try keychain.readData(service: service, account: account, synchronizable: false)
        } catch {
            throw AuthSessionKeychainStoreError.keychainUnavailable
        }
        guard let data else { return nil }

        do {
            let record = try JSONDecoder().decode(AuthSessionKeychainRecord.self, from: data)
            return try record.makeSnapshot()
        } catch {
            throw AuthSessionKeychainStoreError.invalidStoredSnapshot
        }
    }

    func replaceAtomically(with snapshot: AuthSessionSnapshot?) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let snapshot else {
            do {
                try keychain.deleteData(service: service, account: account, synchronizable: false)
                return
            } catch {
                throw AuthSessionKeychainStoreError.keychainUnavailable
            }
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(AuthSessionKeychainRecord(snapshot: snapshot))
        } catch {
            throw AuthSessionKeychainStoreError.encodingFailure
        }

        do {
            try keychain.replaceData(
                data,
                service: service,
                account: account,
                accessibility: .afterFirstUnlockThisDeviceOnly,
                synchronizable: false
            )
        } catch {
            throw AuthSessionKeychainStoreError.keychainUnavailable
        }
    }

    static var defaultService: String {
        "\(Bundle.main.bundleIdentifier ?? "com.movtorun.mov").auth-session"
    }
}

private struct AuthSessionKeychainRecord: Codable {
    let accessToken: String
    let refreshToken: String
    let memberID: String
    let refreshRequestID: UUID?

    init(snapshot: AuthSessionSnapshot) {
        accessToken = snapshot.accessToken
        refreshToken = snapshot.refreshToken
        memberID = snapshot.memberID
        refreshRequestID = snapshot.refreshRequestID
    }

    func makeSnapshot() throws -> AuthSessionSnapshot {
        try AuthSessionSnapshot(
            accessToken: accessToken,
            refreshToken: refreshToken,
            memberID: memberID,
            refreshRequestID: refreshRequestID
        )
    }
}

private final class AuthSessionKeychainCoordinatorRegistry: @unchecked Sendable {
    static let shared = AuthSessionKeychainCoordinatorRegistry()

    private struct Identity: Hashable {
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var coordinators: [Identity: AuthSessionMutationCoordinator] = [:]

    func coordinator(service: String, account: String) -> AuthSessionMutationCoordinator {
        lock.lock()
        defer { lock.unlock() }

        let identity = Identity(service: service, account: account)
        if let coordinator = coordinators[identity] { return coordinator }

        let coordinator = AuthSessionMutationCoordinator()
        coordinators[identity] = coordinator
        return coordinator
    }
}

private struct SecurityAuthSessionKeychainAccess: AuthSessionKeychainAccess {
    func readData(service: String, account: String, synchronizable: Bool) throws -> Data? {
        var query = Self.identityQuery(service: service, account: account, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthSessionKeychainStoreError.keychainUnavailable }
        guard let data = result as? Data else { throw AuthSessionKeychainStoreError.invalidStoredSnapshot }
        return data
    }

    func replaceData(
        _ data: Data,
        service: String,
        account: String,
        accessibility: AuthSessionKeychainAccessibility,
        synchronizable: Bool
    ) throws {
        let identity = Self.identityQuery(service: service, account: account, synchronizable: synchronizable)
        let attributes = Self.valueAttributes(data, accessibility: accessibility)
        var status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var item = identity
            item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
            }
        }

        guard status == errSecSuccess else { throw AuthSessionKeychainStoreError.keychainUnavailable }
    }

    func deleteData(service: String, account: String, synchronizable: Bool) throws {
        let status = SecItemDelete(Self.identityQuery(service: service, account: account, synchronizable: synchronizable) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthSessionKeychainStoreError.keychainUnavailable
        }
    }

    private static func identityQuery(service: String, account: String, synchronizable: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
        ]
    }

    private static func valueAttributes(
        _ data: Data,
        accessibility: AuthSessionKeychainAccessibility
    ) -> [String: Any] {
        let keychainAccessibility: CFString
        switch accessibility {
        case .afterFirstUnlockThisDeviceOnly:
            keychainAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        return [
            kSecValueData as String: data,
            kSecAttrAccessible as String: keychainAccessibility
        ]
    }
}
