import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/constants/app_colors.dart';
import 'core/services/background_service.dart';
import 'core/services/notification_service.dart';
import 'features/home/views/home_view.dart';
import 'features/standing/views/standing_overlay_view.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set status bar styles
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize notification service
  await NotificationService.instance.initialize();

  // Setup notification tap handler to open StandingOverlayView
  NotificationService.onNotificationClick = (String? payload) {
    debugPrint('[Main] Routing to StandingOverlayView via notification payload: $payload');
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const StandingOverlayView(),
        fullscreenDialog: true,
      ),
    );
  };

  // Initialize background service configuration
  await AppBackgroundService.initialize();

  runApp(const DeskfitBackgroundApp());
}

class DeskfitBackgroundApp extends StatelessWidget {
  const DeskfitBackgroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeskFit Background Service',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const HomeView(),
    );
  }
}
