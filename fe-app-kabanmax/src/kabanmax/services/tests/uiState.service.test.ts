import { beforeEach, describe, expect, it } from 'vitest';
import { applyUiStateToStore } from '../uiState.service';
import { store } from '../store.service';
import { KabanMax } from '../../types';
import {
  clearLocalActionOverlay,
  setLocalServiceAction,
} from '../localActionOverlay.service';

function createUiState(
  actions: Partial<KabanMax.UiState['actions']> = {},
  capabilities: Partial<KabanMax.UiState['capabilities']> = {},
  kabanmax: Partial<KabanMax.GetStatus> = {},
): KabanMax.UiState {
  return {
    service: {
      kabanmax: {
        running: 0,
        enabled: 1,
        status: 'stopped but enabled',
        busy: 'start',
        ...kabanmax,
      },
      sing_box: {
        running: 0,
        enabled: 1,
        status: 'stopped but enabled',
      },
    },
    capabilities: {
      server_inbounds_enabled_count: 0,
      sections_enabled_count: 0,
      ...capabilities,
    },
    actions: {
      service: [],
      ...actions,
    },
  };
}

describe('applyUiStateToStore', () => {
  beforeEach(() => {
    clearLocalActionOverlay();
    store.reset();
  });

  it('applies service, capability, and running action state before first render', () => {
    applyUiStateToStore(
      createUiState({
        service: [
          {
            success: true,
            running: true,
            kind: 'service',
            action: 'start',
            job_id: 'service-1',
          },
        ],
      }),
    );

    const state = store.get();

    expect(state.serviceState).toMatchObject({
      loading: false,
      failed: false,
      data: {
        kabanmaxEnabled: 1,
        kabanmaxRunning: 0,
        kabanmaxBusy: 'start',
      },
    });
    expect(state.diagnosticsSystemInfo).toMatchObject({
      capabilitiesLoaded: true,
      server_inbounds_enabled_count: 0,
      sections_enabled_count: 0,
    });
    expect(state.diagnosticsActions.start.loading).toBe(false);
  });

  it('clears finished persisted action flags while preserving local enable actions', () => {
    store.set({
      diagnosticsActions: {
        ...store.get().diagnosticsActions,
        start: { loading: true },
        enable: { loading: true },
      },
    });

    applyUiStateToStore(createUiState());

    const state = store.get();

    expect(state.diagnosticsActions.start.loading).toBe(false);
    expect(state.diagnosticsActions.enable.loading).toBe(true);
  });

  it('keeps locally started actions loading until their owner clears them', () => {
    setLocalServiceAction('restart', true);

    applyUiStateToStore(createUiState());

    expect(store.get().diagnosticsActions.restart.loading).toBe(true);

    clearLocalActionOverlay();
    applyUiStateToStore(createUiState());

    expect(store.get().diagnosticsActions.restart.loading).toBe(false);
  });

  it('hands a locally started service action over to the runtime report', () => {
    setLocalServiceAction('restart', true);

    applyUiStateToStore(
      createUiState(
        {
          service: [
            {
              success: true,
              running: true,
              kind: 'service',
              action: 'restart',
              job_id: 'service-1',
            },
          ],
        },
        {},
        { running: 1, status: 'running & enabled', busy: 'restart' },
      ),
    );
    applyUiStateToStore(
      createUiState({}, {}, { running: 1, status: 'running & enabled' }),
    );

    expect(store.get().diagnosticsActions.restart.loading).toBe(false);
  });

  it('reports an apply without claiming the service went down', () => {
    applyUiStateToStore(
      createUiState(
        {},
        {},
        {
          running: 1,
          status: 'running & enabled',
          busy: 'apply',
        },
      ),
    );

    const state = store.get();

    expect(state.serviceState.data).toMatchObject({
      kabanmaxRunning: 1,
      kabanmaxBusy: 'apply',
    });
    expect(state.diagnosticsActions.restart.loading).toBe(false);
  });

  it('carries no operation when the runtime reports none', () => {
    applyUiStateToStore(
      createUiState(
        {},
        {},
        { running: 1, status: 'running & enabled', busy: null },
      ),
    );

    expect(store.get().serviceState.data.kabanmaxBusy).toBeNull();
  });
});
