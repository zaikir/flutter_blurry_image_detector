import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'kirz_blurry_image_detector_platform_interface.dart';

/// An implementation of [KirzBlurryImageDetectorPlatform] that uses method channels.
class MethodChannelKirzBlurryImageDetector extends KirzBlurryImageDetectorPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('kirz_blurry_image_detector');

  @override
  Future<List<String>> analyzeAssetsByIds({
    required List<String> assetIds,
    required double threshold,
  }) async {
    final result = await methodChannel.invokeMethod<List<String>>('analyzeAssetsByIds', {
      'assetIds': assetIds,
      'threshold': threshold,
    });
    return result ?? [];
  }
}
