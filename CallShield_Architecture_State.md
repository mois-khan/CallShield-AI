🛡️ CallShield-AI: System Architecture & Context Blueprint
Date/State: March 2026 (Phase: Native SOS Integration)

1. Project Overview
Mission: A real-time, zero-trust voice firewall that actively monitors phone calls, detects social engineering/scams, and triggers emergency interventions.

Tech Stack:

Frontend: Flutter (Android native focus).

Backend: Node.js, Express, WebSockets (ws).

AI/APIs: Google Gemini 2.5 Flash (Threat Analysis), Deepgram (Speech-to-Text), Twilio (Voice Routing).

Tunnel: Ngrok (Development).

2. Core Audio & AI Pipeline
The Stream: Twilio routes live call audio (8000Hz Mu-Law) to the Node.js server via WebSocket (/stream).

The Transcription: Node.js pipes the raw audio directly to Deepgram via WSS. Deepgram returns real-time text.

The Sliding Window Buffer: Node.js maintains a 15-line rolling array of context. It triggers an AI analysis every 35 words (or sooner if high-risk heuristics are met).

The AI Brain: Gemini receives the transcript and strictly returns a JSON schema containing: scam_probability (0-100), flagged_tactics (Array), and explanation.

The Broadcast: Node.js blasts the JSON threat payload down a secondary WebSocket (/flutter-alerts) to the user's phone.

3. Key Engineering Optimizations Achieved
Just-In-Time TLS Warmup: We eliminated Google's 14-second "Cold Start" API delay. The exact millisecond a Twilio call connects, Node.js fires a background dummy ping to Gemini. By the time the scammer speaks 35 words, the TLS tunnel is hot, dropping AI latency to ~3.5 - 4.1 seconds.

Zero-Database State Management: To keep the backend stateless and private, SOS contacts are stored in Flutter's SharedPreferences. When the app connects, it fires a register_sos WebSocket handshake, and Node.js holds the contacts in temporary session RAM.

4. The SOS Subsystem (Native Android)
The Pivot: Migrated away from Twilio SMS due to Trial/A2P/DLT carrier restrictions.

The Execution: When a CRITICAL (>85%) threat is detected, Node.js tells Flutter. Flutter uses the background_sms package and Android SEND_SMS permissions to text the emergency contact directly from the user's physical SIM card.

The Lock: hasSentSOSThisSession boolean prevents spamming the contact if the call continues.

5. Known Network Issues & Next Steps (The "To-Do" List)
We are currently upgrading the network layer to enterprise standards to fix "Phantom Connections" and "Stale State":

Watchdog Heartbeat: Implement a 5-second Ping/Pong to kill half-open TCP sockets.

Exponential Backoff: Build auto-reconnect logic so the Flutter background isolate gracefully recovers from tunnel drops.

Reactive State Sync: Push SOS setting updates to the server dynamically without requiring an app restart.

6. Future Roadmap (Whiteboarded)
Privacy Scrubber: Intercept and redact PII (SSN, credit cards) using RegEx/NLP in Node.js before sending transcripts to Gemini.

Grandma Mode (Auto-Hangup): Use Android Accessibility Services or Default Dialer APIs to forcefully drop the call if the threat hits 99%.