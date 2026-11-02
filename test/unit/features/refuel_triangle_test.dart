import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/features/entries/controllers/refuel_triangle.dart';

void main() {
  group('RefuelTriangle', () {
    test('amount and price give the volume', () {
      final triangle = RefuelTriangle();
      expect(triangle.edit(TriangleField.amount, 6000), isNull);
      expect(triangle.edit(TriangleField.price, 1.875), TriangleField.volume);
      expect(triangle.volume, 32);
    });

    test('volume and price give the amount, rounded to cents', () {
      final triangle = RefuelTriangle()
        ..edit(TriangleField.volume, 35.5)
        ..edit(TriangleField.price, 1.859);
      // 35.5 × 1.859 = 65.9945 € → 6599 cents.
      expect(triangle.amountCents, 6599);
    });

    test('amount and volume give the price', () {
      final triangle = RefuelTriangle()
        ..edit(TriangleField.amount, 5000)
        ..edit(TriangleField.volume, 25);
      expect(triangle.price, 2);
    });

    test('editing a third value recomputes the one touched least recently', () {
      final triangle = RefuelTriangle()
        ..edit(TriangleField.amount, 6000)
        ..edit(TriangleField.price, 2);
      expect(triangle.volume, 30);
      // Volume and price are now the last two: the amount follows.
      expect(triangle.edit(TriangleField.volume, 40), TriangleField.amount);
      expect(triangle.amountCents, 8000);
      // Price and volume stay the last two after another price edit.
      expect(triangle.edit(TriangleField.price, 1.5), TriangleField.amount);
      expect(triangle.amountCents, 6000);
      // Typing the amount again: amount and price win, the volume follows.
      expect(triangle.edit(TriangleField.amount, 3000), TriangleField.volume);
      expect(triangle.volume, 20);
    });

    test('an edited entry computes its price and then keeps the volume', () {
      final triangle = RefuelTriangle(amountCents: 7000, volume: 40);
      expect(triangle.price, 1.75);
      expect(triangle.edit(TriangleField.price, 2), TriangleField.amount);
      expect(triangle.amountCents, 8000);
      expect(triangle.volume, 40);
    });

    test('an empty or zero value computes nothing', () {
      final triangle = RefuelTriangle()
        ..edit(TriangleField.amount, 6000)
        ..edit(TriangleField.price, 0);
      expect(triangle.volume, isNull);
      expect(triangle.edit(TriangleField.price, null), isNull);
      expect(triangle.volume, isNull);
    });

    test('the volume is rounded to the stored 3 decimals', () {
      final triangle = RefuelTriangle()
        ..edit(TriangleField.amount, 1000)
        ..edit(TriangleField.price, 3);
      expect(triangle.volume, 3.333);
    });
  });
}
