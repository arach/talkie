import { eventHandler } from 'h3';
import { layout, sidebar } from '../../utils/layout';
import { config } from '../../utils/config';

export default eventHandler(() => {
  const fallbackAdminBadges = config.fallbackAdmins.map(admin =>
    `<span class="text-xs font-mono bg-midnight-surface px-1.5 py-0.5 rounded text-txt-secondary">${admin}</span>`
  ).join('');

  const content = `
    ${sidebar('settings')}
    <main class="ml-56 p-6">
      <header class="mb-6">
        <h1 class="text-lg font-semibold text-txt-primary">Settings</h1>
        <p class="text-sm text-txt-secondary mt-1">Configure admin dashboard</p>
      </header>

      <div class="space-y-4 max-w-2xl">
        <div class="bg-midnight-card rounded-xl border border-midnight-border p-4">
          <h3 class="text-sm font-medium text-txt-primary mb-3">Environment</h3>
          <div class="space-y-2 text-sm">
            <div class="flex justify-between py-2 border-b border-midnight-border">
              <span class="text-txt-secondary">Blob Storage</span>
              <span class="text-txt-primary font-mono text-xs">${process.env.BLOB_READ_WRITE_TOKEN ? 'Configured' : 'Not configured'}</span>
            </div>
            <div class="flex justify-between py-2 border-b border-midnight-border">
              <span class="text-txt-secondary">GitHub Token</span>
              <span class="text-txt-primary font-mono text-xs">${config.githubToken ? 'Configured' : 'Not configured'}</span>
            </div>
            <div class="flex justify-between py-2">
              <span class="text-txt-secondary">Repository</span>
              <span class="text-txt-primary font-mono text-xs">${config.repoOwner}/${config.repoName}</span>
            </div>
          </div>
        </div>

        <div class="bg-midnight-card rounded-xl border border-midnight-border p-4">
          <h3 class="text-sm font-medium text-txt-primary mb-3">Admin Access</h3>
          <p class="text-xs text-txt-secondary">
            Admin access is granted to collaborators of the <span class="font-mono">${config.repoOwner}/${config.repoName}</span> repository.
          </p>
          <div class="mt-3 flex items-center gap-2">
            <span class="text-xs text-txt-tertiary">Fallback admins:</span>
            ${fallbackAdminBadges}
          </div>
        </div>
      </div>
    </main>
  `;

  return layout(content, { title: 'Settings - Talkie Admin' });
});
