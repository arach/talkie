import { eventHandler } from 'h3';
import { layout, sidebar } from '../../utils/layout';

export default eventHandler(() => {
  const flags = [
    { key: 'new_transcription_engine', enabled: true, rollout: 100, description: 'New Whisper-based transcription' },
    { key: 'enhanced_shortcuts', enabled: true, rollout: null, userIds: ['beta-tester-1', 'beta-tester-2'], description: 'Enhanced keyboard shortcuts' },
    { key: 'cloud_sync', enabled: false, rollout: 0, description: 'iCloud sync for memos' },
  ];

  const flagsHtml = flags.map(flag => {
    const statusClass = flag.enabled ? 'bg-accent-green/10 text-accent-green' : 'bg-midnight-surface text-txt-tertiary';
    const statusText = flag.enabled ? 'Enabled' : 'Disabled';

    let extraHtml = '';
    if (flag.rollout !== null) {
      extraHtml = `
        <div class="flex items-center gap-2 mt-2">
          <div class="w-24 h-1.5 bg-midnight-surface rounded-full overflow-hidden">
            <div class="h-full bg-accent-blue rounded-full" style="width: ${flag.rollout}%"></div>
          </div>
          <span class="text-xs text-txt-tertiary">${flag.rollout}% rollout</span>
        </div>
      `;
    }
    if (flag.userIds) {
      const userBadges = flag.userIds.map(uid =>
        `<span class="text-xs font-mono bg-midnight-surface px-1.5 py-0.5 rounded text-txt-secondary">${uid}</span>`
      ).join('');
      extraHtml = `
        <div class="mt-2 flex items-center gap-1">
          <span class="text-xs text-txt-tertiary">User allowlist:</span>
          ${userBadges}
        </div>
      `;
    }

    return `
      <div class="px-4 py-4 flex items-center justify-between">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <span class="font-mono text-sm text-txt-primary">${flag.key}</span>
            <span class="px-2 py-0.5 rounded text-xs font-medium ${statusClass}">${statusText}</span>
          </div>
          <p class="text-xs text-txt-tertiary mt-1">${flag.description}</p>
          ${extraHtml}
        </div>
      </div>
    `;
  }).join('');

  const content = `
    ${sidebar('flags')}
    <main class="ml-56 p-6">
      <header class="mb-6">
        <h1 class="text-lg font-semibold text-txt-primary">Feature Flags</h1>
        <p class="text-sm text-txt-secondary mt-1">Manage feature flags and rollouts</p>
      </header>

      <div class="bg-midnight-card rounded-xl border border-midnight-border">
        <div class="px-4 py-3 border-b border-midnight-border">
          <h2 class="text-sm font-medium text-txt-primary">All Flags</h2>
        </div>
        <div class="divide-y divide-midnight-border">
          ${flagsHtml}
        </div>
      </div>
    </main>
  `;

  return layout(content, { title: 'Feature Flags - Talkie Admin' });
});
