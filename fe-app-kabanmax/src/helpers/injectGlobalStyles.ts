import { GlobalStyles } from '../styles';

const KABANMAX_GLOBAL_STYLES_ID = 'kabanmax-global-styles';

export function injectGlobalStyles() {
  if (document.getElementById(KABANMAX_GLOBAL_STYLES_ID)) {
    return;
  }

  document.head.insertAdjacentHTML(
    'beforeend',
    `
        <style id="${KABANMAX_GLOBAL_STYLES_ID}">
          ${GlobalStyles}
          .kaban-max-logo { display:inline-block; vertical-align:middle; object-fit:contain;
            border-radius:8px; background:#101114; margin-right:8px; }
          @media(max-width:480px) { .kaban-max-logo { width:36px; height:36px; } }
        </style>
    `,
  );
}
