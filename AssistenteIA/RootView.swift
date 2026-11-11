import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var showSettings = false
    @State private var showConversations = false
    @State private var showWhatsNew = false
    @AppStorage("lastSeenBuild") private var lastSeenBuild = ""

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { store.hasKey && !store.settings.onboardingDone },
            set: { showing in
                if !showing {
                    store.settings.onboardingDone = true
                    store.save()
                }
            }
        )
    }

    /// Mostra a tela de novidades uma vez por atualização instalada.
    private func checkWhatsNew() {
        guard store.hasKey, store.settings.onboardingDone else { return }
        guard lastSeenBuild != AppInfo.buildKey else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard lastSeenBuild != AppInfo.buildKey else { return }
            showWhatsNew = true
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            if store.hasKey {
                ChatView(showSettings: $showSettings, showConversations: $showConversations)
                    .transition(.opacity)
            } else {
                KeyEntryView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.hasKey)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showConversations) {
            ConversationsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: { lastSeenBuild = AppInfo.buildKey }) {
            WhatsNewView()
                .environmentObject(store)
        }
        .onAppear { checkWhatsNew() }
        .onChange(of: store.hasKey) { _ in checkWhatsNew() }
        .onChange(of: store.settings.onboardingDone) { _ in checkWhatsNew() }
        .fullScreenCover(isPresented: $store.voiceMode) {
            VoiceView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
                .environmentObject(store)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let until = store.serverBusyUntil {
                    ServerBusyBanner(
                        until: until,
                        onRetry: { store.retryServer() },
                        onDismiss: { store.serverBusyUntil = nil }
                    )
                }

                if let banner = store.banner {
                    Text(banner)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.hairline))
                        .onTapGesture { store.banner = nil }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }
}
