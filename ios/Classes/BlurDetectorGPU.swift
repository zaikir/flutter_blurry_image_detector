import CoreVideo
import Metal
import MetalPerformanceShaders

final class BlurDetectorGPU {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var cache: CVMetalTextureCache!

    // Reused MPS filters
    private let toGray: MPSImageConversion
    private let gauss: MPSImageGaussianBlur
    private let lap: MPSImageLaplacian
    private let stats: MPSImageStatisticsMeanAndVariance

    /// sigma — стандартное отклонение гаусса в пикселях (обычно 0.8–1.6)
    init?(gaussianSigma sigma: Float = 1.0) {
        guard let dev = MTLCreateSystemDefaultDevice(),
              MPSSupportsMTLDevice(dev),
              let q = dev.makeCommandQueue() else { return nil }
        device = dev
        queue = q
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)

        let srcCS = CGColorSpace(name: CGColorSpace.sRGB)!
        let dstCS = CGColorSpace(name: CGColorSpace.linearGray)!
        toGray = MPSImageConversion(device: dev,
                                    srcAlpha: .alphaIsOne,
                                    destAlpha: .alphaIsOne,
                                    backgroundColor: nil,
                                    conversionInfo: .init(src: srcCS, dst: dstCS))

        gauss = MPSImageGaussianBlur(device: dev, sigma: sigma)
        lap   = MPSImageLaplacian(device: dev)
        stats = MPSImageStatisticsMeanAndVariance(device: dev)

        // Убираем артефакты по краям
        gauss.edgeMode = .clamp
        lap.edgeMode   = .clamp
    }

    /// Encodes BGRA -> luma -> (Gaussian) -> Laplacian -> variance. Non-blocking.
    func encodeVarianceOfLaplacian(_ pixelBuffer: CVPixelBuffer,
                                   queue extQueue: MTLCommandQueue? = nil,
                                   completion: @escaping (Float?) -> Void)
    {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let n = w * h

        var cvTex: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm, w, h, 0, &cvTex)

        guard result == kCVReturnSuccess,
              let unwrappedTex = cvTex,
              let src = CVMetalTextureGetTexture(unwrappedTex)
        else { completion(nil); return }

        // Intermediates: gray, blurred, laplacian (single-channel r16f)
        let chanDesc: () -> MTLTextureDescriptor = {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float,
                                                             width: w, height: h, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            return d
        }
        guard let gray   = device.makeTexture(descriptor: chanDesc()),
              let blurTx = device.makeTexture(descriptor: chanDesc()),
              let lapTex = device.makeTexture(descriptor: chanDesc())
        else { completion(nil); return }

        // Stats destination: 2x1 r32f (mean at (0,0), variance at (1,0))
        let statsDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                                 width: 2, height: 1, mipmapped: false)
        statsDesc.storageMode = .shared
        statsDesc.usage = [.shaderRead, .shaderWrite]
        guard let statsTex = device.makeTexture(descriptor: statsDesc) else {
            completion(nil); return
        }

        let q = extQueue ?? queue
        guard let cmd = q.makeCommandBuffer() else { completion(nil); return }

        // BGRA -> luma
        toGray.encode(commandBuffer: cmd, sourceTexture: src, destinationTexture: gray)
        // Gaussian blur (LoG)
        gauss.encode(commandBuffer: cmd, sourceTexture: gray, destinationTexture: blurTx)
        // Laplacian
        lap.encode(commandBuffer: cmd, sourceTexture: blurTx, destinationTexture: lapTex)
        // Mean & variance -> statsTex (2x1)
        stats.encode(commandBuffer: cmd, sourceTexture: lapTex, destinationTexture: statsTex)

        cmd.addCompletedHandler { _ in
            var out = [Float](repeating: 0, count: 2)
            let region = MTLRegionMake2D(0, 0, 2, 1)
            statsTex.getBytes(&out, bytesPerRow: 2 * MemoryLayout<Float>.size, from: region, mipmapLevel: 0)
            let varPop  = out[1]  // σ² (population)

            // Bessel correction -> sample std dev
            let N  = max(2, n) // guard
            let k  = Float(N) / Float(N - 1)
            let stdSample = sqrt(max(0, varPop) * k)

            completion(stdSample)
        }
        cmd.commit()
        // Yield GPU time for UI rendering (16.67ms ≈ 60 FPS)
        cmd.waitUntilScheduled()
//         Thread.sleep(forTimeInterval: 0.008) // 8ms yield per image
    }
}
