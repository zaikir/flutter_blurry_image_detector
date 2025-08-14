import Flutter
import Photos
import UIKit

public class KirzBlurryImageDetectorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var registrar: FlutterPluginRegistrar?
  private var eventChannel: FlutterEventChannel?
  private var sink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "kirz_blurry_image_detector",
                                       binaryMessenger: registrar.messenger())
    let eventsChannel = FlutterEventChannel(name: "kirz_blurry_image_detector_progress",
                                            binaryMessenger: registrar.messenger())

    let instance = KirzBlurryImageDetectorPlugin()
    instance.registrar = registrar
    instance.eventChannel = eventsChannel
    eventsChannel.setStreamHandler(instance)
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

      DispatchQueue.global(qos: .userInitiated).async {
        // Fetch all assets from the photo library
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: fetchOptions)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { a, _, _ in assets.append(a) }

        let totalPages = (assets.count + pageSize - 1) / pageSize

        // Semaphore to limit concurrent page processing
        let pageSemaphore = DispatchSemaphore(value: 1) // Process max 2 pages at once

        for page in 0 ..< totalPages {
          pageSemaphore.wait() // Wait for available slot

          let startIndex = page * pageSize
          let endIndex = min(startIndex + pageSize, assets.count)
          let pageAssets = Array(assets[startIndex ..< endIndex])

          // Process this page
          self.processPage(pageAssets, threshold: Float(threshold)) { pageBlurryIds in
            // Send progress update
            let progressData: [String: Any] = [
              "page": page + 1,
              "ids": pageBlurryIds,
              "total": assets.count,
              "processed": startIndex + pageAssets.count,
            ]

            self.sink?(progressData)

            // Signal that this page is done
            pageSemaphore.signal()
          }
        }

        self.sink?(FlutterEndOfEventStream)
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    sink?(0)
    return nil
  }

  public func onCancel(withArguments _: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func processPage(_ assets: [PHAsset], threshold: Float, completion: @escaping ([String]) -> Void) {
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

    dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
      let detector = BlurDetectorGPU()!
      let inflight = DispatchSemaphore(value: 2)
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
        completion(blurryIds)
      }
    }
  }
}
