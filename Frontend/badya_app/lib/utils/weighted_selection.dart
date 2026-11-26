import 'dart:math';

/// Weighted random sampling **without replacement** using the
/// Efraimidis–Spirakis (A-Res) algorithm.
///
/// Each item receives a key of `random()^(1 / weight)`; the [take] items
/// with the highest keys are returned. Higher-weighted items are
/// proportionally more likely to be selected (for `take == 1` the
/// probability of picking item *i* is exactly `weight_i / Σweights`), and no
/// item can appear more than once.
///
/// - Returns all items (in input order) when `take >= items.length`.
/// - Returns an empty list when `take <= 0`.
/// - Weights are clamped to [minWeight] so a zero or negative weight can
///   never divide by zero; such items are still theoretically pickable but
///   extremely unlikely.
/// - [random] can be injected for deterministic tests.
List<T> weightedSample<T>(
  List<T> items,
  double Function(T) weightOf,
  int take, {
  Random? random,
  double minWeight = 0.1,
}) {
  if (take <= 0) return [];
  if (take >= items.length) return List<T>.from(items);

  final rng = random ?? Random();
  final keyed = <({double key, T item})>[];

  for (final item in items) {
    final weight = weightOf(item)
        .clamp(minWeight, double.infinity)
        .toDouble();
    final u = rng.nextDouble(); // [0, 1)
    keyed.add((key: pow(u, 1.0 / weight).toDouble(), item: item));
  }

  keyed.sort((a, b) => b.key.compareTo(a.key));
  return keyed.take(take).map((e) => e.item).toList();
}
