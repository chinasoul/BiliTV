class BuildFlags {
  const BuildFlags._();

  // Use: --dart-define=ENABLE_PLUGINS=false
  static const bool pluginsEnabled = bool.fromEnvironment(
    'ENABLE_PLUGINS',
    defaultValue: true,
  );
}
