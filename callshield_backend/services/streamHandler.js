require('dotenv').config(); 
const WebSocket = require('ws');
const { getMonitoringState, setMonitoringState } = require('../state');

const { GoogleGenerativeAI, SchemaType } = require("@google/generative-ai");

// ==========================================
// 🛡️ THE PRIVACY SCRUBBER (ZERO-KNOWLEDGE)
// ==========================================
function scrubPII(rawText) {
    if (!rawText) return "";
    let sanitizedText = rawText;

    // 1. Hunt for Credit Cards (13 to 19 digits)
    sanitizedText = sanitizedText.replace(/\b(?:\d[ -]*?){13,19}\b/g, '[CREDIT_CARD_REDACTED]');

    // 2. Hunt for SSN / Aadhaar
    sanitizedText = sanitizedText.replace(/\b\d{3}[- ]?\d{2}[- ]?\d{4}\b/g, '[SSN_REDACTED]'); 
    sanitizedText = sanitizedText.replace(/\b\d{4}[- ]?\d{4}[- ]?\d{4}\b/g, '[AADHAAR_REDACTED]'); 

    // 3. Hunt for OTPs, CVVs, and PINs (3 to 6 digits)
    sanitizedText = sanitizedText.replace(/\b\d{3,6}\b/g, '[OTP_OR_PIN_REDACTED]');

    return sanitizedText;
}

// Initialize the Gemini SDK
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

// Define the exact JSON structure we want back
const responseSchema = {
    type: SchemaType.OBJECT,
    properties: {
        scam_probability: { 
            type: SchemaType.INTEGER, 
            description: "A score from 0 to 100 indicating the likelihood of this being a scam." 
        },
        flagged_tactics: { 
            type: SchemaType.ARRAY, 
            items: { type: SchemaType.STRING },
            description: "List of identified tactics like 'Urgency', 'Impersonation', 'Financial Extraction'." 
        },
        explanation: { 
            type: SchemaType.STRING, 
            description: "A strict, 1-sentence explanation of why this score was given." 
        }
    },
    required: ["scam_probability", "flagged_tactics", "explanation"]
};

// Configure the model - "Gemini-2.5-flash"
const model = genAI.getGenerativeModel({
    model: "gemini-3.1-flash-lite-preview",
    systemInstruction: "You are a real-time cybersecurity AI monitoring a live phone call. Analyze the provided transcript snippet. Detect signs of social engineering, scams, or fraud. You must strictly return the requested JSON format and nothing else.",
    generationConfig: {
        responseMimeType: "application/json",
        responseSchema: responseSchema,
    },
});

// The execution function
const evaluateWithGemini = async (transcriptBlock) => {
    const result = await model.generateContent(transcriptBlock);
    const jsonText = result.response.text();
    return JSON.parse(jsonText); // Returns a clean JavaScript object
};

// ==========================================
// 🚨 NEW: THE JUST-IN-TIME WARM-UP ENGINE 🚨
// ==========================================
const warmUpGemini = async () => {
    console.log("🔥 [SYSTEM] Firing background warmup ping to Gemini API...");
    try {
        const startTime = Date.now();
        // Send a meaningless string to force Google to open the TLS tunnel
        await evaluateWithGemini("[SYSTEM]: Network warmup ping. Ignore.");
        console.log(`✅ [SYSTEM] Gemini TLS connection hot and ready! (Took ${Date.now() - startTime}ms)`);
    } catch (error) {
        // We actually don't care if this errors out (e.g., if Gemini fails to parse the JSON format for the warmup).
        // The simple act of sending the HTTP request forces the TLS handshake to complete!
        console.log(`✅ [SYSTEM] Gemini connection established (Warmup finished).`);
    }
};

// ==========================================
// 🧠 1. THE COGNITIVE ENGINE STATE
// ==========================================
let contextBuffer = [];
let newSentenceCount = 0;
let newWordCount = 0;
let isGeminiProcessing = false; // The Concurrency Lock
const MAX_BUFFER_SIZE = 15;     // The Smart Array Ceiling

// ==========================================
// ⚙️ 2. THE BUFFERING LOGIC (Untouched!)
// ==========================================
const processTranscript = async (speaker, text, broadcastFn) => {
    const formattedLine = `[${speaker.toUpperCase()}]: ${text}`;
    contextBuffer.push(formattedLine);
    
    newSentenceCount++;
    newWordCount += text.split(/\s+/).length;

    if (contextBuffer.length > MAX_BUFFER_SIZE) contextBuffer.shift();

    if (newSentenceCount >= 5 && newWordCount >= 35) {
        if (isGeminiProcessing) return;
        isGeminiProcessing = true;
        
        const transcriptPayload = contextBuffer.join('\n');
        newSentenceCount = 0;
        newWordCount = 0;

        try {
            // ⏱️ 1. Measure Gemini's exact thinking time
            const aiStartTime = Date.now();
            const analysis = await evaluateWithGemini(transcriptPayload);
            const aiEndTime = Date.now();

            console.log("✅ [GEMINI] Analysis Complete:");
            console.log(`🚨 Scam Probability: ${analysis.scam_probability}%`);
            console.log(`🚩 Tactics: ${analysis.flagged_tactics.join(', ') || 'None'}`);
            console.log(`📝 Reasoning: ${analysis.explanation}\n`);
            
            console.log(`🧠 [LATENCY] Gemini Processing Time: ${aiEndTime - aiStartTime}ms`);

            if (analysis.scam_probability > 60 && broadcastFn) {
                const threatPayload = {
                    type: "ALERT",
                    threatLevel: analysis.scam_probability > 85 ? "CRITICAL" : "SUSPICIOUS",
                    probability: analysis.scam_probability,
                    tactics: analysis.flagged_tactics,
                    explanation: analysis.explanation,
                    // ⏱️ 2. The Tracer Bullet: The exact millisecond it leaves the server
                    dispatch_time: Date.now() 
                };
                
                broadcastFn(threatPayload);
                console.log("📡 Threat Alert broadcasted to Flutter app!");
            }

            // 🚨 2. NEW: THE KILL SWITCH COMMAND (Greater than 95%)
            if (analysis.scam_probability >= 95 && broadcastFn) {
                console.log("💀 [SYSTEM] Critical Threat Level Reached! Dispatching KILL_CALL command...");
                broadcastFn({
                    type: "KILL_CALL",
                    probability: analysis.scam_probability,
                    // 🚨 NEW: Pass the full forensic data to the UI for the Receipt
                    tactics: analysis.flagged_tactics,
                    explanation: analysis.explanation
                });
            }

            isGeminiProcessing = false; 
        } catch (error) {
            console.error("❌ [GEMINI] API Error:", error.message);
            isGeminiProcessing = false; 
        }
    }
};

