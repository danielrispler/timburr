import 'package:flutter/material.dart';

// Google Health (Fitbit) dark palette, sampled from its screens.
const _bg = Color(0xFF131314);
const _surface = Color(0xFF1E1F22);
const _surfaceHigh = Color(0xFF2A2B2F);
const _primary = Color(0xFFA8C7FA);
const _onPrimary = Color(0xFF062E6F);
const _tonal = Color(0xFF004A77);
const _onTonal = Color(0xFFC2E7FF);
const _iconTile = Color(0xFFC2E7FF);
const _onIconTile = Color(0xFF0B57D0);

final _pill = WidgetStatePropertyAll(const StadiumBorder());
const _bigButton = WidgetStatePropertyAll(Size(64, 52));
const _buttonText = WidgetStatePropertyAll(
  TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
);

ThemeData buildDarkTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: _primary,
        brightness: Brightness.dark,
      ).copyWith(
        surface: _bg,
        surfaceContainerLowest: _bg,
        surfaceContainerLow: _surface,
        surfaceContainer: _surface,
        surfaceContainerHigh: _surfaceHigh,
        surfaceContainerHighest: _surfaceHigh,
        primary: _primary,
        onPrimary: _onPrimary,
        primaryContainer: _iconTile,
        onPrimaryContainer: _onIconTile,
        secondaryContainer: _tonal,
        onSecondaryContainer: _onTonal,
        error: const Color(0xFFF2B8B5),
        errorContainer: const Color(0xFFB3261E),
      );
  final input = OutlineInputBorder(borderRadius: BorderRadius.circular(8));
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'GoogleSans',
    scaffoldBackgroundColor: _bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: _bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: _surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      minTileHeight: 64,
      titleTextStyle: TextStyle(fontSize: 18, color: Colors.white),
      subtitleTextStyle: TextStyle(fontSize: 15, color: Color(0xFFC4C7C5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: _pill,
        minimumSize: _bigButton,
        textStyle: _buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: _pill,
        minimumSize: _bigButton,
        textStyle: _buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(shape: _pill, textStyle: _buttonText),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _tonal,
      foregroundColor: _onTonal,
      elevation: 0,
      shape: StadiumBorder(),
      extendedTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: input,
      enabledBorder: input.copyWith(
        borderSide: const BorderSide(color: Color(0xFF8E918F)),
      ),
      focusedBorder: input.copyWith(
        borderSide: const BorderSide(color: _primary, width: 2),
      ),
    ),
    searchBarTheme: const SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(_surfaceHigh),
      elevation: WidgetStatePropertyAll(0),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surface,
      showDragHandle: true,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: _surface,
      indicatorColor: _tonal,
      elevation: 0,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _tonal : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _onTonal : null,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    dividerTheme: const DividerThemeData(color: Colors.transparent, space: 16),
  );
}

/// Google Health style grouped list: 2px gaps, big outer corners, small inner ones.
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    const big = Radius.circular(28), small = Radius.circular(4);
    final n = children.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
              child: Text(
                title!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          for (var i = 0; i < n; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
              child: Material(
                color: _surface,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? big : small,
                  bottom: i == n - 1 ? big : small,
                ),
                child: children[i],
              ),
            ),
        ],
      ),
    );
  }
}

/// Light-blue rounded square holding an icon, used as a list tile's leading.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: _iconTile,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(icon, color: _onIconTile, size: 28),
  );
}

/// Icon for an exercise's IconTile, by its primary muscle (catalog muscle names).
IconData muscleIcon(String? muscle) => switch (muscle) {
  'abdominals' || 'lower back' => Icons.self_improvement,
  'quadriceps' ||
  'hamstrings' ||
  'glutes' ||
  'calves' ||
  'abductors' ||
  'adductors' => Icons.directions_run,
  'chest' || 'shoulders' || 'triceps' => Icons.sports_martial_arts,
  'lats' ||
  'middle back' ||
  'traps' ||
  'biceps' ||
  'forearms' => Icons.sports_gymnastics,
  'neck' => Icons.accessibility_new,
  _ => Icons.fitness_center,
};
