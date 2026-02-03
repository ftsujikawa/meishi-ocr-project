class CardData {
  final List<String> names = [];
  final List<String> companies = [];
  final List<String> departments = [];
  final List<String> titles = [];
  final List<String> phones = [];
  final List<String> mobiles = [];
  final List<String> faxes = [];
  final List<String> emails = [];
  final List<String> urls = [];
  final List<String> postalCodes = [];
  final List<String> addresses = [];

  bool get isEmpty =>
      names.isEmpty &&
      companies.isEmpty &&
      departments.isEmpty &&
      titles.isEmpty &&
      phones.isEmpty &&
      mobiles.isEmpty &&
      faxes.isEmpty &&
      emails.isEmpty &&
      urls.isEmpty &&
      postalCodes.isEmpty &&
      addresses.isEmpty;

  String? get primaryName => names.isEmpty ? null : names.first;
  String? get primaryCompany => companies.isEmpty ? null : companies.first;
  String? get primaryDepartment =>
      departments.isEmpty ? null : departments.first;
  String? get primaryTitle => titles.isEmpty ? null : titles.first;
  String? get primaryPostalCode =>
      postalCodes.isEmpty ? null : postalCodes.first;
  String? get primaryAddressLine => addresses.isEmpty ? null : addresses.first;
}
