import 'package:aipin/core/design_system/evt_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class EvtTheme {
  static const componentRadius = Radius.circular(8);
  static const motionDuration = Duration(milliseconds: 180);

  static SystemUiOverlayStyle systemUiOverlayStyle(ThemeData theme) {
    final background = theme.scaffoldBackgroundColor;
    final isLight = theme.brightness == Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: background,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: background,
      systemNavigationBarIconBrightness: isLight
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData light() => _build(
    brightness: Brightness.light,
    canvas: EvtLightColors.canvas,
    surface: EvtLightColors.surface,
    subtle: EvtLightColors.subtle,
    primaryText: EvtLightColors.primaryText,
    secondaryText: EvtLightColors.secondaryText,
    action: EvtLightColors.action,
    border: EvtLightColors.border,
    positive: EvtLightColors.positive,
    danger: EvtLightColors.danger,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    canvas: EvtDarkColors.canvas,
    surface: EvtDarkColors.surface,
    subtle: EvtDarkColors.subtle,
    primaryText: EvtDarkColors.primaryText,
    secondaryText: EvtDarkColors.secondaryText,
    action: EvtDarkColors.action,
    border: EvtDarkColors.border,
    positive: EvtDarkColors.positive,
    danger: EvtDarkColors.danger,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color canvas,
    required Color surface,
    required Color subtle,
    required Color primaryText,
    required Color secondaryText,
    required Color action,
    required Color border,
    required Color positive,
    required Color danger,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: action,
      onPrimary: brightness == Brightness.light
          ? EvtLightColors.surface
          : EvtDarkColors.canvas,
      secondary: secondaryText,
      onSecondary: canvas,
      error: danger,
      onError: brightness == Brightness.light
          ? EvtLightColors.surface
          : EvtDarkColors.canvas,
      surface: surface,
      onSurface: primaryText,
    );
    final textTheme = Typography.material2021().black
        .apply(bodyColor: primaryText, displayColor: primaryText)
        .copyWith(
          bodyMedium: TextStyle(
            color: primaryText,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
    final shape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(componentRadius),
    );
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      animationDuration: motionDuration,
      shape: WidgetStatePropertyAll(shape),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      dividerColor: border,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle.copyWith(
          side: WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface, shape: shape),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: componentRadius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: canvas,
        indicatorColor: subtle,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? primaryText
                : secondaryText,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primaryText
                : secondaryText,
          ),
        ),
      ),
      extensions: [
        EvtStatusColors(positive: positive, danger: danger, subtle: subtle),
      ],
    );
  }
}

class EvtStatusColors extends ThemeExtension<EvtStatusColors> {
  const EvtStatusColors({
    required this.positive,
    required this.danger,
    required this.subtle,
  });

  final Color positive;
  final Color danger;
  final Color subtle;

  @override
  EvtStatusColors copyWith({Color? positive, Color? danger, Color? subtle}) {
    return EvtStatusColors(
      positive: positive ?? this.positive,
      danger: danger ?? this.danger,
      subtle: subtle ?? this.subtle,
    );
  }

  @override
  EvtStatusColors lerp(EvtStatusColors? other, double t) {
    if (other == null) {
      return this;
    }
    return EvtStatusColors(
      positive: Color.lerp(positive, other.positive, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
    );
  }
}
