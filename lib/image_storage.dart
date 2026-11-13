import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

class PendingImage {
  const PendingImage({
    required this.pngBytes,
    required this.width,
    required this.height,
  });
  final Uint8List pngBytes;
  final int width, height;

  static Future<PendingImage> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final png = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (png == null) throw const FormatException('无法转换图片');
        return PendingImage(
          pngBytes: png.buffer.asUint8List(
            png.offsetInBytes,
            png.lengthInBytes,
          ),
          width: frame.image.width,
          height: frame.image.height,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}

/// Image bytes live alongside, but separately from, the daily JSON tree.
/// JSON paths always use a portable POSIX representation and are resolved
/// with the host path API after validation.
class PromptImageStorage {
  PromptImageStorage(this.rootPath);
  final String rootPath;

  static String resolve(String rootPath, String relativePath) {
    if (!RegExp(
      r'^days/\d{4}_image/\d{2}/\d{4}-\d{2}-\d{2}_Image\d+\.png$',
    ).hasMatch(relativePath)) {
      throw const FormatException('无效的图片相对路径');
    }
    return p.joinAll([rootPath, ...p.posix.split(relativePath)]);
  }

  Future<List<PromptImage>> save(
    DateTime date,
    List<PendingImage> images,
  ) async {
    if (images.isEmpty) return [];
    final relativeDirectory = p.posix.join(
      'days',
      '${date.year}_image',
      date.month.toString().padLeft(2, '0'),
    );
    final directory = Directory(
      p.joinAll([rootPath, ...p.posix.split(relativeDirectory)]),
    );
    await directory.create(recursive: true);
    final prefix = '${dateKey(date)}_Image';
    final pattern = RegExp('^${RegExp.escape(prefix)}(\\d+)\\.png\$');
    var sequence = 0;
    await for (final entity in directory.list()) {
      final match = pattern.firstMatch(p.basename(entity.path));
      if (match != null) {
        final number = int.parse(match[1]!);
        if (number > sequence) sequence = number;
      }
    }
    final createdFiles = <File>[];
    final result = <PromptImage>[];
    try {
      for (final image in images) {
        File file;
        String relativePath;
        while (true) {
          sequence++;
          relativePath = p.posix.join(
            relativeDirectory,
            '$prefix${sequence.toString().padLeft(2, '0')}.png',
          );
          file = File(resolve(rootPath, relativePath));
          try {
            await file.create(exclusive: true);
            break;
          } on FileSystemException {
            if (await file.exists()) continue;
            rethrow;
          }
        }
        createdFiles.add(file);
        await file.writeAsBytes(image.pngBytes, flush: true);
        result.add(
          PromptImage(
            relativePath: relativePath,
            width: image.width,
            height: image.height,
            byteLength: image.pngBytes.length,
            sha256: sha256.convert(image.pngBytes).toString(),
          ),
        );
      }
      return result;
    } catch (_) {
      for (final file in createdFiles) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  /// Only used to roll back newly created files if the JSON commit fails.
  /// Sent images are retained when removing a message to keep old backups valid.
  Future<void> rollback(List<PromptImage> images) async {
    for (final image in images) {
      final file = File(resolve(rootPath, image.relativePath));
      if (await file.exists()) await file.delete();
    }
  }
}
