# Mobile app (Flutter)

The Intercity Rideshare app. Each module adds its screens under `lib/features/<name>/`.

## Run it

You need Flutter 3.22 or newer and the backend running (`cd backend && npm run dev`).

```bash
cd mobile
flutter create . --project-name rideshare_mobile --platforms android,ios   # first time only: adds android/ and ios/
flutter pub get
flutter analyze
flutter test
flutter run
```

Tap *Create an account* on the sign-in screen. With `SMS_PROVIDER=console`, the backend prints the
registration and password reset codes in its terminal.

**API address** (in *Developer settings* on the sign-in screen):

| Running on | Use |
| --- | --- |
| Android emulator | `http://10.0.2.2:4000/api/v1` |
| iOS simulator | `http://localhost:4000/api/v1` |
| Real phone | `http://<your computer's Wi-Fi IP>:4000/api/v1` |

Android blocks plain `http` by default. For local testing only, add
`android:usesCleartextTraffic="true"` to `<application>` in `android/app/src/main/AndroidManifest.xml`.

## Layout

```
lib/
  main.dart                 sign-in + home with bottom tabs
  core/                     ApiClient (token refresh), AuthService, AppServices, formatters, widgets
  features/auth/            Member 1
    auth.dart               the only file other features import
    widgets/
    screens/                sign in, register, verify phone, forgot and reset password
  features/trips/           Member 4
    trips.dart              the only file other features import
    models/  data/  widgets/
    screens/driver/         my trips, create (4 steps), detail, edit, active trip, saved routes
    screens/passenger/      search, results, ride detail
    screens/shared/         stop picker
  features/driver/          Member 2
    driver.dart             the only file other features import
    models/  data/  widgets/
    screens/                driver home, register, documents, verification, profile, earnings, trip history
  features/vehicle/         Member 3
    vehicle.dart            the only file other features import
    vehicle_routes.dart     named routes under /vehicles, used by MaterialApp.onGenerateRoute
    data/  widgets/
    screens/                my vehicles, add/edit, documents, verification
test/                       unit and widget tests
```

## Run it in a browser

For a demo without an emulator. Port 3000 is already allowed by the backend's `CORS_ORIGINS`.

```bash
flutter create . --project-name rideshare_mobile --platforms web   # first time only: adds web/
flutter run -d chrome --web-port 3000
```

## For other members

- Get services anywhere below the app with `AppServices.of(context)`. It holds the trip
  repository, the driver's vehicle and the booking hook.
- **Booking / Auction:** set `onBookSegment` in `main.dart`. It receives a `SegmentSelection`
  (trip, pickup and drop stop, seats, price) when a passenger taps *Book* or *Place a bid*.
- **Vehicles:** `main.dart` loads the driver's first approved, active vehicle and sets
  `driverVehicleId` and `vehicleSeatCapacity`. Without one, a driver cannot create a trip.
- **Auth (Member 1):** tokens are only kept in memory, so closing the app signs the user out. The
  next step is to keep the refresh token in secure storage.
