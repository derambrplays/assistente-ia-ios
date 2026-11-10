import Foundation
import Photos
import UIKit

/// Pega o print de tela mais recente da galeria.
///
/// É assim que o Joguim "vê" a tela do iPhone sem precisar de extensão de
/// transmissão: você tira um print (botão lateral + volume) e ele lê a imagem.
enum ScreenshotSource {
    static func requestAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            return true
        }
        if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
        }
        return false
    }

    /// Print mais recente, já reduzido para envio.
    static func latest(maxSide: CGFloat = 1280) async -> Data? {
        guard await requestAccess() else { return nil }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 12

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard assets.count > 0 else { return nil }

        var screenshot: PHAsset?
        assets.enumerateObjects { asset, _, stop in
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                screenshot = asset
                stop.pointee = true
            }
        }

        guard let asset = screenshot else { return nil }

        let imageOptions = PHImageRequestOptions()
        imageOptions.isSynchronous = true
        imageOptions.deliveryMode = .highQualityFormat
        imageOptions.resizeMode = .exact
        imageOptions.isNetworkAccessAllowed = true

        var picked: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: maxSide, height: maxSide),
            contentMode: .aspectFit,
            options: imageOptions
        ) { image, _ in
            picked = image
        }

        guard let image = picked else { return nil }

        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
