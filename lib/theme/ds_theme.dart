import 'package:flutter/material.dart';

/// DeepSeek semantic design tokens ported 1:1 from deepseek-ai/chat-demo `theme.css`.
@immutable
class DsColors extends ThemeExtension<DsColors> {
  final Color bgBase;
  final Color bgLayer2;
  final Color bgLayer3;
  final Color sidebarFill;
  final Color userBubble;
  final Color inputMajor;
  final Color loginInput;
  final Color selectorFill;
  final Color skeleton;
  final Color toastBg;

  final Color brandPrimary;
  final Color brandPrimaryInvert;
  final Color brandText;
  final Color buttonPrimaryFill;
  final Color buttonElevatedFill;
  final Color buttonContrastFill;
  final Color ghostActiveFill;
  final Color ghostActiveBorder;

  final Color sidebarItemActiveBg;
  final Color sidebarItemHoverBg;

  final Color labelPrimary;
  final Color labelSecondary;
  final Color labelTertiary;
  final Color labelCaption;
  final Color labelDimmed;
  final Color labelOnPrimary;

  final Color borderL1;
  final Color borderL2;
  final Color borderL2Thin;
  final Color borderL3;

  final Color interactiveHover;
  final Color interactiveActive;
  final Color dangerHover;

  final Color errorPrimary;
  final Color errorSecondary;
  final Color successPrimary;

  final Color codeBlockBg;
  final Color codeBlockBanner;
  final Color inlineCodeBg;
  final Color citationHoverBg;
  final Color citationBg;
  final Color tagBg;

  final bool isDark;

  const DsColors({
    required this.bgBase,
    required this.bgLayer2,
    required this.bgLayer3,
    required this.sidebarFill,
    required this.userBubble,
    required this.inputMajor,
    required this.loginInput,
    required this.selectorFill,
    required this.skeleton,
    required this.toastBg,
    required this.brandPrimary,
    required this.brandPrimaryInvert,
    required this.brandText,
    required this.buttonPrimaryFill,
    required this.buttonElevatedFill,
    required this.buttonContrastFill,
    required this.ghostActiveFill,
    required this.ghostActiveBorder,
    required this.sidebarItemActiveBg,
    required this.sidebarItemHoverBg,
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.labelCaption,
    required this.labelDimmed,
    required this.labelOnPrimary,
    required this.borderL1,
    required this.borderL2,
    required this.borderL2Thin,
    required this.borderL3,
    required this.interactiveHover,
    required this.interactiveActive,
    required this.dangerHover,
    required this.errorPrimary,
    required this.errorSecondary,
    required this.successPrimary,
    required this.codeBlockBg,
    required this.codeBlockBanner,
    required this.inlineCodeBg,
    required this.citationHoverBg,
    required this.citationBg,
    required this.tagBg,
    required this.isDark,
  });

  static const DsColors light = DsColors(
    bgBase: Color(0xFFFFFFFF),
    bgLayer2: Color(0xFFFFFFFF),
    bgLayer3: Color(0xFFFFFFFF),
    sidebarFill: Color(0xFFF9FAFB),
    userBubble: Color(0xFFEDF3FE),
    inputMajor: Color(0xFFFFFFFF),
    loginInput: Color(0xFFF9FAFB),
    selectorFill: Color(0xFFF1F3F5),
    skeleton: Color(0x0A000000),
    toastBg: Color(0xFF353638),
    brandPrimary: Color(0xFF3964FE),
    brandPrimaryInvert: Color(0xFF3964FE),
    brandText: Color(0xFF3964FE),
    buttonPrimaryFill: Color(0xFF3964FE),
    buttonElevatedFill: Color(0xFFFFFFFF),
    buttonContrastFill: Color(0xFF61666B),
    ghostActiveFill: Color(0xFFEDF3FE),
    ghostActiveBorder: Color(0xFFB7C8FE),
    sidebarItemActiveBg: Color(0xFFE4EDFD),
    sidebarItemHoverBg: Color(0xFFF1F3F5),
    labelPrimary: Color(0xFF0F1115),
    labelSecondary: Color(0xFF61666B),
    labelTertiary: Color(0xFF81858C),
    labelCaption: Color(0xFFADB2B8),
    labelDimmed: Color(0xFFE1E5EE),
    labelOnPrimary: Color(0xFFFFFFFF),
    borderL1: Color(0x0A000000),
    borderL2: Color(0x1A000000),
    borderL2Thin: Color(0x1A000000),
    borderL3: Color(0x1F000000),
    interactiveHover: Color(0x0F263148),
    interactiveActive: Color(0x1A263148),
    dangerHover: Color(0x0DEC1313),
    errorPrimary: Color(0xFFEC1313),
    errorSecondary: Color(0xFFF25A5A),
    successPrimary: Color(0xFF22C55E),
    codeBlockBg: Color(0xFFF9FAFB),
    codeBlockBanner: Color(0xFFF9FAFB),
    inlineCodeBg: Color(0xFFEBEEF2),
    citationHoverBg: Color(0xFFEBEEF2),
    citationBg: Color(0xFFF5F6F7),
    tagBg: Color(0xFFF1F3F5),
    isDark: false,
  );

