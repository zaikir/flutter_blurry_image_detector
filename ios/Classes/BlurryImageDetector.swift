import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders
import Photos

public final class BlurryImageDetector: NSObject {
    // MARK: - GPU

    public let device: MTLDevice = MTLCreateSystemDefaultDevice()!
    public lazy var queue: MTLCommandQueue = device.makeCommandQueue()!
    private lazy var loader: MTKTextureLoader = .init(device: device)

    // MPS kernels
    private lazy var toGray = MPSImageConversion(device: device)
    private lazy var laplacian = MPSImageLaplacian(device: device)
    private lazy var stats = MPSImageStatisticsMeanAndVariance(device: device)
}
