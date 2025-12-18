/**
 * Fan control endpoints for 3D printer
 * Handles part cooling fan speed control
 */

import { NextRequest, NextResponse } from "next/server";
import { initSerialConnection, queueGcode, isPrinterConnected } from "../serial";

/**
 * POST /api/printer/fan
 * Control fan speed
 * Body options:
 * - { action: "set", speed: number (0-255) }
 * - { action: "off" }
 * - { action: "set-percent", percent: number (0-100) }
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
      case "set": {
        // M106 S{0-255} - Set fan speed
        const { speed } = body;

        if (speed === undefined) {
          return NextResponse.json(
            { success: false, error: "speed required (0-255)" },
            { status: 400 }
          );
        }

        // Clamp speed to valid range
        const clampedSpeed = Math.max(0, Math.min(255, speed));

        const cmd = `M106 S${clampedSpeed}`;
        reply = await queueGcode(cmd);

        const percent = Math.round((clampedSpeed / 255) * 100);
        return NextResponse.json({
          success: true,
          message: `Fan set to ${clampedSpeed} (${percent}%)`,
          speed: clampedSpeed,
          percent,
          reply,
        });
      }

      case "set-percent": {
        // M106 S{calculated} - Set fan speed by percentage
        const { percent } = body;

        if (percent === undefined) {
          return NextResponse.json(
            { success: false, error: "percent required (0-100)" },
            { status: 400 }
          );
        }

        // Clamp percent and convert to 0-255 range
        const clampedPercent = Math.max(0, Math.min(100, percent));
        const speed = Math.round((clampedPercent / 100) * 255);

        const cmd = `M106 S${speed}`;
        reply = await queueGcode(cmd);

        return NextResponse.json({
          success: true,
          message: `Fan set to ${clampedPercent}%`,
          speed,
          percent: clampedPercent,
          reply,
        });
      }

      case "off":
        // M107 - Fan off
        reply = await queueGcode("M107");
        return NextResponse.json({
          success: true,
          message: "Fan turned off",
          reply,
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: set, set-percent, or off",
          },
          { status: 400 }
        );
    }
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "Fan control failed";
    return NextResponse.json(
      {
        success: false,
        error: errorMessage,
      },
      { status: 500 }
    );
  }
}
