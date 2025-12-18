/**
 * Safety and emergency control endpoints for 3D printer
 * Handles emergency stops and critical safety operations
 */

import { NextRequest, NextResponse } from "next/server";
import { initSerialConnection, queueGcode, isPrinterConnected } from "../serial";

/**
 * POST /api/printer/safety
 * Safety and emergency controls
 * Body options:
 * - { action: "emergency-stop" } (M112 - IMMEDIATE HALT)
 * - { action: "quick-stop" } (M410 - finish current move then stop)
 * - { action: "all-off" } (turn off all heaters, motors, fans)
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
      case "emergency-stop":
        // M112 - EMERGENCY STOP (immediate halt, firmware may require reset)
        // ⚠️ This is a CRITICAL command - printer may need to be power cycled
        reply = await queueGcode("M112");
        
        return NextResponse.json({
          success: true,
          message: "🚨 EMERGENCY STOP ACTIVATED",
          warning: "Printer halted immediately. May require power cycle or reset.",
          reply,
        });

      case "quick-stop":
        // M410 - Quick stop (finish current move, then stop)
        reply = await queueGcode("M410");
        
        return NextResponse.json({
          success: true,
          message: "Quick stop executed",
          reply,
        });

      case "all-off":
        // Turn off everything safely
        try {
          // Turn off heaters
          await queueGcode("M104 S0"); // Hotend off
          await queueGcode("M140 S0"); // Bed off
          
          // Turn off fans
          await queueGcode("M107");
          
          // Disable motors
          await queueGcode("M18");
          
          return NextResponse.json({
            success: true,
            message: "All systems turned off (heaters, fans, motors)",
          });
        } catch (error: Error | unknown) {
          const errorMessage = error instanceof Error ? error.message : "Failed to turn off all systems";
          return NextResponse.json({
            success: false,
            error: errorMessage,
          }, { status: 500 });
        }

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: emergency-stop, quick-stop, all-off",
          },
          { status: 400 }
        );
    }
  } catch (error: Error | unknown) {
    const errorMessage = error instanceof Error ? error.message : "Safety operation failed";
    return NextResponse.json(
      {
        success: false,
        error: errorMessage,
      },
      { status: 500 }
    );
  }
}
