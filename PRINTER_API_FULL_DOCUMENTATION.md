# 3D Printer API — Full Documentation

Summary
-------
- Purpose: REST API to control a Marlin-based 3D printer from this Next.js app.
- Transport: local server (development) communicating with printer via /dev/ttyUSB0 using shell commands.

Important serial notes
----------------------
- Configure the serial port once (prevents DTR reset which reboots Marlin):

  sudo stty -F /dev/ttyUSB0 115200 raw -echo -hupcl

  - `-hupcl` disables hangup-on-close (prevents DTR toggling/reset when opening/closing the device).

- Always send commands with a newline. Example:

  printf "M105\n" | sudo tee /dev/ttyUSB0

- You can read printer responses in another terminal with:

  sudo cat /dev/ttyUSB0

- If you don't want to use `sudo` for each command, add a sudoers rule (example):

  jonjon ALL=(ALL) NOPASSWD: /usr/bin/tee /dev/ttyUSB*

  After adding the user to `dialout` you can remove the need for sudo (requires re-login):

  sudo usermod -a -G dialout jonjon

How the app communicates (high level)
------------------------------------
- The server-side serial module configures the port once with `stty -hupcl` and then sends G-code via `printf "<GCODE>\n" | sudo tee /dev/ttyUSB0`.
- Responses are read by spawning `cat` on the device for a short timeout; the API returns the printer's `ok`/status lines.

Files and helpers
-----------------
- `app/api/printer/serial.ts`: core serial helper — configures port, sends G-code, reads responses.
- `app/api/printer/*.route.ts`: API route controllers (temperature, motion, extruder, fan, speed, sd, status, safety).
- `test-printer.sh`: small helper script to exercise the API (in repository root).

Endpoints (quick reference)
--------------------------

**Temperature**: `POST /api/printer/temperature`
- Body: `{ action: "hotend" | "bed" | "hotend-wait" | "bed-wait" | "off", temp?: number }`
- Examples:
  - Set bed to 60°C: `{ "action":"bed", "temp":60 }` — sends `M140 S60` (non-blocking)
  - Set hotend to 200°C and wait: `{ "action":"hotend-wait", "temp":200 }` — sends `M109 S200`
  - Turn off heaters: `{ "action":"off" }` — sends `M104 S0` and `M140 S0`

**Motion**: `POST /api/printer/motion`
- Body: `{ action: "home" | "move" | "motors" | "position", params?: {...} }`
- Examples:
  - Home all axes: `{ "action":"home" }` — sends `G28`
  - Move: `{ "action":"move", params:{ x:10, y:0, z:0, feedrate:1500 } }` — sends `G1 X10 F1500`

**Extruder**: `POST /api/printer/extruder`
- Actions: `extrude`, `retract`, `mode` (absolute/relative)
- Example: extrude 10mm: `{ "action":"extrude", "amount":10, "feedrate":1200 }` (sends `G1 E10 F1200`)

**Fan**: `POST /api/printer/fan`
- Actions: `on` with speed (0-255 or percent), `off` (M106 / M107)

**Speed and Flow**: `POST /api/printer/speed`
- Actions: `feed` (`M220`) and `flow` (`M221`) with percentages.

**SD card**: `GET /api/printer/sd?action=list` and `GET /api/printer/sd?action=progress`
- `POST /api/printer/sd` to control SD printing. Body options:
  - `{ action: "init" }` → `M21` (init card)
  - `{ action: "print", filename: "path/to/file.gcode" }` → `M23 <file>` then `M24`
  - `{ action: "pause" }` → `M25`
  - `{ action: "resume" }` → `M24`
  - `{ action: "stop" }` → `M26 S0`
  - `{ action: "delete", filename: "..." }` → `M30 <file>`

**Status**: `GET /api/printer/status` (various commands like `M115`, `M31`, `M119`, `M503` available depending on implementation)

**Safety**: `POST /api/printer/safety` (emergency stop, etc.) — mapped to `M112`, `M410`, or other safety G-codes.

Implementation notes / troubleshooting
------------------------------------
- Avoid opening/closing the serial device repeatedly with tools that toggle DTR (this resets Marlin). Configure the port once with `-hupcl`.
- Use `printf "<GCODE>\n" | sudo tee /dev/ttyUSB0` rather than `echo -e` to avoid shell differences.
- If you see `echo:Unknown command: "-e M140 S60"`, the firmware received the shell flag as data — switch to `printf`.
- If you see a `busy: processing` reply from the printer, it means the firmware is currently executing or managing SD operations; use `M27` to check progress.

Quick commands
--------------
Start server (dev):
```bash
cd /home/jonjon/micheal
npm run dev
```

Heat bed to 60°C:
```bash
curl -X POST http://localhost:3000/api/printer/temperature \
  -H 'Content-Type: application/json' \
  -d '{"action":"bed","temp":60}'
```

List SD files and progress:
```bash
curl "http://localhost:3000/api/printer/sd?action=list" | jq .
curl "http://localhost:3000/api/printer/sd?action=progress" | jq .
```

Stop SD print:
```bash
curl -X POST http://localhost:3000/api/printer/sd \
  -H 'Content-Type: application/json' \
  -d '{"action":"stop"}' | jq .
```

Where to look next
------------------
- `app/api/printer/serial.ts` — see how the port is configured and how commands are sent.
- `app/api/printer/sd/route.ts` — SD endpoints and parsing helpers.
- `test-printer.sh` — quick test script created in repository root.

If you want, I can:
- Export a short `curl` script to start a particular SD file (if there's an idle SD file available).
- Add an endpoint to list full SD directory tree (recursively) if your firmware supports it.

-- End of document
