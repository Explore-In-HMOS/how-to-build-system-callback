import { serialManager } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { ErrorHandler, ErrorSink } from '../utils/ErrorHandler';
import { SerialConfig, PortEntry } from '../model/Types';

const SYSCAP_SERIAL: string = 'SystemCapability.USB.USBManager.Serial';
const READ_BUF_BYTES: number = 8192;   // hardware read cap per verified research
const READ_TIMEOUT_MS: number = 250;   // short timeout keeps the read loop cancellable

export type RxSink = (text: string) => void;

/**
 * Wraps serialManager (module @ohos.usbManager.serial, re-exported by @kit.BasicServicesKit).
 *
 * IMPORTANT (verified): there is NO `serial` namespace and NO `@ohos.serial` module. The real,
 * and only, namespace is `serialManager`, @since 19, syscap SystemCapability.USB.USBManager.Serial.
 * Access is a per-device RIGHT (requestSerialRight), not a manifest permission.
 *
 * Call-shape rules honored below:
 *   - open/close/setAttribute/cancelSerialRight are SYNCHRONOUS (void) — wrapped in try/catch, never awaited.
 *   - read/write are Promise-based over Uint8Array (read <= 8192 B, write <= 128 KB).
 *   - requestSerialRight is a Promise<boolean>.
 */
export class SerialService {
  static readonly SUPPORTED: boolean = canIUse(SYSCAP_SERIAL);

  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
  private readonly encoder: util.TextEncoder = new util.TextEncoder('utf-8');

  private reading: boolean = false;
  private openPortId: number = -1;

  isSupported(): boolean {
    return SerialService.SUPPORTED;
  }

  /** Enumerate ports (no right required to list) and report whether we already hold each right. */
  scan(sink: ErrorSink): PortEntry[] {
    if (!SerialService.SUPPORTED) {
      sink(ErrorHandler.fromCode('serial.scan', 801, 'USB serial capability absent on this device.', 'Unsupported'));
      return [];
    }
    const ports: readonly serialManager.SerialPort[] | undefined =
      ErrorHandler.guardSync<readonly serialManager.SerialPort[]>(
        'serialManager.getPortList', () => serialManager.getPortList(), sink);
    if (ports === undefined) {
      return [];
    }
    const result: PortEntry[] = [];
    ports.forEach((p: serialManager.SerialPort): void => {
      const right: boolean | undefined = ErrorHandler.guardSync<boolean>(
        'serialManager.hasSerialRight', () => serialManager.hasSerialRight(p.portId), sink);
      result.push({ portId: p.portId, deviceName: p.deviceName, hasRight: right ?? false });
    });
    return result;
  }

  /** Ensure access right: system apps already hold it; otherwise prompt via requestSerialRight. */
  async ensureRight(portId: number, sink: ErrorSink): Promise<boolean> {
    const already: boolean | undefined = ErrorHandler.guardSync<boolean>(
      'serialManager.hasSerialRight', () => serialManager.hasSerialRight(portId), sink);
    if (already === true) {
      return true;
    }
    const granted: boolean | undefined = await ErrorHandler.guardAsync<boolean>(
      'serialManager.requestSerialRight',
      () => serialManager.requestSerialRight(portId),
      sink
    );
    return granted === true;
  }

  /** Open (sync void) then apply the line configuration (setAttribute, sync void). */
  open(portId: number, config: SerialConfig, sink: ErrorSink): boolean {
    const opened: boolean = ErrorHandler.guardSync<boolean>('serialManager.open', (): boolean => {
      serialManager.open(portId);
      return true;
    }, sink) === true;
    if (!opened) {
      return false;
    }
    this.openPortId = portId;
    return this.configure(portId, config, sink);
  }

  configure(portId: number, config: SerialConfig, sink: ErrorSink): boolean {
    const attr: serialManager.SerialAttribute = {
      baudRate: config.baudRate,
      dataBits: config.dataBits,
      parity: config.parity,
      stopBits: config.stopBits
    };
    return ErrorHandler.guardSync<boolean>('serialManager.setAttribute', (): boolean => {
      serialManager.setAttribute(portId, attr);
      return true;
    }, sink) === true;
  }

  readAttribute(portId: number, sink: ErrorSink): serialManager.SerialAttribute | undefined {
    return ErrorHandler.guardSync<serialManager.SerialAttribute>(
      'serialManager.getAttribute',
      () => serialManager.getAttribute(portId) as serialManager.SerialAttribute,
      sink
    );
  }

  /** Write a UTF-8 string as Uint8Array (async, Promise). */
  async writeText(portId: number, text: string, sink: ErrorSink): Promise<number> {
    const payload: Uint8Array = this.encoder.encodeInto(text);
    const written: number | undefined = await ErrorHandler.guardAsync<number>(
      'serialManager.write',
      () => serialManager.write(portId, payload, 1000),
      sink
    );
    return written ?? 0;
  }

  /**
   * Continuous, cancellable read loop. Uses a short per-read timeout so stop() takes effect promptly.
   * A 31400006 (timeout) is expected/benign and does NOT terminate the loop or raise a UI error.
   */
  async startReadLoop(portId: number, onData: RxSink, sink: ErrorSink): Promise<void> {
    if (this.reading) {
      return;
    }
    this.reading = true;
    const buffer: Uint8Array = new Uint8Array(READ_BUF_BYTES);

    while (this.reading) {
      try {
        const count: number = await serialManager.read(portId, buffer, READ_TIMEOUT_MS);
        if (count > 0) {
          const slice: Uint8Array = buffer.subarray(0, count);
          onData(this.decoder.decodeToString(slice));
        }
      } catch (e) {
        // Downcast to BusinessError (extends Error, carries .code) — the only cast ArkTS strict mode accepts.
        const be: BusinessError = e as BusinessError;
        if (be.code === 31400006) {
          // Timeout with no data — keep polling so cancellation stays responsive.
          continue;
        }
        // Any other error stops the loop and surfaces to the UI.
        sink(ErrorHandler.format('serialManager.read', be));
        this.reading = false;
      }
    }
  }

  stopReadLoop(): void {
    this.reading = false;
  }

  isReading(): boolean {
    return this.reading;
  }

  /** Stop reading, then close (sync void). */
  close(portId: number, sink: ErrorSink): void {
    this.stopReadLoop();
    ErrorHandler.guardSync<void>('serialManager.close', () => serialManager.close(portId), sink);
    if (this.openPortId === portId) {
      this.openPortId = -1;
    }
  }

  /** Revoke this app's access right (sync void); no-op for system-app default rights. */
  cancelRight(portId: number, sink: ErrorSink): void {
    ErrorHandler.guardSync<void>('serialManager.cancelSerialRight',
      () => serialManager.cancelSerialRight(portId), sink);
  }
}
