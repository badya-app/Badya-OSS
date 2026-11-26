import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Holds all reader & typography settings.
class ReaderSettings {
  final double fontSize;
  final String fontFamily;
  final double lineHeight;
  final int textAlignIndex;
  final int fontWeightIndex;
  final bool indentEnabled;

  const ReaderSettings({
    this.fontSize = 18.0,
    this.fontFamily = 'Nunito',
    this.lineHeight = 1.7,
    this.textAlignIndex = 0,
    this.fontWeightIndex = 0,
    this.indentEnabled = false,
  });

  ReaderSettings copyWith({
    double? fontSize,
    String? fontFamily,
    double? lineHeight,
    int? textAlignIndex,
    int? fontWeightIndex,
    bool? indentEnabled,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      textAlignIndex: textAlignIndex ?? this.textAlignIndex,
      fontWeightIndex: fontWeightIndex ?? this.fontWeightIndex,
      indentEnabled: indentEnabled ?? this.indentEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'font_size': fontSize,
    'font_family': fontFamily,
    'line_height': lineHeight,
    'text_align_index': textAlignIndex,
    'font_weight_index': fontWeightIndex,
    'indent_enabled': indentEnabled,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    return ReaderSettings(
      fontSize: (json['font_size'] as num?)?.toDouble() ?? 18.0,
      fontFamily: json['font_family']?.toString() ?? 'Nunito',
      lineHeight: (json['line_height'] as num?)?.toDouble() ?? 1.7,
      textAlignIndex: (json['text_align_index'] as num?)?.toInt() ?? 0,
      fontWeightIndex: (json['font_weight_index'] as num?)?.toInt() ?? 0,
      indentEnabled: (json['indent_enabled'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderSettings &&
          runtimeType == other.runtimeType &&
          fontSize == other.fontSize &&
          fontFamily == other.fontFamily &&
          lineHeight == other.lineHeight &&
          textAlignIndex == other.textAlignIndex &&
          fontWeightIndex == other.fontWeightIndex &&
          indentEnabled == other.indentEnabled;

  @override
  int get hashCode => Object.hash(
    fontSize,
    fontFamily,
    lineHeight,
    textAlignIndex,
    fontWeightIndex,
    indentEnabled,
  );
}

/// Resolves a font-family name to a [TextStyle] via Google Fonts with safe fallback.
/// Handles Latin, Arabic, CJK, Devanagari, Hebrew, Thai, Cyrillic, and more.
TextStyle resolveFontStyle(
  String fontFamily, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
}) {
  switch (fontFamily) {
    // ── Latin ──
    case 'Nunito':
      return GoogleFonts.nunito(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Merriweather':
      return GoogleFonts.merriweather(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Lora':
      return GoogleFonts.lora(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Open Sans':
      return GoogleFonts.openSans(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Roboto':
      return GoogleFonts.roboto(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Poppins':
      return GoogleFonts.poppins(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Noto Serif':
      return GoogleFonts.notoSerif(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Roboto Mono':
      return GoogleFonts.robotoMono(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Playfair Display':
      return GoogleFonts.playfairDisplay(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Source Serif 4':
      return GoogleFonts.sourceSerif4(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'EB Garamond':
      return GoogleFonts.ebGaramond(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Crimson Pro':
      return GoogleFonts.crimsonPro(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Libre Baskerville':
      return GoogleFonts.libreBaskerville(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Josefin Sans':
      return GoogleFonts.josefinSans(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'DM Sans':
      return GoogleFonts.dmSans(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Mulish':
      return GoogleFonts.mulish(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Raleway':
      return GoogleFonts.raleway(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Montserrat':
      return GoogleFonts.montserrat(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Inter':
      return GoogleFonts.inter(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Arabic / RTL ──
    case 'Cairo':
      return GoogleFonts.cairo(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Tajawal':
      return GoogleFonts.tajawal(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Almarai':
      return GoogleFonts.almarai(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'El Messiri':
      return GoogleFonts.elMessiri(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Amiri':
      return GoogleFonts.amiri(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Rakkas':
      return GoogleFonts.rakkas(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Noto Sans Arabic':
      return GoogleFonts.notoSansArabic(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Noto Naskh Arabic':
      return GoogleFonts.notoNaskhArabic(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Scheherazade New':
      return GoogleFonts.scheherazadeNew(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Japanese ──
    case 'Noto Sans JP':
      return GoogleFonts.notoSansJp(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Noto Serif JP':
      return GoogleFonts.notoSerifJp(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'M PLUS Rounded 1c':
      return GoogleFonts.mPlusRounded1c(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Zen Kaku Gothic New':
      return GoogleFonts.zenKakuGothicNew(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Shippori Mincho':
      return GoogleFonts.shipporiMincho(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Chinese ──
    case 'Noto Sans SC':
      return GoogleFonts.notoSansSc(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Noto Serif SC':
      return GoogleFonts.notoSerifSc(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'ZCOOL XiaoWei':
      return GoogleFonts.zcoolXiaoWei(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'ZCOOL QingKe HuangYou':
      return GoogleFonts.zcoolQingKeHuangYou(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Long Cang':
      return GoogleFonts.longCang(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Korean ──
    case 'Noto Sans KR':
      return GoogleFonts.notoSansKr(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Noto Serif KR':
      return GoogleFonts.notoSerifKr(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Black Han Sans':
      return GoogleFonts.blackHanSans(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Do Hyeon':
      return GoogleFonts.doHyeon(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Nanum Myeongjo':
      return GoogleFonts.nanumMyeongjo(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Devanagari (Hindi / Marathi / Nepali) ──
    case 'Noto Sans Devanagari':
      return GoogleFonts.notoSansDevanagari(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Hind':
      return GoogleFonts.hind(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Tiro Devanagari Hindi':
      return GoogleFonts.tiroDevanagariHindi(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Baloo 2':
      return GoogleFonts.baloo2(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Mukta':
      return GoogleFonts.mukta(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Thai ──
    case 'Noto Sans Thai':
      return GoogleFonts.notoSansThai(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Sarabun':
      return GoogleFonts.sarabun(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Kanit':
      return GoogleFonts.kanit(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Charm':
      return GoogleFonts.charm(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Mitr':
      return GoogleFonts.mitr(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Hebrew ──
    case 'Noto Sans Hebrew':
      return GoogleFonts.notoSansHebrew(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Frank Ruhl Libre':
      return GoogleFonts.frankRuhlLibre(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Heebo':
      return GoogleFonts.heebo(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Rubik':
      return GoogleFonts.rubik(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Assistant':
      return GoogleFonts.assistant(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Cyrillic (Russian / Ukrainian / Bulgarian) ──
    case 'Noto Serif Cyrillic':
      return GoogleFonts.notoSerif(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'PT Serif':
      return GoogleFonts.ptSerif(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'PT Sans':
      return GoogleFonts.ptSans(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Russo One':
      return GoogleFonts.russoOne(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Oswald':
      return GoogleFonts.oswald(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Greek ──
    case 'Noto Serif Greek':
      return GoogleFonts.notoSerifDisplay(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'GFS Didot':
      return GoogleFonts.gfsDidot(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Bangla ──
    case 'Noto Sans Bengali':
      return GoogleFonts.notoSansBengali(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Hind Siliguri':
      return GoogleFonts.hindSiliguri(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Baloo Da 2':
      return GoogleFonts.balooDa2(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    // ── Vietnamese ──
    case 'Be Vietnam Pro':
      return GoogleFonts.beVietnamPro(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    case 'Bai Jamjuree':
      return GoogleFonts.baiJamjuree(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
    default:
      return GoogleFonts.nunito(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
  }
}

// ── Script groups used by [fontsForLanguage] ──────────────────────────────────

const Map<String, String> _latinFonts = {
  'Nunito': 'Nunito',
  'Open Sans': 'Open Sans',
  'Lora': 'Lora',
  'Merriweather': 'Merriweather',
  'Playfair Display': 'Playfair Display',
  'EB Garamond': 'EB Garamond',
  'Crimson Pro': 'Crimson Pro',
  'Montserrat': 'Montserrat',
};

const Map<String, String> _arabicFonts = {
  'Cairo': 'Cairo',
  'Tajawal': 'Tajawal',
  'Almarai': 'Almarai',
  'El Messiri': 'El Messiri',
  'Amiri': 'Amiri',
  'Noto Sans Arabic': 'Noto Sans Arabic',
  'Noto Naskh Arabic': 'Noto Naskh Arabic',
  'Scheherazade New': 'Scheherazade New',
};

const Map<String, String> _japaneseFonts = {
  'Noto Sans JP': 'Noto Sans JP',
  'Noto Serif JP': 'Noto Serif JP',
  'M PLUS Rounded 1c': 'M PLUS Rounded 1c',
  'Zen Kaku Gothic New': 'Zen Kaku Gothic New',
  'Shippori Mincho': 'Shippori Mincho',
};

const Map<String, String> _chineseFonts = {
  'Noto Sans SC': 'Noto Sans SC',
  'Noto Serif SC': 'Noto Serif SC',
  'ZCOOL XiaoWei': 'ZCOOL XiaoWei',
  'ZCOOL QingKe HuangYou': 'ZCOOL QingKe HuangYou',
  'Long Cang': 'Long Cang',
};

const Map<String, String> _koreanFonts = {
  'Noto Sans KR': 'Noto Sans KR',
  'Noto Serif KR': 'Noto Serif KR',
  'Black Han Sans': 'Black Han Sans',
  'Do Hyeon': 'Do Hyeon',
  'Nanum Myeongjo': 'Nanum Myeongjo',
};

const Map<String, String> _devanagariFonts = {
  'Noto Sans Devanagari': 'Noto Sans Devanagari',
  'Hind': 'Hind',
  'Tiro Devanagari Hindi': 'Tiro Devanagari Hindi',
  'Baloo 2': 'Baloo 2',
  'Mukta': 'Mukta',
};

const Map<String, String> _thaiFonts = {
  'Noto Sans Thai': 'Noto Sans Thai',
  'Sarabun': 'Sarabun',
  'Kanit': 'Kanit',
  'Charm': 'Charm',
  'Mitr': 'Mitr',
};

const Map<String, String> _hebrewFonts = {
  'Noto Sans Hebrew': 'Noto Sans Hebrew',
  'Frank Ruhl Libre': 'Frank Ruhl Libre',
  'Heebo': 'Heebo',
  'Rubik': 'Rubik',
  'Assistant': 'Assistant',
};

const Map<String, String> _cyrillicFonts = {
  'Noto Serif Cyrillic': 'Noto Serif Cyrillic',
  'PT Serif': 'PT Serif',
  'PT Sans': 'PT Sans',
  'Russo One': 'Russo One',
  'Oswald': 'Oswald',
};

const Map<String, String> _greekFonts = {
  'Noto Serif Greek': 'Noto Serif Greek',
  'GFS Didot': 'GFS Didot',
  'Open Sans': 'Open Sans',
  'Roboto': 'Roboto',
  'Lora': 'Lora',
};

const Map<String, String> _banglaFonts = {
  'Noto Sans Bengali': 'Noto Sans Bengali',
  'Hind Siliguri': 'Hind Siliguri',
  'Baloo Da 2': 'Baloo Da 2',
};

const Map<String, String> _vietnameseFonts = {
  'Be Vietnam Pro': 'Be Vietnam Pro',
  'Bai Jamjuree': 'Bai Jamjuree',
  'Open Sans': 'Open Sans',
  'Nunito': 'Nunito',
  'Lora': 'Lora',
};

/// Returns the curated font map for [language] (the study/current language name
/// as stored in [LanguageManager], e.g. 'Arabic', 'Japanese', 'English').
///
/// Falls back to [_latinFonts] for any language without a dedicated script map.
Map<String, String> fontsForLanguage(String language) {
  switch (language) {
    // Arabic script
    case 'Arabic':
    case 'Persian':
    case 'Urdu':
    case 'Sindhi':
    case 'Pashto':
      return _arabicFonts;
    // Japanese
    case 'Japanese':
      return _japaneseFonts;
    // Chinese
    case 'Chinese, Mandarin':
      return _chineseFonts;
    // Korean
    case 'Korean':
      return _koreanFonts;
    // Devanagari
    case 'Hindi':
    case 'Marathi':
    case 'Nepali':
    case 'Konkani':
    case 'Maithili':
      return _devanagariFonts;
    // Thai
    case 'Thai':
    case 'Lao':
      return _thaiFonts;
    // Hebrew
    case 'Hebrew':
      return _hebrewFonts;
    // Cyrillic
    case 'Russian':
    case 'Ukrainian':
    case 'Bulgarian':
    case 'Belarusian':
    case 'Macedonian':
    case 'Serbian':
    case 'Mongolian':
      return _cyrillicFonts;
    // Greek
    case 'Greek':
      return _greekFonts;
    // Bangla
    case 'Bangla':
      return _banglaFonts;
    // Vietnamese (Latin + diacritics — best with dedicated fonts)
    case 'Vietnamese':
      return _vietnameseFonts;
    // All other Latin-based languages
    default:
      return _latinFonts;
  }
}

/// The default Latin font list (used when no language is specified).
const Map<String, String> availableFonts = _latinFonts;

/// Resolves a font weight index (0: regular, 1: medium, 2: bold) to a [FontWeight].
FontWeight resolveFontWeight(int weightIndex) {
  switch (weightIndex) {
    case 1:
      return FontWeight.w500;
    case 2:
      return FontWeight.w700;
    case 0:
    default:
      return FontWeight.w400;
  }
}

/// Resolves a text alignment index to [TextAlign].
TextAlign resolveTextAlign(int textAlignIndex) {
  switch (textAlignIndex) {
    case 1:
      return TextAlign.center;
    case 2:
      return TextAlign.justify;
    case 3:
      return TextAlign.right;
    case 0:
    default:
      return TextAlign.left;
  }
}

/// Resolves a text alignment index to Markdown [WrapAlignment].
WrapAlignment resolveWrapAlignment(int textAlignIndex) {
  switch (textAlignIndex) {
    case 1:
      return WrapAlignment.center;
    case 3:
      return WrapAlignment.end;
    case 0:
    case 2:
    default:
      return WrapAlignment.start;
  }
}




/// Unified Font Control Widget that can be embedded directly or in a modal sheet.
/// Automatically updates internal state and notifies [onChanged] on any parameter change.
class FontControlWidget extends StatefulWidget {
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;
  final Map<String, String> fonts;
  final bool showPreview;
  final bool showParagraphOptions;

  const FontControlWidget({
    super.key,
    required this.settings,
    required this.onChanged,
    this.fonts = availableFonts,
    this.showPreview = true,
    this.showParagraphOptions = true,
  });

  @override
  State<FontControlWidget> createState() => _FontControlWidgetState();
}

class _FontControlWidgetState extends State<FontControlWidget> {
  late ReaderSettings _draft;

  static const double _minFontSize = 12.0;
  static const double _maxFontSize = 36.0;

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
  }

  @override
  void didUpdateWidget(FontControlWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _draft = widget.settings;
    }
  }

  void _update(ReaderSettings next) {
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = theme.colorScheme.secondary;

    final clampedFontSize = _draft.fontSize.clamp(_minFontSize, _maxFontSize);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live typography preview
        if (widget.showPreview) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFFAF9F5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0x1A2D3436),
              ),
            ),
            child: Text(
              'Sample reading text for visual preview.',
              textAlign: resolveTextAlign(_draft.textAlignIndex),
              style: resolveFontStyle(
                _draft.fontFamily,
                fontSize: clampedFontSize.clamp(13.0, 22.0),
                height: _draft.lineHeight,
                fontWeight: resolveFontWeight(_draft.fontWeightIndex),
                color: isDark ? Colors.white : const Color(0xFF2A2A28),
              ),
            ),
          ),
        ],

        // ─── 1. Font Size ───
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Font Size', isDark),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${clampedFontSize.round()} px',
                style: GoogleFonts.plusJakartaSans(
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              Icons.format_size,
              size: 16,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accentColor,
                  thumbColor: accentColor,
                  inactiveTrackColor: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.12),
                  trackHeight: 4.0,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 9.0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18.0,
                  ),
                ),
                child: Slider(
                  value: clampedFontSize,
                  min: _minFontSize,
                  max: _maxFontSize,
                  divisions: (_maxFontSize - _minFontSize).round(),
                  label: '${clampedFontSize.round()}',
                  onChanged: (v) => _update(_draft.copyWith(fontSize: v)),
                ),
              ),
            ),
            Icon(
              Icons.format_size,
              size: 24,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ─── 2. Font Family ───
        _buildSectionHeader('Font Family', isDark),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: widget.fonts.keys.map((f) {
              final isSelected = _draft.fontFamily == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _update(_draft.copyWith(fontFamily: f)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accentColor
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? accentColor
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.08)),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        f,
                        style: resolveFontStyle(
                          f,
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        // ─── 3. Spacing & Weight ───
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Spacing
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Line Spacing', isDark),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildSpacingButton(
                        icon: Icons.format_line_spacing,
                        heightVal: 1.2,
                        tooltip: 'Compact',
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildSpacingButton(
                        icon: Icons.notes,
                        heightVal: 1.7,
                        tooltip: 'Normal',
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildSpacingButton(
                        icon: Icons.sort,
                        heightVal: 2.2,
                        tooltip: 'Spacious',
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Weight
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Weight', isDark),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildWeightButton(
                        label: 'REG',
                        index: 0,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 6),
                      _buildWeightButton(
                        label: 'MED',
                        index: 1,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 6),
                      _buildWeightButton(
                        label: 'BOLD',
                        index: 2,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ─── 4. Alignment & Optional Indent ───
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: widget.showParagraphOptions ? 3 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Alignment', isDark),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildAlignButton(
                        icon: Icons.format_align_left,
                        index: 0,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 6),
                      _buildAlignButton(
                        icon: Icons.format_align_center,
                        index: 1,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 6),
                      _buildAlignButton(
                        icon: Icons.format_align_justify,
                        index: 2,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 6),
                      _buildAlignButton(
                        icon: Icons.format_align_right,
                        index: 3,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.showParagraphOptions) ...[
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('Indent', isDark),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildIndentButton(
                          icon: Icons.format_indent_decrease,
                          enabled: false,
                          accentColor: accentColor,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildIndentButton(
                          icon: Icons.format_indent_increase,
                          enabled: true,
                          accentColor: accentColor,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String text, bool isDark) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: isDark ? Colors.white60 : const Color(0xFF636E72),
      ),
    );
  }

  Widget _buildSpacingButton({
    required IconData icon,
    required double heightVal,
    required String tooltip,
    required Color accentColor,
    required bool isDark,
  }) {
    final isSelected = (_draft.lineHeight - heightVal).abs() < 0.05;
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () => _update(_draft.copyWith(lineHeight: heightVal)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? accentColor
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeightButton({
    required String label,
    required int index,
    required Color accentColor,
    required bool isDark,
  }) {
    final isSelected = _draft.fontWeightIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _update(_draft.copyWith(fontWeightIndex: index)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08)),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlignButton({
    required IconData icon,
    required int index,
    required Color accentColor,
    required bool isDark,
  }) {
    final isSelected = _draft.textAlignIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _update(_draft.copyWith(textAlignIndex: index)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08)),
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildIndentButton({
    required IconData icon,
    required bool enabled,
    required Color accentColor,
    required bool isDark,
  }) {
    final isSelected = _draft.indentEnabled == enabled;
    return Expanded(
      child: GestureDetector(
        onTap: () => _update(_draft.copyWith(indentEnabled: enabled)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08)),
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }
}

/// Shows the unified reader and typography settings bottom sheet.
///
/// Pass [language] (e.g. `'Arabic'`, `'Japanese'`) to automatically show fonts
/// appropriate for that script. When [language] is provided the [fonts] map is
/// ignored. Falls back to Latin fonts when [language] is null or unrecognised.
///
/// Calls [onChanged] immediately whenever any setting is altered.
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderSettings current,
  String? language,
  Map<String, String> fonts = availableFonts,
  required ValueChanged<ReaderSettings> onChanged,
}) {
  final resolvedFonts = language != null ? fontsForLanguage(language) : fonts;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF222220) : Colors.white)
                    .withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0x1A2D3436),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sheet grab handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    FontControlWidget(
                      settings: current,
                      fonts: resolvedFonts,
                      onChanged: onChanged,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
