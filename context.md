# CallShield AI - Project Context & Progress
**Last Updated:** March 2026
**Project Type:** Real-time Scam Detection & Prevention System
**Platform:** Flutter (Frontend) + Node.js (Backend)

## 📌 1. Project Overview
CallShield AI is a real-time, privacy-first mobile security application. It intercepts active phone calls, transcribes the audio in real-time using Deepgram, analyzes the conversation for social engineering/scam tactics using Google Gemini, and instantly triggers native hardware responses (Local Notifications, SOS SMS) via a Flutter Background Service.

## 🏗️ 2. Tech Stack & Architecture
* **Frontend Mobile:** Flutter (Dart)
* **Backend Server:** Node.js (Express, WebSockets)
* **Telephony Intercept:** Twilio (TwiML Media Streams)
* **Speech-to-Text (STT):** Deepgram (Nova-2 Model, Twin-channel streaming)
* **AI Engine:** Google Gemini (Gemini 3.1 Pro via prompt injection)
* **Native Hardware APIs:** `flutter_background_service`, `sms_sender_background`, `flutter_local_notifications`

## 🔄 3. Core Data Flow (The Pipeline)
1.  **Audio Capture:** Twilio routes live inbound/outbound audio over a WebSocket (`/stream`) to the Node.js backend.
2.  **Transcription:** Node.js pipes the raw audio to Deepgram via twin WebSocket streams.
3.  **Privacy Scrubbing (Zero-Knowledge):** Deepgram returns raw text. Node.js intercepts it using a RegEx Sniper to redact PII (Credit Cards, Aadhaar, SSNs, OTPs) *before* it leaves the server.
4.  **Threat Analysis:** The scrubbed text buffer is sent to Gemini. Gemini returns a JSON threat payload (Probability %, Tactics, Explanation).
5.  **Device Broadcast:** If Threat > 90%, Node.js broadcasts an `ALERT` payload over WebSocket (`/flutter-alerts`) to the Flutter app.
6.  **Background Execution:** The Flutter Isolate (running in the background) catches the alert, pops a Local Notification, and uses native Android Telephony to send a physical SMS to the user's saved SOS contact.

---

## ✅ 4. Completed Milestones (What Works)

### Backend (Node.js)
* [x] **Twilio Stream Handler:** Successfully ingests live call audio.
* [x] **Deepgram Integration:** Dual-channel (Inbound/Outbound) real-time STT.
* [x] **Gemini Analysis Engine:** 4-second latency sliding window buffer analysis.
* [x] **WebSocket Broadcast Server:** Manages active Flutter clients, handles pings/pongs, and syncs SOS state.
* [x] **Zero-Knowledge Scrubber:** RegEx middleware successfully intercepts and redacts sensitive data (e.g., `[OTP_OR_PIN_REDACTED]`) before AI analysis.

### Frontend (Flutter)
* [x] **Background Service:** App runs a headless Isolate that survives app minimization and screen locks.
* [x] **Resilient Networking:** WebSocket engine with exponential backoff and phantom-connection detection.
* [x] **UI-Isolate Bridge:** Bi-directional communication. UI updates dynamically on connection loss; UI pushes instant SOS updates to the Isolate.
* [x] **Native SOS SMS:** Bypassed Android 14 Broadcast Receiver limits using modern `sms_sender_background` package. Texts send securely without UI prompts.
* [x] **Anti-Spam Lock:** Stateful boolean prevents the app from firing 50 text messages for the same scam call.
* [x] **The "Answering Machine":** If a threat hits while the app is asleep, the Isolate saves the alert to `SharedPreferences`. The `WidgetsBindingObserver` catches it on wake-up and guarantees the Red Scam Banner is displayed.
* [x] **Success/Failure UX:** Emerald green notification confirms SOS delivery; Red notification warns if SMS fails.

---

## 🛠️ 5. Key Engineering Solutions (Do Not Revert)
* **The SMS Silent Crash:** Older packages like `telephony` crash silently on Android 14+ due to `RECEIVER_EXPORTED` broadcast rules. We *must* use `sms_sender_background` to bypass this and handle Dual-SIM Indian networks correctly.
* **The Isolate Barrier:** `SharedPreferences` in the background isolate do not instantly sync with the UI. We use `FlutterBackgroundService().invoke('force_sos_sync')` to manually bridge memory gaps.
* **Emoji/Length Limits:** SMS strings are strictly under 160 characters and contain NO emojis to prevent the modem from switching to UCS-2 encoding (which limits texts to 70 chars and causes silent failures).
* **Flutter Lifecycle Trap:** Background isolates cannot draw UI. Alerts are routed through Local Notifications, and UI rendering is deferred to `didChangeAppLifecycleState` using local storage.

---

## 🚀 6. Roadmap / Pending Features

### Priority 1: "Grandma Mode" (Auto-Hangup)
* **Goal:** Use native Android Telecom APIs (or MethodChannels) to forcefully terminate the active cellular call if the Gemini Threat Level hits 99%.
* **Challenge:** Android aggressively restricts call-termination APIs to default dialer apps. Will require investigating `TelecomManager` or Accessibility Services to execute the hang-up.

### Priority 2: Backend Prompt Hardening
* **Goal:** Further refine the Gemini prompt to reduce false positives in highly-stressful but legitimate calls (e.g., arguing with a real bank teller).

### Priority 3: iOS Porting
* **Goal:** Replicate the Android Background Service configuration in `AppDelegate.swift` for Apple ecosystem compatibility.