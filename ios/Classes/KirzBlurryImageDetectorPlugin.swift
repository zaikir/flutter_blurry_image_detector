import Flutter
import Photos
import UIKit

public class KirzBlurryImageDetectorPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "kirz_blurry_image_detector",
                                       binaryMessenger: registrar.messenger())
    let instance = KirzBlurryImageDetectorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "analyzeAssetsByIds":
      guard let args = call.arguments as? [String: Any],
            let assetIds = args["assetIds"] as? [String],
            let threshold = args["threshold"] as? Double
      else {
        result(FlutterError(code: "BAD_ARGS", message: "Invalid args", details: nil))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { a, _, _ in assets.append(a) }

        var blurryIds: [String] = []
        let blurryIdsLock = NSLock()
        var assetBuffers: [String: CVPixelBuffer] = [:]
        let dispatchGroup = DispatchGroup()

        let assetToPixelBuffer = AssetToPixelBuffer()
        for asset in assets {
          dispatchGroup.enter()
          assetToPixelBuffer.pixelBuffer(from: asset, inputSize: CGSize(width: 224, height: 224)) { pixelBuffer in
            if let pixelBuffer = pixelBuffer {
              assetBuffers[asset.localIdentifier] = pixelBuffer
            }
            dispatchGroup.leave()
          }
        }

        // Wait for all buffer extraction to finish
        dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
          let detector = BlurDetectorGPU()!
          let inflight = DispatchSemaphore(value: 2)
          let threshold: Float = 0.010
          let workGroup = DispatchGroup()

          for (id, pb) in assetBuffers {
            inflight.wait()
            workGroup.enter()
            detector.encodeVarianceOfLaplacian(pb) { variance in
              if let v = variance, v < threshold {
                blurryIdsLock.lock()
                blurryIds.append(id)
                blurryIdsLock.unlock()
              }
              inflight.signal()
              workGroup.leave()
            }
          }

          workGroup.notify(queue: .global(qos: .userInitiated)) {
            result(blurryIds)
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
