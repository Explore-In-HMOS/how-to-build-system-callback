import { display } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Callback } from '@kit.BasicServicesKit';
import { ErrorHandler, ErrorSink } from './ErrorHandler';

/** Immutable, density-independent layout metrics derived from the physical display. */
export interface Metrics {
  widthPx: number;
  heightPx: number;
  densityPixels: number;   // vp -> px scale factor (~2.0); vp = px / densityPixels
  densityDPI: number;      // DPI (~320) — NOT the same as densityPixels
  diameterVp: number;      // min(width,height) / densityPixels
  isRound: boolean;
  roundDetectionReliable: boolean;
  // Proportional sizing (all in vp, fonts in fp) — ratios stay constant across watch sizes.
  outerMargin: number;
  gutter: number;
  captionFont: number;
  baseFont: number;
  titleFont: number;
  safeSquareSide: number;  // inscribed square side for round-safe content
  cornerInset: number;     // radial corner inset for round screens
}

type MetricsListener = (m: Metrics) => void;

/**
 * Reads the default Display via getDefaultDisplaySync() (the current, non-deprecated call),
 * derives vp/fp scaling from densityPixels (NOT densityDPI), and detects round vs square.
 *
 * Round detection reality (per verified research):
 *   - API 18+: Display.screenShape (optional) is the ONLY runtime round detector.
 *   - API 12–17: NO runtime shape API exists. We fall back to a deviceType('wearable') + square-aspect
 *     heuristic and flag roundDetectionReliable=false so the UI can prefer resource-qualifier branching.
 *   - We NEVER use CutoutInfo.boundingRects for shape (those are notches/cutouts, not overall shape).
 */
export class ResponsiveMetrics {
  private current: Metrics;
  private listeners: MetricsListener[] = [];
  // Store the exact handler reference so display.off() can unregister the identical function.
  private readonly changeHandler: Callback<number>;
  private registered: boolean = false;

  constructor(sink?: ErrorSink) {
    this.changeHandler = (id: number): void => {
      // The 'change' callback delivers a display ID (number), NOT a Display object.
      // Re-read a fresh snapshot; Display objects are snapshots that do not auto-update.
      const fresh: display.Display | undefined = ErrorHandler.guardSync<display.Display>(
        'display.getDisplayByIdSync',
        () => display.getDisplayByIdSync(id),
        sink
      );
      const source: display.Display | undefined = fresh ??
        ErrorHandler.guardSync<display.Display>(
          'display.getDefaultDisplaySync',
          () => display.getDefaultDisplaySync(),
          sink
        );
      if (source !== undefined) {
        this.current = ResponsiveMetrics.derive(source);
        this.notify();
      }
    };

    const initial: display.Display | undefined = ErrorHandler.guardSync<display.Display>(
      'display.getDefaultDisplaySync',
      () => display.getDefaultDisplaySync(),
      sink
    );
    this.current = initial !== undefined
      ? ResponsiveMetrics.derive(initial)
      : ResponsiveMetrics.fallback();
  }

  get metrics(): Metrics {
    return this.current;
  }

  onChange(listener: MetricsListener): void {
    this.listeners.push(listener);
  }

  /** Register the display listener. Mirror with dispose() in aboutToDisappear. */
  subscribe(sink?: ErrorSink): void {
    if (this.registered) {
      return;
    }
    ErrorHandler.guardSync<void>('display.on(change)',
      () => display.on('change', this.changeHandler), sink);
    this.registered = true;
  }

  /** Unregister with the SAME handler reference used in subscribe(). */
  dispose(sink?: ErrorSink): void {
    if (!this.registered) {
      return;
    }
    ErrorHandler.guardSync<void>('display.off(change)',
      () => display.off('change', this.changeHandler), sink);
    this.registered = false;
    this.listeners = [];
  }

  private notify(): void {
    this.listeners.forEach((l: MetricsListener): void => l(this.current));
  }

  private static detectRound(d: display.Display): boolean {
    // screenShape is the ONLY runtime shape API and exists only @since 18 (optional).
    // On API 12–17 the property is simply absent, so a plain undefined-guard is the correct
    // and sufficient gate — a SystemCapability check would prove nothing about its presence.
    const shape: display.ScreenShape | undefined = d.screenShape;
    if (shape !== undefined) {
      return shape === display.ScreenShape.ROUND;
    }
    // API 12–17 fallback heuristic (NOT authoritative — see class doc).
    const isWear: boolean = deviceInfo.deviceType === 'wearable';
    const squareAspect: boolean = d.width > 0 && Math.abs(d.width - d.height) <= 2;
    return isWear && squareAspect;
  }

  private static isReliable(d: display.Display): boolean {
    return d.screenShape !== undefined;
  }

  private static derive(d: display.Display): Metrics {
    const density: number = d.densityPixels > 0 ? d.densityPixels : 1.0;
    const widthVp: number = d.width / density;
    const heightVp: number = d.height / density;
    const diameterVp: number = Math.min(widthVp, heightVp);
    const isRound: boolean = ResponsiveMetrics.detectRound(d);

    return {
      widthPx: d.width,
      heightPx: d.height,
      densityPixels: density,
      densityDPI: d.densityDPI,
      diameterVp: diameterVp,
      isRound: isRound,
      roundDetectionReliable: ResponsiveMetrics.isReliable(d),
      outerMargin: Math.round(diameterVp * 0.06),
      gutter: Math.round(diameterVp * 0.04),
      captionFont: Math.round(diameterVp * 0.046),
      baseFont: Math.round(diameterVp * 0.060),
      titleFont: Math.round(diameterVp * 0.088),
      safeSquareSide: Math.round(diameterVp / Math.sqrt(2)),
      cornerInset: Math.round(diameterVp * (1 - 1 / Math.sqrt(2)) / 2)
    };
  }

  private static fallback(): Metrics {
    // Conservative 466x466 @2.0 baseline if the display read failed entirely.
    const diameterVp: number = 233;
    return {
      widthPx: 466, heightPx: 466, densityPixels: 2.0, densityDPI: 320,
      diameterVp: diameterVp, isRound: true, roundDetectionReliable: false,
      outerMargin: 14, gutter: 9, captionFont: 11, baseFont: 14, titleFont: 21,
      safeSquareSide: Math.round(diameterVp / Math.sqrt(2)),
      cornerInset: Math.round(diameterVp * (1 - 1 / Math.sqrt(2)) / 2)
    };
  }
}
