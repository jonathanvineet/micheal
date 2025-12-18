/**
 * Speed and flow override endpoints for 3D printer
 * Allows real-time adjustment of print speed and material flow rate
 */

import { NextRequest, NextResponse } from "next/server";
import { initSerialConnection, queueGcode, isPrinterConnected } from "../serial";

/**
 * POST /api/printer/speed
 * Control speed and flow overrides
 * Body options:
 * - { action: "speed", percent: number } (M220 - speed override)
 * - { action: "flow", percent: number } (M221 - flow override)
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action, percent } = body;

    if (!isPrinterConnected()) {
      await initSerialConnection();
    }

    if (percent === undefined) {
      return NextResponse.json(
        { success: false, error: "percent required" },
        { status: 400 }
      );
    }

    // Clamp to reasonable range (typically 50-200%)
    const clampedPercent = Math.max(10, Math.min(300, percent));
    let reply: string[];

    switch (action) {
      case "speed":
        // M220 S{percent} - Set speed override
        reply = await queueGcode(`M220 S${clampedPercent}`);
        return NextResponse.json({
          success: true,
          message: `Speed set to ${clampedPercent}%`,
          percent: clampedPercent,
          reply,
        });

      case "flow":
        // M221 S{percent} - Set flow (extrusion) override
        reply = await queueGcode(`M221 S${clampedPercent}`);
        return NextResponse.json({
          success: true,
          message: `Flow rate set to ${clampedPercent}%`,
          percent: clampedPercent,
          reply,
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: speed or flow",
          },
          { status: 400 }
        );
    }
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "Speed/flow control failed";
    return NextResponse.json(
      {
        success: false,
        error: errorMessage,
      },
      { status: 500 }
    );
  }
}
