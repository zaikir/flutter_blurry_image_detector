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
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pxbuf: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pxbuf
        )
        guard status == kCVReturnSuccess, let pb = pxbuf else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }

        // Draw the CGImage into the pixel buffer.
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: base,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Clear & draw (no explicit colors to keep it simple)
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return pb
    }
}
