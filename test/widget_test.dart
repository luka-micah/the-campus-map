import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:the_campus_map/features/auth/auth_binding.dart';
import 'package:the_campus_map/features/auth/views/login_view.dart';

void main() {
  testWidgets('LoginView renders correctly', (WidgetTester tester) async {
    Get.testMode = true;

    await tester.pumpWidget(
      GetMaterialApp(
        initialBinding: AuthBinding(),
        home: LoginView(),
      ),
    );

    // 'Login' appears twice by design: the AppBar title and the submit button.
    expect(find.text('Login'), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}