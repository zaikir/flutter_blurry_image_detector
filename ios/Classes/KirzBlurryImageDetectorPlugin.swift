import Flutter
import UIKit
import Photos

public class KirzBlurryImageDetectorPlugin: NSObject, FlutterPlugin {
   let detector = BlurryImageDetector()

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
            let threshold = args["threshold"] as? Double else {
        result(FlutterError(code: "BAD_ARGS", message: "Invalid args", details: nil))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { a,_,_ in assets.append(a) }

        var blurryIds: [String] = []

        for asset in assets {
          autoreleasepool {
            if let cg = self.detector.getAssetThumbnail(asset: asset) {
              let s = self.detector.getImageBlurriness(assetImage: cg)
              if s >= 0 && s < threshold { blurryIds.append(asset.localIdentifier) }
            }
          }
        }

        DispatchQueue.main.async {
          result(blurryIds)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
