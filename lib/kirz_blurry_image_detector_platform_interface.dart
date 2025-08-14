import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'kirz_blurry_image_detector_method_channel.dart';

abstract class KirzBlurryImageDetectorPlatform extends PlatformInterface {
  /// Constructs a KirzBlurryImageDetectorPlatform.
  KirzBlurryImageDetectorPlatform() : super(token: _token);

  static final Object _token = Object();

  static KirzBlurryImageDetectorPlatform _instance = MethodChannelKirzBlurryImageDetector();

  /// The default instance of [KirzBlurryImageDetectorPlatform] to use.
  ///
  /// Defaults to [MethodChannelKirzBlurryImageDetector].
  static KirzBlurryImageDetectorPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [KirzBlurryImageDetectorPlatform] when
  /// they register themselves.
  static set instance(KirzBlurryImageDetectorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Analyzes multiple assets by their IDs with paging and progress updates
  Future<List<String>> findBlurryImages({
    double? threshold,
    required int pageSize,
    required Function(int page, List<String> blurryIds) onProgress,
  }) {
    throw UnimplementedError('findBlurryImages() has not been implemented.');
  }
}
