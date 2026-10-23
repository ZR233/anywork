/// Settings-local editor lifecycle, not a Repository or operation registry.
/// The Accounts VM hands off a mounted editor without creating an unseen family.
abstract interface class AccountDetailParticipant {
  void setVisible(bool visible);
  void leave();
  void endEditing();
}
