import Foundation
import Security

final class CredentialStore {
    private let service = "com.local.github-jira-system-tray"
    private let account = "github-personal-access-token"

    func readGitHubToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    @discardableResult
    func saveGitHubToken(_ token: String) -> Bool {
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !data.isEmpty else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func deleteGitHubToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func tokenFromEnvironment() -> String? {
        let environment = ProcessInfo.processInfo.environment
        return [environment["GITHUB_TOKEN"], environment["GH_TOKEN"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// Reads only simple assignments; it never executes the user's shell configuration.
    func tokenFromEnvironmentOrZshrc() -> String? {
        shellValue(for: ["GITHUB_TOKEN", "GH_TOKEN"])
    }

    func readJiraToken() -> String? {
        readValue(service: service, account: "jira-api-token")
    }

    func readJiraEmail() -> String? {
        readValue(service: service, account: "jira-account-email")
    }

    @discardableResult
    func saveJiraCredentials(email: String, token: String) -> Bool {
        saveValue(email, service: service, account: "jira-account-email")
            && saveValue(token, service: service, account: "jira-api-token")
    }

    func deleteJiraCredentials() {
        deleteValue(service: service, account: "jira-account-email")
        deleteValue(service: service, account: "jira-api-token")
    }

    func jiraTokenFromEnvironmentOrZshrc() -> String? {
        shellValue(for: [
            "JIRA_TOKEN",
            "JIRA_API_TOKEN",
            "JIRA_API_KEY",
            "JIRA_PAT",
            "ATLASSIAN_API_TOKEN",
            "ATLASSIAN_TOKEN"
        ])
    }

    func jiraEmailFromEnvironmentOrZshrc() -> String? {
        shellValue(for: [
            "JIRA_EMAIL",
            "ATLASSIAN_EMAIL",
            "ATLASSIAN_ACCOUNT_EMAIL"
        ])
    }

    private func readValue(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func saveValue(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !data.isEmpty else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess {
            return true
        }
        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func deleteValue(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Returns the first non-empty value found in the process environment, then in `~/.zshrc`.
    private func shellValue(for names: [String]) -> String? {
        let environment = ProcessInfo.processInfo.environment
        for name in names {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        guard let contents = try? String(contentsOf: zshrcURL, encoding: .utf8) else { return nil }
        for rawLine in contents.components(separatedBy: .newlines) {
            guard let assignment = parseAssignment(rawLine),
                  names.contains(where: { $0.caseInsensitiveCompare(assignment.name) == .orderedSame }) else {
                continue
            }
            let value = unquotedValue(assignment.value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !value.hasPrefix("$") {
                return value
            }
        }
        return nil
    }

    private var zshrcURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
    }

    private func parseAssignment(_ rawLine: String) -> (name: String, value: String)? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.hasPrefix("#") else { return nil }
        if line.hasPrefix("export ") {
            line.removeFirst("export ".count)
        }
        guard let equalsIndex = line.firstIndex(of: "=") else { return nil }
        let name = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(line[line.index(after: equalsIndex)...])
        return (String(name), value)
    }

    private func unquotedValue(_ rawValue: String) -> String {
        if rawValue.hasPrefix("\""), let end = rawValue.dropFirst().firstIndex(of: "\"") {
            return String(rawValue.dropFirst()[..<end])
        }
        if rawValue.hasPrefix("'"), let end = rawValue.dropFirst().firstIndex(of: "'") {
            return String(rawValue.dropFirst()[..<end])
        }
        return rawValue.split(separator: "#", maxSplits: 1).first.map(String.init) ?? rawValue
    }
}
