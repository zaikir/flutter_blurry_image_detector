import Foundation
import Accelerate
import Metal
import MetalKit
import MetalPerformanceShaders
import Photos

public class BlurryImageDetector: NSObject {
  var mtlGlobalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()
  var mtlGlobalCommandQueue: MTLCommandQueue?
  var pixelFormat: MTLPixelFormat = .r8Unorm

  override public init() {
    mtlGlobalCommandQueue = mtlGlobalDevice?.makeCommandQueue()
    super.init()
  }

  func getAssetThumbnail(asset: PHAsset) -> CGImage? {
    let manager = PHImageManager.default()
    let option = PHImageRequestOptions()
    option.isSynchronous = true
    option.deliveryMode = .fastFormat
    option.resizeMode = .fast
    var image: CGImage?
    manager.requestImage(for: asset,
                         targetSize: CGSize(width: 512, height: 512),
                         contentMode: .aspectFit,
                         options: option) { result, _ in
      image = result?.cgImage
    }
    return image
  }

  func getTextureBytes(_ texture: MTLTexture) -> [UInt8] {
    let rowBytes = texture.width
    var bytes = [UInt8](repeating: 0, count: texture.width * texture.height)
    let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
    texture.getBytes(&bytes, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
    return bytes
  }

  func getImageBlurriness(assetImage: CGImage) -> Double {
    guard let device = mtlGlobalDevice,
          let queue = mtlGlobalCommandQueue else { return -1 }

    let loader = MTKTextureLoader(device: device)
    do {
      let src = try loader.newTexture(cgImage: assetImage, options: nil)
      guard let cmd = queue.makeCommandBuffer() else { return -1 }

      let convert = MPSImageConversion(device: device)
      let lap = MPSImageLaplacian(device: device)

      let grayDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat, width: src.width, height: src.height, mipmapped: false)
      grayDesc.usage = [.shaderWrite, .shaderRead]
      guard let gray = device.makeTexture(descriptor: grayDesc) else { return -1 }
      convert.encode(commandBuffer: cmd, sourceTexture: src, destinationTexture: gray)

      let lapDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat, width: src.width, height: src.height, mipmapped: false)
      lapDesc.usage = [.shaderWrite, .shaderRead]
      guard let lapTex = device.makeTexture(descriptor: lapDesc) else { return -1 }
      lap.encode(commandBuffer: cmd, sourceTexture: gray, destinationTexture: lapTex)

      cmd.commit()
      cmd.waitUntilCompleted()

      let bytes = getTextureBytes(lapTex).map { Double($0) }
      if bytes.count < 10 { return -1 }

      var mean = 0.0, std = 0.0
      vDSP_normalizeD(bytes, 1, nil, 1, &mean, &std, vDSP_Length(bytes.count))
      std *= sqrt(Double(bytes.count) / Double(bytes.count - 1))
      return std
    } catch { return -1 }
  }
}
