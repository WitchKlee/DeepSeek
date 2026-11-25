import '../../data/location_data.dart';
import '../../models/settings_models.dart';

const _weekdaysZh = [
  '星期一',
  '星期二',
  '星期三',
  '星期四',
  '星期五',
  '星期六',
  '星期日',
];

const _weekdaysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Builds the exact 5-tuple `latest_reminder` string expected by DeepSeek's API:
/// `YYYY-MM-DD,Weekday,LocationName,Web,中文|English`
String buildLatestReminder({
  required DateTime now,
  required String locale,
  required UserLocation? location,
}) {
  final isZh = locale.startsWith('zh');
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final dateStr = '$y-$m-$d';

  final weekdayIdx = (now.weekday - 1).clamp(0, 6);
  final weekdayStr = isZh ? _weekdaysZh[weekdayIdx] : _weekdaysEn[weekdayIdx];

  String locationName = '';
  if (location != null) {
    if (location.region == 'CN' && isZh) {
      if (location.city != null && kCityNames.containsKey(location.city)) {
        locationName = kCityNames[location.city]!;
      } else if (location.province != null &&
          kProvinceNames.containsKey(location.province)) {
        locationName = kProvinceNames[location.province]!;
      } else {
        locationName = getRegionDisplayName('CN', locale);
      }
    } else {
      locationName = getRegionDisplayName(location.region, locale);
    }
  }

  final langStr = isZh ? '中文' : 'English';
  return '$dateStr,$weekdayStr,$locationName,Web,$langStr';
}
