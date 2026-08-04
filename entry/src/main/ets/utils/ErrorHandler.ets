import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DiagnosticError } from '../model/Types';

const DOMAIN: number = 0x0002;
const TAG: string = 'ErrorHandler';

/** Sink pushed by services/components; usually sets an @State field. */
export type ErrorSink = (err: DiagnosticError) => void;

/**
 * Central, strict-ArkTS error boundary. Normalizes every BusinessError/Error into a
 * DiagnosticError (code + message + name + context) and surfaces it to a UI sink.
 * No 'any'/'unknown' escapes; all callbacks are typed arrow functions.
 */
export class ErrorHandler {
  static format(context: string, raw: BusinessError | Error): DiagnosticError {
    // BusinessError.code is the only guaranteed numeric member; message/name are inherited from Error.
    const be: BusinessError = raw as BusinessError;
    const code: number = typeof be.code === 'number' ? be.code : -1;
    const err: DiagnosticError = {
      code: code,
      message: raw.message !== undefined && raw.message.length > 0 ? raw.message : 'Unknown error',
      name: raw.name !== undefined && raw.name.length > 0 ? raw.name : 'Error',
      context: context,
      timestamp: Date.now()
    };
    hilog.error(DOMAIN, TAG, '[%{public}s] code=%{public}d name=%{public}s msg=%{public}s',
      context, err.code, err.name, err.message);
    return err;
  }

  /**
   * Build a DiagnosticError directly from an explicit code/message — used when there is no thrown
   * BusinessError to wrap (e.g. an unsupported-capability short-circuit). Avoids constructing an
   * untyped object literal, which ArkTS strict mode (arkts-no-untyped-obj-literals) rejects.
   */
  static fromCode(context: string, code: number, message: string, name: string = 'Error'): DiagnosticError {
    const err: DiagnosticError = {
      code: code,
      message: message,
      name: name,
      context: context,
      timestamp: Date.now()
    };
    hilog.error(DOMAIN, TAG, '[%{public}s] code=%{public}d name=%{public}s msg=%{public}s',
      context, err.code, err.name, err.message);
    return err;
  }

  /** Guard a synchronous, possibly-throwing call (open/close/setAttribute/getDefaultDisplaySync...). */
  static guardSync<T>(context: string, fn: () => T, sink?: ErrorSink): T | undefined {
    try {
      return fn();
    } catch (e) {
      const err: DiagnosticError = ErrorHandler.format(context, e as BusinessError);
      if (sink !== undefined) {
        sink(err);
      }
      return undefined;
    }
  }

  /** Guard a Promise-returning call (read/write/requestSerialRight/systemLoad.getLevel...). */
  static async guardAsync<T>(context: string, fn: () => Promise<T>, sink?: ErrorSink): Promise<T | undefined> {
    try {
      return await fn();
    } catch (e) {
      const err: DiagnosticError = ErrorHandler.format(context, e as BusinessError);
      if (sink !== undefined) {
        sink(err);
      }
      return undefined;
    }
  }

  /** Human-readable hint for the serialManager 314xxxxx / 401 / 14400005 error family. */
  static describeSerialCode(code: number): string {
    switch (code) {
      case 401: return 'Invalid parameter.';
      case 14400005: return 'Database operation exception (right table).';
      case 31400001: return 'Serial management exception.';
      case 31400002: return 'Access denied — call requestSerialRight() first.';
      case 31400003: return 'portId does not exist.';
      case 31400004: return 'Device is occupied by another process.';
      case 31400005: return 'Port is not opened — call open() first.';
      case 31400006: return 'Data transfer timed out.';
      case 31400007: return 'I/O exception.';
      case 11400104: return 'System CPU status abnormal (hidebug).';
      case 1400001: return 'Invalid display.';
      case 801: return 'Capability not supported on this device.';
      default: return 'Unclassified error.';
    }
  }
}
