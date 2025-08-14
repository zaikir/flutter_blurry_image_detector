import Accelerate // optional but handy for scaling
import CoreVideo
import Photos

final class AssetToPixelBuffer {
    private let manager = PHCachingImageManager.default()

    /// Fetches a pixel buffer sized for your model (e.g., 224x224) as fast as possible.
    func pixelBuffer(
        from asset: PHAsset,
        inputSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        completion: @escaping (CVPixelBuffer?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        manager.requestImage(
            for: asset,
            targetSize: inputSize,
            contentMode: contentMode,
            options: options
        ) { image, _ in
            guard let cg = image?.cgImage else {
                completion(nil)
                return
            }
            completion(Self.cgImageToPixelBuffer(cg, size: inputSize))
        }
    }

    /// Convert CGImage to CVPixelBuffer (kCVPixelFormatType_32BGRA).
    private static func cgImageToPixelBuffer(_ cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        // ВАЖНО: добавили Metal + IOSurface, чтобы потом работал CVMetalTextureCache...
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary, // обязательна для zero-copy
            // (необязательно) kCVPixelBufferBytesPerRowAlignmentKey: 64
        ]

        var pxbuf: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA, // под .bgra8Unorm
            attrs as CFDictionary,
            &pxbuf
        )
        guard status == kCVReturnSuccess, let pb = pxbuf else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

        // Рисуем CGImage в буфер (CPU). Цветовое пространство — sRGB (по умолчанию для большинства изображений).
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(
            data: base,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .low // быстрее; для Laplacian достаточно
        ctx.setAllowsAntialiasing(false)
        ctx.setShouldAntialias(false)

        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))

        return pb
    }
}
