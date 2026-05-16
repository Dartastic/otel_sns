// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_sns/otel_sns.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_sns-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  const topicArn = 'arn:aws:sns:us-east-1:123:OrdersTopic';

  test('Publish to topic records PRODUCER span', () async {
    await tracedSnsPublish<String>(
      topicArn: topicArn,
      payloadSize: 128,
      region: 'us-east-1',
      messageGroupId: 'user-1',
      invoke: () async => const SnsPublishResult(value: 'ok', messageId: 'm-1'),
    );
    final span = spans.findSpanByName('publish OrdersTopic');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.producer);
    final a = attrsOf(span);
    expect(a['messaging.system'], 'aws_sns');
    expect(a['messaging.destination.name'], 'OrdersTopic');
    expect(a['aws.sns.topic.arn'], topicArn);
    expect(a['messaging.message.body.size'], 128);
    expect(a['aws.sns.message_group.id'], 'user-1');
    expect(a['messaging.message.id'], 'm-1');
  });

  test('Publish SMS uses sms destination', () async {
    await tracedSnsPublish<String>(
      phoneNumber: '+15551112222',
      invoke: () async => const SnsPublishResult(value: 'ok', messageId: 'm-2'),
    );
    final span = spans.findSpanByName('publish sms');
    expect(span, isNotNull);
    final a = attrsOf(span!);
    expect(a['aws.sns.phone_number'], '+15551112222');
    expect(a['messaging.destination.name'], 'sms');
  });

  test('records exception', () async {
    await expectLater(
      tracedSnsPublish<String>(
        topicArn: topicArn,
        invoke: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      spans.findSpanByName('publish OrdersTopic')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutSnsInstrumentationAsync(() async {
      await tracedSnsPublish<String>(
        topicArn: topicArn,
        invoke: () async => const SnsPublishResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('publish '), isEmpty);
  });
}
