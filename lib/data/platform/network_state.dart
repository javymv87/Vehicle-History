import 'package:flutter/services.dart';

/// What kind of network the phone is on, as far as the backup cares.
enum NetworkKind {
  /// No network with internet access.
  none,

  /// A network whose traffic the system counts: mobile data or a phone's
  /// hotspot.
  metered,

  /// Wi-Fi or another network the system does not count.
  unmetered,
}

/// The network check of `MainActivity.kt` (channel
/// `vehicle_history/network`), Android only.
///
/// Injected so tests replace it with a fake.
abstract interface class NetworkState {
  /// The active network right now.
  Future<NetworkKind> current();
}

/// [NetworkState] on the method channel implemented in `MainActivity.kt`.
class MethodChannelNetworkState implements NetworkState {
  /// Creates the wrapper. Stateless.
  const MethodChannelNetworkState();

  /// The channel; its name must match `MainActivity.kt`.
  static const MethodChannel _channel = MethodChannel(
    'vehicle_history/network',
  );

  @override
  Future<NetworkKind> current() async {
    try {
      final code = await _channel.invokeMethod<String>('networkState');
      return switch (code) {
        'unmetered' => NetworkKind.unmetered,
        'metered' => NetworkKind.metered,
        _ => NetworkKind.none,
      };
    } on MissingPluginException {
      // Not on Android: assume a network the user does not pay for, and let
      // the request itself fail if there is none.
      return NetworkKind.unmetered;
    }
  }
}
