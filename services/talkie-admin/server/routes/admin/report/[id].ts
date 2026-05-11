import { eventHandler, getRouterParam } from 'h3';
import { list } from '@vercel/blob';
import { layout, sidebar } from '../../../utils/layout';

export default eventHandler(async (event) => {
  const id = getRouterParam(event, 'id') || '';

  // Fetch all reports for the list
  let reports: Array<{ id: string; size: number; uploadedAt: Date }> = [];
  try {
    const { blobs } = await list({ prefix: 'reports/' });
    reports = blobs
      .map(blob => ({
        url: blob.url,
        pathname: blob.pathname,
        size: blob.size,
        uploadedAt: blob.uploadedAt,
        id: blob.pathname.split('/').pop()?.replace('.json', '') || '',
      }))
      .sort((a, b) => new Date(b.uploadedAt).getTime() - new Date(a.uploadedAt).getTime())
      .slice(0, 50);
  } catch (e) {
    console.error('Failed to fetch reports:', e);
  }

  // Fetch the specific report
  let report: any = null;
  try {
    const { blobs } = await list({ prefix: `reports/${id}` });
    if (blobs.length > 0) {
      const res = await fetch(blobs[0].url);
      report = await res.json();
    }
  } catch (e) {
    console.error('Failed to fetch report:', e);
  }

  if (!report) {
    const content = `
      ${sidebar('reports')}
      <main class="ml-56 p-6">
        <h1 class="text-xl font-semibold text-txt-primary">Report not found</h1>
        <a href="/admin" class="text-accent-blue hover:underline mt-4 inline-block text-sm">Back to reports</a>
      </main>
    `;
    return layout(content, { title: 'Report Not Found' });
  }

  const reportListHtml = reports.map(r => {
    const isActive = r.id === id;
    const classes = isActive ? 'bg-midnight-hover border-l-2 border-accent-orange' : 'hover:bg-midnight-hover';
    const textClass = isActive ? 'text-txt-primary' : 'text-txt-secondary';

    return `
      <a href="/admin/report/${r.id}" class="block px-4 py-3 transition-colors ${classes}">
        <div class="flex justify-between items-start">
          <span class="font-mono text-xs truncate flex-1 ${textClass}">${r.id}</span>
          <span class="text-[10px] text-txt-tertiary ml-2">${(r.size / 1024).toFixed(1)}KB</span>
        </div>
        <div class="text-[11px] text-txt-tertiary mt-1">
          ${new Date(r.uploadedAt).toLocaleDateString()} ${new Date(r.uploadedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
        </div>
      </a>
    `;
  }).join('');

  // Build report detail sections
  let sectionsHtml = '';

  // Context section
  sectionsHtml += `
    <section class="bg-midnight-card rounded-xl border border-midnight-border p-4">
      <h3 class="text-xs font-medium text-txt-tertiary uppercase tracking-wider mb-3">Context</h3>
      <div class="space-y-2 text-sm">
        <div class="flex justify-between">
          <span class="text-txt-secondary">Source</span>
          <span class="text-txt-primary font-medium">${report.context?.source || 'Unknown'}</span>
        </div>
        ${report.context?.connectionState ? `
          <div class="flex justify-between">
            <span class="text-txt-secondary">Connection</span>
            <span class="${report.context.connectionState === 'connected' ? 'text-accent-green' : 'text-accent-orange'}">
              ${report.context.connectionState}
            </span>
          </div>
        ` : ''}
        ${report.context?.lastError ? `
          <div class="mt-3 pt-3 border-t border-midnight-border">
            <p class="text-xs text-red-400 font-medium mb-1">Last Error</p>
            <p class="text-sm text-red-300 font-mono bg-red-500/5 rounded p-2">${report.context.lastError}</p>
          </div>
        ` : ''}
      </div>
    </section>
  `;

  // User Description
  if (report.context?.userDescription) {
    sectionsHtml += `
      <section class="bg-midnight-card rounded-xl border border-midnight-border p-4">
        <h3 class="text-xs font-medium text-txt-tertiary uppercase tracking-wider mb-3">User Description</h3>
        <p class="text-sm text-txt-secondary">${report.context.userDescription}</p>
      </section>
    `;
  }

  // System
  if (report.system) {
    sectionsHtml += `
      <section class="bg-midnight-card rounded-xl border border-midnight-border p-4">
        <h3 class="text-xs font-medium text-txt-tertiary uppercase tracking-wider mb-3">System</h3>
        <div class="grid grid-cols-3 gap-4 text-sm">
          <div>
            <p class="text-txt-tertiary text-xs mb-1">Operating System</p>
            <p class="text-txt-primary">${report.system.os || ''} ${report.system.osVersion || ''}</p>
          </div>
          <div>
            <p class="text-txt-tertiary text-xs mb-1">Chip</p>
            <p class="text-txt-primary text-xs font-mono">${report.system.chip || ''}</p>
          </div>
          <div>
            <p class="text-txt-tertiary text-xs mb-1">Memory</p>
            <p class="text-txt-primary">${report.system.memory || ''}</p>
          </div>
        </div>
      </section>
    `;
  }

  // Apps
  if (report.apps) {
    const appsHtml = Object.entries(report.apps).map(([name, info]: [string, any]) => `
      <div class="flex items-center justify-between py-2 border-b border-midnight-border last:border-0">
        <div class="flex items-center gap-2">
          <span class="w-2 h-2 rounded-full ${info.running ? 'bg-accent-green' : 'bg-txt-tertiary'}"></span>
          <span class="text-sm font-medium text-txt-primary capitalize">${name}</span>
          ${info.version ? `<span class="text-xs text-txt-tertiary">v${info.version}</span>` : ''}
        </div>
        ${info.pid ? `<span class="text-xs text-txt-tertiary font-mono">PID ${info.pid}</span>` : ''}
      </div>
    `).join('');

    sectionsHtml += `
      <section class="bg-midnight-card rounded-xl border border-midnight-border p-4">
        <h3 class="text-xs font-medium text-txt-tertiary uppercase tracking-wider mb-3">Applications</h3>
        <div class="space-y-2">${appsHtml}</div>
      </section>
    `;
  }

  // Logs
  if (report.logs && report.logs.length > 0) {
    sectionsHtml += `
      <section class="bg-midnight-card rounded-xl border border-midnight-border p-4">
        <h3 class="text-xs font-medium text-txt-tertiary uppercase tracking-wider mb-3">
          Logs <span class="text-txt-tertiary">(${report.logs.length} entries)</span>
        </h3>
        <div class="bg-midnight-base rounded-lg p-3 max-h-80 overflow-y-auto scrollbar-thin">
          <pre class="text-xs font-mono text-txt-secondary whitespace-pre-wrap">${report.logs.join('\n')}</pre>
        </div>
      </section>
    `;
  }

  const content = `
    ${sidebar('reports')}
    <main class="ml-56 flex h-screen">
      <!-- Narrow list panel -->
      <div class="w-72 border-r border-midnight-border flex flex-col bg-midnight-base">
        <header class="p-4 border-b border-midnight-border">
          <div class="flex items-center justify-between mb-1">
            <h1 class="text-sm font-semibold text-txt-primary">Reports</h1>
            <span class="text-xs text-txt-tertiary bg-midnight-surface px-2 py-0.5 rounded">${reports.length}</span>
          </div>
        </header>
        <div class="flex-1 overflow-y-auto scrollbar-thin">
          <div class="divide-y divide-midnight-border">${reportListHtml}</div>
        </div>
      </div>

      <!-- Large detail canvas -->
      <div class="flex-1 overflow-y-auto scrollbar-thin bg-midnight-surface/20">
        <div class="p-6 max-w-4xl">
          <header class="mb-6">
            <div class="flex items-center gap-2 text-txt-tertiary text-xs mb-2">
              <a href="/admin" class="hover:text-txt-secondary">&larr; All Reports</a>
            </div>
            <h1 class="text-lg font-semibold text-txt-primary font-mono">${id}</h1>
            <p class="text-sm text-txt-secondary mt-1">${new Date(report.timestamp).toLocaleString()}</p>
          </header>
          <div class="space-y-4">${sectionsHtml}</div>
        </div>
      </div>
    </main>
  `;

  return layout(content, { title: `Report ${id} - Talkie Admin` });
});
