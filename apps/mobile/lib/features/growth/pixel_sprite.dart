import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Draws one cell without baking labels or controls into bitmap assets.
class PixelSprite extends StatefulWidget {
  final int index;
  final double size;
  const PixelSprite(this.index, {this.size = 48, super.key});
  @override
  State<PixelSprite> createState() => _PixelSpriteState();
}

class _PixelSpriteState extends State<PixelSprite> {
  static Future<ui.Image>? _atlas;
  ui.Image? image;
  static Future<ui.Image> load() async {
    final bytes = await rootBundle.load('assets/decorations-badges.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  @override
  void initState() {
    super.initState();
    (_atlas ??= load()).then((value) {
      if (mounted) setState(() => image = value);
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: image == null
        ? const SizedBox()
        : CustomPaint(painter: _SpritePainter(image!, widget.index)),
  );
}

class _SpritePainter extends CustomPainter {
  final ui.Image image;
  final int index;
  _SpritePainter(this.image, this.index);
  @override
  void paint(Canvas canvas, Size size) {
    final width = image.width / 3, height = image.height / 3;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(index % 3 * width, index ~/ 3 * height, width, height),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.image != image || old.index != index;
}
