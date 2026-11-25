import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/speech_provider.dart';
import 'screens/home_screen.dart';
import 'theme/ds_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const DeepSeekApp());
}

class DeepSeekApp extends StatelessWidget {
  const DeepSeekApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<SettingsProvider, SpeechProvider>(
          create: (ctx) => SpeechProvider(ctx.read<SettingsProvider>()),
          update: (_, settings, prev) => prev ?? SpeechProvider(settings),
        ),
        ChangeNotifierProxyProvider<SettingsProvider, ChatProvider>(
          create: (ctx) => ChatProvider(ctx.read<SettingsProvider>()),
          update: (_, settings, prev) => prev ?? ChatProvider(settings),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (ctx, settingsProv, _) {
          final localeStr = settingsProv.settings.locale;
          final locale = localeStr.startsWith('zh')
              ? const Locale('zh', 'CN')
              : const Locale('en', 'US');

          return MaterialApp(
            title: 'DeepSeek',
            debugShowCheckedModeBanner: false,
            theme: DsTheme.buildLight(),
            darkTheme: DsTheme.buildDark(),
            themeMode: settingsProv.settings.themePreference.themeMode,
            locale: locale,
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('en', 'US'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
