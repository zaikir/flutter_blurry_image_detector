import Flutter
import Photos
import UIKit

public class KirzBlurryImageDetectorPlugin: NSObject, FlutterPlugin {
  private var registrar: FlutterPluginRegistrar?
  
  // Cache for storing blur detection results
  private static let cacheKey = "BlurDetectionCache"
  private static var cache: [String: [String: Any]] = [:]
  
  // Load cache from UserDefaults
  private func loadCache() {
    if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
      Self.cache = decoded
    }
  }
  
  // Save cache to UserDefaults
  private func saveCache() {
    if let data = try? JSONSerialization.data(withJSONObject: Self.cache) {
      UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
  }
  
  // Get cache key for asset and threshold combination
  private func getCacheKey(assetId: String, threshold: Float) -> String {
    return "\(assetId)_\(threshold)"
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "kirz_blurry_image_detector",
                                       binaryMessenger: registrar.messenger())

    let instance = KirzBlurryImageDetectorPlugin()
    instance.registrar = registrar
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "findBlurryImages":
      guard let args = call.arguments as? [String: Any],
            let pageSize = args["pageSize"] as? Int
      else {
        result(FlutterError(code: "BAD_ARGS", message: "Invalid args", details: nil))
        return
      }

      let threshold = args["threshold"] as! Double
      let forceRefresh = args["forceRefresh"] as? Bool ?? false
      
      // Load cache if not already loaded
      self.loadCache()

      DispatchQueue.global(qos: .background).async {
        // Fetch all assets from the photo library
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetch = PHAsset.fetchAssets(with: fetchOptions)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { a, _, _ in assets.append(a) }

        let totalPages = (assets.count + pageSize - 1) / pageSize
        var allBlurryIds: [String] = []

        // Process pages sequentially
        for page in 0 ..< totalPages {
          autoreleasepool {
            let startIndex = page * pageSize
            let endIndex = min(startIndex + pageSize, assets.count)
            let pageAssets = Array(assets[startIndex ..< endIndex])

            // Process this page synchronously
            let pageBlurryIds = self.processPageSync(pageAssets, threshold: Float(threshold), forceRefresh: forceRefresh)

            // Accumulate results from this page
            allBlurryIds.append(contentsOf: pageBlurryIds)
          }
        }

        // Save cache after processing
        self.saveCache()

        DispatchQueue.main.async {
          // Return complete results array
          result(allBlurryIds)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func processPageSync(_ assets: [PHAsset], threshold: Float, forceRefresh: Bool) -> [String] {
    var blurryIds: [String] = []
    var assetBuffers: [String: CVPixelBuffer] = [:]
    var assetsToProcess: [PHAsset] = []

    // Check cache first if not forcing refresh
    for asset in assets {
      let cacheKey = getCacheKey(assetId: asset.localIdentifier, threshold: threshold)

      if !forceRefresh, let cachedResult = Self.cache[cacheKey] {
        // Use cached result
        if let isBlurry = cachedResult["isBlurry"] as? Bool, isBlurry {
          blurryIds.append(asset.localIdentifier)
        }
      } else {
        // Need to process this asset
        assetsToProcess.append(asset)
      }
    }

    // If no assets need processing, return cached results
    if assetsToProcess.isEmpty {
      return blurryIds
    }

    let dispatchGroup = DispatchGroup()
    let assetToPixelBuffer = AssetToPixelBuffer()

    for asset in assetsToProcess {
      dispatchGroup.enter()
      autoreleasepool {
        assetToPixelBuffer.pixelBuffer(from: asset, inputSize: CGSize(width: 128, height: 128)) { pixelBuffer in
          if let pixelBuffer = pixelBuffer {
            assetBuffers[asset.localIdentifier] = pixelBuffer
          }
          dispatchGroup.leave()
        }
      }
    }

    // Wait for pixel buffer loading to complete
    dispatchGroup.wait()

    let detector = BlurDetectorGPU()!
    let inflight = DispatchSemaphore(value: 1)
    let workGroup = DispatchGroup()

    for (id, pb) in assetBuffers {
      inflight.wait()
      workGroup.enter()
      detector.encodeVarianceOfLaplacian(pb) { variance in
        if let v = variance {
          let isBlurry = v < threshold

          // Cache the result
          let cacheKey = self.getCacheKey(assetId: id, threshold: threshold)
          Self.cache[cacheKey] = [
            "isBlurry": isBlurry,
            "variance": v,
            "timestamp": Date().timeIntervalSince1970
          ]

          if isBlurry {
            blurryIds.append(id)
          }
        }
        inflight.signal()
        workGroup.leave()
      }
    }

    // Wait for GPU processing to complete
    workGroup.wait()

    // Clear pixel buffers to free memory
    assetBuffers.removeAll()

    return blurryIds
  }
}
