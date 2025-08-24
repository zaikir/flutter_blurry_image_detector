// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/to/pubspec-plugin-platforms.

import 'kirz_blurry_image_detector_platform_interface.dart';

class BlurryImageDetector {
  /// Analyzes multiple assets by their IDs and returns blurry image results
  static Future<List<String>> findBlurryImages({
    double? threshold,
    int? pageSize,
    Function(int page, double progress, List<String> blurryIds)? onProgress,
  }) {
    return KirzBlurryImageDetectorPlatform.instance.findBlurryImages(
      threshold: threshold ?? 0.010,
      pageSize: pageSize ?? 200,
      onProgress: onProgress,
    );
  }
}
