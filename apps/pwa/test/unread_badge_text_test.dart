import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/homepage/widgets/unread_badge_text.dart';

void main() {
  test('shows the real count up to 99', () {
    expect(unreadBadgeText(1), '1');
    expect(unreadBadgeText(42), '42');
    expect(unreadBadgeText(99), '99');
  });

  test('caps larger counts at 99+', () {
    expect(unreadBadgeText(100), '99+');
    expect(unreadBadgeText(1451), '99+');
  });
}
