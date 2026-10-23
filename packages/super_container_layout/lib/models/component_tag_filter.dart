/// Code-defined categories accepted by a receiving zone.
///
/// A component restricted by placement tags (for example an application bar,
/// `{'appBar'}`) is only offered to zones whose [include] names one of them;
/// see [admits].
class ComponentTagFilter {
  const ComponentTagFilter({this.include = const {}, this.exclude = const {}});

  final Set<String> include;
  final Set<String> exclude;

  bool accepts(Set<String> tags) =>
      !tags.any(exclude.contains) &&
      (include.isEmpty || tags.any(include.contains));

  /// Whether a component with [tags] and [placementTags] fits this zone.
  bool admits(Set<String> tags, Set<String> placementTags) =>
      accepts(tags) && fits(placementTags, include);

  /// Whether a component restricted to [placementTags] may go in a zone
  /// explicitly dedicated to [zoneTags]; unrestricted components fit anywhere.
  static bool fits(Set<String> placementTags, Set<String> zoneTags) =>
      placementTags.isEmpty || placementTags.any(zoneTags.contains);
}
