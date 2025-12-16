# Android Device Connectivity Troubleshooting

## ✅ What Was Fixed
1. AndroidManifest.xml - Added cleartext traffic permission
2. network_security_config.xml - Created to allow HTTP to 10.0.0.127
3. Firewall rule - Port 4000 allowed in Windows Firewall

## ⚠️ IMPORTANT: Full Rebuild Required

**Android manifest changes require a FULL REBUILD, not hot reload!**

Run these commands:
```bash
flutter clean
flutter pub get
flutter run
```

Or rebuild in your IDE (stop app completely, then run again).

## 🔍 Step-by-Step Diagnosis

### Step 1: Test from Phone Browser
On your Android device, open Chrome/Safari and go to:
```
http://10.0.0.127:4000/api/test
```

**Expected:** You should see:
```json
{"success":true,"message":"Backend is reachable!",...}
```

**If this works:** The network is fine, issue is in Flutter app
**If this fails:** Network/firewall issue

### Step 2: Verify Same WiFi Network
- Phone WiFi: Check Settings → WiFi → Connected network name
- Computer WiFi: Check network name in Windows
- **They must match!**

### Step 3: Check Backend Logs
When you submit query, backend should show:
```
📥 [timestamp] ========== NEW REQUEST ==========
```

**If you don't see this:** Request isn't reaching backend

### Step 4: Verify IP Address
Run on your computer:
```cmd
ipconfig
```

Look for "IPv4 Address" under your WiFi adapter (not Ethernet).
It should be `10.0.0.127` or something like `192.168.x.x` or `10.0.0.x`.

If it's different, update:
- `lib/services/AgentService.dart` line 38
- `lib/core/api_client.dart` line 10
- `android/app/src/main/res/xml/network_security_config.xml` line 5

### Step 5: Check Flutter Logs
Look for these in Flutter console:
- `🚀 Sending POST request to: http://10.0.0.127:4000/api/agent`
- `📡 Network check: Platform=android, BaseURL=http://10.0.0.127:4000`
- `⚠️ Connection error:` (if connection fails)
- `⏱️ Request timeout` (if timeout)

## 🐛 Common Issues

### Issue 1: "Connection timed out"
**Cause:** Device can't reach backend IP
**Fix:**
1. Verify same WiFi network
2. Test http://10.0.0.127:4000/api/test in phone browser
3. Check Windows Firewall isn't blocking

### Issue 2: "Cleartext HTTP traffic not permitted"
**Cause:** Android security config not applied
**Fix:**
1. Do FULL rebuild (flutter clean + flutter run)
2. Verify network_security_config.xml exists
3. Check AndroidManifest.xml has both attributes

### Issue 3: Backend logs show nothing
**Cause:** Request never reaches backend
**Fix:**
1. Check firewall rule is active
2. Verify backend is listening on 0.0.0.0:4000 (not just localhost)
3. Test from phone browser first

## ✅ Quick Test Script

Add this temporarily to test connectivity:

```dart
// Test connectivity
try {
  final testResponse = await http.get(Uri.parse('http://10.0.0.127:4000/api/test'));
  print('✅ Test successful: ${testResponse.body}');
} catch (e) {
  print('❌ Test failed: $e');
}
```

Run this first before trying the agent query.

