// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_sns_suppression.dart';

const _tracerName = 'dartastic_otel_libs_sns';
const _systemValue = 'aws_sns';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedSnsPublish` callback.
class SnsPublishResult<T> {
  const SnsPublishResult({required this.value, this.messageId});
  final T value;
  final String? messageId;
}

String _topicNameFromArn(String topicArn) {
  final i = topicArn.lastIndexOf(':');
  return i < 0 ? topicArn : topicArn.substring(i + 1);
}

/// Wraps an SNS `Publish` in a PRODUCER span using OTel messaging
/// semconv (messaging.system=aws_sns). Use either [topicArn] for
/// topic publishes or [phoneNumber] for direct-SMS publishes.
Future<T> tracedSnsPublish<T>({
  required Future<SnsPublishResult<T>> Function() invoke,
  String? topicArn,
  String? phoneNumber,
  String? messageGroupId,
  int? payloadSize,
  String? region,
}) async {
  if (snsInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  assert(
    (topicArn != null) ^ (phoneNumber != null),
    'tracedSnsPublish requires exactly one of topicArn or phoneNumber',
  );
  final m = <String, Object>{
    'messaging.system': _systemValue,
    'messaging.operation': 'publish',
  };
  String destName;
  if (topicArn != null) {
    destName = _topicNameFromArn(topicArn);
    m['aws.sns.topic.arn'] = topicArn;
    m['messaging.destination.name'] = destName;
  } else {
    destName = 'sms';
    m['aws.sns.phone_number'] = phoneNumber!;
    m['messaging.destination.name'] = destName;
  }
  if (payloadSize != null) m['messaging.message.body.size'] = payloadSize;
  if (region != null) m['cloud.region'] = region;
  if (messageGroupId != null) {
    m['aws.sns.message_group.id'] = messageGroupId;
  }

  final span = _tracer().startSpan(
    'publish $destName',
    kind: SpanKind.producer,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.messageId != null) {
      span.addAttributes(OTel.attributes([
        OTel.attributeString('messaging.message.id', r.messageId!),
      ]));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
