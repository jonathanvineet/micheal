/**
 * Extruder control endpoints for 3D printer
 * Handles filament extrusion, retraction, and extrusion modes
 */

import { NextRequest, NextResponse } from "next/server";
import { initSerialConnection, queueGcode, isPrinterConnected } from "../serial";

/**
 * POST /api/printer/extruder
 * Control extruder
 * Body options:
 * - { action: "extrude", amount: number, feedrate?: number }
 * - { action: "retract", amount: number, feedrate?: number }
 * - { action: "absolute-mode" } (M82)
 * - { action: "relative-mode" } (M83)
 * - { action: "cold-extrusion", enable: boolean }
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
      case "extrude": {
        // G1 E{amount} F{feedrate} - Extrude filament
        const { amount, feedrate = 300 } = body;

        if (amount === undefined) {
          return NextResponse.json(
            { success: false, error: "amount required" },
            { status: 400 }
          );
        }

        // Set relative extrusion mode for convenience
        await queueGcode("M83");
        
        const cmd = `G1 E${amount} F${feedrate}`;
        reply = await queueGcode(cmd);

        return NextResponse.json({
          success: true,
          message: `Extruded ${amount}mm at ${feedrate}mm/min`,
          reply,
        });
      }

      case "retract": {
        // G1 E-{amount} F{feedrate} - Retract filament
        const { amount, feedrate = 300 } = body;

        if (amount === undefined) {
          return NextResponse.json(
            { success: false, error: "amount required" },
            { status: 400 }
          );
        }

        // Set relative extrusion mode for convenience
        await queueGcode("M83");
        
        const cmd = `G1 E-${amount} F${feedrate}`;
        reply = await queueGcode(cmd);

        return NextResponse.json({
          success: true,
          message: `Retracted ${amount}mm at ${feedrate}mm/min`,
          reply,
        });
      }

      case "absolute-mode":
        // M82 - Absolute extrusion mode
        reply = await queueGcode("M82");
        return NextResponse.json({
          success: true,
          message: "Absolute extrusion mode enabled",
          reply,
        });

      case "relative-mode":
        // M83 - Relative extrusion mode
        reply = await queueGcode("M83");
        return NextResponse.json({
          success: true,
          message: "Relative extrusion mode enabled",
          reply,
        });

      case "cold-extrusion": {
        // M302 S0 - Allow cold extrusion (⚠️ DANGEROUS - use with caution)
        const { enable } = body;

        if (enable) {
          reply = await queueGcode("M302 S0");
          return NextResponse.json({
            success: true,
            message: "⚠️ Cold extrusion ENABLED (dangerous!)",
            warning: "Cold extrusion can damage your printer. Use with extreme caution.",
            reply,
          });
        } else {
          reply = await queueGcode("M302 S170"); // Reset to safe minimum (170°C)
          return NextResponse.json({
            success: true,
            message: "Cold extrusion disabled",
            reply,
          });
        }
      }

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: extrude, retract, absolute-mode, relative-mode, cold-extrusion",
          },
          { status: 400 }
        );
    }
  } catch (error: any) {
    return NextResponse.json(
      {
        success: false,
        error: error.message || "Extruder control failed",
      },
      { status: 500 }
    );
  }
}
