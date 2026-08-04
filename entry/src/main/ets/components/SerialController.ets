import { serialManager } from '@kit.BasicServicesKit';
import { Metrics } from '../utils/ResponsiveMetrics';
import { ErrorHandler } from '../utils/ErrorHandler';
import { DiagnosticError, PortEntry, LogLine, LogDirection, SerialConfig } from '../model/Types';
import { SerialViewModel } from '../viewmodel/SerialViewModel';

@Component
export struct SerialController {
  @Prop metrics: Metrics;
  @State private ports: PortEntry[] = [];
  @State private log: LogLine[] = [];
  @State private lastError: DiagnosticError | undefined = undefined;
  @State private outbound: string = 'AT\r\n';
  @State private streaming: boolean = false;
  @State private selectedBaud: number = serialManager.BaudRates.BAUDRATE_115200;
  // Real tracked-state mirrors of ViewModel fields that build() binds to (a plain @Observed
  // field held privately is NOT a reactive source, so these must be driven from the handlers).
  @State private supported: boolean = false;
  @State private portOpen: boolean = false;
  private vm: SerialViewModel = new SerialViewModel();
  private disposed: boolean = false;

  private sink = (e: DiagnosticError): void => {
    if (this.disposed) {
      return;
    }
    this.lastError = e;
  };

  aboutToAppear(): void {
    this.supported = this.vm.isSupported();
  }

  aboutToDisappear(): void {
    // Cancel the read loop and close the port so no callback outlives the component.
    this.disposed = true;
    this.vm.stopStream();
    this.vm.close(this.sink);
  }

  private appendLine(line: LogLine): void {
    const next: LogLine[] = this.log.concat(line);
    this.log = SerialViewModel.trim(next); // reassign to trigger re-render
  }

  private onScan(): void {
    this.ports = this.vm.scan(this.sink);
    this.appendLine(this.vm.makeLine(LogDirection.INFO, `Found ${this.ports.length} port(s)`));
  }

  private async onOpen(port: PortEntry): Promise<void> {
    const granted: boolean = await this.vm.requestRight(port.portId, this.sink);
    if (!granted) {
      this.appendLine(this.vm.makeLine(LogDirection.ERROR, `Right denied for port ${port.portId}`));
      return;
    }
    this.vm.config = this.buildConfig();
    const ok: boolean = this.vm.openAndConfigure(port.portId, this.sink);
    if (ok) {
      this.portOpen = true; // mirror into tracked state so buttons enable
      this.appendLine(this.vm.makeLine(LogDirection.INFO,
        `Opened ${port.deviceName} @ ${this.selectedBaud} 8N1`));
    }
  }

  private buildConfig(): SerialConfig {
    return {
      baudRate: this.selectedBaud as serialManager.BaudRates,
      dataBits: serialManager.DataBits.DATABIT_8,
      parity: serialManager.Parity.PARITY_NONE,
      stopBits: serialManager.StopBits.STOPBIT_1
    };
  }

  private toggleStream(): void {
    if (this.streaming) {
      this.vm.stopStream();
      this.streaming = false;
      this.appendLine(this.vm.makeLine(LogDirection.INFO, 'Read loop stopped'));
    } else {
      this.streaming = true;
      this.appendLine(this.vm.makeLine(LogDirection.INFO, 'Read loop started'));
      this.vm.startStream((line: LogLine): void => this.appendLine(line), this.sink);
    }
  }

  private async onSend(): Promise<void> {
    await this.vm.send(this.outbound, (line: LogLine): void => this.appendLine(line), this.sink);
  }

  private onClose(): void {
    this.vm.stopStream();
    this.streaming = false;
    this.vm.close(this.sink);
    this.portOpen = false; // mirror into tracked state so buttons disable
    this.appendLine(this.vm.makeLine(LogDirection.INFO, 'Port closed'));
  }

  @Builder
  actionButton(label: string, action: () => void, enabled: boolean) {
    Button(label)
      .fontSize(this.metrics.captionFont)
      .height(this.metrics.baseFont * 2.2)
      .width('100%')
      .backgroundColor(enabled ? '#0A84FF' : '#3A3A3C')
      .enabled(enabled)
      .onClick(action)
  }

