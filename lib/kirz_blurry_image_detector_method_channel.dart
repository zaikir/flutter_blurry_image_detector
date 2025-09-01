import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'kirz_blurry_image_detector_platform_interface.dart';

/// An implementation of [KirzBlurryImageDetectorPlatform] that uses method channels.
class MethodChannelKirzBlurryImageDetector extends KirzBlurryImageDetectorPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('kirz_blurry_image_detector');

  @override
  Future<List<String>> findBlurryImages({
    double? threshold,
    required int pageSize,
    required bool forceRefresh,
    Function(int page, double progress, List<String> blurryIds)? onProgress,
  }) async {
    final blurryIds = await methodChannel.invokeListMethod<String>('findBlurryImages', {
      'threshold': threshold,
      'pageSize': pageSize,
      'forceRefresh': forceRefresh,
    });

    return blurryIds ?? [];
  }
}
