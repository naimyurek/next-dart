# counter_app demo

A server-driven counter plus a `ProductCard` composite component — all delivered
over a signed, encrypted, and versioned next-dart payload, rendered by the rfw
adapter with no code in the payload.

## Run it

### 1. (Optional) Regenerate the demo keys

The committed keys work out of the box. If you want fresh keys:

```
cd examples/counter_app/server
dart run tool/gen_keys.dart
```

Paste the printed values into **both**
`examples/counter_app/server/lib/keys.dart` and
`examples/counter_app/app/lib/keys.dart`.

> Note: the keys in `keys.dart` are for demo purposes only — see the banner
> comment in that file. Never reuse them in a real deployment.

### 2. Start the backend

```
cd examples/counter_app/server
dart pub get
dart run bin/server.dart
```

The server prints its listening URL (default: `http://127.0.0.1:8080`). The port
can be overridden at compile time: `dart run -DPORT=9000 bin/server.dart`.

### 3. Run the Flutter app

```
cd examples/counter_app/app
flutter pub get
flutter run
```

Use `-d chrome` or `-d windows` for a quick desktop/web run. For an **Android
emulator**, change the `baseUrl` in `lib/main.dart` from `http://localhost:8080`
to `http://10.0.2.2:8080` before running.

## The point

Open `examples/counter_app/server/lib/app.dart`. That file owns the entire UI:
the page layout, the `Increment` button, and the `ProductCard` composite
component. Edit anything there — reorder widgets, rename the button, change the
`ProductCard` fields — then **restart only the server**. The running Flutter app
picks up the new UI immediately with **no Flutter rebuild and no app-store
update**.

Adding a genuinely new *native* widget (e.g. a map view or a camera preview) is
the only operation that requires a client update, because the Flutter catalog
must be extended to know how to render it. Everything else is pure data.
