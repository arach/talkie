//
//  GatewaySettingsView.swift
//  Talkie macOS
//
//  Settings view for the Gateway module - external API access (OpenAI, Anthropic, etc.)
//

import SwiftUI
import TalkieKit

struct GatewaySettingsView: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var providers: [ProviderInfo] = []
    @State private var isLoading = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.up.arrow.down.circle",
                title: "GATEWAY",
                subtitle: "External API access for inference providers."
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                // Module Status
                GatewayStatusSection(serverStatus: bridgeManager.bridgeStatus)

                if bridgeManager.bridgeStatus == .running {
                    Divider()

                    // Providers List
                    ProvidersSection(providers: providers, isLoading: isLoading)

                    Divider()

                    // Endpoints Info
                    EndpointsSection()
                }

                Divider()
                    .padding(.vertical, 4)

                // Info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Gateway provides a unified API for external inference providers. Configure API keys in Settings → AI Models → Providers & Keys.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .onAppear {
            if bridgeManager.bridgeStatus == .running {
                loadProviders()
            }
        }
        .onChange(of: bridgeManager.bridgeStatus) { _, newStatus in
            if newStatus == .running {
                loadProviders()
            }
        }
    }

    private func loadProviders() {
        isLoading = true

        Task {
            do {
                guard let url = URL(string: "http://localhost:8765/inference/providers") else { return }
                let (data, _) = try await URLSession.shared.data(from: url)

                struct ProvidersResponse: Codable {
                    let providers: [String]
                }

                let response = try JSONDecoder().decode(ProvidersResponse.self, from: data)
                await MainActor.run {
                    providers = response.providers.map { name in
                        ProviderInfo(
                            name: name,
                            displayName: name.capitalized,
                            icon: iconFor(name),
                            isConfigured: true // TODO: Check API key status
                        )
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    // Default providers if fetch fails
                    providers = [
                        ProviderInfo(name: "openai", displayName: "OpenAI", icon: "brain", isConfigured: false),
                        ProviderInfo(name: "anthropic", displayName: "Anthropic", icon: "sparkles", isConfigured: false),
                        ProviderInfo(name: "google", displayName: "Google", icon: "g.circle", isConfigured: false),
                        ProviderInfo(name: "groq", displayName: "Groq", icon: "bolt", isConfigured: false)
                    ]
                    isLoading = false
                }
            }
        }
    }

    private func iconFor(_ provider: String) -> String {
        switch provider.lowercased() {
        case "openai": return "brain"
        case "anthropic": return "sparkles"
        case "google": return "g.circle"
        case "groq": return "bolt"
        default: return "cloud"
        }
    }
}

// MARK: - Provider Info

struct ProviderInfo: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let icon: String
    let isConfigured: Bool
}

// MARK: - Gateway Status Section

private struct GatewayStatusSection: View {
    let serverStatus: BridgeManager.BridgeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("MODULE STATUS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 12) {
                Image(systemName: isLoaded ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 24))
                    .foregroundColor(isLoaded ? .green : .gray)
                    .frame(width: 40, height: 40)
                    .background((isLoaded ? Color.green : Color.gray).opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoaded ? "Loaded" : "Not Loaded")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(statusDescription)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)
        }
    }

    private var isLoaded: Bool {
        serverStatus == .running
    }

    private var statusDescription: String {
        switch serverStatus {
        case .running: return "Gateway module active on TalkieServer"
        case .stopped: return "Start TalkieServer to enable Gateway"
        case .starting: return "Server starting..."
        case .error: return "Server error - Gateway unavailable"
        }
    }
}

// MARK: - Providers Section

private struct ProvidersSection: View {
    let providers: [ProviderInfo]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cloud")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("PROVIDERS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            if isLoading {
                HStack {
                    BrailleSpinner(speed: 0.08)
                        .font(.system(size: 12))
                    Text("Loading providers...")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(providers) { provider in
                        ProviderRow(provider: provider)
                    }
                }
            }
        }
    }
}

private struct ProviderRow: View {
    let provider: ProviderInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)

            Text(provider.displayName)
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            Text("Available")
                .font(Theme.current.fontXS)
                .foregroundColor(.green)
        }
        .padding(10)
        .background(Theme.current.surface1)
        .cornerRadius(6)
    }
}

// MARK: - Endpoints Section

private struct EndpointsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("ENDPOINTS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                EndpointRow(
                    method: "POST",
                    path: "/inference",
                    description: "Run inference with any provider"
                )
                EndpointRow(
                    method: "GET",
                    path: "/inference/providers",
                    description: "List available providers"
                )
                EndpointRow(
                    method: "GET",
                    path: "/inference/models",
                    description: "List models for a provider"
                )
            }
            .padding(10)
            .background(Theme.current.surface1)
            .cornerRadius(8)
        }
    }
}

private struct EndpointRow: View {
    let method: String
    let path: String
    let description: String

    var body: some View {
        HStack(spacing: 8) {
            Text(method)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(methodColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(methodColor.opacity(0.15))
                .cornerRadius(3)

            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.current.foreground)

            Spacer()

            Text(description)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private var methodColor: Color {
        switch method {
        case "GET": return .green
        case "POST": return .blue
        case "PUT": return .orange
        case "DELETE": return .red
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    GatewaySettingsView()
        .frame(width: 500, height: 600)
        .padding()
}
