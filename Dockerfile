const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const path = require('path');
const fs = require('fs');
const handlers = require('./handlers');

// Konfigurasi path untuk session
const SESSION_DIR = path.join(__dirname, '.wwebjs_auth');
const SESSION_DEBUG_FILE = path.join(__dirname, 'session-debug.log');

// Pastikan folder session ada
if (!fs.existsSync(SESSION_DIR)) {
  fs.mkdirSync(SESSION_DIR, { recursive: true });
}

const client = new Client({
  authStrategy: new LocalAuth({
    clientId: "bot-wa", // Nama unik untuk session
    dataPath: SESSION_DIR
  }),
  puppeteer: {
    headless: true,
    executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/chromium',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--single-process',
      '--no-zygote',
      '--disable-gpu',
      '--disable-accelerated-2d-canvas',
      '--disable-software-rasterizer'
    ],
    timeout: 120000  // Timeout 2 menit
  },
  takeoverOnConflict: true, // Auto-reconnect
  qrTimeoutMs: 60000 // Timeout QR 1 menit
});

// Debug session
function logSessionState() {
  const files = fs.existsSync(SESSION_DIR) ? 
    fs.readdirSync(SESSION_DIR).join(', ') : 'none';
  const log = `[${new Date().toISOString()}] Session files: ${files}\n`;
  fs.appendFileSync(SESSION_DEBUG_FILE, log);
}

async function initialize() {
  // Log session awal
  logSessionState();

  client.on('qr', (qr) => {
    console.log('QR Code diterima, silahkan scan dengan WhatsApp Anda:');
    qrcode.generate(qr, { small: true });
    
    // Untuk environment server (Koyeb)
    console.log('Alternatif QR Text:');
    console.log(qr); // Bisa discan dengan WhatsApp > Linked Devices > Link with QR Code
  });

  client.on('ready', () => {
    console.log('WhatsApp Bot siap digunakan!');
    logSessionState();
  });

  client.on('authenticated', () => {
    console.log('Autentikasi berhasil!');
    logSessionState();
  });

  client.on('auth_failure', (msg) => {
    console.error('Autentikasi gagal:', msg);
    fs.writeFileSync(SESSION_DEBUG_FILE, `Auth Failed: ${msg}\n`, { flag: 'a' });
  });

  client.on('disconnected', (reason) => {
    console.log('Client logged out:', reason);
    fs.writeFileSync(SESSION_DEBUG_FILE, `Disconnected: ${reason}\n`, { flag: 'a' });
  });

  // Handle incoming messages
  client.on('message', async (msg) => {
    try {
      await handlers.handleMessage(client, msg);
    } catch (error) {
      console.error('Error handling message:', error);
    }
  });

  // Handle errors
  client.on('error', (error) => {
    console.error('Client error:', error);
    fs.writeFileSync(SESSION_DEBUG_FILE, `Error: ${error.stack}\n`, { flag: 'a' });
  });

  try {
    await client.initialize();
  } catch (error) {
    console.error('Initialization error:', error);
    throw error;
  }

  return client;
}

async function sendMessage(to, message, options = {}) {
  try {
    console.log(`Mengirim pesan ke ${to}...`);
    const formattedNumber = to.includes('@c.us') ? to : `${to}@c.us`;
    const result = await client.sendMessage(formattedNumber, message, options);
    console.log(`Pesan terkirim ke ${to} [ID: ${result.id.id}]`);
    return { success: true, messageId: result.id.id };
  } catch (error) {
    console.error(`Gagal mengirim pesan ke ${to}:`, error);
    return { 
      success: false, 
      error: error.message,
      stack: error.stack
    };
  }
}

async function shutdown() {
  try {
    console.log('Menutup koneksi WhatsApp Bot...');
    await client.destroy();
    console.log('WhatsApp Bot ditutup.');
    logSessionState();
  } catch (error) {
    console.error('Error saat shutdown:', error);
  }
}

// Auto-restart jika crash
process.on('unhandledRejection', (error) => {
  console.error('Unhandled Rejection:', error);
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
});

module.exports = {
  initialize,
  sendMessage,
  shutdown,
  client
};
