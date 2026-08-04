import { TelemetryService } from '../services/TelemetryService';
import { ErrorSink } from '../utils/ErrorHandler';
import { TelemetrySnapshot, emptyTelemetry } from '../model/Types';

const POLL_INTERVAL_MS: number = 2000; // low cadence — resource-friendly on wearables

type SnapshotListener = (s: TelemetrySnapshot) => void;

/**
 * Owns the telemetry setInterval and the event listeners. The component holds an instance,
 * calls begin() in aboutToAppear and end() in aboutToDisappear — guaranteeing the interval and
 * every registered callback are torn down together (no leaked 'this', no post-unmount @State writes).
 */
@Observed
export class TelemetryViewModel {
  private readonly service: TelemetryService = new TelemetryService();
  private timerId: number = -1;
  private listener?: SnapshotListener;
  private sink?: ErrorSink;

  begin(onSnapshot: SnapshotListener, sink: ErrorSink): void {
    this.listener = onSnapshot;
    this.sink = sink;
    this.service.start((): void => this.pushSample(), sink);
    // Immediate first sample so the UI is not blank for one interval.
    this.pushSample();
    this.timerId = setInterval((): void => this.pushSample(), POLL_INTERVAL_MS);
  }

  private pushSample(): void {
    if (this.sink === undefined || this.listener === undefined) {
      return;
    }
    const snap: TelemetrySnapshot = this.service.sample(this.sink);
    this.listener(snap);
  }

  end(sink: ErrorSink): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.service.stop(sink);
    this.listener = undefined;
    this.sink = undefined;
  }
}

export function initialSnapshot(): TelemetrySnapshot {
  return emptyTelemetry();
}
