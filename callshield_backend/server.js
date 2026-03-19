require('dotenv').config();
const dns = require('dns'); 
dns.setDefaultResultOrder('ipv4first');
const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const bodyParser = require('body-parser');
const twilio = require('twilio');

const twilioClient = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
const TWILIO_PHONE_NUMBER = process.env.TWILIO_PHONE_NUMBER;

const { setMonitoringState } = require('./state');

const callRoutes = require('./routes/callRoutes');
const { handleStream } = require('./services/streamHandler');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Middleware
app.use(bodyParser.urlencoded({ extended: false }));
app.use(bodyParser.json());
app.use((req, res, next) => {
    console.log(`[Incoming Request] ${req.method} ${req.url}`);
    next();
});


// Routes
app.use('/api', callRoutes);

// WebSocket Handling
// Twilio connects to wss://your-url.com/stream
// --- NEW: The Flutter Client Registry ---
const flutterClients = new Set();

const broadcastToFlutter = (payload) => {
    flutterClients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
            // 1. Send the visual alert to the Flutter app's UI
            client.send(JSON.stringify(payload));

            // 🚨 2. THE SOS TWILIO TRIGGER 🚨
            if (payload.threatLevel === 'CRITICAL') {
                // Check if they have contacts saved
                if (client.sosContacts && client.sosContacts.length > 0) {
                    if (!client.hasSentSOS) {
                        client.hasSentSOS = true; 

                        const messageBody = `🚨 CallShield SOS 🚨\nYour contact, ${client.userName || 'a user'}, is currently on a phone call with a highly probable scammer (Threat Level: ${payload.probability}%).\n\nTactics detected: ${payload.tactics.join(', ')}.\n\nPlease call them immediately to interrupt the scam.`;

                        client.sosContacts.forEach(number => {
                            twilioClient.messages.create({
                                body: messageBody,
                                from: TWILIO_PHONE_NUMBER,
                                to: number
                            }).then(message => {
                                console.log(`📲 [SOS] SMS sent successfully to ${number}! SID: ${message.sid}`);
                            }).catch(err => {
                                console.error(`❌ [SOS] Failed to send SMS to ${number}:`, err.message);
                            });
                        });
                    }
                } else {
                    // 🚨 THE BLINDSPOT FIX: Tell us why it failed!
                    console.log(`⚠️ [SOS] Threat is CRITICAL, but no emergency contacts are registered for this device!`);
                }
            }
        }
    });
};

// --- UPDATED: WebSocket Handling ---
wss.on('connection', (ws, req) => {
    if (req.url === '/stream') {
        // 1. Twilio connecting to stream audio
        // We now pass 'broadcastToFlutter' as a second argument!
        handleStream(ws, broadcastToFlutter); 

    } else if (req.url === '/flutter-alerts') {
        // 2. Mobile App connecting to listen for scams
        console.log('📱 Flutter App Connected to Alerts Channel!');
        flutterClients.add(ws);

        // Send a handshake so the app knows it connected successfully
        ws.send(JSON.stringify({ type: "SYSTEM", message: "Monitoring Active" }));

        // 🚨 NEW: Listen for messages coming UP from the Flutter app
        ws.on('message', (message) => {
            try {
                const data = JSON.parse(message);

                // 🏓 THE HEARTBEAT ECHO
                if (data.action === 'ping') {
                    ws.send(JSON.stringify({ action: 'pong' }));
                    return; // Stop processing, this is just a heartbeat
                }
                
                // 🚨 CATCH THE SOS HANDSHAKE
                if (data.action === 'register_sos') {
                    // Attach the user's name and contacts directly to their active WebSocket session!
                    ws.userName = data.userName;
                    ws.sosContacts = data.contacts;
                    console.log(`🛡️ [SOS] Registered emergency contacts for ${ws.userName}: ${ws.sosContacts.join(', ')}`);
                } 
                else if (data.action === 'pause_monitoring') {
                    setMonitoringState(false);
                } else if (data.action === 'resume_monitoring') {
                    setMonitoringState(true);
                }
            } catch (error) {
                console.error('Error reading command from Flutter:', error);
            }
        });

        ws.on('close', () => {
            console.log('📱 Flutter App Disconnected.');
            flutterClients.delete(ws);
        });

    } else {
        // Reject unknown connections
        ws.close(); 
    }
});

// Start Server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`-------------------------------------------`);
    console.log(`Server listening on port ${PORT}`);
    console.log(`Ensure SERVER_URL in .env is public (e.g. ngrok)`);
    console.log(`-------------------------------------------`);
});