  static const DsColors dark = DsColors(
    bgBase: Color(0xFF151517),
    bgLayer2: Color(0xFF2C2C2E),
    bgLayer3: Color(0xFF353638),
    sidebarFill: Color(0xFF1B1B1C),
    userBubble: Color(0xFF2C2C2E),
    inputMajor: Color(0xFF2C2C2E),
    loginInput: Color(0xFF1B1B1C),
    selectorFill: Color(0xFF43454A),
    skeleton: Color(0x14FFFFFF),
    toastBg: Color(0xFF43454A),
    brandPrimary: Color(0xFF5686FE),
    brandPrimaryInvert: Color(0xFFFFFFFF),
    brandText: Color(0xFF679EFE),
    buttonPrimaryFill: Color(0xFF5686FE),
    buttonElevatedFill: Color(0xFF43454A),
    buttonContrastFill: Color(0xFFF9FAFB),
    ghostActiveFill: Color(0xFF283142),
    ghostActiveBorder: Color(0xFF4868B2),
    sidebarItemActiveBg: Color(0xFF353638),
    sidebarItemHoverBg: Color(0xFF2C2C2E),
    labelPrimary: Color(0xFFF9FAFB),
    labelSecondary: Color(0xFFCFD3D6),
    labelTertiary: Color(0xFFADB2B8),
    labelCaption: Color(0xFF81858C),
    labelDimmed: Color(0xFF43454A),
    labelOnPrimary: Color(0xFFFFFFFF),
    borderL1: Color(0x0FFFFFFF),
    borderL2: Color(0x1FFFFFFF),
    borderL2Thin: Color(0x0FFFFFFF),
    borderL3: Color(0x29FFFFFF),
    interactiveHover: Color(0x14FFFFFF),
    interactiveActive: Color(0x24FFFFFF),
    dangerHover: Color(0x26F25A5A),
    errorPrimary: Color(0xFFF25A5A),
    errorSecondary: Color(0xFFF25A5A),
    successPrimary: Color(0xFF4ED17E),
    codeBlockBg: Color(0xFF1B1B1C),
    codeBlockBanner: Color(0xFF2C2C2E),
    inlineCodeBg: Color(0xFF2C2C2E),
    citationHoverBg: Color(0xFF353638),
    citationBg: Color(0xFF2C2C2E),
    tagBg: Color(0xFF2C2C2E),
    isDark: true,
  );

