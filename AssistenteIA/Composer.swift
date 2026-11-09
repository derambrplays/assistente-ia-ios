import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct Composer: View {
    @Binding var text: String
    @Binding var attachments: [Attachment]
    var isSending: Bool
    @FocusState.Binding var focused: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    var onVoice: () -> Void
    var onError: (String) -> Void

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var loading = false

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 7) {
            if !attachments.isEmpty {
                previewStrip
            }

            HStack(alignment: .bottom, spacing: 7) {
                Button {
                    focused = false
                    onVoice()
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.accent.opacity(0.22)))
                        .overlay(Circle().strokeBorder(Theme.accent.opacity(0.45)))
                }
                .buttonStyle(PressableStyle())
                .fixedSize()

                Menu {
                    Button {
                        showPhotos = true
                    } label: {
                        Label("Fotos", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        showFiles = true
                    } label: {
                        Label("Arquivo", systemImage: "folder")
                    }
                } label: {
                    Group {
                        if loading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperclip")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Theme.hairline))
                }
                .buttonStyle(PressableStyle())
                .fixedSize()
                .disabled(loading || attachments.count >= AttachmentStore.maxCount)

                TextField("Pergunte algo…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(Theme.hairline)
                    )

                Button {
                    if isSending {
                        onStop()
                    } else {
                        focused = false
                        onSend()
                    }
                } label: {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isSending || canSend ? Color.white : Color.white.opacity(0.45))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(
                                isSending
                                    ? AnyShapeStyle(Color.white.opacity(0.16))
                                    : AnyShapeStyle(
                                        LinearGradient(
                                            colors: canSend
                                                ? [Theme.accent, Theme.accent.opacity(0.75)]
                                                : [Color.white.opacity(0.10), Color.white.opacity(0.07)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                        )
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22)))
                }
                .buttonStyle(PressableStyle())
                .disabled(!isSending && !canSend)
                .fixedSize()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 23, strength: 0.9)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .photosPicker(
            isPresented: $showPhotos,
            selection: $photoItems,
            maxSelectionCount: AttachmentStore.maxCount,
            matching: .images
        )
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            loadPhotos(items)
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                addFiles(urls)
            case .failure:
                onError("Não consegui abrir o arquivo escolhido.")
            }
        }
    }

    // MARK: - Anexos escolhidos

    private var previewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 7) {
                        thumbnail(for: attachment)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(attachment.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(attachment.sizeText)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .frame(maxWidth: 120, alignment: .leading)

                        Button {
                            remove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func thumbnail(for attachment: Attachment) -> some View {
        if let image = AttachmentStore.image(for: attachment) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: attachment.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent2)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        loading = true
        Task {
            var added: [Attachment] = []
            var failed = false

            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let jpeg = AttachmentStore.compressedImageData(data),
                   let attachment = AttachmentStore.make(
                       name: "Foto \(index + 1).jpg",
                       mimeType: "image/jpeg",
                       data: jpeg
                   ) {
                    added.append(attachment)
                } else {
                    failed = true
                }
            }

            await MainActor.run {
                photoItems = []
                loading = false
                append(added)
                if failed {
                    onError("Não consegui carregar algumas fotos.")
                }
            }
        }
    }

    private func addFiles(_ urls: [URL]) {
        loading = true
        var added: [Attachment] = []
        var failed = false

        for url in urls {
            if attachments.count + added.count >= AttachmentStore.maxCount {
                failed = true
                break
            }
            if let attachment = AttachmentStore.makeFile(url: url) {
                added.append(attachment)
            } else {
                failed = true
            }
        }

        loading = false
        append(added)
        if failed {
            onError("Alguns arquivos não puderam ser anexados (limite de 8 MB por arquivo).")
        }
    }

    private func append(_ items: [Attachment]) {
        var list = attachments

        for item in items {
            guard list.count < AttachmentStore.maxCount else {
                onError("Você pode anexar até \(AttachmentStore.maxCount) arquivos por mensagem.")
                AttachmentStore.remove(item)
                break
            }
            guard AttachmentStore.totalBytes(list) + item.byteCount <= AttachmentStore.maxTotalBytes else {
                onError("Os anexos passaram do limite de 14 MB por mensagem.")
                AttachmentStore.remove(item)
                break
            }
            list.append(item)
        }

        attachments = list
    }

    private func remove(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
        AttachmentStore.remove(attachment)
    }
}
