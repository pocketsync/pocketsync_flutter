extension IterableExtensions<T> on Iterable<T> {
  Map<K, V> groupBy<K, V>(K Function(T element) key, V Function(T element) value) {
    return fold(
      <K, V>{},
      (map, element) {
        map[key(element)] = value(element);
        return map;
      },
    );
  }
}