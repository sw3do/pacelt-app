# Pacelt - Step Counter App

A beautiful and elegant step counter application built with Flutter that tracks your daily steps with a modern design.

## Features

- 📱 **Real-time Step Tracking**: Monitor your steps throughout the day
- 🎯 **Daily Goals**: Set and track your daily step goals
- 📊 **Progress Tracking**: View your walking progress with beautiful charts
- 🔔 **Background Monitoring**: Continues tracking steps even when the app is closed
- 💾 **Data Persistence**: Your step data is saved locally on your device
- 🎨 **Modern UI**: Clean and intuitive user interface
- 🌍 **Multi-Language Support**: Full localization with English and Turkish language options
- 🔄 **Language Switcher**: Easy language switching with flag indicators and instant UI updates

## Screenshots

![Pacelt App](images/app.png)

## Installation

### Prerequisites

Before you begin, ensure you have the following installed:

- [Flutter](https://flutter.dev/docs/get-started/install) (version 3.8.1 or higher)
- [Dart](https://dart.dev/get-dart) (comes with Flutter)
- [Android Studio](https://developer.android.com/studio) or [Xcode](https://developer.apple.com/xcode/) for device testing

### Getting Started

1. **Clone the repository**
   ```bash
   git clone https://github.com/sw3do/pacelt-app.git
   cd pacelt
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the application**
   ```bash
   flutter run
   ```

### Platform-specific Setup

#### Android Setup
- Minimum SDK version: 21
- Target SDK version: 34
- Permissions required: Activity Recognition, Boot Completed

#### iOS Setup
- Minimum iOS version: 12.0
- Permissions required: Motion & Fitness access

## Dependencies

This project uses the following key packages:

- **pedometer** (^4.0.2): For step counting functionality
- **permission_handler** (^12.0.0+1): Managing device permissions
- **shared_preferences** (^2.2.2): Local data storage
- **workmanager** (^0.6.0): Background task management
- **easy_localization** (^3.0.7): Multi-language support
- **cupertino_icons** (^1.0.8): iOS-style icons

## Building for Production

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle
```bash
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

## Permissions

The app requires the following permissions:

### Android
- `android.permission.ACTIVITY_RECOGNITION`
- `android.permission.RECEIVE_BOOT_COMPLETED`
- `android.permission.WAKE_LOCK`

### iOS
- Motion & Fitness access

## Language Support

The app supports multiple languages with complete localization:

### Supported Languages
- **English (US)** - Default language with full feature support
- **Turkish (TR)** - Complete localization including all UI elements

### Language Features
- **Instant Language Switching**: Change language on-the-fly through the language button in header
- **Automatic Detection**: System language detection on first app launch
- **Persistent Settings**: Language preference saved across app sessions
- **Complete Translation**: All UI elements, messages, and dialogs are fully localized

### How to Change Language
1. Tap the 🌍 language button in the top-right corner
2. Select your preferred language (🇺🇸 English or 🇹🇷 Turkish)
3. The app interface will immediately update to the selected language

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── screens/                  # UI screens
├── models/                   # Data models
├── services/                 # Business logic and APIs
└── widgets/                  # Reusable UI components
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

If you have any questions or need help, please:

- Open an issue on GitHub
- Contact us at sw3doo@gmail.com

## Acknowledgments

- Flutter team for the amazing framework
- Contributors to the open-source packages used in this project

---

Made with ❤️ using Flutter
