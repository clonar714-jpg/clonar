# Perplexity-Style Streaming UI Architecture Fix

## 1. How Perplexity Models Its UI State Machine

Perplexity uses an **explicit phase-based state machine** with three distinct phases:

```
┌─────────────┐
│  SEARCHING  │  ← Transient "Working..." UI shown
└──────┬──────┘
       │ (first token arrives)
       ▼
┌─────────────┐
│  ANSWERING  │  ← Answer widget mounted ONCE, text streams internally
└──────┬──────┘
       │ (END event arrives)
       ▼
┌─────────────┐
│    DONE     │  ← Sources/images/follow-ups attached, no more streaming
└─────────────┘
```

**Key Principles:**
- **Phase transitions are ONE-TIME events** (searching → answering happens exactly once)
- **Working UI disappears permanently** when phase transitions to `answering`
- **Answer widget is mounted once** and never unmounted during streaming
- **Text updates are internal** to the text widget (no parent rebuilds)
- **Attachments (sources/images) only appear** after phase transitions to `done`

## 2. Architectural Mistakes in Current Flutter + Riverpod Setup

### Mistake #1: No Explicit Phase Enum
- Current code uses boolean flags (`isStreaming`, `hasReceivedFirstChunk`)
- These create ambiguous state combinations
- No clear "point of no return" for UI transitions

### Mistake #2: Widget Rebuilds on Every Text Chunk
- `PerplexityAnswerWidget` watches `sessionHistoryProvider` directly
- Every `updateSessionById()` call creates a new `QuerySession` object
- Riverpod emits new state → widget rebuilds → `build()` reads `widget.session.answer`
- Even though `StreamingTextWidget` has internal state, the parent rebuilds unnecessarily

### Mistake #3: Reading Text Directly in build()
```dart
// ❌ BAD: This causes rebuilds on every text update
final answerText = widget.session.answer ?? widget.session.summary ?? "";
```
- Every time `session.answer` changes, the entire widget tree rebuilds
- `StreamingTextWidget` receives a new `targetText` prop, triggering `didUpdateWidget()`

### Mistake #4: Mixed Concerns
- Loading UI and answer UI are conditionally rendered in the same widget
- No clear separation between "working" phase and "answering" phase

## 3. Correct State Model with Explicit Phase Enum

```dart
enum QueryPhase {
  searching,  // Initial state: show "Working..." UI
  answering,  // First token arrived: mount answer widget, hide working UI
  done,       // END event arrived: show sources/images/follow-ups
}
```

**State Flow:**
```
QuerySession.phase = searching
  ↓ (first message/updateBlock event with non-empty text)
QuerySession.phase = answering
  ↓ (END event)
QuerySession.phase = done
```

**Rules:**
- Phase can only advance forward (never goes backwards)
- `searching → answering` transition happens exactly once (on first token)
- `answering → done` transition happens exactly once (on END event)

## 4. One-Time Transition on First Token

**Implementation:**
```dart
// In agent_provider.dart, when handling message/updateBlock events:

if (currentSession.phase == QueryPhase.searching && chunk.isNotEmpty) {
  // ✅ ONE-TIME TRANSITION: searching → answering
  final transitionedSession = currentSession.copyWith(
    phase: QueryPhase.answering,  // ← Phase transition
    summary: accumulatedText,
    answer: accumulatedText,
    hasReceivedFirstChunk: true,
    isStreaming: true,
  );
  ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, transitionedSession);
}
```

**Widget Logic:**
```dart
// In PerplexityAnswerWidget.build():

// ✅ Show working UI ONLY during searching phase
if (widget.session.phase == QueryPhase.searching) {
  return _buildLoadingStatus();
}

// ✅ Answer widget is mounted once when phase = answering
// It stays mounted and never rebuilds during streaming
if (widget.session.phase == QueryPhase.answering || widget.session.phase == QueryPhase.done) {
  return _buildAnswerContent();
}
```

## 5. Streaming Text Without Widget Rebuilds

**Solution: Use Riverpod `select` to Watch Only Phase Changes**

```dart
// In PerplexityAnswerScreen.build():

// ❌ BAD: Watches entire session (rebuilds on every text update)
final sessions = ref.watch(sessionHistoryProvider);

// ✅ GOOD: Only watch phase changes
final sessions = ref.watch(
  sessionHistoryProvider.select((sessions) => 
    sessions.map((s) => s.phase).toList()
  )
);
```

