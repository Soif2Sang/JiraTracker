import SwiftUI

struct SourcesSettingsView: View {
    @ObservedObject var integrations: IntegrationSettingsStore
    @State private var organization = ""
    @State private var jiraSite = ""

    private var normalizedOrganization: String {
        organization.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedJiraSite: String {
        jiraSite.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isOrganizationValid: Bool {
        !normalizedOrganization.isEmpty
    }

    private var isJiraSiteValid: Bool {
        guard let url = URL(string: normalizedJiraSite), let host = url.host else { return false }
        return !host.isEmpty
    }

    private var hasChanges: Bool {
        normalizedOrganization != integrations.organization
            || normalizedJiraSite != integrations.jiraSiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(
                title: "Organisation GitHub",
                placeholder: IntegrationSettingsStore.defaultOrganization,
                text: $organization,
                isValid: isOrganizationValid,
                error: "Indiquez le nom de l'organisation GitHub."
            )
            field(
                title: "Site Atlassian",
                placeholder: IntegrationSettingsStore.defaultJiraSite,
                text: $jiraSite,
                isValid: isJiraSiteValid,
                error: "URL invalide. Exemple : https://votre-site.atlassian.net"
            )

            HStack {
                Button("Réinitialiser") {
                    integrations.reset()
                    syncDrafts()
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11, weight: .medium))
                Spacer()
                Button("Appliquer") {
                    if normalizedOrganization != integrations.organization {
                        integrations.githubOrganization = normalizedOrganization
                    }
                    if normalizedJiraSite != integrations.jiraSiteURL.trimmingCharacters(in: .whitespacesAndNewlines) {
                        integrations.jiraSiteURL = normalizedJiraSite
                    }
                    syncDrafts()
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 11, weight: .medium))
                .disabled(!hasChanges || !isOrganizationValid || !isJiraSiteValid)
            }

            Text("Changer de source réinitialise les données mises en cache et relance la synchronisation.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: syncDrafts)
    }

    private func syncDrafts() {
        organization = integrations.githubOrganization
        jiraSite = integrations.jiraSiteURL
    }

    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isValid: Bool,
        error: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isValid ? Color.clear : Color.red.opacity(0.7), lineWidth: 1)
                }
            if !isValid {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }
}
