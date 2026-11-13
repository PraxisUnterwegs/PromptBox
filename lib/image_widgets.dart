import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'image_storage.dart';
import 'models.dart';

class PendingImageStrip extends StatelessWidget {
  const PendingImageStrip({
    super.key,
    required this.images,
    required this.onRemove,
  });
  final List<PendingImage> images;
  final ValueChanged<PendingImage> onRemove;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 90,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: images.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder:
          (context, index) => SizedBox(
            width: 110,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        images[index].pngBytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton.filledTonal(
                    tooltip: '移除待发送图片 ${index + 1}',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: () => onRemove(images[index]),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
    ),
  );
}

class PromptImageGallery extends StatelessWidget {
  const PromptImageGallery({
    super.key,
    required this.images,
    required this.databasePath,
  });
  final List<PromptImage> images;
  final String databasePath;

  Widget _image(PromptImage image, {bool original = false}) {
    try {
      return Image.file(
        File(PromptImageStorage.resolve(databasePath, image.relativePath)),
        fit: BoxFit.contain,
        cacheWidth: original ? null : 600,
        errorBuilder:
            (_, __, ___) => const Center(child: Text('图片暂不可用，请检查数据库文件是否已同步')),
      );
    } on FormatException {
      return const Center(child: Text('图片路径无效'));
    }
  }

  Future<void> _preview(BuildContext context, PromptImage image) =>
      showDialog<void>(
        context: context,
        builder:
            (context) => Dialog(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * .85,
                height: MediaQuery.sizeOf(context).height * .85,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.posix.basename(image.relativePath),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭图片预览',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: InteractiveViewer(
                        minScale: .5,
                        maxScale: 8,
                        child: Center(child: _image(image, original: true)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      );

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final image in images)
        SizedBox(
          width: 260,
          height: 196,
          child: Tooltip(
            message:
                '${p.posix.basename(image.relativePath)} · ${image.width} × ${image.height} · 点击查看大图',
            child: InkWell(
              onTap: () => _preview(context, image),
              borderRadius: BorderRadius.circular(10),
              child: Card(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Expanded(child: _image(image)),
                      const SizedBox(height: 6),
                      Text(
                        p.posix.basename(image.relativePath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
