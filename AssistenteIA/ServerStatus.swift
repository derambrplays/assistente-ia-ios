import Foundation
import SwiftUI

/// Relógio do "servidor ocupado".
///
/// A cota gratuita renova à meia-noite no horário do Pacífico (onde ficam os
/// servidores). Aqui convertemos isso para o horário de Brasília, que é o do
/// usuário, e mostramos uma contagem regressiva até lá.
enum ServerStatus {
    static let pacific = TimeZone(identifier: "America/Los_Angeles") ?? .current
    static let brasilia = TimeZone(identifier: "America/Sao_Paulo") ?? .current

    /// Próxima meia-noite no Pacífico.
    static var nextReset: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? Date().addingTimeInterval(6 * 3600)
    }

    /// Horário de Brasília em que o servidor volta, por exemplo "05:00".
    static func resetClockBrasilia(from date: Date? = nil) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = brasilia
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date ?? nextReset)
    }

    /// Contagem regressiva no formato HH:MM:SS.
    static func countdown(until date: Date, now: Date = Date()) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Texto padrão quando o servidor está sobrecarregado.
    static func busyMessage(until date: Date) -> String {
        "O servidor está sobrecarregado agora. Ele volta a funcionar às \(resetClockBrasilia(from: date)) (horário de Brasília)."
    }
}

/// Aviso fixo no topo com a contagem regressiva até o servidor voltar.
struct ServerBusyBanner: View {
    let until: Date
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = until.timeIntervalSince(context.date)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(remaining > 0 ? "Servidor sobrecarregado" : "O servidor já deve ter voltado")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)

                    if remaining > 0 {
                        Text("Volta em \(ServerStatus.countdown(until: until, now: context.date))")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent2)

                        Text("Renova às \(ServerStatus.resetClockBrasilia(from: until)) (horário de Brasília)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textFaint)
                    } else {
                        Text("Tente de novo agora.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textDim)
                    }

                    Button(action: onRetry) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Tentar agora")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.accent.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.danger.opacity(0.35))
            )
        }
    }
}
