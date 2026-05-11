import { eventHandler } from 'h3';
import { list } from '@vercel/blob';
import { layout, sidebar } from '../../utils/layout';

export default eventHandler(async () => {
  // Fetch reports for SSR
  let reports: Array<{ id: string; url: string; pathname: string; size: number; uploadedAt: Date }> = [];

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

  const reportListHtml = reports.length === 0
    ? `<div class="p-6 text-center text-txt-tertiary"><p class="text-sm">No reports yet</p></div>`
    : `<div class="divide-y divide-midnight-border">
        ${reports.map(r => `
          <a href="/admin/report/${r.id}" class="block px-4 py-3 hover:bg-midnight-hover transition-colors">
            <div class="flex justify-between items-start">
              <span class="font-mono text-xs text-txt-primary truncate flex-1">${r.id}</span>
              <span class="text-[10px] text-txt-tertiary ml-2">${(r.size / 1024).toFixed(1)}KB</span>
            </div>
            <div class="text-[11px] text-txt-tertiary mt-1">
              ${new Date(r.uploadedAt).toLocaleDateString()} ${new Date(r.uploadedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </div>
          </a>
        `).join('')}
      </div>`;

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
          <p class="text-xs text-txt-tertiary">Error reports from users</p>
        </header>
        <div class="flex-1 overflow-y-auto scrollbar-thin">
          ${reportListHtml}
        </div>
      </div>

      <!-- Large detail canvas -->
      <div class="flex-1 flex items-center justify-center bg-midnight-surface/30">
        <div class="text-center">
          <div class="w-12 h-12 mx-auto mb-4 rounded-xl bg-midnight-surface border border-midnight-border flex items-center justify-center">
            <svg class="w-6 h-6 text-txt-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
          </div>
          <p class="text-sm text-txt-secondary">Select a report</p>
          <p class="text-xs text-txt-tertiary mt-1">Click a report from the list to view details</p>
        </div>
      </div>
    </main>
  `;

  return layout(content, { title: 'Reports - Talkie Admin' });
});
