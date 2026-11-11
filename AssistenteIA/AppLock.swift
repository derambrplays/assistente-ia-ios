import Foundation
import LocalAuthentication
import SwiftUI

/// Tranca o app com Face ID / Touch ID / código do iPhone.
///
/// É opcional (Ajustes → Privacidade). Serve para as conversas não ficarem
/// à vista se alguém pegar o aparelho emprestado.
final class AppLock: ObservableObject {
    @Published var locked = false

    private var authenticating = false

    func lock() {
        locked = true
    }

    /// Pede a biometria. Se o iPhone não tiver Face ID/Touch ID nem código
    /// configurado, libera — prender a pessoa fora do próprio app seria pior.
    func unlock() {
        guard !authenticating else { return }
        authenticating = true

        let context = LAContext()
        context.localizedCancelTitle = "Agora não"
        context.localizedFallbackTitle = "Usar código"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticating = false
            locked = false
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Desbloquear o Joguim AI"
        ) { success, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                if success {
                    self.locked = false
                }
            }
        }
    }
}

/// Tela que cobre o app enquanto está trancado.
struct LockScreenView: View {
    var onUnlock: () -> Void

    @State private var tried = false

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 14) {
                SparkleMark(size: 60)

                Text("Joguim AI")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("Suas conversas estão protegidas.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textDim)

                Button {
                    onUnlock()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "faceid")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Desbloquear")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Theme.accent.opacity(0.9)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 18, x: 0, y: 8)
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 10)
            }
            .padding(30)
        }
        .onAppear {
            guard !tried else { return }
            tried = true
            onUnlock()
        }
    }
}
