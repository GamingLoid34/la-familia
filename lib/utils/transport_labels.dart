/// Transportmarkering på en aktivitet ("hur tar du dig dit?").
///
/// Ren logik utan Flutter-beroenden — portas 1:1 till Kotlin i Android-appen
/// (Fas 7) med samma testfall.
///
/// Personen i texten är medveten och skiljer sig åt mellan de två ytorna:
/// - **Chippen** (den här filen) talar TILL användaren: "De hämtar dig".
/// - **Valknappen** i transport-sheeten talar FÖR användaren: "De hämtar mig".
///   Den ligger kvar i `min_dag_view.dart` eftersom den hör ihop med sheetens
///   övriga knapptexter ("Jag tar mig dit själv").
library;

/// Lagrat värde för "tar sig dit själv".
const String transportSjalv = 'sjalv';

/// Lagrat värde för "blir hämtad".
const String transportHamtas = 'hamtas';

/// Texten på transportchippet i Min dag-tidslinjen.
///
/// [isNext] är sant för nästa/pågående block, som får den längre, mer
/// uppmanande texten. Övriga block får kortformen.
/// Returnerar null när ingen transport är vald (inget chip ska visas).
String? transportChipText(String? transport, bool isNext) {
  if (transport == transportSjalv) {
    return isNext ? '🚶‍♀️ Ta dig dit själv' : '🚶‍♀️ Själv';
  }
  if (transport == transportHamtas) {
    return isNext ? '🤝 De hämtar dig' : '🤝 Hämtas';
  }
  return null;
}
