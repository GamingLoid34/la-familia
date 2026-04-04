class PiktogramItem {
  final String emoji;
  final String label;
  final String category;

  const PiktogramItem({
    required this.emoji,
    required this.label,
    required this.category,
  });
}

const List<String> piktogramCategories = [
  'Alla',
  'Skola',
  'Sport',
  'Mat',
  'Hälsa',
  'Fritid',
  'Hemma',
  'Transport',
  'Socialt',
  'Känslor',
  'Övrigt',
];

const List<PiktogramItem> piktogramLibrary = [
  // ─── SKOLA ────────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '🏫', label: 'Skolan', category: 'Skola'),
  PiktogramItem(emoji: '📚', label: 'Läxa', category: 'Skola'),
  PiktogramItem(emoji: '✏️', label: 'Prov', category: 'Skola'),
  PiktogramItem(emoji: '🎒', label: 'Ryggsäck', category: 'Skola'),
  PiktogramItem(emoji: '🖊️', label: 'Pennor', category: 'Skola'),
  PiktogramItem(emoji: '📐', label: 'Matte', category: 'Skola'),
  PiktogramItem(emoji: '📖', label: 'Läsning', category: 'Skola'),
  PiktogramItem(emoji: '🔬', label: 'NO', category: 'Skola'),
  PiktogramItem(emoji: '🌍', label: 'SO', category: 'Skola'),
  PiktogramItem(emoji: '🎨', label: 'Bild', category: 'Skola'),
  PiktogramItem(emoji: '🎵', label: 'Musik i skolan', category: 'Skola'),
  PiktogramItem(emoji: '🏃', label: 'Idrott', category: 'Skola'),

  // ─── SPORT ────────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '⚽', label: 'Fotboll', category: 'Sport'),
  PiktogramItem(emoji: '🏊', label: 'Simning', category: 'Sport'),
  PiktogramItem(emoji: '🎾', label: 'Tennis', category: 'Sport'),
  PiktogramItem(emoji: '🏀', label: 'Basket', category: 'Sport'),
  PiktogramItem(emoji: '🤸', label: 'Gymnastik', category: 'Sport'),
  PiktogramItem(emoji: '🚴', label: 'Cykling', category: 'Sport'),
  PiktogramItem(emoji: '🏃', label: 'Löpning', category: 'Sport'),
  PiktogramItem(emoji: '⛷️', label: 'Skidåkning', category: 'Sport'),
  PiktogramItem(emoji: '🥊', label: 'Kampsport', category: 'Sport'),
  PiktogramItem(emoji: '🏋️', label: 'Träning', category: 'Sport'),
  PiktogramItem(emoji: '🎿', label: 'Längdskidor', category: 'Sport'),
  PiktogramItem(emoji: '🏒', label: 'Ishockey', category: 'Sport'),

  // ─── MAT ──────────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '🍽️', label: 'Middag', category: 'Mat'),
  PiktogramItem(emoji: '🥗', label: 'Lunch', category: 'Mat'),
  PiktogramItem(emoji: '🥞', label: 'Frukost', category: 'Mat'),
  PiktogramItem(emoji: '🍕', label: 'Pizza', category: 'Mat'),
  PiktogramItem(emoji: '🌮', label: 'Tacos', category: 'Mat'),
  PiktogramItem(emoji: '🍝', label: 'Pasta', category: 'Mat'),
  PiktogramItem(emoji: '🥘', label: 'Soppa', category: 'Mat'),
  PiktogramItem(emoji: '🍱', label: 'Matlåda', category: 'Mat'),
  PiktogramItem(emoji: '🛒', label: 'Handla', category: 'Mat'),
  PiktogramItem(emoji: '🍔', label: 'Hamburgare', category: 'Mat'),
  PiktogramItem(emoji: '🥙', label: 'Wrap', category: 'Mat'),
  PiktogramItem(emoji: '🍜', label: 'Nudlar', category: 'Mat'),

  // ─── HÄLSA ────────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '🏥', label: 'Läkare', category: 'Hälsa'),
  PiktogramItem(emoji: '🦷', label: 'Tandläkare', category: 'Hälsa'),
  PiktogramItem(emoji: '💊', label: 'Medicin', category: 'Hälsa'),
  PiktogramItem(emoji: '🧘', label: 'Avkoppling', category: 'Hälsa'),
  PiktogramItem(emoji: '😴', label: 'Vila', category: 'Hälsa'),
  PiktogramItem(emoji: '🛁', label: 'Bad/Dusch', category: 'Hälsa'),
  PiktogramItem(emoji: '🏃', label: 'Promenad', category: 'Hälsa'),
  PiktogramItem(emoji: '🌿', label: 'Terapeut', category: 'Hälsa'),

  // ─── FRITID ───────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '🎮', label: 'Spel', category: 'Fritid'),
  PiktogramItem(emoji: '🎬', label: 'Film', category: 'Fritid'),
  PiktogramItem(emoji: '🎵', label: 'Musik', category: 'Fritid'),
  PiktogramItem(emoji: '🎨', label: 'Rita', category: 'Fritid'),
  PiktogramItem(emoji: '📱', label: 'Mobil', category: 'Fritid'),
  PiktogramItem(emoji: '🎸', label: 'Instrument', category: 'Fritid'),
  PiktogramItem(emoji: '🧩', label: 'Pussel', category: 'Fritid'),
  PiktogramItem(emoji: '📺', label: 'TV', category: 'Fritid'),
  PiktogramItem(emoji: '🎲', label: 'Sällskapsspel', category: 'Fritid'),
  PiktogramItem(emoji: '📚', label: 'Läsa bok', category: 'Fritid'),
  PiktogramItem(emoji: '🎭', label: 'Teater', category: 'Fritid'),

  // ─── HEMMA ────────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '🧹', label: 'Städa', category: 'Hemma'),
  PiktogramItem(emoji: '🍳', label: 'Laga mat', category: 'Hemma'),
  PiktogramItem(emoji: '🗑️', label: 'Sopor', category: 'Hemma'),
  PiktogramItem(emoji: '🧺', label: 'Tvätt', category: 'Hemma'),
  PiktogramItem(emoji: '🐕', label: 'Rasta hunden', category: 'Hemma'),
  PiktogramItem(emoji: '🐱', label: 'Mata katten', category: 'Hemma'),
  PiktogramItem(emoji: '🛏️', label: 'Bädda', category: 'Hemma'),
  PiktogramItem(emoji: '🪟', label: 'Damma', category: 'Hemma'),
  PiktogramItem(emoji: '🧽', label: 'Diska', category: 'Hemma'),
  PiktogramItem(emoji: '🛒', label: 'Handla mat', category: 'Hemma'),
  PiktogramItem(emoji: '🌿', label: 'Vattna blommor', category: 'Hemma'),

  // ─── TRANSPORT ────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '🚌', label: 'Buss', category: 'Transport'),
  PiktogramItem(emoji: '🚗', label: 'Bil', category: 'Transport'),
  PiktogramItem(emoji: '🚆', label: 'Tåg', category: 'Transport'),
  PiktogramItem(emoji: '🚲', label: 'Cykel', category: 'Transport'),
  PiktogramItem(emoji: '🛴', label: 'Elsparkcykel', category: 'Transport'),
  PiktogramItem(emoji: '✈️', label: 'Flyg', category: 'Transport'),
  PiktogramItem(emoji: '🚶', label: 'Gå', category: 'Transport'),
  PiktogramItem(emoji: '🚇', label: 'Tunnelbana', category: 'Transport'),

  // ─── SOCIALT ──────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '👨‍👩‍👧‍👦', label: 'Familj', category: 'Socialt'),
  PiktogramItem(emoji: '👫', label: 'Kompisar', category: 'Socialt'),
  PiktogramItem(emoji: '🎂', label: 'Födelsedag', category: 'Socialt'),
  PiktogramItem(emoji: '🎉', label: 'Fest', category: 'Socialt'),
  PiktogramItem(emoji: '🤝', label: 'Möte', category: 'Socialt'),
  PiktogramItem(emoji: '📞', label: 'Samtal', category: 'Socialt'),
  PiktogramItem(emoji: '☕', label: 'Fika', category: 'Socialt'),

  // ─── KÄNSLOR ──────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '😊', label: 'Glad', category: 'Känslor'),
  PiktogramItem(emoji: '😴', label: 'Trött', category: 'Känslor'),
  PiktogramItem(emoji: '😰', label: 'Orolig', category: 'Känslor'),
  PiktogramItem(emoji: '💪', label: 'Stark', category: 'Känslor'),
  PiktogramItem(emoji: '🤒', label: 'Sjuk', category: 'Känslor'),
  PiktogramItem(emoji: '😤', label: 'Frustrerad', category: 'Känslor'),
  PiktogramItem(emoji: '🥳', label: 'Exalterad', category: 'Känslor'),
  PiktogramItem(emoji: '😌', label: 'Lugn', category: 'Känslor'),

  // ─── ÖVRIGT ───────────────────────────────────────────────────────────────
  PiktogramItem(emoji: '📷', label: 'Eget foto', category: 'Övrigt'),
  PiktogramItem(emoji: '⭐', label: 'Övrigt', category: 'Övrigt'),
  PiktogramItem(emoji: '📅', label: 'Kalender', category: 'Övrigt'),
  PiktogramItem(emoji: '⏰', label: 'Timer', category: 'Övrigt'),
  PiktogramItem(emoji: '🎯', label: 'Mål', category: 'Övrigt'),
  PiktogramItem(emoji: '🏆', label: 'Belöning', category: 'Övrigt'),
];
