import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'image_storage.dart';

class UpdateDraft {
  const UpdateDraft(this.markdown, this.images, this.plannedDate);
  final String markdown;
  final List<PendingImage> images;
  final DateTime? plannedDate;
}

class UpdateDraftStore {
  UpdateDraftStore({Future<File> Function()? file})
    : _file = file ?? _defaultFile;
  final Future<File> Function() _file;

  static Future<File> _defaultFile() async {
    const demo = String.fromEnvironment('PROMPTBOX_DEMO_ROOT');
    final directory =
        demo.isNotEmpty
            ? Directory(demo)
            : await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'pending-update-draft.json'));
  }

  Future<void> save(
    String markdown,
    List<PendingImage> images, {
    DateTime? plannedDate,
  }) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'markdown': markdown,
        'plannedDate': plannedDate?.toIso8601String(),
        'images':
            images
                .map(
                  (image) => {
                    'png': base64Encode(image.pngBytes),
                    'width': image.width,
                    'height': image.height,
                  },
                )
                .toList(),
      }),
      flush: true,
    );
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temp.rename(file.path);
    } catch (_) {
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
  }

  Future<UpdateDraft?> read() async {
    final file = await _file();
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    }
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return UpdateDraft(
      data['markdown'] as String,
      (data['images'] as List<dynamic>)
          .map(
            (raw) => PendingImage(
              pngBytes: base64Decode(raw['png'] as String),
              width: raw['width'] as int,
              height: raw['height'] as int,
            ),
          )
          .toList(),
      DateTime.tryParse(data['plannedDate'] as String? ?? ''),
    );
  }

  Future<void> consume() async {
    final file = await _file();
    if (!await file.exists()) return;
    final restored = File('${file.path}.restored');
    final backup = File('${file.path}.bak');
    if (await restored.exists()) await restored.delete();
    if (await backup.exists()) await backup.delete();
    await file.rename(restored.path);
  }
}
