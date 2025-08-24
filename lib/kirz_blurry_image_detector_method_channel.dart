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
    // Set up event channel for progress updates
    const eventChannel = EventChannel('kirz_blurry_image_detector_progress');
    final stream = eventChannel.receiveBroadcastStream();

    List<String> blurryIds = [];
    // Listen to progress updates
    stream.listen((dynamic event) {
      if (event is Map) {
        final page = event['page'] as int;
        final ids = (event['ids'] as List<dynamic>?)?.cast<String>() ?? [];
        final total = event['total'] as int;
        final processed = event['processed'] as int;
        final percentage = (processed / total) * 100;

        blurryIds.addAll(ids);
        onProgress?.call(page, percentage.clamp(0, 100), blurryIds);
      }
    });

    await methodChannel.invokeMethod('findBlurryImages', {
      'threshold': threshold,
      'pageSize': pageSize,
      'forceRefresh': forceRefresh,
    });

    return blurryIds;
  }
}
