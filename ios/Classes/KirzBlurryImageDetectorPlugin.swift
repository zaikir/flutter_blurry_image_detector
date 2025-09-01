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

      DispatchQueue.global(qos: .userInitiated).async {
        // Fetch all assets from the photo library
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: fetchOptions)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { a, _, _ in assets.append(a) }

        let totalPages = (assets.count + pageSize - 1) / pageSize
        var allBlurryIds: [String] = []

        // Process pages sequentially
        for page in 0 ..< totalPages {
          let startIndex = page * pageSize
          let endIndex = min(startIndex + pageSize, assets.count)
          let pageAssets = Array(assets[startIndex ..< endIndex])

          // Process this page synchronously
          let pageBlurryIds = self.processPageSync(pageAssets, threshold: Float(threshold), forceRefresh: forceRefresh)

          // Accumulate results from this page
          allBlurryIds.append(contentsOf: pageBlurryIds)
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
      assetToPixelBuffer.pixelBuffer(from: asset, inputSize: CGSize(width: 224, height: 224)) { pixelBuffer in
        if let pixelBuffer = pixelBuffer {
          assetBuffers[asset.localIdentifier] = pixelBuffer
        }
        dispatchGroup.leave()
      }
    }

    // Wait for pixel buffer loading to complete
    dispatchGroup.wait()

    let detector = BlurDetectorGPU()!
    let inflight = DispatchSemaphore(value: 2)
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

    return blurryIds
  }

  private func processPage(_ assets: [PHAsset], threshold: Float, forceRefresh: Bool, completion: @escaping ([String]) -> Void) {
    var blurryIds: [String] = []
    let blurryIdsLock = NSLock()
    var assetBuffers: [String: CVPixelBuffer] = [:]
    var assetsToProcess: [PHAsset] = []

    // Check cache first if not forcing refresh
    for asset in assets {
      let cacheKey = getCacheKey(assetId: asset.localIdentifier, threshold: threshold)

      if !forceRefresh, let cachedResult = Self.cache[cacheKey] {
        // Use cached result
        if let isBlurry = cachedResult["isBlurry"] as? Bool, isBlurry {
          blurryIdsLock.lock()
          blurryIds.append(asset.localIdentifier)
          blurryIdsLock.unlock()
        }
      } else {
        // Need to process this asset
        assetsToProcess.append(asset)
      }
    }

    // If no assets need processing, return cached results
    if assetsToProcess.isEmpty {
      completion(blurryIds)
      return
    }

    let dispatchGroup = DispatchGroup()
    let assetToPixelBuffer = AssetToPixelBuffer()

    for asset in assetsToProcess {
      dispatchGroup.enter()
      assetToPixelBuffer.pixelBuffer(from: asset, inputSize: CGSize(width: 224, height: 224)) { pixelBuffer in
        if let pixelBuffer = pixelBuffer {
          assetBuffers[asset.localIdentifier] = pixelBuffer
        }
        dispatchGroup.leave()
      }
    }

    dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
      let detector = BlurDetectorGPU()!
      let inflight = DispatchSemaphore(value: 2)
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
              blurryIdsLock.lock()
              blurryIds.append(id)
              blurryIdsLock.unlock()
            }
          }
          inflight.signal()
          workGroup.leave()
        }
      }

      workGroup.notify(queue: .global(qos: .userInitiated)) {
        completion(blurryIds)
      }
    }
  }
}
