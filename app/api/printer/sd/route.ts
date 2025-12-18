/**
 * SD/TF card control endpoints for 3D printer
 * Handles file listing, print starting/pausing, and progress monitoring
 */

import { NextRequest, NextResponse } from "next/server";
import { initSerialConnection, queueGcode, isPrinterConnected } from "../serial";

/**
 * GET /api/printer/sd
 * List files on SD card or get print progress
 * Query params:
 * - ?action=list (default)
 * - ?action=progress
 * - ?folder=/path (for listing specific folder)
 */
export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const action = searchParams.get("action") || "list";
    const folder = searchParams.get("folder") || "";

    if (!isPrinterConnected()) {
      await initSerialConnection();
    }

    let reply: string[];

    switch (action) {
      case "list":
        // M21 - Initialize SD card
        await queueGcode("M21");
        
        // M20 - List files
        const cmd = folder ? `M20 ${folder}` : "M20";
        reply = await queueGcode(cmd);
        
        const files = parseFileList(reply);
        
        return NextResponse.json({
          success: true,
          files,
          folder,
          raw: reply,
        });

      case "progress":
        // M27 - SD print progress
        reply = await queueGcode("M27");
        const progress = parseProgress(reply);
        
        return NextResponse.json({
          success: true,
          progress,
          raw: reply,
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: list or progress",
          },
          { status: 400 }
        );
    }
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "SD card operation failed";
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
 * POST /api/printer/sd
 * Control SD card printing
 * Body options:
 * - { action: "init" } (M21)
 * - { action: "print", filename: string } (M23 + M24)
 * - { action: "pause" } (M25)
 * - { action: "resume" } (M24)
 * - { action: "stop" } (M26 S0)
 * - { action: "delete", filename: string } (M30)
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action, filename } = body;

    if (!isPrinterConnected()) {
      await initSerialConnection();
    }

    let reply: string[];

    switch (action) {
      case "init":
        // M21 - Initialize SD card
        reply = await queueGcode("M21");
        return NextResponse.json({
          success: true,
          message: "SD card initialized",
          reply,
        });

      case "print":
        // M23 + M24 - Select file and start print
        if (!filename) {
          return NextResponse.json(
            { success: false, error: "filename required" },
            { status: 400 }
          );
        }

        await queueGcode("M21"); // Init SD
        await queueGcode(`M23 ${filename}`); // Select file
        reply = await queueGcode("M24"); // Start print

        return NextResponse.json({
          success: true,
          message: `Started printing: ${filename}`,
          filename,
          reply,
        });

      case "pause":
        // M25 - Pause SD print
        reply = await queueGcode("M25");
        return NextResponse.json({
          success: true,
          message: "Print paused",
          reply,
        });

      case "resume":
        // M24 - Resume SD print
        reply = await queueGcode("M24");
        return NextResponse.json({
          success: true,
          message: "Print resumed",
          reply,
        });

      case "stop":
        // M26 S0 - Reset SD position (stop print)
        reply = await queueGcode("M26 S0");
        return NextResponse.json({
          success: true,
          message: "Print stopped",
          reply,
        });

      case "delete":
        // M30 - Delete file
        if (!filename) {
          return NextResponse.json(
            { success: false, error: "filename required" },
            { status: 400 }
          );
        }

        reply = await queueGcode(`M30 ${filename}`);
        return NextResponse.json({
          success: true,
          message: `Deleted: ${filename}`,
          filename,
          reply,
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action. Use: init, print, pause, resume, stop, delete",
          },
          { status: 400 }
        );
    }
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "SD card operation failed";
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
 * Parse file list from M20 response
 */
function parseFileList(lines: string[]): string[] {
  const files: string[] = [];
  
  for (const line of lines) {
    // Skip headers and "ok" responses
    if (
      line.startsWith("Begin file list") ||
      line.startsWith("End file list") ||
      line.toLowerCase().startsWith("ok") ||
      line.trim() === ""
    ) {
      continue;
    }

    // Extract filename (format varies by firmware)
    const trimmed = line.trim();
    if (trimmed) {
      files.push(trimmed);
    }
  }

  return files;
}

/**
 * Parse progress from M27 response
 */
interface PrintProgress {
  printing: boolean;
  bytesPrinted: number | null;
  totalBytes: number | null;
  percent: number | null;
}

function parseProgress(lines: string[]): PrintProgress {
  const result: PrintProgress = {
    printing: false,
    bytesPrinted: null,
    totalBytes: null,
    percent: null,
  };

  for (const line of lines) {
    // Match patterns like "SD printing byte 1234/5678"
    const match = line.match(/SD printing byte (\d+)\/(\d+)/);
    
    if (match) {
      result.printing = true;
      result.bytesPrinted = parseInt(match[1], 10);
      result.totalBytes = parseInt(match[2], 10);
      
      if (result.totalBytes > 0) {
        result.percent = Math.round((result.bytesPrinted / result.totalBytes) * 100);
      }
    } else if (line.includes("Not SD printing")) {
      result.printing = false;
    }
  }

  return result;
}
