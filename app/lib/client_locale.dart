/// Accepted product locales. Every catalog entry must supply both translations.
enum ClientLocale {
  en,
  ru;

  String text({required String en, required String ru}) => switch (this) {
    ClientLocale.en => en,
    ClientLocale.ru => ru,
  };
}
