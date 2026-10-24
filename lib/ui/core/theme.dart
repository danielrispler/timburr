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
const _onSurfaceVariant = Color(0xFFC4C7C5);

const _pill = WidgetStatePropertyAll(StadiumBorder());
const _bigButton = WidgetStatePropertyAll(Size(64, 52));
const _buttonText = WidgetStatePropertyAll(TextStyle(fontSize: 16, fontWeight: FontWeight.w500));
const _buttons = ButtonStyle(shape: _pill, minimumSize: _bigButton, textStyle: _buttonText);

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: _primary, brightness: Brightness.dark).copyWith(
      surface: _bg,
      surfaceContainerLowest: _bg,
      surfaceContainerLow: _surface,
      surfaceContainer: _surface,
      surfaceContainerHigh: _surfaceHigh,
      surfaceContainerHighest: _surfaceHigh,
      onSurfaceVariant: _onSurfaceVariant,
      primary: _primary,
      onPrimary: _onPrimary,
      primaryContainer: _iconTile,
      onPrimaryContainer: _onIconTile,
      secondaryContainer: _tonal,
      onSecondaryContainer: _onTonal,
      outlineVariant: const Color(0xFF444746),
      error: const Color(0xFFF2B8B5),
      errorContainer: const Color(0xFFB3261E));
  final input = OutlineInputBorder(borderRadius: BorderRadius.circular(8));
  // Sizes only: colors come from the scheme so disabled and error states still apply.
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'GoogleSans',
    scaffoldBackgroundColor: _bg,
    appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        titleTextStyle: TextStyle(fontFamily: 'GoogleSans', fontSize: 28)),
    cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        titleTextStyle: TextStyle(fontFamily: 'GoogleSans', fontSize: 18),
        subtitleTextStyle: TextStyle(fontFamily: 'GoogleSans', fontSize: 15)),
    filledButtonTheme: const FilledButtonThemeData(style: _buttons),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: _buttons),
    textButtonTheme: const TextButtonThemeData(style: ButtonStyle(shape: _pill, textStyle: _buttonText)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _tonal,
        foregroundColor: _onTonal,
        elevation: 0,
        shape: StadiumBorder(),
        extendedTextStyle: TextStyle(fontFamily: 'GoogleSans', fontSize: 16, fontWeight: FontWeight.w500)),
    inputDecorationTheme: InputDecorationTheme(
        border: input,
        enabledBorder: input.copyWith(borderSide: const BorderSide(color: Color(0xFF8E918F))),
        focusedBorder: input.copyWith(borderSide: const BorderSide(color: _primary, width: 2))),
    searchBarTheme: const SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(_surfaceHigh), elevation: WidgetStatePropertyAll(0)),
    chipTheme: ChipThemeData(
        backgroundColor: _bg,
        selectedColor: _tonal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: const TextStyle(fontFamily: 'GoogleSans', fontSize: 15)),
    dialogTheme: DialogThemeData(
        backgroundColor: _surfaceHigh, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: _surface, showDragHandle: true),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: _surface, indicatorColor: _tonal, elevation: 0),
    segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? _tonal : null),
            foregroundColor:
                WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? _onTonal : null))),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
  );
}

/// One item of a Google Health style grouped list: 2px gaps, big outer corners, small inner ones.
/// Lazy lists call this per item; TileGroup wraps a short fixed list.
Widget groupedTile(int i, int n, Widget child) {
  const big = Radius.circular(28), small = Radius.circular(4);
  return Padding(
    padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
    child: Material(
      color: _surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.vertical(top: i == 0 ? big : small, bottom: i == n - 1 ? big : small),
      child: child,
    ),
  );
}

class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) SectionTitle(title!),
          for (var i = 0; i < children.length; i++) groupedTile(i, children.length, children[i]),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
      );
}

/// Light-blue rounded square holding an icon, used as a list tile's leading.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: _iconTile, borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: _onIconTile, size: 28),
      );
}

/// Full-width pill buttons pinned at the bottom of a screen, as in Google Health. Use as bottomNavigationBar.
class BottomAction extends StatelessWidget {
  const BottomAction({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, c) in children.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: c),
          ]),
        ),
      );
}

/// Icon for an exercise's IconTile, by its primary muscle. Names are the catalog's (assets/exercises.json);
/// an unknown name falls back to the generic icon.
IconData muscleIcon(String? muscle) => switch (muscle) {
      'abdominals' || 'lower back' => Icons.self_improvement,
      'quadriceps' || 'hamstrings' || 'glutes' || 'calves' || 'abductors' || 'adductors' => Icons.directions_walk,
      'chest' || 'shoulders' || 'triceps' => Icons.fitness_center,
      'lats' || 'middle back' || 'traps' || 'biceps' || 'forearms' => Icons.sports_gymnastics,
      'neck' => Icons.accessibility_new,
      _ => Icons.sports_martial_arts,
    };
