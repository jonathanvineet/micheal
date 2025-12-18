/**
 * Temperature control endpoints for 3D printer
 * Handles hotend and bed temperature management
 */

import { NextRequest, NextResponse } from "next/server";
import { initSerialConnection, queueGcode, isPrinterConnected } from "../serial";

/**
 * GET /api/printer/temperature
 * Read current temperatures (M105)
 */
export async function GET() {
  try {
    if (!isPrinterConnected()) {
      await initSerialConnection();
    }

    const reply = await queueGcode("M105");
    
    // Parse temperature response
    // Example: "ok T:25.0 /0.0 B:24.5 /0.0"
    const parsed = parseTemperature(reply);

    return NextResponse.json({
      success: true,
      temperatures: parsed,
      raw: reply,
    });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "Failed to read temperatures";
    return NextResponse.json(
      {
        success: false,
        error: errorMessage,
      },
      { status: 500 }
    );
  }
}

/**
 * POST /api/printer/temperature
 * Set temperatures or turn heaters off
 * Body: { action: "hotend" | "bed" | "hotend-wait" | "bed-wait" | "off", temp?: number }
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action, temp } = body;

    if (!isPrinterConnected()) {
      await initSerialConnection();
    }

    let reply: string[];

    switch (action) {
      case "hotend":
        // M104 S{temp} - Set hotend temp (no wait)
        if (temp === undefined) {
          return NextResponse.json(
            { success: false, error: "Temperature required" },
            { status: 400 }
          );
        }
        reply = await queueGcode(`M104 S${temp}`);
        return NextResponse.json({
          success: true,
          message: `Hotend set to ${temp}°C`,
          reply,
        });

      case "hotend-wait":
        // M109 S{temp} - Set hotend temp and wait
        if (temp === undefined) {
          return NextResponse.json(
            { success: false, error: "Temperature required" },
            { status: 400 }
          );
        }
        reply = await queueGcode(`M109 S${temp}`);
        return NextResponse.json({
          success: true,
          message: `Hotend heated to ${temp}°C`,
          reply,
        });

      case "bed":
        // M140 S{temp} - Set bed temp (no wait)
        if (temp === undefined) {
          return NextResponse.json(
            { success: false, error: "Temperature required" },
            { status: 400 }
          );
        }
        reply = await queueGcode(`M140 S${temp}`);
        return NextResponse.json({
          success: true,
          message: `Bed set to ${temp}°C`,
          reply,
        });

      case "bed-wait":
        // M190 S{temp} - Set bed temp and wait
        if (temp === undefined) {
          return NextResponse.json(
            { success: false, error: "Temperature required" },
            { status: 400 }
          );
        }
        reply = await queueGcode(`M190 S${temp}`);
        return NextResponse.json({
          success: true,
          message: `Bed heated to ${temp}°C`,
          reply,
        });

      case "off":
        // Turn all heaters off
        await queueGcode("M104 S0"); // Hotend off
        await queueGcode("M140 S0"); // Bed off
        return NextResponse.json({
          success: true,
          message: "All heaters turned off",
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: hotend, bed, hotend-wait, bed-wait, or off",
          },
          { status: 400 }
        );
    }
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "Temperature control failed";
    return NextResponse.json(
      {
        success: false,
        error: errorMessage,
      },
      { status: 500 }
    );
  }
}

/**
 * Parse temperature from M105 response
 */
interface TemperatureResult {
  hotend: { current: number | null; target: number | null };
  bed: { current: number | null; target: number | null };
}

function parseTemperature(lines: string[]): TemperatureResult {
  const result: TemperatureResult = {
    hotend: { current: null, target: null },
    bed: { current: null, target: null },
  };

  for (const line of lines) {
    // Match patterns like "T:200.0 /210.0 B:60.0 /60.0"
    const hotendMatch = line.match(/T:(\d+\.?\d*)\s*\/(\d+\.?\d*)/);
    const bedMatch = line.match(/B:(\d+\.?\d*)\s*\/(\d+\.?\d*)/);

    if (hotendMatch) {
      result.hotend.current = parseFloat(hotendMatch[1]);
      result.hotend.target = parseFloat(hotendMatch[2]);
    }

    if (bedMatch) {
      result.bed.current = parseFloat(bedMatch[1]);
      result.bed.target = parseFloat(bedMatch[2]);
    }
  }

  return result;
}
