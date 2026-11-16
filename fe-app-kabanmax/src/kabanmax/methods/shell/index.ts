import { callBaseMethod } from './callBaseMethod';
import { KabanMax } from '../../types';
import { callUbus } from '../../../helpers/callUbus';
import { executeShellCommand } from '../../../helpers/executeShellCommand';

const UI_ACTION_RPC_TIMEOUT_MS = 15000;
const GET_UI_STATE_RPC_TIMEOUT_MS = 3000;
// Covers only the state service still computing its first answer.
const SYSTEM_INFO_UBUS_TIMEOUT_MS = 5000;
const LOG_TEXT_UBUS_TIMEOUT_MS = 15000;
// The router-side Clash transport gives an update a minute; LuCI aborts an RPC after twenty
// seconds unless the timeout is raised.
const CLASH_API_TRANSPORT_TIMEOUT_MS = 65000;
// A check on a slow router takes far longer than an ordinary RPC.
const DIAGNOSTIC_CHECK_RPC_TIMEOUT_MS = 3 * 60 * 1000;

let checkLogsRequest: Promise<KabanMax.MethodResponse<string>> | null = null;
let servedLog: { cursor: number; text: string } | null = null;

type LogTextReply = {
  cursor?: number;
  unchanged?: boolean;
  text?: string;
  next?: number;
  reset?: boolean;
};

// The state service reads the log again only once a line arrived past the cursor it handed out;
// the CLI answers when the service does not run. A log with no KabanMax line yet is empty, not a
// failed read.
async function readLogs(): Promise<KabanMax.MethodResponse<string>> {
  let params: Record<string, unknown> = servedLog
    ? { cursor: servedLog.cursor }
    : {};
  let cursor: number | undefined;
  let text = '';
  let resets = 0;
  for (let page = 0; page < 32; page++) {
    const served = await callUbus<LogTextReply>({
      object: 'kabanmax',
      method: 'log_text',
      params,
      timeoutMs: LOG_TEXT_UBUS_TIMEOUT_MS,
      nobatch: true,
    });
    if (!served.success) return { success: false, error: served.message };
    const reply = served.data;
    if (reply.reset || (cursor !== undefined && reply.cursor !== cursor)) {
      if (++resets > 1) break;
      params = {};
      cursor = undefined;
      text = '';
      continue;
    }
    if (typeof reply.cursor !== 'number') break;
    if (
      reply.unchanged &&
      !servedLog &&
      cursor === undefined &&
      resets++ === 0
    ) {
      params = { cursor: -1 };
      continue;
    }
    if (reply.unchanged && servedLog && cursor === undefined)
      return { success: true, data: servedLog.text };
    if (typeof reply.text !== 'string') break;
    cursor = reply.cursor;
    text += reply.text;
    if (reply.next === undefined) {
      servedLog = { cursor, text };
      return { success: true, data: text };
    }
    if (
      !Number.isInteger(reply.next) ||
      reply.next <= Number(params.offset || 0)
    )
      break;
    params = { cursor, offset: reply.next };
  }

  // The CLI reads the system ring, whose entries are not erased by clear_logs.
  // Falling back to it would resurrect deliberately cleared application lines.
  return { success: false, error: _('Failed to load logs') };
}

function checkLogs() {
  if (!checkLogsRequest) {
    checkLogsRequest = readLogs().finally(() => {
      checkLogsRequest = null;
    });
  }

  return checkLogsRequest;
}

async function clearLogs(): Promise<KabanMax.MethodResponse<string>> {
  // Let an older read finish before discarding its cursor and cached text.
  await checkLogsRequest?.catch(() => undefined);
  const result = await callUbus<{ success?: boolean; message?: string }>({
    object: 'kabanmax',
    method: 'clear_logs',
    timeoutMs: LOG_TEXT_UBUS_TIMEOUT_MS,
    retryUnavailable: false,
  });
  if (!result.success) {
    return { success: false, error: result.message };
  }
  if (!result.data.success) {
    return {
      success: false,
      error: result.data.message || _('Failed to clear logs'),
    };
  }
  servedLog = null;
  return { success: true, data: '' };
}

function parseJsonObjectOutput<T>(output: string): T | null {
  if (!output) {
    return null;
  }

  try {
    return JSON.parse(output) as T;
  } catch (_error) {
    const jsonMatch = output.match(/(\{[\s\S]*\})\s*$/);

    if (!jsonMatch) {
      return null;
    }

    try {
      return JSON.parse(jsonMatch[1]) as T;
    } catch (_jsonError) {
      return null;
    }
  }
}

function parseUiActionStartResult(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
) {
  return parseJsonObjectOutput<KabanMax.UiActionStartResult>(response.stdout);
}

function uiActionFailure(
  response: Awaited<ReturnType<typeof executeShellCommand>>,
  parsedResponse?: { message?: string } | null,
  fallback: string = _('Failed to execute'),
) {
  return {
    success: false,
    error: parsedResponse?.message || response.stderr || fallback,
  } as KabanMax.MethodFailureResponse;
}

