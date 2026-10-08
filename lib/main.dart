import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/constants/app_colors.dart';
import 'core/services/background_service.dart';
import 'core/services/notification_service.dart';
import 'features/home/views/home_view.dart';
import 'features/standing/views/standing_overlay_view.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void navigateToStandingOverlay() {
  if (StandingOverlayView.isStandingOverlayActive) return;

  void pushScreen() {
    if (StandingOverlayView.isStandingOverlayActive) return;
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const StandingOverlayView(),
        fullscreenDialog: true,
      ),
    );
  }

  if (rootNavigatorKey.currentState != null) {
    pushScreen();
  } else {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushScreen();
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set status bar styles
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Set notification click callback before initialize
  NotificationService.onNotificationClick = (String? payload) {
    debugPrint('[Main] Notification tapped payload: $payload -> opening StandingOverlayView');
    navigateToStandingOverlay();
  };

  // Initialize notification service
  await NotificationService.instance.initialize();

  // Initialize background service configuration
  await AppBackgroundService.initialize();

  runApp(const DeskfitBackgroundApp());
}

class DeskfitBackgroundApp extends StatefulWidget {
  const DeskfitBackgroundApp({super.key});

  @override
  State<DeskfitBackgroundApp> createState() => _DeskfitBackgroundAppState();
}

class _DeskfitBackgroundAppState extends State<DeskfitBackgroundApp> {
  @override
  void initState() {
    super.initState();
    // Check if app was launched via notification click (Cold start)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final launchDetails =
            await NotificationService.instance.getNotificationAppLaunchDetails();
        if (launchDetails?.didNotificationLaunchApp ?? false) {
          debugPrint('[Main] App launched via notification click. Navigating to StandingOverlayView...');
          navigateToStandingOverlay();
        }
      } catch (e) {
        debugPrint('[Main] Error checking notification launch details: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeskFit Standing Schedule',
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
