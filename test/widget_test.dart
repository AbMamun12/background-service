import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_service/core/constants/app_colors.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  test('AppColors verify constants', () {
    expect(AppColors.primary.toARGB32(), isNotNull);
    expect(AppColors.background.toARGB32(), isNotNull);
  });
}
