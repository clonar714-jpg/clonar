import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;

class EmulatorDetector {
  static bool? _isEmulator;
  
  static Future<bool> isEmulator() async {
    if (_isEmulator != null) return _isEmulator!;
    
    if (!Platform.isAndroid) {
      _isEmulator = false;
      return false;
    }
    
    try {
      final result = await Process.run('getprop', ['ro.kernel.qemu']);
      final isQemu = result.stdout.toString().trim() == '1';
      
      final buildModel = await Process.run('getprop', ['ro.product.model']);
      final model = buildModel.stdout.toString().trim().toLowerCase();
      final isEmulatorModel = model.contains('sdk') || 
                              model.contains('emulator') ||
                              model.contains('google_sdk') ||
                              model.contains('droid4x') ||
                              model.contains('genymotion') ||
                              model.contains('vbox86');
      
      final buildManufacturer = await Process.run('getprop', ['ro.product.manufacturer']);
      final manufacturer = buildManufacturer.stdout.toString().trim().toLowerCase();
      final isEmulatorManufacturer = manufacturer.contains('unknown') ||
                                     manufacturer.contains('genymotion') ||
                                     manufacturer.contains('google');
      
      final buildHardware = await Process.run('getprop', ['ro.hardware']);
      final hardware = buildHardware.stdout.toString().trim().toLowerCase();
      final isEmulatorHardware = hardware.contains('goldfish') ||
                                 hardware.contains('ranchu') ||
                                 hardware.contains('vbox86');
      
      _isEmulator = isQemu || isEmulatorModel || isEmulatorManufacturer || isEmulatorHardware;
      return _isEmulator!;
    } catch (e) {
      if (kDebugMode) {
        
      }
      _isEmulator = false;
      return false;
    }
  }
  
  static bool get isDebugMode => kDebugMode;
  
  static bool get shouldApplyEmulatorFixes {
    return isDebugMode && _isEmulator == true;
  }
}

