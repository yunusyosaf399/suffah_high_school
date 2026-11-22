# Attendance Reports & Analytics — Suffah High School

The **Attendance** module has two tabs:

- **Daily Register**: select a class/date, record Present, Absent, Late or Leave and save only changed marks.
- **Reports & Analytics**: summary KPI widgets, circular attendance status breakdown, seven-day bar chart and dated report rows.

The selected class/date from **Daily Register** determines the report and its seven-day range. Changing class or date updates the reporting context. Saving new attendance and reloading the register refreshes the report. A dedicated Refresh action reads saved marks again.

## Report calculations

- **Students**: currently active students in the selected class roster.
- **Marked on date**: Present + Absent + Late + Leave for the selected date.
- **Present + late**: students physically attending, with late shown separately in the status chart.
- **Absent on date**: explicitly marked Absent only.
- **7-day attendance %**: `(Present + Late) / (Present + Late + Absent + Leave)`, aggregated across seven calendar days; **unmarked students are excluded** instead of incorrectly counting them as absent.
- **Days recorded**: days with at least one saved mark.

The ring chart shows Present, Absent, Late, Leave and Unmarked. The seven-day bar chart has **—** for days without any marks rather than displaying false zero-attendance values. Daily rows show exact counts and completion.

Data is queried only from the selected class's existing `attendance_days/{classId}_YYYYMMDD/marks` records. No external analytics service or paid Firebase product is needed. Reports perform **seven class/day reads** per refresh, so large classes consume Firestore document reads; they do not require new database writes.

## Permissions and privacy

Owner/principal use their regular class selector. A teacher opens **My class attendance**, where the class is fixed to their designated attendance class, so analytics never queries other classes or full private student profiles. Teacher reports reuse the privacy-safe roster and class-filtered mark reads.

These reports summarize the **current active roster** over historical marks; student transfers during the period are not historically reconstructed. For official annual reports, class transfer history and snapshotting must be implemented separately.

## Launcher icon configuration

Launcher icon generation is configured for Android and iOS using `flutter_launcher_icons`. **The approved icon image has not yet been committed to GitHub.** Add it to `assets/icon/app_icon.png` (square 1024px PNG) and commit the file. The GitHub Android APK workflow then runs `dart run flutter_launcher_icons` and embeds the regenerated icon. Without this file, the existing icon remains unchanged and a build warning is emitted.

Instructions: [assets/icon/README.md](../assets/icon/README.md).

## Checks

1. Open Daily Register, select a class and date, and save student attendance.
2. Open Reports & Analytics and check counts, ring and seven-day bars.
3. Verify no marks shows **—** (not 0% attendance).
4. Change class/date, then verify a different report context is displayed.
5. Sign in as a teacher and confirm the report is restricted to their one attendance class.
6. With valid committed icon image, rebuild and verify the actual Android home-screen icon changed.
