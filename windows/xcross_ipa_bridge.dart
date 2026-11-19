// SPDX-License-Identifier: AGPL-3.0-only
// Adapter to the pinned XCross 2.1.2 signing engine (AGPL-3.0).
// No credentials are exported or copied by this adapter.
import 'dart:io';
import 'dart:ffi';

import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:xcross/src/composition/native_runtime.dart';
import 'package:xcross/src/target/iphone/device/device_backend.dart';

Future<void> main(List<String> args) async {
  var code = 0;
  try {
    if (args.length != 3) {
      throw ArgumentError('Expected app directory, UDID and bundle identifier');
    }
    // The installed XCross already ships the ABI bridge used by saved ADI
    // sessions. Load its DLL for Dart's @Native process-symbol fallback.
    final local = Platform.environment['LOCALAPPDATA'];
    if (Platform.isWindows && local != null) {
      final bridge = File('$local/xcross/lib/sysv_abi_bridge.dll');
      if (bridge.existsSync()) DynamicLibrary.open(bridge.path);
    }
    final application = await createNativeXcrossContext().load();
    final runtime = application.runtime;
    final backend = await DeviceBackend.resolve(
      application.pymd,
      hostServices: runtime.appleHostServices,
      createNativeLibraryLoader: runtime.createNativeLibraryLoader,
      httpClients: runtime.signingHttpClients,
    );
    final device = await backend.resolveDevice(
      mode: DeviceSearchMode.usb,
      selector: args[1],
    );
    final installedId = await backend.install(
      args[0],
      device: device,
      bundleId: args[2],
    );
    stdout.writeln('Installed: $installedId');
  } on Object catch (error) {
    // The UI retains the log. Do not print raw stacks or credentials.
    stderr.writeln('XCross signing/install failed: $error');
    code = 1;
  }
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
