import { theme, TALKIE_ICON_BASE64 } from './config';

export function layout(content: string, options: { title?: string } = {}): string {
  const title = options.title || 'Talkie Admin';

  return `<!DOCTYPE html>
<html lang="en" class="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <link rel="icon" type="image/png" href="${TALKIE_ICON_BASE64}">
  <script src="https://cdn.tailwindcss.com"></script>
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            midnight: {
              base: '${theme.base}',
              surface: '${theme.surface}',
              hover: '${theme.surfaceHover}',
              elevated: '${theme.surfaceElevated}',
              card: '${theme.card}',
              border: '${theme.border}',
              'border-active': '${theme.borderActive}',
            },
            txt: {
              primary: '${theme.textPrimary}',
              secondary: '${theme.textSecondary}',
              tertiary: '${theme.textTertiary}',
            },
            accent: {
              orange: '${theme.accentOrange}',
              purple: '${theme.accentPurple}',
              green: '${theme.accentGreen}',
              blue: '${theme.accentBlue}',
            }
          }
        }
      }
    }
  </script>
  <style>
    body { background: ${theme.base}; color: ${theme.textPrimary}; }
    .scrollbar-thin::-webkit-scrollbar { width: 6px; }
    .scrollbar-thin::-webkit-scrollbar-track { background: transparent; }
    .scrollbar-thin::-webkit-scrollbar-thumb { background: ${theme.border}; border-radius: 3px; }
    .scrollbar-thin::-webkit-scrollbar-thumb:hover { background: ${theme.borderActive}; }
  </style>
</head>
<body class="min-h-screen antialiased">
  ${content}
</body>
</html>`;
}

export function sidebar(active: string): string {
  const navItems = [
    { id: 'reports', href: '/admin', label: 'Reports', icon: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />' },
    { id: 'flags', href: '/admin/flags', label: 'Feature Flags', icon: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 21v-4m0 0V5a2 2 0 012-2h6.5l1 1H21l-3 6 3 6h-8.5l-1-1H5a2 2 0 00-2 2zm9-13.5V9" />' },
    { id: 'settings', href: '/admin/settings', label: 'Settings', icon: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />' },
  ];

  const navHtml = navItems.map(item => {
    const isActive = item.id === active;
    const classes = isActive
      ? 'bg-midnight-hover text-txt-primary'
      : 'text-txt-secondary hover:text-txt-primary hover:bg-midnight-surface';

    return `<li>
      <a href="${item.href}" class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm ${classes}">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">${item.icon}</svg>
        ${item.label}
      </a>
    </li>`;
  }).join('\n');

  return `<aside class="w-56 bg-midnight-base border-r border-midnight-border flex flex-col h-screen fixed left-0 top-0">
  <div class="p-4 border-b border-midnight-border">
    <a href="/admin" class="flex items-center gap-3">
      <img src="${TALKIE_ICON_BASE64}" alt="Talkie" class="w-8 h-8 rounded-lg" />
      <div>
        <div class="font-semibold text-txt-primary">Talkie</div>
        <div class="text-xs text-txt-tertiary">Admin</div>
      </div>
    </a>
  </div>

  <nav class="flex-1 p-2">
    <ul class="space-y-0.5">
      ${navHtml}
    </ul>
  </nav>

  <div class="p-2 border-t border-midnight-border">
    <div class="px-3 py-1.5 bg-accent-orange/10 border border-accent-orange/20 rounded-lg">
      <span class="text-accent-orange text-xs font-medium">Dev Mode</span>
    </div>
  </div>
</aside>`;
}
