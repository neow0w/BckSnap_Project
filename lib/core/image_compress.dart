import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class _Job {
  final Uint8List bytes;
  final int maxSide;
  final int quality;
  final int maxBytes;
  const _Job(this.bytes, this.maxSide, this.quality, this.maxBytes);
}

/// Shrinks a photo to a small JPEG so it fits comfortably in Firestore.
/// It lowers the quality, then the size, until it is under [maxBytes].
class ImageCompressor {
  static Future<Uint8List> shrink(
    Uint8List bytes, {
    int maxSide = 720,
    int quality = 60,
    int maxBytes = 120 * 1024,
  }) => compute(_run, _Job(bytes, maxSide, quality, maxBytes));
}

Uint8List _run(_Job job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) throw const FormatException('Not a valid image.');
  final image = img.bakeOrientation(decoded);
  var side = job.maxSide;
  var quality = job.quality;
  while (true) {
    final resized = image.width >= image.height
        ? (image.width > side ? img.copyResize(image, width: side) : image)
        : (image.height > side ? img.copyResize(image, height: side) : image);
    final out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    if (out.length <= job.maxBytes || (quality <= 35 && side <= 240)) {
      return out;
    }
    if (quality > 35) {
      quality -= 10;
    } else {
      side = (side * 0.8).round();
    }
  }
}
