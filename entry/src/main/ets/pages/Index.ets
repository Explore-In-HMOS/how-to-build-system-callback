import { ResponsiveMetrics, Metrics } from '../utils/ResponsiveMetrics';
import { DiagnosticError } from '../model/Types';
import { TelemetryDashboard } from '../components/TelemetryDashboard';
import { SerialController } from '../components/SerialController';

@Entry
@Component
struct Index {
  // Single source of truth for layout metrics; recomputed on display 'change'.
  private responsive: ResponsiveMetrics = new ResponsiveMetrics();
  @State private metrics: Metrics = this.responsive.metrics;
  @State private tab: number = 0; // 0 = telemetry, 1 = serial
  private displayError: DiagnosticError | undefined = undefined;
  private disposed: boolean = false;

  // Log-only-after-teardown sink: never writes @State once the page is disappearing.
  private displaySink = (e: DiagnosticError): void => {
    if (this.disposed) {
      return;
    }
    this.displayError = e;
  };

  aboutToAppear(): void {
    this.responsive.onChange((m: Metrics): void => {
      this.metrics = m; // fresh snapshot -> re-render both features
    });
    // display.on('change', Callback<number>) — payload is an ID; ResponsiveMetrics re-reads internally.
    this.responsive.subscribe(this.displaySink);
  }

  aboutToDisappear(): void {
    // Unregister with the SAME handler reference stored inside ResponsiveMetrics.
    this.disposed = true;
    this.responsive.dispose(this.displaySink);
  }

  @Builder
  tabButton(label: string, index: number) {
    Button(label)
      .fontSize(this.metrics.captionFont)
      .width(this.metrics.diameterVp * 0.36)
      .height(this.metrics.baseFont * 2.2)
      .backgroundColor(this.tab === index ? '#0A84FF' : '#2C2C2E')
      .onClick((): void => { this.tab = index; })
  }

  build() {
    Column() {
      Row({ space: this.metrics.gutter / 2 }) {
        this.tabButton('Telemetry', 0)
        this.tabButton('Serial', 1)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({
        left: this.metrics.outerMargin,
        right: this.metrics.outerMargin,
        top: this.metrics.isRound ? this.metrics.cornerInset : this.metrics.gutter
      })

      if (this.tab === 0) {
        TelemetryDashboard({ metrics: this.metrics })
          .layoutWeight(1)
      } else {
        SerialController({ metrics: this.metrics })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
