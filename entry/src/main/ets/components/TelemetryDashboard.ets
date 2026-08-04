import { Metrics } from '../utils/ResponsiveMetrics';
import { ErrorHandler } from '../utils/ErrorHandler';
import { DiagnosticError, TelemetrySnapshot } from '../model/Types';
import { TelemetryViewModel, initialSnapshot } from '../viewmodel/TelemetryViewModel';
import { TelemetryService } from '../services/TelemetryService';

@Component
export struct TelemetryDashboard {
  @Prop metrics: Metrics;
  @State private snapshot: TelemetrySnapshot = initialSnapshot();
  @State private lastError: DiagnosticError | undefined = undefined;
  private vm: TelemetryViewModel = new TelemetryViewModel();
  private disposed: boolean = false;

  // Single sink; becomes a no-op once teardown begins so no @State is written post-unmount.
  private sink = (e: DiagnosticError): void => {
    if (this.disposed) {
      return;
    }
    this.lastError = e;
  };

  aboutToAppear(): void {
    this.vm.begin(
      (s: TelemetrySnapshot): void => {
        this.snapshot = s; // async Callback -> @State update -> re-render
      },
      this.sink
    );
  }

  aboutToDisappear(): void {
    // MANDATORY teardown: clears the setInterval AND unregisters the thermal callback.
    // disposed=true first so the teardown sink cannot write @State on a dying component.
    this.disposed = true;
    this.vm.end(this.sink);
  }

  @Builder
  metricTile(label: string, value: string, emphasis: boolean) {
    Column({ space: this.metrics.gutter / 2 }) {
      Text(label)
        .fontSize(this.metrics.captionFont)
        .fontColor('#9AA0A6')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(this.metrics.baseFont)
        .fontWeight(FontWeight.Medium)
        .fontColor(emphasis ? '#FF5252' : '#E8EAED')
        .maxLines(1)
    }
    .width('100%')
    .padding(this.metrics.gutter)
    .borderRadius(this.metrics.gutter)
    .backgroundColor('#1C1C1E')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: this.metrics.gutter }) {
        Text('Diagnostics')
          .fontSize(this.metrics.titleFont)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ top: this.metrics.gutter })

        if (!TelemetryService.HIDEBUG_SUPPORTED) {
          Text('CPU/Memory telemetry unavailable on this device.')
            .fontSize(this.metrics.captionFont)
            .fontColor('#FFB74D')
        }

        this.metricTile('Process CPU', `${this.snapshot.processCpuPercent.toFixed(1)} %`, false)
        this.metricTile('System CPU', `${this.snapshot.systemCpuPercent.toFixed(1)} %`,
          this.snapshot.systemCpuPercent >= 85)
        this.metricTile('Mem Pressure', `${this.snapshot.memPressurePercent.toFixed(1)} %`,
          this.snapshot.memPressurePercent >= 90)
        this.metricTile('Free Memory',
          `${Math.round(this.snapshot.memAvailableKb / 1024)} MB`, false)
        this.metricTile('Thermal', this.snapshot.thermalLabel, this.snapshot.thermalLevel >= 3)
        this.metricTile('Sys Load', this.snapshot.loadLabel, this.snapshot.loadLevel >= 3)
        this.metricTile('Battery',
          this.snapshot.batterySoc >= 0 ? `${this.snapshot.batterySoc} %` : '—', false)

        if (this.lastError !== undefined) {
          Text(`⚠ ${this.lastError.context} [${this.lastError.code}] ${ErrorHandler.describeSerialCode(this.lastError.code)}`)
            .fontSize(this.metrics.captionFont)
            .fontColor('#FF8A80')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      // Round-safe: keep interactive/text content inside the inscribed square, centered.
      .constraintSize({ maxWidth: this.metrics.isRound ? this.metrics.safeSquareSide : '100%' })
      .width('100%')
      .padding(this.metrics.outerMargin)
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .align(Alignment.Top)
  }
}
