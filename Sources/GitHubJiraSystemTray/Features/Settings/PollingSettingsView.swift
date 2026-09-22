import SwiftUI

struct PollingSettingsView: View {
    @ObservedObject var polling: PollingSettingsStore
    @ObservedObject var store: AppStore
    @ObservedObject var jiraStore: JiraStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            rateLimitCard

            Toggle("Activer l'actualisation automatique", isOn: $polling.isEnabled)
                .font(.system(size: 12, weight: .medium))
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                intervalRow(
                    title: "Découverte des PR",
                    subtitle: "Recherche des nouvelles pull requests GitHub.",
                    value: $polling.discoveryInterval,
                    range: 60...1800,
                    step: 30
                )
                intervalRow(
                    title: "CI en cours",
                    subtitle: "Rafraîchissement tant qu'un pipeline tourne.",
                    value: $polling.runningInterval,
                    range: 10...600,
                    step: 5
                )
                intervalRow(
                    title: "CI terminée",
                    subtitle: "Rafraîchissement au repos.",
                    value: $polling.idleInterval,
                    range: 30...1800,
                    step: 30
                )
                intervalRow(
                    title: "Quota GitHub faible",
                    subtitle: "Fréquence réduite sous le seuil de requêtes restantes.",
                    value: $polling.lowRateLimitInterval,
                    range: 60...3600,
                    step: 30
                )
                stepperRow(
                    title: "Seuil de quota bas",
                    subtitle: "Nombre de requêtes restantes déclenchant la réduction.",
                    value: $polling.lowRateLimitThreshold,
                    range: 0...1000,
                    step: 10,
                    label: "\(polling.lowRateLimitThreshold) req."
                )
                intervalRow(
                    title: "Tickets Jira",
                    subtitle: "Intervalle de rafraîchissement Jira Cloud.",
                    value: $polling.jiraInterval,
                    range: 60...1800,
                    step: 30
                )
            }

            HStack {
                Text(lastUpdatedLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Réinitialiser") { polling.reset() }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11, weight: .medium))
            }
        }
    }

    private var rateLimitCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Quota GitHub", systemImage: "speedometer")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let rateLimit = store.rateLimit, let reset = rateLimit.reset {
                    Text("Reset \(resetLabel(reset))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let rateLimit = store.rateLimit {
                let total = Double(max(rateLimit.limit, 1))
                ProgressView(value: Double(max(rateLimit.remaining, 0)), total: total)
                    .tint(rateLimit.remaining < polling.lowRateLimitThreshold ? .orange : .green)
                Text("\(rateLimit.remaining) requêtes restantes sur \(rateLimit.limit)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Aucune donnée de quota pour le moment.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func intervalRow(
        title: String,
        subtitle: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        stepperRow(
            title: title,
            subtitle: subtitle,
            value: value,
            range: range,
            step: step,
            label: durationLabel(value.wrappedValue)
        )
    }

    private func stepperRow<Value: Strideable>(
        title: String,
        subtitle: String,
        value: Binding<Value>,
        range: ClosedRange<Value>,
        step: Value.Stride,
        label: String
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
        .frame(minHeight: 38)
    }

    private func durationLabel(_ seconds: Double) -> String {
        let value = Int(seconds.rounded())
        if value < 60 { return "\(value) s" }
        let minutes = value / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours) h" : "\(hours) h \(remainingMinutes) min"
    }

    private func resetLabel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var lastUpdatedLabel: String {
        let dates = [store.lastUpdated, jiraStore.lastUpdated].compactMap { $0 }
        guard let date = dates.min() else { return "Pas encore synchronisé" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Dernière mise à jour : \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