**Better: Use a Separate Provider for Phase-Only Updates**

```dart
// Create a phase-only provider
final sessionPhaseProvider = Provider.family<QueryPhase, String>((ref, sessionId) {
  final sessions = ref.watch(sessionHistoryProvider);
  final session = sessions.firstWhere((s) => s.sessionId == sessionId);
  return session.phase;
});

// In widget:
final phase = ref.watch(sessionPhaseProvider(sessionId));
if (phase == QueryPhase.searching) {
  return _buildLoadingStatus();
}
```

**StreamingTextWidget Already Handles Internal Updates:**
- `StreamingTextWidget` maintains internal `_displayedText` state
- When `targetText` prop changes, it updates internally via `didUpdateWidget()`
- Parent widget should NOT rebuild just because text changed

## 6. Layer Ownership

### Phase Changes
**Owner:** `agent_provider.dart` (AgentController)
- Detects first token arrival → transitions `searching → answering`
- Detects END event → transitions `answering → done`
- Updates session via `updateSessionById()`

### Streaming Buffer
**Owner:** `StreamingTextWidget` (internal state)
- Maintains `_displayedText` internally
- Updates via `didUpdateWidget()` when `targetText` prop changes
- Parent widget should use `select` to avoid rebuilds

### Final Attachments (Sources/Images)
**Owner:** `agent_provider.dart` (END event handler)
- END event sets `sections`, `sources`, `cardsByDomain`, `images`
- Sets `phase = done` and `isFinalized = true`
- Widget reads these fields but only after phase = done

## 7. Minimal Changes Required

### Change 1: Add Phase Enum to QuerySession
```dart
// In query_session_model.dart
enum QueryPhase { searching, answering, done }

class QuerySession {
  final QueryPhase phase;  // ← Add this
  // ... rest of fields
}
```

### Change 2: Update Phase in agent_provider.dart
```dart
// On first token:
if (currentSession.phase == QueryPhase.searching && chunk.isNotEmpty) {
  final updated = currentSession.copyWith(
    phase: QueryPhase.answering,  // ← Transition
    // ... other fields
  );
}

// On END event:
final completeSession = currentSession.copyWith(
  phase: QueryPhase.done,  // ← Transition
  isFinalized: true,
  // ... structured data
);
```

### Change 3: Use Phase in Widget (Not isStreaming)
```dart
// In PerplexityAnswerWidget.build():

// ❌ REMOVE: if (widget.session.isStreaming && !widget.session.hasReceivedFirstChunk)
// ✅ REPLACE WITH:
if (widget.session.phase == QueryPhase.searching) {
  return _buildLoadingStatus();
}

// Answer content only shows when phase >= answering
if (widget.session.phase == QueryPhase.answering || widget.session.phase == QueryPhase.done) {
  return _buildAnswerContent();
}
```

### Change 4: Use `select` to Prevent Rebuilds
```dart
// In PerplexityAnswerScreen.build():

// ✅ Only rebuild when phase changes, not when text changes
final sessions = ref.watch(
  sessionHistoryProvider.select((sessions) => 
    sessions.map((s) => (s.sessionId, s.phase)).toList()
  )
);
```

### Change 5: Make StreamingTextWidget More Resilient
```dart
// In StreamingTextWidget.didUpdateWidget():
// ✅ Only update if targetText actually changed (not just parent rebuild)
if (widget.targetText != oldWidget.targetText && 
    widget.targetText.length > oldWidget.targetText.length) {
  // Append new text, don't restart animation
}
```

## Summary

**Root Cause:** Widget rebuilds on every text chunk because it watches the entire session object, which changes on every `updateSessionById()` call.

**Fix:** 
1. Add explicit `QueryPhase` enum
2. Transition phase on first token (searching → answering)
3. Use `select` to watch only phase changes, not text changes
4. Let `StreamingTextWidget` handle text updates internally

**Result:** 
- Working UI disappears once (on phase transition)
- Answer widget mounts once (never rebuilds during streaming)
- Text streams smoothly without parent rebuilds
- Sources/images attach only after streaming completes

