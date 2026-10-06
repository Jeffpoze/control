import 'package:control/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    expect(formatBytes(200 * 1024 * 1024), '200 MB');
  });

  test('formatEta', () {
    expect(formatEta(null), '');
    expect(formatEta(const Duration(seconds: 42)), '42s');
    expect(formatEta(const Duration(minutes: 62)), '1h 2m');
    expect(formatEta(const Duration(hours: 50)), '2d 2h');
  });

  test('parseClockDuration', () {
    expect(
      parseClockDuration('0:12:05'),
      const Duration(minutes: 12, seconds: 5),
    );
    expect(
      parseClockDuration('1:02:03:04'),
      const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
    );
    expect(parseClockDuration('soon'), isNull);
  });

  test('formatDay', () {
    final now = DateTime(2026, 10, 5, 15);
    expect(formatDay(DateTime(2026, 10, 5, 1), now: now), 'Today');
    expect(formatDay(DateTime(2026, 10, 6, 23), now: now), 'Tomorrow');
    expect(formatDay(DateTime(2026, 10, 12), now: now), 'Mon 12 Oct');
  });

  test('asInt and asDouble accept strings', () {
    expect(asInt('42'), 42);
    expect(asInt('4.6'), 5);
    expect(asDouble('2.5'), 2.5);
    expect(asDouble(null), 0);
  });
}
