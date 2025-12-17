/**
 * Status and information endpoints for 3D printer
 * Provides firmware info, print time, endstop states, and general status
 */

import { NextRequest, NextResponse } from "next/server";
import { initSerialConnection, queueGcode, isPrinterConnected, getConnectionInfo } from "../serial";

/**
 * GET /api/printer/status
 * Get printer status information
 * Query params:
 * - ?info=firmware (M115)
 * - ?info=time (M31)
 * - ?info=endstops (M119)
 * - ?info=settings (M503)
 * - ?info=connection (connection status)
 * - ?info=all (default - returns basic status)
 */
export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const info = searchParams.get("info") || "all";

    // Connection info doesn't require serial connection
    if (info === "connection") {
      const connInfo = getConnectionInfo();
      return NextResponse.json({
        success: true,
        connection: connInfo,
      });
    }

    if (!isPrinterConnected()) {
      await initSerialConnection();
    }

    let reply: string[];

    switch (info) {
      case "firmware":
        // M115 - Get firmware info
        reply = await queueGcode("M115");
        const firmware = parseFirmwareInfo(reply);
        
        return NextResponse.json({
          success: true,
          firmware,
          raw: reply,
        });

      case "time":
        // M31 - Print time
        reply = await queueGcode("M31");
        const time = parsePrintTime(reply);
        
        return NextResponse.json({
          success: true,
          printTime: time,
          raw: reply,
        });

      case "endstops":
        // M119 - Endstop states
        reply = await queueGcode("M119");
        const endstops = parseEndstops(reply);
        
        return NextResponse.json({
          success: true,
          endstops,
          raw: reply,
        });

      case "settings":
        // M503 - Report settings
        reply = await queueGcode("M503");
        
        return NextResponse.json({
          success: true,
          settings: reply,
          raw: reply,
        });

      case "all":
      default:
        // Basic status - position and temperature
        const posReply = await queueGcode("M114");
        const tempReply = await queueGcode("M105");
        const connInfo = getConnectionInfo();
        
        return NextResponse.json({
          success: true,
          status: {
            connected: connInfo.connected,
            position: posReply,
            temperature: tempReply,
          },
          raw: {
            position: posReply,
            temperature: tempReply,
          },
        });
    }
  } catch (error: any) {
    return NextResponse.json(
      {
        success: false,
        error: error.message || "Status query failed",
      },
      { status: 500 }
    );
  }
}

/**
 * POST /api/printer/status
 * Perform status-related actions
 * Body options:
 * - { action: "save-settings" } (M500)
 * - { action: "reset-settings" } (M502)
 * - { action: "lights-on" } (M355 S1)
 * - { action: "lights-off" } (M355 S0)
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action } = body;

    if (!isPrinterConnected()) {
      await initSerialConnection();
    }

    let reply: string[];

    switch (action) {
      case "save-settings":
        // M500 - Save settings to EEPROM
        reply = await queueGcode("M500");
        return NextResponse.json({
          success: true,
          message: "Settings saved to EEPROM",
          reply,
        });

      case "reset-settings":
        // M502 - Reset settings to defaults
        reply = await queueGcode("M502");
        return NextResponse.json({
          success: true,
          message: "Settings reset to defaults (use save-settings to persist)",
          reply,
        });

      case "lights-on":
        // M355 S1 - Turn lights on (if supported)
        reply = await queueGcode("M355 S1");
        return NextResponse.json({
          success: true,
          message: "Lights turned on",
          reply,
        });

      case "lights-off":
        // M355 S0 - Turn lights off (if supported)
        reply = await queueGcode("M355 S0");
        return NextResponse.json({
          success: true,
          message: "Lights turned off",
          reply,
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: save-settings, reset-settings, lights-on, lights-off",
          },
          { status: 400 }
        );
    }
  } catch (error: any) {
    return NextResponse.json(
      {
        success: false,
        error: error.message || "Status action failed",
      },
      { status: 500 }
    );
  }
}

/**
 * Parse firmware information from M115 response
 */
function parseFirmwareInfo(lines: string[]) {
  const info: any = {
    firmware: null,
    version: null,
    machine: null,
    uuid: null,
  };

  for (const line of lines) {
    if (line.includes("FIRMWARE_NAME")) {
      const match = line.match(/FIRMWARE_NAME:([^\s]+)/);
      if (match) info.firmware = match[1];
    }
    
    if (line.includes("FIRMWARE_VERSION")) {
      const match = line.match(/FIRMWARE_VERSION:([^\s]+)/);
      if (match) info.version = match[1];
    }
    
    if (line.includes("MACHINE_TYPE")) {
      const match = line.match(/MACHINE_TYPE:([^\s]+)/);
      if (match) info.machine = match[1];
    }
    
    if (line.includes("UUID")) {
      const match = line.match(/UUID:([^\s]+)/);
      if (match) info.uuid = match[1];
    }
  }

  return info;
}

/**
 * Parse print time from M31 response
 */
function parsePrintTime(lines: string[]) {
  for (const line of lines) {
    // Match patterns like "Print time: 1h 23m 45s"
    const match = line.match(/(\d+)h?\s*(\d+)m?\s*(\d+)s?/);
    
    if (match) {
      return {
        hours: parseInt(match[1], 10),
        minutes: parseInt(match[2], 10),
        seconds: parseInt(match[3], 10),
        totalSeconds: parseInt(match[1], 10) * 3600 + parseInt(match[2], 10) * 60 + parseInt(match[3], 10),
      };
    }
  }

  return null;
}

/**
 * Parse endstop states from M119 response
 */
function parseEndstops(lines: string[]) {
  const endstops: any = {
    x_min: null,
    y_min: null,
    z_min: null,
    x_max: null,
    y_max: null,
    z_max: null,
  };

  for (const line of lines) {
    const lower = line.toLowerCase();
    
    if (lower.includes("x_min")) {
      endstops.x_min = lower.includes("triggered") ? "TRIGGERED" : "open";
    }
    if (lower.includes("y_min")) {
      endstops.y_min = lower.includes("triggered") ? "TRIGGERED" : "open";
    }
    if (lower.includes("z_min")) {
      endstops.z_min = lower.includes("triggered") ? "TRIGGERED" : "open";
    }
    if (lower.includes("x_max")) {
      endstops.x_max = lower.includes("triggered") ? "TRIGGERED" : "open";
    }
    if (lower.includes("y_max")) {
      endstops.y_max = lower.includes("triggered") ? "TRIGGERED" : "open";
    }
    if (lower.includes("z_max")) {
      endstops.z_max = lower.includes("triggered") ? "TRIGGERED" : "open";
    }
  }

  return endstops;
}
