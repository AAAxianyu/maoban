import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pixel_sprite.dart';

class RoomScene extends StatefulWidget {
  /// Celebration frame from the controller; 0 means idle.
  final ValueListenable<int>? pose;
  final bool reduceMotion;
  final double height;
  final Set<String> decorations;
  const RoomScene({
    super.key,
    this.pose,
    this.reduceMotion = false,
    this.height = 200,
    this.decorations = const {},
  });
  @override
  State<RoomScene> createState() => _RoomSceneState();
}

class _RoomSceneState extends State<RoomScene> {
  // Decoded once for the whole app; every scene shares the same texture.
  static Future<ui.Image>? _atlas;
  static Future<ui.Image> _load() async {
    final bytes = await rootBundle.load('assets/cats-atlas.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  ui.Image? atlas;
  Timer? _blink;
  final _idle = ValueNotifier<int>(0);
  ValueListenable<TickerModeData>? _tickerMode;

  bool get _animate =>
      !widget.reduceMotion &&
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
      (_tickerMode?.value.enabled ?? true);

  @override
  void initState() {
    super.initState();
    (_atlas ??= _load()).then((image) {
      if (mounted) setState(() => atlas = image);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getValuesNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_updateBlink);
      _tickerMode = notifier..addListener(_updateBlink);
    }
    _updateBlink();
  }

  @override
  void didUpdateWidget(RoomScene old) {
    super.didUpdateWidget(old);
    _updateBlink();
  }

  /// Blinks only while visible and motion is allowed, so offstage tabs stay idle.
  void _updateBlink() {
    if (!_animate) {
      _blink?.cancel();
      _blink = null;
      _idle.value = 0;
      return;
    }
    _blink ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || (widget.pose?.value ?? 0) != 0) return;
      _idle.value = 1;
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (mounted) _idle.value = 0;
    });
  }

  @override
  void dispose() {
    _blink?.cancel();
    _tickerMode?.removeListener(_updateBlink);
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '两只像素猫咪一起在温暖书桌前学习',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/room-background.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
            ),
            if (atlas != null)
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: Listenable.merge([_idle, ?widget.pose]),
                  builder: (context, _) {
                    final pose = widget.pose?.value ?? 0;
                    final still =
                        widget.reduceMotion ||
                        (MediaQuery.maybeOf(context)?.disableAnimations ??
                            false);
                    return CustomPaint(
                      painter: _Cats(
                        atlas!,
                        still ? 0 : (pose == 0 ? _idle.value : pose),
                      ),
                    );
                  },
                ),
              ),
            LayoutBuilder(
              builder: (context, bounds) => Stack(
                children: [
                  if (widget.decorations.contains('bookshelf'))
                    Positioned(
                      right: 0,
                      top: 8,
                      child: PixelSprite(3, size: bounds.maxWidth * .28),
                    ),
                  if (widget.decorations.contains('plant'))
                    Positioned(
                      right: 6,
                      bottom: 12,
                      child: PixelSprite(2, size: bounds.maxWidth * .20),
                    ),
                  if (widget.decorations.contains('cat_bed'))
                    Positioned(
                      left: 10,
                      bottom: 0,
                      child: PixelSprite(1, size: bounds.maxWidth * .22),
                    ),
                  if (widget.decorations.contains('lamp'))
                    Positioned(
                      left: bounds.maxWidth * .05,
                      top: bounds.maxHeight * .35,
                      child: PixelSprite(0, size: bounds.maxWidth * .18),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Cats extends CustomPainter {
  final ui.Image atlas;
  final int frame;
  _Cats(this.atlas, this.frame);
  @override
  void paint(Canvas canvas, Size size) {
    final cellW = atlas.width / 4, cellH = atlas.height / 2;
    final width = size.width * .31;
    final height = width * cellH / cellW;
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (var row = 0; row < 2; row++) {
      canvas.drawImageRect(
        atlas,
        Rect.fromLTWH(frame * cellW, row * cellH, cellW, cellH),
        Rect.fromLTWH(
          size.width * (row == 0 ? .20 : .47),
          size.height * .47 - height * .25,
          width,
          height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Cats old) => old.frame != frame || old.atlas != atlas;
}
