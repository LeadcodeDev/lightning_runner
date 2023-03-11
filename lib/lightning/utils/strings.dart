String substringAfter(final String searchIn, final String searchFor) {
  if (searchIn.isEmpty) {
    return searchIn;
  }

  final pos = searchIn.indexOf(searchFor);
  return pos < 0 ? '' : searchIn.substring(pos + searchFor.length);
}