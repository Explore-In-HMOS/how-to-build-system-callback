import { hidebug } from '@kit.PerformanceAnalysisKit';
import { thermal } from '@kit.BasicServicesKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { Callback } from '@kit.BasicServicesKit';
import { ErrorHandler, ErrorSink } from '../utils/ErrorHandler';
import { TelemetrySnapshot, emptyTelemetry, thermalLabel, loadLabel } from '../model/Types';

const SYSCAP_HIDEBUG: string = 'SystemCapability.HiviewDFX.HiProfiler.HiDebug';
const SYSCAP_THERMAL: string = 'SystemCapability.PowerManager.ThermalManager';
const SYSCAP_BATTERY: string = 'SystemCapability.PowerManager.BatteryManager.Core';

/**
 * The REAL telemetry stack.
 *   CPU     -> hidebug.getCpuUsage() / getSystemCpuUsage()
 *   Memory  -> hidebug.getSystemMemInfo() (cheap /proc/meminfo read)
 *   Thermal -> thermal.getLevel() (synchronous) + registerThermalLevelCallback
 *   Load    -> DERIVED locally from CPU/memory/thermal.
 *
 * NOTE (verified against the SDK at build time): there is NO public `systemLoad` module exported by
 * @kit.BackgroundTasksKit (or resolvable in this SDK), and even where it exists it only emits a coarse
 * SystemLoadLevel enum — never raw CPU%/memory/thermal. Rather than depend on an unresolved API, we
 * synthesize a 0..3 (LOW/NORMAL/MEDIUM/HIGH) pressure level from the real signals we already read.
 *
 * All SystemCapabilities are canIUse-guarded so the dashboard degrades gracefully on lite wearables.
 * getSystemMemInfo/getCpuUsage are cheap; we deliberately avoid getPss/getAppNativeMemInfo (smaps) on
 * the UI thread. Poll cadence is set by the caller (low, e.g. 2 s) via setInterval.
 */
export class TelemetryService {
  // Cached, event-driven value so the poll does not have to re-read the thermal level.
  private lastThermal: number = -1;

  private thermalCb?: Callback<thermal.ThermalLevel>;
  private thermalSubscribed: boolean = false;

  static readonly HIDEBUG_SUPPORTED: boolean = canIUse(SYSCAP_HIDEBUG);
  static readonly THERMAL_SUPPORTED: boolean = canIUse(SYSCAP_THERMAL);
  static readonly BATTERY_SUPPORTED: boolean = canIUse(SYSCAP_BATTERY);

  /** Register the event-driven thermal listener. Mirror with stop() in aboutToDisappear. */
  start(onLevelChange: () => void, sink: ErrorSink): void {
    if (TelemetryService.THERMAL_SUPPORTED) {
      this.thermalCb = (level: thermal.ThermalLevel): void => {
        this.lastThermal = level;
        onLevelChange();
      };
      const cb: Callback<thermal.ThermalLevel> = this.thermalCb;
      ErrorHandler.guardSync<void>('thermal.registerThermalLevelCallback',
        () => thermal.registerThermalLevelCallback(cb), sink);
      this.thermalSubscribed = true;
      // Seed with a synchronous read (thermal.getLevel is synchronous).
      const seed: thermal.ThermalLevel | undefined = ErrorHandler.guardSync<thermal.ThermalLevel>(
        'thermal.getLevel', () => thermal.getLevel(), sink);
      if (seed !== undefined) {
        this.lastThermal = seed;
      }
    }
  }

  /** Cheap synchronous sample intended for a low-cadence setInterval poll. */
  sample(sink: ErrorSink): TelemetrySnapshot {
    const snap: TelemetrySnapshot = emptyTelemetry();

    if (TelemetryService.HIDEBUG_SUPPORTED) {
      const proc: number | undefined = ErrorHandler.guardSync<number>(
        'hidebug.getCpuUsage', () => hidebug.getCpuUsage(), sink);
      if (proc !== undefined) {
        snap.processCpuPercent = Math.round(proc * 1000) / 10;
      }
      // getSystemCpuUsage can throw 11400104 if system CPU status is abnormal — guarded.
      const sys: number | undefined = ErrorHandler.guardSync<number>(
        'hidebug.getSystemCpuUsage', () => hidebug.getSystemCpuUsage(), sink);
      if (sys !== undefined) {
        snap.systemCpuPercent = Math.round(sys * 1000) / 10;
      }
      const mem: hidebug.SystemMemInfo | undefined = ErrorHandler.guardSync<hidebug.SystemMemInfo>(
        'hidebug.getSystemMemInfo', () => hidebug.getSystemMemInfo(), sink);
      if (mem !== undefined) {
        // Fields are bigint KB — convert to number for UI math.
        const total: number = Number(mem.totalMem);
        const avail: number = Number(mem.availableMem);
        snap.memTotalKb = total;
        snap.memAvailableKb = avail;
        snap.memPressurePercent = total > 0
          ? Math.round(((total - avail) / total) * 1000) / 10
          : 0;
      }
    }

    snap.thermalLevel = this.lastThermal;
    snap.thermalLabel = thermalLabel(this.lastThermal);

    // Derived load pressure (0..3) from the real signals above.
    const loadLevel: number = TelemetryService.deriveLoad(
      snap.systemCpuPercent, snap.memPressurePercent, snap.thermalLevel);
    snap.loadLevel = loadLevel;
    snap.loadLabel = loadLabel(loadLevel);

    if (TelemetryService.BATTERY_SUPPORTED) {
      // batterySOC is a synchronous read-only namespace const (no getter call, no permission).
      snap.batterySoc = batteryInfo.batterySOC;
    }

    snap.updatedAt = Date.now();
    return snap;
  }

  /** Synthesize a coarse 0..3 pressure level (LOW/NORMAL/MEDIUM/HIGH) from real metrics. */
  private static deriveLoad(systemCpuPercent: number, memPressurePercent: number, thermalLevel: number): number {
    const cpuScore: number = systemCpuPercent >= 90 ? 3 : systemCpuPercent >= 70 ? 2 : systemCpuPercent >= 40 ? 1 : 0;
    const memScore: number = memPressurePercent >= 90 ? 3
      : memPressurePercent >= 75 ? 2
        : memPressurePercent >= 50 ? 1 : 0;
    const thermScore: number = thermalLevel >= 3 ? 3 : thermalLevel >= 2 ? 2 : thermalLevel >= 1 ? 1 : 0;
    return Math.max(cpuScore, Math.max(memScore, thermScore));
  }

  /** Unregister the thermal listener. */
  stop(sink: ErrorSink): void {
    if (this.thermalSubscribed) {
      // unregisterThermalLevelCallback's parameter is Callback<void> and OPTIONAL — omit it to
      // remove the registered listener. (Do NOT pass the Callback<ThermalLevel> register reference:
      // it is not assignable to the Callback<void> slot under ArkTS strict function-type checking.)
      ErrorHandler.guardSync<void>('thermal.unregisterThermalLevelCallback',
        () => thermal.unregisterThermalLevelCallback(), sink);
      this.thermalSubscribed = false;
      this.thermalCb = undefined;
    }
  }
}
