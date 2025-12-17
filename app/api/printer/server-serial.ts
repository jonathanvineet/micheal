/**
 * Server-only serial port initialization
 * Falls back to mock mode if native modules can't be loaded
 * This is suitable for development and testing
 */
"use server"

let SerialPort: any = null;
let ReadlineParser: any = null;
let mockMode = false;

export async function getSerialPortClasses() {
  if (SerialPort && ReadlineParser) {
    return { SerialPort, ReadlineParser, mockMode: false };
  }

  try {
    // Require serialport at runtime
    const sp = require("serialport");
    SerialPort = sp.SerialPort;
    
    const parserModule = require("@serialport/parser-readline");
    ReadlineParser = parserModule.ReadlineParser;
    
    mockMode = false;
    return { SerialPort, ReadlineParser, mockMode: false };
  } catch (err: any) {
    console.log("SerialPort native bindings unavailable - using MOCK MODE for testing");
    console.log("The API endpoints will work but commands won't affect a real printer");
    mockMode = true;
    return { SerialPort: null, ReadlineParser: null, mockMode: true };
  }
}

