import CoreVideo
import Metal
import MetalPerformanceShaders

final class BlurDetectorGPU {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var cache: CVMetalTextureCache!

    // Reused MPS filters
    private let toGray: MPSImageConversion
    private let lap: MPSImageLaplacian
    private let stats: MPSImageStatisticsMeanAndVariance

    init?() {
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
                                    conversionInfo: .init(src: srcCS,
                                                          dst: dstCS))
        lap = MPSImageLaplacian(device: dev)
        stats = MPSImageStatisticsMeanAndVariance(device: dev)
    }

    /// Encodes BGRA -> luma -> Laplacian -> variance. Non-blocking, calls `completion` when ready.
    /// Reuse one shared `MTLCommandQueue` externally and throttle concurrency with a semaphore.
    func encodeVarianceOfLaplacian(_ pixelBuffer: CVPixelBuffer,
                                   queue extQueue: MTLCommandQueue? = nil,
                                   completion: @escaping (Float?) -> Void)
    {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

      
        var cvTex: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil,
                                                        .bgra8Unorm, w, h, 0, &cvTex)

        guard result == kCVReturnSuccess,
              let unwrappedTex = cvTex,
              let src = CVMetalTextureGetTexture(unwrappedTex)
        else {
            completion(nil); return
        }

        // Intermediates: luma + laplacian (single-channel)
        let grayDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: w, height: h, mipmapped: false)
        grayDesc.usage = [.shaderRead, .shaderWrite]
        grayDesc.storageMode = .private
        guard let gray = device.makeTexture(descriptor: grayDesc),
              let lapTex = device.makeTexture(descriptor: grayDesc)
        else {
            completion(nil); return
        }

        // Stats destination: 2x1 r32f (mean at (0,0), variance at (1,0))
        let statsDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 2, height: 1, mipmapped: false)
        statsDesc.storageMode = .shared
        statsDesc.usage = [.shaderRead, .shaderWrite]
        guard let statsTex = device.makeTexture(descriptor: statsDesc) else {
            completion(nil); return
        }

        let q = extQueue ?? queue
        guard let cmd = q.makeCommandBuffer() else { completion(nil); return }

        // BGRA -> luma
        toGray.encode(commandBuffer: cmd, sourceTexture: src, destinationTexture: gray)
        // Laplacian
        lap.encode(commandBuffer: cmd, sourceTexture: gray, destinationTexture: lapTex)
        // Mean & variance -> statsTex (2x1)
        stats.encode(commandBuffer: cmd, sourceTexture: lapTex, destinationTexture: statsTex)

        cmd.addCompletedHandler { _ in
            var out = [Float](repeating: 0, count: 2)
            let region = MTLRegionMake2D(0, 0, 2, 1)
            statsTex.getBytes(&out, bytesPerRow: 2 * MemoryLayout<Float>.size, from: region, mipmapLevel: 0)
            let variance = out[1] // (0) = mean, (1) = variance
            completion(variance)
        }
        cmd.commit()
    }
}
