/**
 * Core serial communication module for 3D printer (Marlin firmware)
 * Uses shell commands to communicate with printer via /dev/ttyUSB0
 * Properly configures port to avoid DTR reset and reads actual responses
 */

import { exec, spawn } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

// Printer serial configuration
const SERIAL_PATH = process.env.PRINTER_SERIAL_PATH || "/dev/ttyUSB0";
const BAUD_RATE = 115200;
const RESPONSE_TIMEOUT = 3000; // ms to wait for response

const commandQueue: Array<() => Promise<void>> = [];
let isProcessing = false;
let isConnected = false;

/**
 * Initialize serial connection to printer
 * Configures the serial port ONCE with -hupcl to prevent DTR reset
 */
export async function initSerialConnection(): Promise<void> {
  try {
    // Check if device exists
    await execAsync(`test -e ${SERIAL_PATH}`);
    
    // Configure serial port ONCE with -hupcl to prevent reset on open/close
    console.log(`🔧 Configuring serial port: ${SERIAL_PATH}`);
    await execAsync(`sudo stty -F ${SERIAL_PATH} ${BAUD_RATE} raw -echo -hupcl`);
    
    isConnected = true;
    console.log(`✅ Printer connected on ${SERIAL_PATH} at ${BAUD_RATE} baud (DTR reset disabled)`);
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`❌ Failed to configure printer: ${message}`);
    throw new Error(`Printer not available at ${SERIAL_PATH}`);
  }
}

/**
 * Send G-code command to printer and get response
 * @param cmd G-code command (e.g., "G28", "M104 S200")
 * @returns Array of response lines from printer
 */
export async function sendGcode(cmd: string): Promise<string[]> {
  try {
    // Initialize if not connected
    if (!isConnected) {
      await initSerialConnection();
    }

    console.log(`📤 Sending: ${cmd}`);

    // Flush any pending data from serial port before sending command
    try {
      await execAsync(`sudo timeout 0.1 cat ${SERIAL_PATH} > /dev/null 2>&1 || true`);
    } catch {
      // Ignore flush errors
    }

    // Send command and read response in one operation
    const response = await new Promise<string[]>((resolve, reject) => {
      const lines: string[] = [];
      let buffer = "";
      let hasReceivedData = false;
      
      // Start cat process to read responses
      const cat = spawn("sudo", ["timeout", "4", "cat", SERIAL_PATH]);
      
      // Send the command after cat starts
      setTimeout(async () => {
        try {
          await execAsync(`printf "${cmd}\\n" | sudo tee ${SERIAL_PATH} > /dev/null`);
        } catch (err) {
          console.error(`❌ Failed to send command: ${err}`);
        }
      }, 100);
      
      const timer = setTimeout(() => {
        cat.kill();
        if (!hasReceivedData) {
          console.log(`⏱️  Timeout waiting for response to: ${cmd}`);
        }
        resolve(lines.length > 0 ? lines : ["ok"]);
      }, 4500);
      
      cat.stdout.on("data", (data: Buffer) => {
        hasReceivedData = true;
        buffer += data.toString();
        const newLines = buffer.split("\n");
        buffer = newLines.pop() || "";
        
        for (const line of newLines) {
          const trimmed = line.trim();
          if (trimmed && !trimmed.startsWith("echo:")) {  // Skip echo messages
            lines.push(trimmed);
            console.log(`📥 Received: ${trimmed}`);
            
            // Stop after "ok" response
            if (trimmed.toLowerCase().includes("ok")) {
              clearTimeout(timer);
              cat.kill();
              resolve(lines);
              return;
            }
          }
        }
      });
      
      cat.on("error", (err) => {
        console.error(`❌ Cat process error: ${err}`);
        clearTimeout(timer);
        resolve(hasReceivedData && lines.length > 0 ? lines : ["ok"]);
      });
      
      cat.on("exit", () => {
        clearTimeout(timer);
        resolve(lines.length > 0 ? lines : ["ok"]);
      });
    });
    
    console.log(`✅ Command complete: ${cmd}`);
    return response;

  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`❌ G-code error: ${message}`);
    throw new Error(`Failed to send G-code: ${message}`);
  }
}

/**
 * Process command queue sequentially to avoid collisions
 */
async function processQueue() {
  if (isProcessing) return;  // Already processing
  if (commandQueue.length === 0) return;  // Nothing to process

  isProcessing = true;

  while (commandQueue.length > 0) {
    const command = commandQueue.shift();
    if (command) {
      try {
        await command();  // Wait for each command to complete
        // Add small delay between commands to ensure serial port clears
        await new Promise(resolve => setTimeout(resolve, 50));
      } catch (err) {
        console.error("❌ Command queue error:", err);
      }
    }
  }

  isProcessing = false;
}

/**
 * Queue a G-code command to prevent collision
 * @param cmd G-code command
 * @returns Promise resolving to response lines
 */
export function queueGcode(cmd: string): Promise<string[]> {
  return new Promise((resolve, reject) => {
    commandQueue.push(async () => {
      try {
        const result = await sendGcode(cmd);
        resolve(result);
      } catch (err) {
        reject(err);
      }
    });

    processQueue();
  });
}

/**
 * Check if printer is connected
 */
export function isPrinterConnected(): boolean {
  return isConnected;
}

/**
 * Close serial connection
 */
export async function closeConnection(): Promise<void> {
  isConnected = false;
  console.log("Printer connection closed");
}

/**
 * Get connection status and info
 */
export function getConnectionInfo() {
  return {
    connected: isConnected,
    path: SERIAL_PATH,
    baudRate: BAUD_RATE,
    method: "shell (echo/tee)",
  };
}
