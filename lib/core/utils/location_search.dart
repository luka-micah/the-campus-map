import '../models/location_model.dart';

/// Shared destination-search matching used by both the map search field
/// ([MapController.search]) and voice search
/// ([CampusRepository.searchLocations]).
///
/// Previously the two paths each implemented their own ad-hoc
/// `name.contains(query)` check, with three strictness bugs that turned
/// valid queries into "No location found":
///  * the repository never trimmed, so `" library "` never matched;
///  * only `name` was searched, so department queries never matched;
///  * voice transcripts like `"take me to the library"` were matched
///    verbatim, so the extra command words prevented any match.
///
/// Matching is now: normalize (trim, lowercase, strip punctuation, collapse
/// whitespace, drop voice-command wrappers) then match against
/// `"<name> <department>"` by full-phrase containment, falling back to
/// all-tokens-present so word order doesn't matter (`"library main"` still
/// finds `"Main Library"`).

/// Leading voice-command wrappers stripped before matching, longest first.
const _commandPrefixes = [
  'how do i get to',
  'how to get to',
  'take me to the',
  'take me to',
  'navigate to the',
  'navigate to',
  'directions to the',
  'directions to',
  'show me the',
  'where is the',
  'where is',
  'go to the',
  'get me to',
  'show me',
  'take me',
  'go to',
  'find the',
  'find',
  'show',
];

/// Normalizes raw user/STT input for matching.
String normalizeLocationQuery(String query) {
  var q = query.toLowerCase().trim();
  // STT often leaves punctuation: "library.", "library?" — drop it.
  q = q.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Strip one command wrapper ("take me to the library" -> "library").
  for (final prefix in _commandPrefixes) {
    if (q.startsWith('$prefix ')) {
      q = q.substring(prefix.length + 1).trim();
      break;
    } else if (q == prefix) {
      return '';
    }
  }
  // Leading "the" left over from stripping ("the library" -> "library").
  if (q.startsWith('the ')) q = q.substring(4);
  // Trailing politeness filler.
  if (q.endsWith(' please')) q = q.substring(0, q.length - 7).trim();
  return q;
}

/// Haystack a location is matched against: name + department, normalized.
String _haystack(LocationModel loc) {
  final raw = '${loc.name} ${loc.department}'.toLowerCase();
  return raw.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(
        RegExp(r'\s+'),
        ' ',
      ).trim();
}

/// Returns true when [location] matches the raw [query].
bool locationMatchesQuery(LocationModel location, String query) {
  final q = normalizeLocationQuery(query);
  if (q.isEmpty) return false;
  final hay = _haystack(location);
  if (hay.contains(q)) return true;
  // Token fallback so word order doesn't matter.
  final tokens = q.split(' ');
  if (tokens.length > 1) {
    return tokens.every((t) => hay.contains(t));
  }
  return false;
}

/// Filters [locations] by [query]; empty/blank query returns [].
List<LocationModel> filterLocations(
  List<LocationModel> locations,
  String query,
) {
  if (query.trim().isEmpty) return [];
  final q = normalizeLocationQuery(query);
  if (q.isEmpty) return [];
  return locations.where((loc) => locationMatchesQuery(loc, q)).toList();
}
