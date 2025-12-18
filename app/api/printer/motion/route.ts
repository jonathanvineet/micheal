/**
 * Motion control endpoints for 3D printer
 * Handles homing, movement, positioning, and motor control
 */

import { NextRequest, NextResponse } from "next/server";
import { initSerialConnection, queueGcode, isPrinterConnected } from "../serial";

/**
 * GET /api/printer/motion
 * Get current position (M114)
 */
export async function GET() {
  try {
    if (!isPrinterConnected()) {
      await initSerialConnection();
    }

    const reply = await queueGcode("M114");
    const parsed = parsePosition(reply);

    return NextResponse.json({
      success: true,
      position: parsed,
      raw: reply,
    });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "Failed to get position";
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
 * POST /api/printer/motion
 * Control motion: home, move, motors
 * Body options:
 * - { action: "home", axes?: "X" | "Y" | "Z" | "XY" | "all" }
 * - { action: "move", axis: "X"|"Y"|"Z", distance: number, feedrate?: number, relative?: boolean }
 * - { action: "motors-on" }
 * - { action: "motors-off" }
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
      case "home": {
        // G28 - Home axes
        const axes = body.axes || "all";
        let cmd = "G28";
        
        if (axes !== "all") {
          cmd += ` ${axes.split("").join(" ")}`;
        }

        reply = await queueGcode(cmd);
        return NextResponse.json({
          success: true,
          message: `Homed ${axes}`,
          reply,
        });
      }

      case "move": {
        // G1 - Linear move
        const { axis, distance, feedrate = 3000, relative = false, disableSoftEndstops = false } = body;

        if (!axis || distance === undefined) {
          return NextResponse.json(
            { success: false, error: "axis and distance required" },
            { status: 400 }
          );
        }

        // Optionally disable soft endstops (for manual moves beyond limits)
        if (disableSoftEndstops) {
          await queueGcode("M211 S0");
        }

        // Set positioning mode - default to absolute (like Python script)
        if (relative) {
          await queueGcode("G91"); // Relative
        } else {
          await queueGcode("G90"); // Absolute
        }

        // Invert Z-axis: positive = down, negative = up
        let actualDistance = distance;
        if (axis.toUpperCase() === "Z") {
          actualDistance = -distance;
        }

        // Move command
        const cmd = `G1 ${axis.toUpperCase()}${actualDistance} F${feedrate}`;
        reply = await queueGcode(cmd);

        // Re-enable soft endstops if we disabled them
        if (disableSoftEndstops) {
          await queueGcode("M211 S1");
        }

        return NextResponse.json({
          success: true,
          message: `Moved ${axis} to ${distance}mm at ${feedrate}mm/min`,
          reply,
        });
      }

      case "motors-on":
        // M17 - Enable motors
        reply = await queueGcode("M17");
        return NextResponse.json({
          success: true,
          message: "Motors enabled",
          reply,
        });

      case "motors-off":
        // M18 - Disable motors
        reply = await queueGcode("M18");
        return NextResponse.json({
          success: true,
          message: "Motors disabled",
          reply,
        });

      case "absolute":
        // G90 - Absolute positioning
        reply = await queueGcode("G90");
        return NextResponse.json({
          success: true,
          message: "Absolute positioning mode",
          reply,
        });

      case "relative":
        // G91 - Relative positioning
        reply = await queueGcode("G91");
        return NextResponse.json({
          success: true,
          message: "Relative positioning mode",
          reply,
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: home, move, motors-on, motors-off, absolute, relative",
          },
          { status: 400 }
        );
    }
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "Motion control failed";
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
 * Parse position from M114 response
 */
interface Position {
  x: number | null;
  y: number | null;
  z: number | null;
  e: number | null;
}

function parsePosition(lines: string[]): Position {
  const result: Position = {
    x: null,
    y: null,
    z: null,
    e: null,
  };

  for (const line of lines) {
    // Match patterns like "X:100.00 Y:50.00 Z:10.00 E:0.00"
    const match = line.match(/X:([\d.-]+)\s+Y:([\d.-]+)\s+Z:([\d.-]+)\s+E:([\d.-]+)/);
    
    if (match) {
      result.x = parseFloat(match[1]);
      result.y = parseFloat(match[2]);
      result.z = parseFloat(match[3]);
      result.e = parseFloat(match[4]);
    }
  }

  return result;
}
