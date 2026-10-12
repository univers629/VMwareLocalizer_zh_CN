import 'dart:async';

import 'localizer_service.dart';

class OpBatchResult {
  const OpBatchResult({
    required this.updates,
    required this.finalMessage,
    required this.errors,
    required this.reachedEnd,
  });

  final List<OpProgress> updates;

  final String finalMessage;

  final List<String> errors;

  final bool reachedEnd;

  bool get ok => errors.isEmpty && reachedEnd;

  double get finalFraction =>
      updates.isEmpty ? 0 : updates.last.fraction;
}

class OpBatch {
  OpBatch._();

  static Future<OpBatchResult> collect(
    Stream<OpProgress> stream, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final List<OpProgress> updates = <OpProgress>[];
    final List<String> errors = <String>[];
    bool ended = false;

    await stream
        .timeout(
          timeout,
          onTimeout: (EventSink<OpProgress> sink) {
            errors.add('operation timed out after ${timeout.inSeconds}s');
            sink.close();
          },
        )
        .forEach((OpProgress p) {
      updates.add(p);
      if (p.failed) {
        errors.add(p.message);
      }
    }).then((_) => ended = true);

    return OpBatchResult(
      updates: updates,
      finalMessage: updates.isEmpty ? '' : updates.last.message,
      errors: errors,
      reachedEnd: ended,
    );
  }
}