  @override
  DsColors copyWith({
    Color? bgBase,
    Color? bgLayer2,
    Color? bgLayer3,
    Color? sidebarFill,
    Color? userBubble,
    Color? inputMajor,
    Color? loginInput,
    Color? selectorFill,
    Color? skeleton,
    Color? toastBg,
    Color? brandPrimary,
    Color? brandPrimaryInvert,
    Color? brandText,
    Color? buttonPrimaryFill,
    Color? buttonElevatedFill,
    Color? buttonContrastFill,
    Color? ghostActiveFill,
    Color? ghostActiveBorder,
    Color? sidebarItemActiveBg,
    Color? sidebarItemHoverBg,
    Color? labelPrimary,
    Color? labelSecondary,
    Color? labelTertiary,
    Color? labelCaption,
    Color? labelDimmed,
    Color? labelOnPrimary,
    Color? borderL1,
    Color? borderL2,
    Color? borderL2Thin,
    Color? borderL3,
    Color? interactiveHover,
    Color? interactiveActive,
    Color? dangerHover,
    Color? errorPrimary,
    Color? errorSecondary,
    Color? successPrimary,
    Color? codeBlockBg,
    Color? codeBlockBanner,
    Color? inlineCodeBg,
    Color? citationHoverBg,
    Color? citationBg,
    Color? tagBg,
    bool? isDark,
  }) {
    return DsColors(
      bgBase: bgBase ?? this.bgBase,
      bgLayer2: bgLayer2 ?? this.bgLayer2,
      bgLayer3: bgLayer3 ?? this.bgLayer3,
      sidebarFill: sidebarFill ?? this.sidebarFill,
      userBubble: userBubble ?? this.userBubble,
      inputMajor: inputMajor ?? this.inputMajor,
      loginInput: loginInput ?? this.loginInput,
      selectorFill: selectorFill ?? this.selectorFill,
      skeleton: skeleton ?? this.skeleton,
      toastBg: toastBg ?? this.toastBg,
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandPrimaryInvert: brandPrimaryInvert ?? this.brandPrimaryInvert,
      brandText: brandText ?? this.brandText,
      buttonPrimaryFill: buttonPrimaryFill ?? this.buttonPrimaryFill,
      buttonElevatedFill: buttonElevatedFill ?? this.buttonElevatedFill,
      buttonContrastFill: buttonContrastFill ?? this.buttonContrastFill,
      ghostActiveFill: ghostActiveFill ?? this.ghostActiveFill,
      ghostActiveBorder: ghostActiveBorder ?? this.ghostActiveBorder,
      sidebarItemActiveBg: sidebarItemActiveBg ?? this.sidebarItemActiveBg,
      sidebarItemHoverBg: sidebarItemHoverBg ?? this.sidebarItemHoverBg,
      labelPrimary: labelPrimary ?? this.labelPrimary,
      labelSecondary: labelSecondary ?? this.labelSecondary,
      labelTertiary: labelTertiary ?? this.labelTertiary,
      labelCaption: labelCaption ?? this.labelCaption,
      labelDimmed: labelDimmed ?? this.labelDimmed,
      labelOnPrimary: labelOnPrimary ?? this.labelOnPrimary,
      borderL1: borderL1 ?? this.borderL1,
      borderL2: borderL2 ?? this.borderL2,
      borderL2Thin: borderL2Thin ?? this.borderL2Thin,
      borderL3: borderL3 ?? this.borderL3,
      interactiveHover: interactiveHover ?? this.interactiveHover,
      interactiveActive: interactiveActive ?? this.interactiveActive,
      dangerHover: dangerHover ?? this.dangerHover,
      errorPrimary: errorPrimary ?? this.errorPrimary,
      errorSecondary: errorSecondary ?? this.errorSecondary,
      successPrimary: successPrimary ?? this.successPrimary,
      codeBlockBg: codeBlockBg ?? this.codeBlockBg,
      codeBlockBanner: codeBlockBanner ?? this.codeBlockBanner,
      inlineCodeBg: inlineCodeBg ?? this.inlineCodeBg,
      citationHoverBg: citationHoverBg ?? this.citationHoverBg,
      citationBg: citationBg ?? this.citationBg,
      tagBg: tagBg ?? this.tagBg,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  DsColors lerp(ThemeExtension<DsColors>? other, double t) {
    if (other is! DsColors) return this;
    return t < 0.5 ? this : other;
  }
}

extension DsThemeContext on BuildContext {
  DsColors get ds => Theme.of(this).extension<DsColors>() ?? DsColors.light;
}

class DsTheme {
  static ThemeData buildLight() => _build(DsColors.light, Brightness.light);
  static ThemeData buildDark() => _build(DsColors.dark, Brightness.dark);

  static ThemeData _build(DsColors c, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bgBase,
      canvasColor: c.bgBase,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.brandPrimary,
        onPrimary: c.labelOnPrimary,
        secondary: c.brandText,
        onSecondary: c.labelOnPrimary,
        error: c.errorPrimary,
        onError: Colors.white,
        surface: c.bgLayer2,
        onSurface: c.labelPrimary,
      ),
      dividerColor: c.borderL2,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.brandText,
        selectionColor: c.brandPrimary.withValues(alpha: 0.2),
        selectionHandleColor: c.brandPrimary,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: c.interactiveHover,
      extensions: [c],
    );
  }
}

/// File type icon colors matching `FileIcon.tsx`.
class DsFileColors {
  static const Color pdf = Color(0xFFEE5138);
  static const Color spreadsheet = Color(0xFF3FB67F);
  static const Color image = Color(0xFF8B76F6);
  static const Color presentation = Color(0xFFFB8E34);
  static const Color document = Color(0xFF418CFF);
}
