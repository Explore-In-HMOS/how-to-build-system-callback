import { serialManager } from '@kit.BasicServicesKit';

/** Normalized, UI-bindable error produced by ErrorHandler from any BusinessError/Error. */
export interface DiagnosticError {
  code: number;
  message: string;
  name: string;
  context: string;
  timestamp: number;
}

/** One immutable telemetry sample. All raw numbers come from REAL APIs (hidebug/thermal/batteryInfo). */
export interface TelemetrySnapshot {
  processCpuPercent: number;   // hidebug.getCpuUsage() * 100
  systemCpuPercent: number;    // hidebug.getSystemCpuUsage() * 100
  memTotalKb: number;          // hidebug.getSystemMemInfo().totalMem (bigint KB -> number)
  memAvailableKb: number;      // hidebug.getSystemMemInfo().availableMem
  memPressurePercent: number;  // derived: (total - available) / total * 100
  thermalLevel: number;        // thermal.getLevel()
  thermalLabel: string;
  loadLevel: number;           // derived pressure level (0..3) from CPU/memory/thermal
  loadLabel: string;
  batterySoc: number;          // batteryInfo.batterySOC (public field, no permission)
  updatedAt: number;
}

export function emptyTelemetry(): TelemetrySnapshot {
  return {
    processCpuPercent: 0,
    systemCpuPercent: 0,
    memTotalKb: 0,
    memAvailableKb: 0,
    memPressurePercent: 0,
    thermalLevel: -1,
    thermalLabel: '—',
    loadLevel: -1,
    loadLabel: '—',
    batterySoc: -1,
    updatedAt: 0
  };
}

/** thermal.ThermalLevel enum values (COOL=0 .. ESCAPE=7). */
export function thermalLabel(level: number): string {
  switch (level) {
    case 0: return 'COOL';
    case 1: return 'NORMAL';
    case 2: return 'WARM';
    case 3: return 'HOT';
    case 4: return 'OVERHEATED';
    case 5: return 'WARNING';
    case 6: return 'EMERGENCY';
    case 7: return 'ESCAPE';
    default: return 'UNKNOWN';
  }
}

/** Derived load-pressure labels (LOW=0, NORMAL=1, MEDIUM=2, HIGH=3; 4..7 retained for headroom). */
export function loadLabel(level: number): string {
  switch (level) {
    case 0: return 'LOW';
    case 1: return 'NORMAL';
    case 2: return 'MEDIUM';
    case 3: return 'HIGH';
    case 4: return 'OVERHEATED';
    case 5: return 'WARNING';
    case 6: return 'EMERGENCY';
    case 7: return 'ESCAPE';
    default: return 'UNKNOWN';
  }
}

/** Treat >= HIGH(3) as elevated pressure (there is no 'highLoad' event — we branch ourselves). */
export function isHighLoad(level: number): boolean {
  return level >= 3;
}

/** User-selectable serial line configuration. */
export interface SerialConfig {
  baudRate: serialManager.BaudRates;
  dataBits: serialManager.DataBits;
  parity: serialManager.Parity;
  stopBits: serialManager.StopBits;
}

export function defaultSerialConfig(): SerialConfig {
  return {
    baudRate: serialManager.BaudRates.BAUDRATE_115200,
    dataBits: serialManager.DataBits.DATABIT_8,
    parity: serialManager.Parity.PARITY_NONE,
    // CAUTION: STOPBIT_1's numeric value is 0, STOPBIT_2 is 1 — always use the named constant.
    stopBits: serialManager.StopBits.STOPBIT_1
  };
}

export interface PortEntry {
  portId: number;
  deviceName: string;
  hasRight: boolean;
}

export enum LogDirection { RX = 'RX', TX = 'TX', INFO = 'INFO', ERROR = 'ERR' }

export interface LogLine {
  seq: number;
  direction: LogDirection;
  text: string;
  at: number;
}
