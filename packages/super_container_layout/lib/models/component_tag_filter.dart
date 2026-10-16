/// Code-defined categories accepted by a receiving zone.
class ComponentTagFilter {
  const ComponentTagFilter({this.include = const {}, this.exclude = const {}});

  final Set<String> include;
  final Set<String> exclude;

  bool accepts(Set<String> tags) =>
      !tags.any(exclude.contains) &&
      (include.isEmpty || tags.any(include.contains));
}