const api = process.env.DEEPGRAM_API_KEY;
const handleStream = (ws, broadcastFn) => {
    console.log('[StreamService] Twilio Call Connected');

    console.log(`🔑 Deepgram Key Check: ${api ? 'Key Loaded' : 'KEY MISSING!'}`);
    
    // Helper function to spawn a Deepgram connection for a specific track
    const createDeepgramStream = (trackName) => {
        const deepgramUrl = 'wss://api.deepgram.com/v1/listen?encoding=mulaw&sample_rate=8000&channels=1&model=nova-2&smart_format=true&language=en-IN';
        
        const dgSocket = new WebSocket(deepgramUrl, {
            headers: { Authorization: `Token ${api}` }
        });

        dgSocket.on('open', () => console.log(`🔗 Deepgram connected for ${trackName}`));
        
        dgSocket.on('message', (data) => {
            const response = JSON.parse(data);
            if (response.is_final && response.channel && response.channel.alternatives[0].transcript) {
                const rawTranscript = response.channel.alternatives[0].transcript;
                
                if (rawTranscript && rawTranscript.trim().length > 0) {
                    // 🚨 1. INTERCEPT AND SCRUB IMMEDIATELY
                    const safeTranscript = scrubPII(rawTranscript);

                    // 🚨 2. STRICT RULE: NEVER log the 'rawTranscript'
                    console.log(`🗣️ [${trackName.toUpperCase()}]: ${safeTranscript}`);

                    broadcastFn({
                        type: "TRANSCRIPT",
                        role: trackName, // 'inbound' (scammer) or 'outbound' (victim)
                        text: safeTranscript
                    });

                    // 🚨 3. Send ONLY the scrubbed text to Gemini
                    processTranscript(trackName, safeTranscript, broadcastFn);
                }
            }
        });

        dgSocket.on('error', (err) => {
            console.error(`❌ Deepgram Raw Error (${trackName}):`, err);
        });
                
        dgSocket.on('unexpected-response', (req, res) => {
            console.error(`🛑 Deepgram Connection Rejected (${trackName}). HTTP Status: ${res.statusCode}`);
            if (res.statusCode === 401) console.error("   -> Reason: Your API Key is missing, invalid, or out of credits.");
            if (res.statusCode === 400) console.error("   -> Reason: Bad Request (Check URL parameters).");
            if (res.statusCode === 403) console.error("   -> Reason: Forbidden. You might have pasted a Project ID instead of an API Key.");
        });

        return dgSocket;
    };

    // Spawn the Twin Streams
    const dgInbound = createDeepgramStream('inbound');   // Customer
    const dgOutbound = createDeepgramStream('outbound'); // Agent

    ws.on('message', (message) => {
        try {
            const msg = JSON.parse(message);

            // 🚨 1. RESET SHIELD ON NEW CALL AND TRIGGER WARMUP
            if (msg.event === 'start') {
                console.log('📞 New call started. Resetting shield to ACTIVE.');
                setMonitoringState(true); 
                
                // 🚨 NEW: Trigger the background warmup instantly! 
                // Notice there is no 'await' here, so it doesn't block Twilio or Deepgram.
                warmUpGemini();
            }

            // 🚨 2. THE GATEKEEPER
            if (msg.event === 'media' && msg.media.payload) {
                if (getMonitoringState() === true) {
                    const track = msg.media.track; 
                    
                    const rawAudio = Buffer.from(msg.media.payload, 'base64');
                    
                    if (track === 'inbound' && dgInbound.readyState === WebSocket.OPEN) {
                        dgInbound.send(rawAudio);
                    } else if (track === 'outbound' && dgOutbound.readyState === WebSocket.OPEN) {
                        dgOutbound.send(rawAudio);
                    }
                }
            }
        } catch (error) {
            console.error('Error in Node.js stream handler:', error);
        }
    });

    ws.on('close', () => {
        console.log('[StreamService] Twilio Call Ended');
        if (dgInbound.readyState === WebSocket.OPEN) dgInbound.close();
        if (dgOutbound.readyState === WebSocket.OPEN) dgOutbound.close();
    });
};

module.exports = { handleStream };