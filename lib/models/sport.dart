import 'package:flutter/material.dart';

class SportType {
  final String id;
  final IconData icon;
  final Map<String, String> labels; // langCode -> localized name
  final Color color;

  /// Race sports (dash, swimming, cycling, athletics): everyone starts once and
  /// the event ends once. They have no league, no knockout and no groups; the
  /// result is a ranking by time.
  final bool isRace;

  const SportType({
    required this.id,
    required this.icon,
    required this.labels,
    required this.color,
    this.isRace = false,
  });

  String label(String langCode) => labels[langCode] ?? labels['en'] ?? id;

  /// The sport colour adjusted so text and icons stay readable: lighter on
  /// the dark navy background, darker on the light background.
  Color tone(bool dark) {
    final hsl = HSLColor.fromColor(color);
    final l = dark ? hsl.lightness.clamp(0.70, 0.86) : hsl.lightness.clamp(0.20, 0.34);
    final sat = dark ? hsl.saturation.clamp(0.45, 1.0) : hsl.saturation.clamp(0.5, 1.0);
    return hsl.withLightness(l.toDouble()).withSaturation(sat.toDouble()).toColor();
  }
}

class Sports {
  static const List<SportType> all = [
    SportType(
      id: 'football',
      icon: Icons.sports_soccer,
      color: Color(0xFF27AE60),
      labels: {
        'fa': 'فوتبال', 'en': 'Football', 'es': 'Fútbol', 'fr': 'Football',
        'ar': 'كرة القدم', 'ru': 'Футбол', 'hi': 'फ़ुटबॉल', 'zh': '足球',
      },
    ),
    SportType(
      id: 'futsal',
      icon: Icons.sports_soccer,
      color: Color(0xFF1ABC9C),
      labels: {
        'fa': 'فوتسال', 'en': 'Futsal', 'es': 'Fútbol sala', 'fr': 'Futsal',
        'ar': 'كرة الصالات', 'ru': 'Футзал', 'hi': 'फुटसल', 'zh': '五人制足球',
      },
    ),
    SportType(
      id: 'volleyball',
      icon: Icons.sports_volleyball,
      color: Color(0xFFF39C12),
      labels: {
        'fa': 'والیبال', 'en': 'Volleyball', 'es': 'Voleibol', 'fr': 'Volleyball',
        'ar': 'الكرة الطائرة', 'ru': 'Волейбол', 'hi': 'वॉलीबॉल', 'zh': '排球',
      },
    ),
    SportType(
      id: 'basketball',
      icon: Icons.sports_basketball,
      color: Color(0xFFE67E22),
      labels: {
        'fa': 'بسکتبال', 'en': 'Basketball', 'es': 'Baloncesto', 'fr': 'Basketball',
        'ar': 'كرة السلة', 'ru': 'Баскетбол', 'hi': 'बास्केटबॉल', 'zh': '篮球',
      },
    ),
    SportType(
      id: 'wrestling',
      icon: Icons.sports_kabaddi,
      color: Color(0xFF8E44AD),
      labels: {
        'fa': 'پهلوانی / کشتی', 'en': 'Wrestling', 'es': 'Lucha Libre', 'fr': 'Lutte',
        'ar': 'المصارعة', 'ru': 'Борьба', 'hi': 'कुश्ती', 'zh': '摔跤',
      },
    ),
    SportType(
      id: 'judo',
      icon: Icons.sports_mma,
      color: Color(0xFF2C3E50),
      labels: {
        'fa': 'مبارزات آزاد', 'en': 'Free Fighting', 'es': 'Combate Libre', 'fr': 'Combat Libre',
        'ar': 'القتال الحر', 'ru': 'Вольный бой', 'hi': 'मुक्त लड़ाई', 'zh': '自由搏击',
      },
    ),
    SportType(
      id: 'judoSport',
      icon: Icons.sports_gymnastics,
      color: Color(0xFF1F618D),
      labels: {
        'fa': 'جودو', 'en': 'Judo', 'es': 'Judo', 'fr': 'Judo',
        'ar': 'الجودو', 'ru': 'Дзюдо', 'hi': 'जूडो', 'zh': '柔道',
      },
    ),
    SportType(
      id: 'taekwondo',
      icon: Icons.sports_martial_arts,
      color: Color(0xFFC0392B),
      labels: {
        'fa': 'تکواندو', 'en': 'Taekwondo', 'es': 'Taekwondo', 'fr': 'Taekwondo',
        'ar': 'التايكوندو', 'ru': 'Тхэквондо', 'hi': 'ताइक्वांडो', 'zh': '跆拳道',
      },
    ),
    SportType(
      id: 'tennis',
      icon: Icons.sports_tennis,
      color: Color(0xFF16A085),
      labels: {
        'fa': 'تنیس', 'en': 'Tennis', 'es': 'Tenis', 'fr': 'Tennis',
        'ar': 'التنس', 'ru': 'Теннис', 'hi': 'टेनिस', 'zh': '网球',
      },
    ),
    SportType(
      id: 'tableTennis',
      icon: Icons.sports_tennis,
      color: Color(0xFFE67E22),
      labels: {
        'fa': 'تنیس روی میز', 'en': 'Table tennis', 'es': 'Tenis de mesa', 'fr': 'Tennis de table',
        'ar': 'كرة الطاولة', 'ru': 'Настольный теннис', 'hi': 'टेबल टेनिस', 'zh': '乒乓球',
      },
    ),
    SportType(
      id: 'cricket',
      icon: Icons.sports_cricket,
      color: Color(0xFF2980B9),
      labels: {
        'fa': 'کریکت', 'en': 'Cricket', 'es': 'Críquet', 'fr': 'Cricket',
        'ar': 'الكريكيت', 'ru': 'Крикет', 'hi': 'क्रिकेट', 'zh': '板球',
      },
    ),
    SportType(
      id: 'chess',
      icon: Icons.grid_view_rounded,
      color: Color(0xFF4B5BD6),
      labels: {
        'fa': 'شطرنج', 'en': 'Chess', 'es': 'Ajedrez', 'fr': 'Échecs',
        'ar': 'الشطرنج', 'ru': 'Шахматы', 'hi': 'शतरंज', 'zh': '国际象棋',
      },
    ),
    SportType(
      id: 'kurash',
      icon: Icons.sports_handball,
      color: Color(0xFF0E8F8F),
      labels: {
        'fa': 'کورش', 'en': 'Kurash', 'es': 'Kurash', 'fr': 'Kourach',
        'ar': 'كوراش', 'ru': 'Кураш', 'hi': 'कुराश', 'zh': '库拉什',
      },
    ),
    SportType(
      id: 'dash',
      icon: Icons.directions_run,
      color: Color(0xFFE4572E),
      isRace: true,
      labels: {'fa': 'دوش (دو سرعت)', 'en': 'Dash (sprint)', 'es': 'Carrera de velocidad', 'fr': 'Sprint', 'ar': 'سباق العدو', 'ru': 'Спринт', 'hi': 'स्प्रिंट दौड़', 'zh': '短跑'},
    ),
    SportType(
      id: 'athletics',
      icon: Icons.timer,
      color: Color(0xFFC0392B),
      isRace: true,
      labels: {'fa': 'دو و میدانی', 'en': 'Athletics (track)', 'es': 'Atletismo (pista)', 'fr': 'Athlétisme (piste)', 'ar': 'ألعاب القوى (مضمار)', 'ru': 'Лёгкая атлетика', 'hi': 'एथलेटिक्स', 'zh': '田径（径赛）'},
    ),
    SportType(
      id: 'swimming',
      icon: Icons.pool,
      color: Color(0xFF1E88E5),
      isRace: true,
      labels: {'fa': 'شنا', 'en': 'Swimming', 'es': 'Natación', 'fr': 'Natation', 'ar': 'السباحة', 'ru': 'Плавание', 'hi': 'तैराकी', 'zh': '游泳'},
    ),
    SportType(
      id: 'cycling',
      icon: Icons.directions_bike,
      color: Color(0xFF2E7D32),
      isRace: true,
      labels: {'fa': 'دوچرخه‌سواری', 'en': 'Cycling', 'es': 'Ciclismo', 'fr': 'Cyclisme', 'ar': 'ركوب الدراجات', 'ru': 'Велоспорт', 'hi': 'साइकिलिंग', 'zh': '自行车'},
    ),
    SportType(
      id: 'esports',
      icon: Icons.sports_esports,
      color: Color(0xFF6C5CE7),
      labels: {
        'fa': 'ای‌اسپورت', 'en': 'Esports', 'es': 'Esports', 'fr': 'Esport',
        'ar': 'الرياضات الإلكترونية', 'ru': 'Киберспорт', 'hi': 'ई-स्पोर्ट्स', 'zh': '电子竞技',
      },
    ),
    SportType(
      id: 'other',
      icon: Icons.emoji_events,
      color: Color(0xFF7F8C8D),
      labels: {
        'fa': 'سایر', 'en': 'Other', 'es': 'Otro', 'fr': 'Autre',
        'ar': 'أخرى', 'ru': 'Другое', 'hi': 'अन्य', 'zh': '其他',
      },
    ),
  ];

  static SportType byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.last);
}
