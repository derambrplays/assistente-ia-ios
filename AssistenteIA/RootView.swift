import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var showSettings = false
    @State private var showConversations = false

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
        .fullScreenCover(isPresented: $store.voiceMode) {
            VoiceView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
                .environmentObject(store)
        }
        .overlay(alignment: .top) {
            if let banner = store.banner {
                Text(banner)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .onTapGesture { store.banner = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
