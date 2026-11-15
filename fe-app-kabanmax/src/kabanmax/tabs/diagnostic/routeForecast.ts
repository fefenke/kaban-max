import { executeShellCommand } from '../../../helpers/executeShellCommand';

export interface RouteForecast {
  predicted: {
    status: string;
    reason?: string;
    action?: string;
    outbound?: string;
    rule_index?: number;
  };
  observed?: { status: string; reason?: string };
  verified?: { status: string; requests?: number };
  dns?: { status: string; reason?: string };
  automation?: { status: string; reason?: string };
  assumptions?: string[];
}

export async function requestRouteForecast(
  destination: string,
  source: string,
  port: string,
): Promise<RouteForecast> {
  const response = await executeShellCommand({
    command: '/usr/bin/kabanmax',
    args: ['check_route', destination, source, port],
    timeout: 15000,
  });
  if (response.code)
    throw new Error(response.stderr || 'Route forecast failed');
  const result = JSON.parse(response.stdout) as RouteForecast;
  if (!result?.predicted || typeof result.predicted.status !== 'string') {
    throw new Error('Invalid route forecast response');
  }
  return result;
}

export function formatRouteForecast(result: RouteForecast): string {
  return JSON.stringify(
    {
      ...result,
      observed: result.observed ?? { status: 'unavailable' },
      verified: result.verified ?? { status: 'not_run', requests: 0 },
    },
    null,
    2,
  );
}
