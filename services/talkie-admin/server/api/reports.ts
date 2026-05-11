import { eventHandler, getHeader, createError } from 'h3';
import { list } from '@vercel/blob';
import { config } from '../utils/config';
import { isLocalhost } from '../utils/github';

export default eventHandler(async (event) => {
  const url = event.node.req.url || '';

  // Allow localhost
  if (!isLocalhost(url)) {
    // Check API key
    const authHeader = getHeader(event, 'authorization');
    const apiKey = authHeader?.replace('Bearer ', '');

    if (!apiKey || apiKey !== config.apiKey) {
      throw createError({ statusCode: 401, statusMessage: 'Unauthorized' });
    }
  }

  try {
    const { blobs } = await list({ prefix: 'reports/' });

    const reports = blobs
      .map(blob => ({
        url: blob.url,
        pathname: blob.pathname,
        size: blob.size,
        uploadedAt: blob.uploadedAt,
      }))
      .sort((a, b) => new Date(b.uploadedAt).getTime() - new Date(a.uploadedAt).getTime());

    return { count: reports.length, reports: reports.slice(0, 50) };
  } catch (error) {
    throw createError({
      statusCode: 500,
      statusMessage: 'Failed to list reports',
      data: { message: error instanceof Error ? error.message : 'Unknown error' }
    });
  }
});
