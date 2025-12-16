# Quick Fix: Android Emulator Can't Connect to Backend

## Problem
- Backend works from browser (localhost:4000) ✅
- Flutter app times out connecting from Android emulator ❌
- Connection timeout: `10.0.2.2:4000`

## Solution 1: Allow Port 4000 in Windows Firewall (FASTEST)

Run this in PowerShell as Administrator:

```powershell
New-NetFirewallRule -DisplayName "Node.js Backend Port 4000" -Direction Inbound -LocalPort 4000 -Protocol TCP -Action Allow
```

Or manually:
1. Open Windows Defender Firewall
2. Advanced Settings → Inbound Rules → New Rule
3. Port → TCP → Specific local ports: 4000
4. Allow the connection
5. Apply to all profiles

## Solution 2: Use Your Machine's IP Instead

Your machine IP is: `10.0.0.127`

Update `lib/core/api_client.dart`:
```dart
static const String baseUrl = 'http://10.0.0.127:4000/api';
```

Update `lib/services/AgentService.dart`:
```dart
static String get baseUrl {
  if (Platform.isAndroid) {
    return "http://10.0.0.127:4000";  // Your actual IP
  }
  // ... rest stays same
}
```

## Solution 3: Test Connectivity First

Add this test in your Flutter app to verify:
```dart
try {
  final response = await http.get(Uri.parse('http://10.0.2.2:4000/api/test'));
  print('✅ Connected: ${response.body}');
} catch (e) {
  print('❌ Connection failed: $e');
}
```

## Most Likely Fix
**Windows Firewall is blocking port 4000** - Run Solution 1 first!