function diagnosticCheck<T>(
  method: KabanMax.AvailableMethods,
  args: string[] = [],
) {
  return callBaseMethod<T>(method, args, '/usr/bin/kabanmax', {
    timeout: DIAGNOSTIC_CHECK_RPC_TIMEOUT_MS,
  });
}

export const KabanMaxShellMethods = {
  checkService: async () =>
    diagnosticCheck<KabanMax.ServiceCheckResult>(
      KabanMax.AvailableMethods.CHECK_SERVICE,
    ),
  checkDns: async () =>
    diagnosticCheck<KabanMax.DnsCheckResult>(
      KabanMax.AvailableMethods.CHECK_DNS,
    ),
  checkTraffic: async () =>
    diagnosticCheck<KabanMax.TrafficCheckResult>(
      KabanMax.AvailableMethods.CHECK_TRAFFIC,
    ),
  checkServers: async () =>
    diagnosticCheck<KabanMax.ServersCheckResult>(
      KabanMax.AvailableMethods.CHECK_SERVERS,
    ),
  // The router masks the checks by the same rules as the rest of the report.
  report: async (masked: boolean, checks: string) =>
    diagnosticCheck<KabanMax.ReportAttachments>(
      KabanMax.AvailableMethods.REPORT,
      [masked ? 'masked' : 'raw', checks],
    ),
  clashApi: async (method: string, path: string, body = '') =>
    callBaseMethod<KabanMax.ClashApiResponse>(
      KabanMax.AvailableMethods.CLASH_API,
      [method, path, body],
      '/usr/bin/kabanmax',
      {
        timeout:
          method.toUpperCase() === 'GET' && !/\/(delay|exit)\?/.test(path)
            ? 10000
            : CLASH_API_TRANSPORT_TIMEOUT_MS,
      },
    ),
  clashSummary: async () =>
    callBaseMethod<KabanMax.ClashApiResponse>(
      KabanMax.AvailableMethods.CLASH_SUMMARY,
      [],
      '/usr/bin/kabanmax',
      { timeout: 10000 },
    ),
  // Through the CLI: init script commands wait on procd's per-service lock.
  enable: async () => callBaseMethod<unknown>(KabanMax.AvailableMethods.ENABLE),
  disable: async () =>
    callBaseMethod<unknown>(KabanMax.AvailableMethods.DISABLE),
  checkLogs,
  clearLogs,
  // The state service holds the versions until the installed packages change; the CLI answers
  // when it is not running.
  getSystemInfo: async () => {
    const served = await callUbus<{
      available?: boolean;
      system_info?: KabanMax.GetSystemInfo;
    }>({
      object: 'kabanmax',
      method: 'system_info',
      timeoutMs: SYSTEM_INFO_UBUS_TIMEOUT_MS,
    });

    if (served.success && served.data.available && served.data.system_info) {
      return { success: true as const, data: served.data.system_info };
    }

    return callBaseMethod<KabanMax.GetSystemInfo>(
      KabanMax.AvailableMethods.GET_SYSTEM_INFO,
    );
  },
  // Runs the core itself, so only a page the state service cannot answer asks.
  getCoreFeatures: async () =>
    callBaseMethod<KabanMax.CoreFeatures>(
      KabanMax.AvailableMethods.GET_CORE_FEATURES,
    ),
  getUiState: async () =>
    callBaseMethod<KabanMax.UiState>(
      KabanMax.AvailableMethods.GET_UI_STATE,
      [],
      '/usr/bin/kabanmax',
      { timeout: GET_UI_STATE_RPC_TIMEOUT_MS },
    ),
  serviceActionStart: async (action: KabanMax.ServiceAction) => {
    const response = await executeShellCommand({
      command: '/usr/bin/kabanmax',
      args: [KabanMax.AvailableMethods.SERVICE_ACTION_ASYNC, action],
      timeout: UI_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseUiActionStartResult(response);

    if (
      (response.code ?? 0) !== 0 ||
      !parsedResponse?.success ||
      !parsedResponse.job_id
    ) {
      return uiActionFailure(
        response,
        parsedResponse,
        _('Service action failed'),
      );
    }

    return {
      success: true,
      data: parsedResponse,
    } as KabanMax.MethodSuccessResponse<KabanMax.UiActionStartResult>;
  },
  uiActionAck: async (jobId: string) => {
    const response = await executeShellCommand({
      command: '/usr/bin/kabanmax',
      args: [KabanMax.AvailableMethods.UI_ACTION_ACK, jobId],
      timeout: UI_ACTION_RPC_TIMEOUT_MS,
    });
    const parsedResponse = parseUiActionStartResult(response);

    if ((response.code ?? 0) !== 0 || !parsedResponse?.success) {
      return uiActionFailure(response, parsedResponse);
    }

    return {
      success: true,
      data: parsedResponse,
    } as KabanMax.MethodSuccessResponse<KabanMax.UiActionStartResult>;
  },
};
