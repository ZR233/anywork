import 'raw_tap.dart';

/// Dispatches a normal sidebar tap while a real page request is pending.
class PageSwitch extends RawTap {
  PageSwitch(
    super.finder, {
    required this.threadId,
    required this.generation,
    required this.destinationThreadId,
    this.bounceBack = false,
    super.timeout,
  });

  PageSwitch.deserialize(super.json, super.finderFactory)
    : threadId = json['threadId']!,
      destinationThreadId = json['destinationThreadId']!,
      bounceBack = json['bounceBack'] == 'true',
      generation = int.parse(json['generation']!),
      super.deserialize();

  final String threadId;
  final String destinationThreadId;
  final int generation;
  final bool bounceBack;

  @override
  String get kind => 'PageSwitch';

  @override
  Map<String, String> serialize() => {
    ...super.serialize(),
    'threadId': threadId,
    'destinationThreadId': destinationThreadId,
    'generation': '$generation',
    'bounceBack': '$bounceBack',
  };
}
