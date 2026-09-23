require('dotenv').config();
const twilio = require('twilio');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const https = require('https');

async function testAPIs() {
  console.log("Testing APIs...");

  // 1. Twilio
  try {
    const client = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
    const account = await client.api.v2010.accounts(process.env.TWILIO_ACCOUNT_SID).fetch();
    console.log("✅ Twilio Auth: OK (Account Status: " + account.status + ")");
  } catch (e) {
    console.log("❌ Twilio Error:", e.message);
  }

  // 2. Gemini
  try {
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    // Using a fast model just for pinging
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" }); 
    const result = await model.generateContent("Respond with 'OK' if you receive this.");
    console.log("✅ Gemini Auth: OK (Response: " + result.response.text().trim() + ")");
  } catch (e) {
    console.log("❌ Gemini Error:", e.message);
  }

  // 3. Deepgram
  try {
    const options = {
      hostname: 'api.deepgram.com',
      path: '/v1/projects',
      method: 'GET',
      headers: {
        'Authorization': `Token ${process.env.DEEPGRAM_API_KEY}`
      }
    };
    
    await new Promise((resolve, reject) => {
      const req = https.request(options, (res) => {
        if (res.statusCode === 200 || res.statusCode === 201) {
          console.log("✅ Deepgram Auth: OK");
          resolve();
        } else {
          console.log("❌ Deepgram Error: Status code", res.statusCode);
          resolve();
        }
      });
      req.on('error', (e) => reject(e));
      req.end();
    });
  } catch(e) {
     console.log("❌ Deepgram Error:", e.message);
  }
}

testAPIs();
