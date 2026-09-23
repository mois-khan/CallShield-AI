require('dotenv').config(); 
const WebSocket = require('ws');
const { getMonitoringState, setMonitoringState } = require('../state');
const Groq = require('groq-sdk');

function scrubPII(rawText) {
    if (!rawText) return "";
    let sanitizedText = rawText;
    sanitizedText = sanitizedText.replace(/\b(?:\d[ -]*?){13,19}\b/g, '[CREDIT_CARD_REDACTED]');
    sanitizedText = sanitizedText.replace(/\b\d{3}[- ]?\d{2}[- ]?\d{4}\b/g, '[SSN_REDACTED]'); 
    sanitizedText = sanitizedText.replace(/\b\d{4}[- ]?\d{4}[- ]?\d{4}\b/g, '[AADHAAR_REDACTED]'); 
    sanitizedText = sanitizedText.replace(/\b\d{3,6}\b/g, '[OTP_OR_PIN_REDACTED]');
    return sanitizedText;
}

const groq = new Groq({ apiKey: process.env.GROQ_API_KEY });

const evaluateWithGroq = async (transcriptBlock) => {
    const systemPrompt = `You are a real-time cybersecurity AI monitoring a live phone call. Analyze the transcript for social engineering, scams, or fraud. Return ONLY a JSON object with this exact schema:
{
    "scam_probability": <integer 0-100>,
    "flagged_tactics": [<short string array, max 3 items>],
    "explanation": "<1 sentence max, under 20 words>"
}`;

    const chatCompletion = await groq.chat.completions.create({
        messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: transcriptBlock }
        ],
        model: "qwen/qwen3.8-27b",
        temperature: 0.1,
        max_tokens: 200,
        response_format: { type: "json_object" }
    });

    return JSON.parse(chatCompletion.choices[0].message.content);
};

const warmUpGroq = async () => {
    try {
        await evaluateWithGroq("[SYSTEM]: Network warmup ping. Ignore.");
        console.log(`✅ [SYSTEM] Groq connection established (Warmup finished).`);
    } catch (error) {
        console.error("❌ [SYSTEM] Groq connection warm-up failed:", error);
    }
};

const api = process.env.DEEPGRAM_API_KEY;

const handleStream = (ws, broadcastFn) => {
    console.log('[StreamService] Twilio Call Connected');

    // 🚨 PER-CALL SESSION STATE
    let activeSession = {
        callerId: "Unknown",
        maxThreatLevel: 0,
        tactics: new Set(),
        transcript: []
    };

    let contextBuffer = [];
    let newSentenceCount = 0;
    let newWordCount = 0;
    let isGroqProcessing = false;

    const processTranscript = async (speaker, text) => {
        const formattedLine = `[${speaker.toUpperCase()}]: ${text}`;
        contextBuffer.push(formattedLine);
        activeSession.transcript.push(formattedLine); // 🚨 Save to permanent record
        
        newSentenceCount++;
        newWordCount += text.split(/\s+/).length;

        if (contextBuffer.length > 15) contextBuffer.shift();

        if (newSentenceCount >= 5 && newWordCount >= 35) {
            if (isGroqProcessing) return;
            isGroqProcessing = true;
            
            const transcriptPayload = contextBuffer.join('\n');
            newSentenceCount = 0;
            newWordCount = 0;

            console.log(`🧠 [Groq AI] Evaluating transcript payload:\n${transcriptPayload}`);

            try {
                const analysis = await evaluateWithGroq(transcriptPayload);
                console.log(`🧠 [Groq AI] Verdict received:`, JSON.stringify(analysis, null, 2));

                // Update Session Aggregates
                if (analysis.scam_probability > activeSession.maxThreatLevel) {
                    activeSession.maxThreatLevel = analysis.scam_probability;
                }
                if (analysis.flagged_tactics) {
                    analysis.flagged_tactics.forEach(t => activeSession.tactics.add(t));
                }

                if (analysis.scam_probability > 60 && broadcastFn) {
                    broadcastFn({
                        type: "ALERT",
                        threatLevel: analysis.scam_probability > 85 ? "CRITICAL" : "SUSPICIOUS",
                        probability: analysis.scam_probability,
                        tactics: analysis.flagged_tactics,
                        explanation: analysis.explanation,
                        dispatch_time: Date.now() 
                    });
                }

                if (analysis.scam_probability >= 95 && broadcastFn) {
                    broadcastFn({ type: "KILL_CALL", probability: analysis.scam_probability });
                }
                isGroqProcessing = false; 
            } catch (error) {
                console.error("❌ [Groq AI] Evaluation failed:", error);
                isGroqProcessing = false; 
            }
        }
    };

    const createDeepgramStream = (trackName) => {
        // 🚨 ADDED KEYWORD BOOSTING FOR INDIAN CONTEXT
        const deepgramUrl = 'wss://api.deepgram.com/v1/listen?encoding=mulaw&sample_rate=8000&channels=1&model=nova-2&smart_format=true&language=en-IN&keywords=Aadhaar:3&keywords=OTP:2&keywords=TRAI:2&keywords=CBI:2&keywords=FedEx:2';
        const dgSocket = new WebSocket(deepgramUrl, { headers: { Authorization: `Token ${api}` } });
        
        dgSocket.on('message', (data) => {
            const response = JSON.parse(data);
            if (response.is_final && response.channel && response.channel.alternatives[0].transcript) {
                const rawTranscript = response.channel.alternatives[0].transcript;
                if (rawTranscript && rawTranscript.trim().length > 0) {
                    const safeTranscript = scrubPII(rawTranscript);
                    console.log(`🗣️ [${trackName.toUpperCase()}]: ${safeTranscript}`);
                    broadcastFn({ type: "TRANSCRIPT", role: trackName, text: safeTranscript });
                    processTranscript(trackName, safeTranscript);
                }
            }
        });
        return dgSocket;
    };

    const dgInbound = createDeepgramStream('inbound');  
    const dgOutbound = createDeepgramStream('outbound'); 

    ws.on('message', (message) => {
        try {
            const msg = JSON.parse(message);
            if (msg.event === 'start') {
                setMonitoringState(true); 
                // Capture Caller ID from Twilio, or use realistic Indian demo number
                activeSession.callerId = msg.start?.customParameters?.callerId || "+91 9876543210";
                warmUpGroq();
            }
            if (msg.event === 'media' && msg.media.payload && getMonitoringState() === true) {
                const rawAudio = Buffer.from(msg.media.payload, 'base64');
                if (msg.media.track === 'inbound' && dgInbound.readyState === WebSocket.OPEN) dgInbound.send(rawAudio);
                else if (msg.media.track === 'outbound' && dgOutbound.readyState === WebSocket.OPEN) dgOutbound.send(rawAudio);
            }
        } catch (error) {}
    });

    ws.on('close', () => {
        console.log('🛑 [StreamService] Call Ended. Generating Final Summary...');
        
        // 🚨 SEND FINAL SUMMARY TO DEVICE
        if (activeSession.maxThreatLevel > 0 && broadcastFn) {
            broadcastFn({
                type: "CALL_SUMMARY",
                callerId: activeSession.callerId,
                maxThreat: activeSession.maxThreatLevel,
                tactics: Array.from(activeSession.tactics),
                transcript: activeSession.transcript.join('\n')
            });
        }
        if (dgInbound.readyState === WebSocket.OPEN) dgInbound.close();
        if (dgOutbound.readyState === WebSocket.OPEN) dgOutbound.close();
    });
};

module.exports = { handleStream };