import 'package:flutter/material.dart';

/// Utility icons use the same pixel grid as the room without turning controls into bitmaps.
class PixelGlyph extends StatelessWidget {
  final String kind;
  final double size;
  final Color? color;
  const PixelGlyph(this.kind, {this.size = 24, this.color, super.key});
  static const patterns = {
    'today': [
      '..#..#..',
      '.######.',
      '.#....#.',
      '.######.',
      '.#.#..#.',
      '.#..#.#.',
      '.#....#.',
      '.######.',
    ],
    'room': [
      '...##...',
      '..####..',
      '.##..##.',
      '##....##',
      '.#....#.',
      '.#.##.#.',
      '.#.##.#.',
      '.######.',
    ],
    'gift': [
      '.##..##.',
      '.#.##.#.',
      '..####..',
      '########',
      '#..##..#',
      '########',
      '#..##..#',
      '########',
    ],
    'growth': [
      '....#...',
      '..#.#.#.',
      '...###..',
      '.#######',
      '...###..',
      '....#...',
      '.####...',
      '..##....',
    ],
    'c': [
      '...##...',
      '..##.##.',
      '.##...##',
      '##.....#',
      '.##...##',
      '..##.##.',
      '...##...',
      '........',
    ],
    'book': [
      '.###.###',
      '#..##..#',
      '#..##..#',
      '#..##..#',
      '#..##..#',
      '#..##..#',
      '.###.###',
      '....#...',
    ],
    'exercise': [
      '.##..##.',
      '###..###',
      '########',
      '########',
      '###..###',
      '.##..##.',
      '........',
      '........',
    ],
    'fish': [
      '...###..',
      '..#####.',
      '.######.',
      '###.#.##',
      '.######.',
      '..#####.',
      '...###..',
      '........',
    ],
    'paw': [
      '.#..#...',
      '#.##.#..',
      '..#..#..',
      '...#....',
      '..###...',
      '.#####..',
      '.#####..',
      '..#.#...',
    ],
  };
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _Glyph(
        patterns[kind] ?? patterns['book']!,
        color ?? IconTheme.of(context).color ?? const Color(0xFF392A25),
      ),
    ),
  );
}

class _Glyph extends CustomPainter {
  final List<String> rows;
  final Color color;
  _Glyph(this.rows, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if (rows[y][x] == '#') {
          canvas.drawRect(
            Rect.fromLTWH(
              x * size.width / 8,
              y * size.height / 8,
              size.width / 8,
              size.height / 8,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Glyph old) => old.rows != rows || old.color != color;
}