  build() {
    Scroll() {
      Column({ space: this.metrics.gutter }) {
        Text('Serial Console')
          .fontSize(this.metrics.titleFont)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ top: this.metrics.gutter })

        if (!this.supported) {
          Text('USB serial (SystemCapability.USB.USBManager.Serial) is not available on this device. Wearables typically lack the USB host stack.')
            .fontSize(this.metrics.captionFont)
            .fontColor('#FFB74D')
            .maxLines(4)
        }

        this.actionButton('Scan Ports', (): void => this.onScan(), this.supported)

        ForEach(this.ports, (p: PortEntry): void => {
          Column({ space: this.metrics.gutter / 2 }) {
            Text(`#${p.portId} ${p.deviceName}`)
              .fontSize(this.metrics.captionFont)
              .fontColor('#E8EAED')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            this.actionButton(p.hasRight ? 'Open' : 'Request + Open',
              (): void => { this.onOpen(p); }, true)
          }
          .width('100%')
          .padding(this.metrics.gutter)
          .backgroundColor('#1C1C1E')
          .borderRadius(this.metrics.gutter)
          .alignItems(HorizontalAlign.Start)
        }, (p: PortEntry): string => `${p.portId}`)

        // Baud selection (drives setAttribute via config).
        Text(`Baud: ${this.selectedBaud}`)
          .fontSize(this.metrics.captionFont)
          .fontColor('#9AA0A6')
        Row({ space: this.metrics.gutter / 2 }) {
          Button('9600')
            .fontSize(this.metrics.captionFont)
            .layoutWeight(1)
            .backgroundColor(this.selectedBaud === serialManager.BaudRates.BAUDRATE_9600 ? '#0A84FF' : '#3A3A3C')
            .onClick((): void => { this.selectedBaud = serialManager.BaudRates.BAUDRATE_9600; })
          Button('115200')
            .fontSize(this.metrics.captionFont)
            .layoutWeight(1)
            .backgroundColor(this.selectedBaud === serialManager.BaudRates.BAUDRATE_115200 ? '#0A84FF' : '#3A3A3C')
            .onClick((): void => { this.selectedBaud = serialManager.BaudRates.BAUDRATE_115200; })
        }
        .width('100%')

        this.actionButton(this.streaming ? 'Stop Read Loop' : 'Start Read Loop',
          (): void => this.toggleStream(), this.portOpen)

        TextInput({ text: this.outbound, placeholder: 'Payload to write' })
          .fontSize(this.metrics.captionFont)
          .height(this.metrics.baseFont * 2.4)
          .backgroundColor('#1C1C1E')
          .fontColor('#FFFFFF')
          .onChange((v: string): void => { this.outbound = v; })

        this.actionButton('Send', (): void => { this.onSend(); }, this.portOpen)
        this.actionButton('Close Port', (): void => this.onClose(), this.portOpen)

        // Stream log
        Column({ space: 2 }) {
          ForEach(this.log, (line: LogLine): void => {
            Text(`[${line.direction}] ${line.text}`)
              .fontSize(this.metrics.captionFont)
              .fontColor(this.lineColor(line.direction))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }, (line: LogLine): string => `${line.seq}`)
        }
        .width('100%')
        .padding(this.metrics.gutter)
        .backgroundColor('#0D0D0D')
        .borderRadius(this.metrics.gutter)
        .alignItems(HorizontalAlign.Start)

        if (this.lastError !== undefined) {
          Text(`⚠ ${this.lastError.context} [${this.lastError.code}] ${ErrorHandler.describeSerialCode(this.lastError.code)}`)
            .fontSize(this.metrics.captionFont)
            .fontColor('#FF8A80')
            .maxLines(3)
        }
      }
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

  private lineColor(dir: LogDirection): string {
    switch (dir) {
      case LogDirection.RX: return '#69F0AE';
      case LogDirection.TX: return '#82B1FF';
      case LogDirection.ERROR: return '#FF8A80';
      default: return '#BDBDBD';
    }
  }
}
