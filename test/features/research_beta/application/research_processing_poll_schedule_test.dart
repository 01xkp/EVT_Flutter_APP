import 'package:aipin/features/research_beta/application/research_processing_poll_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const schedule = ResearchProcessingPollSchedule();

  test('uses two seconds before the first minute', () {
    expect(
      schedule.nextDelay(const Duration(seconds: 59)),
      const Duration(seconds: 2),
    );
  });

  test('uses five seconds from one minute until five minutes', () {
    expect(
      schedule.nextDelay(const Duration(minutes: 1)),
      const Duration(seconds: 5),
    );
    expect(
      schedule.nextDelay(const Duration(minutes: 4, seconds: 59)),
      const Duration(seconds: 5),
    );
  });

  test('uses ten seconds from five minutes onward', () {
    expect(
      schedule.nextDelay(const Duration(minutes: 5)),
      const Duration(seconds: 10),
    );
  });
}
