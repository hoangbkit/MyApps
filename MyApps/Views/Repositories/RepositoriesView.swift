import SwiftUI

struct RepositoriesView: View {
    @StateObject private var session = GitHubSession()
    @State private var token = ""

    var body: some View {
        Group {
            switch session.connectionState {
            case .loading:
                ProgressView("Connecting to GitHub…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .disconnected:
                connectionView

            case let .connected(account):
                connectedView(account)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Repos")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await session.restore()
        }
        .alert(
            "GitHub",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var connectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect GitHub")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Connect your GitHub account to use repository history and Git operations from MyApps.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Personal access token")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    SecureField("github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .padding(12)
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    Text("The token is validated with GitHub and stored only in this device's Keychain.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        if await session.connect(token: token) {
                            token = ""
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if session.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(session.isWorking ? "Connecting…" : "Connect GitHub")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    session.isWorking ||
                    token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
    }

    private func connectedView(_ account: GitHubAccount) -> some View {
        List {
            Section("GitHub") {
                LabeledContent {
                    Text("@\(account.login)")
                } label: {
                    Label("Account", systemImage: "person.crop.circle.badge.checkmark")
                }

                Button(role: .destructive) {
                    session.disconnect()
                } label: {
                    Label("Disconnect GitHub", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                ContentUnavailableView(
                    "Repositories Coming Next",
                    systemImage: "shippingbox",
                    description: Text("Phase 2 will load and search repositories available to @\(account.login).")
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }
}
