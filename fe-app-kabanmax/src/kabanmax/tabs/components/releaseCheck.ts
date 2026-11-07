import { executeShellCommand } from '../../../helpers/executeShellCommand';

export interface ReleaseCheck {
  success: boolean;
  installed?: string;
  latest?: string;
  update_available?: boolean;
  release?: string;
  core_installed?: string;
  core_latest?: string;
  message?: string;
}

export function releaseAction(state: ReleaseCheck | null): 'check' | 'install' {
  return state?.success && state.update_available ? 'install' : 'check';
}

export async function checkRelease(): Promise<ReleaseCheck> {
  const reply = await executeShellCommand({
    command: '/usr/bin/kabanmax',
    args: ['release_check'],
    timeout: 75000,
  });
  const state = JSON.parse(reply.stdout || '{}') as ReleaseCheck;
  if (reply.code || !state.success) {
    throw new Error(state.message || reply.stderr || _('Failed to execute'));
  }
  return state;
}
