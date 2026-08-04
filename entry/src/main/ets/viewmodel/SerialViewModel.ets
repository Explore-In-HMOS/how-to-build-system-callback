import { SerialService, RxSink } from '../services/SerialService';
import { ErrorSink } from '../utils/ErrorHandler';
import { SerialConfig, PortEntry, LogLine, LogDirection, defaultSerialConfig } from '../model/Types';

const MAX_LOG_LINES: number = 200;

/** Owns the serial session and the rolling stream log. */
@Observed
export class SerialViewModel {
  private readonly service: SerialService = new SerialService();
  private seq: number = 0;
  activePortId: number = -1;
  config: SerialConfig = defaultSerialConfig();

  isSupported(): boolean {
    return this.service.isSupported();
  }

  scan(sink: ErrorSink): PortEntry[] {
    return this.service.scan(sink);
  }

  async requestRight(portId: number, sink: ErrorSink): Promise<boolean> {
    return this.service.ensureRight(portId, sink);
  }

  openAndConfigure(portId: number, sink: ErrorSink): boolean {
    const ok: boolean = this.service.open(portId, this.config, sink);
    if (ok) {
      this.activePortId = portId;
    }
    return ok;
  }

  applyConfig(sink: ErrorSink): boolean {
    if (this.activePortId === -1) {
      return false;
    }
    return this.service.configure(this.activePortId, this.config, sink);
  }

  startStream(onLine: (line: LogLine) => void, sink: ErrorSink): void {
    if (this.activePortId === -1) {
      return;
    }
    const rx: RxSink = (text: string): void => onLine(this.makeLine(LogDirection.RX, text));
    this.service.startReadLoop(this.activePortId, rx, sink);
  }

  stopStream(): void {
    this.service.stopReadLoop();
  }

  isStreaming(): boolean {
    return this.service.isReading();
  }

  async send(text: string, onLine: (line: LogLine) => void, sink: ErrorSink): Promise<void> {
    if (this.activePortId === -1) {
      return;
    }
    const written: number = await this.service.writeText(this.activePortId, text, sink);
    if (written > 0) {
      onLine(this.makeLine(LogDirection.TX, text));
    }
  }

  close(sink: ErrorSink): void {
    if (this.activePortId !== -1) {
      this.service.close(this.activePortId, sink);
      this.activePortId = -1;
    }
  }

  makeLine(direction: LogDirection, text: string): LogLine {
    this.seq += 1;
    return { seq: this.seq, direction: direction, text: text, at: Date.now() };
  }

  static trim(lines: LogLine[]): LogLine[] {
    if (lines.length <= MAX_LOG_LINES) {
      return lines;
    }
    return lines.slice(lines.length - MAX_LOG_LINES);
  }
}
