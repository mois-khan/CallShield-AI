/// Message Shield — the second protection section of CallShield.
///
/// This library is intentionally isolated from the existing Call Shield code:
/// nothing here touches call detection, WebSockets, Deepgram/Gemini integration,
/// alerts, Grandma Mode or the forensic report pipeline. Message Shield is a
/// self-contained module that only *reads* the app's theme conventions and is
/// reached from a single additive navigation entry point in `main.dart`.
library;

export 'models/analysis_result.dart';
export 'models/message_input.dart';
export 'models/scam_category.dart';
export 'models/shield_signal.dart';
export 'engine/message_shield_engine.dart';
