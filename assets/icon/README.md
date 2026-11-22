# School app launcher icon

Place the school's approved square PNG image here, with the exact filename:

`assets/icon/app_icon.png`

Use a high-resolution **1024 × 1024 px** PNG with adequate padding around the school emblem. The icon must be committed to GitHub; an image saved only on your computer or phone is unavailable to GitHub Actions.

Configured generator:

```bash
flutter pub get
dart run flutter_launcher_icons
```

The GitHub Android build automatically runs this generator whenever `assets/icon/app_icon.png` exists. Android and iOS launcher icons are generated from the same source. Until the image is present, the workflow retains the existing icon and shows a warning rather than failing the APK build.

If a different school icon image already exists elsewhere in `assets`, copy or move that **same original image** here under the specified filename. Do not use a generic replacement.
