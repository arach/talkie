/**
 * TalkieReporter - Cloudflare Worker for receiving error reports from Talkie apps
 *
 * Endpoints:
 *   POST /report - Submit a new report
 *   GET  /report/:id - Retrieve a report (for debugging)
 *   GET  /reports - List recent reports (for debugging)
 */

export interface Env {
  REPORTS: R2Bucket;
  API_KEY: string;  // Required: set via `wrangler secret put API_KEY`
  RATE_LIMIT_KV?: KVNamespace;  // Optional: for rate limiting
}

// Simple in-memory rate limiting (resets on worker restart, but good enough)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 10;  // Max 10 reports per hour per IP
const RATE_LIMIT_WINDOW = 60 * 60 * 1000;  // 1 hour in ms

function checkRateLimit(ip: string): { allowed: boolean; remaining: number } {
  const now = Date.now();
  const record = rateLimitMap.get(ip);

  if (!record || now > record.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_LIMIT_WINDOW });
    return { allowed: true, remaining: RATE_LIMIT_MAX - 1 };
  }

  if (record.count >= RATE_LIMIT_MAX) {
    return { allowed: false, remaining: 0 };
  }

  record.count++;
  return { allowed: true, remaining: RATE_LIMIT_MAX - record.count };
}

// Report structure from Talkie apps
interface TalkieReport {
  id: string;
  timestamp: string;
  system: {
    os: string;
    osVersion: string;
    chip: string;
    memory: string;
    locale?: string;
  };
  apps: {
    talkie?: AppInfo;
    live?: AppInfo;
    engine?: AppInfo;
  };
  context: {
    source: 'talkie' | 'live' | 'engine';  // Which app submitted
    connectionState?: string;
    lastError?: string;
    userDescription?: string;
  };
  logs: string[];  // Recent log lines (already anonymized by client)
  performance?: {
    [key: string]: unknown;
  };
}

interface AppInfo {
  running: boolean;
  pid: number | null;
  version: string | null;
  uptime?: number;  // seconds
  memoryMB?: number;
}

// Validation: ensure no obvious PII
function validateReport(report: TalkieReport): { valid: boolean; error?: string } {
  // Check required fields
  if (!report.id || !report.timestamp || !report.system || !report.apps || !report.context) {
    return { valid: false, error: 'Missing required fields' };
  }

  // Check for obvious PII patterns in logs (emails, paths with usernames, etc.)
  const piiPatterns = [
    /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g,  // Email
    /\/Users\/[^\/\s]+/g,  // macOS user paths (should be anonymized)
  ];

  const logsString = report.logs.join('\n');
  for (const pattern of piiPatterns) {
    if (pattern.test(logsString)) {
      return { valid: false, error: 'Logs contain potential PII - please anonymize' };
    }
  }

  return { valid: true };
}

// Generate a short ID for the report
function generateShortId(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  // Removed ambiguous chars
  let id = '';
  for (let i = 0; i < 8; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS headers for browser requests (if needed later)
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    // Handle preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      // POST /report - Submit a new report
      if (request.method === 'POST' && path === '/report') {
        // API Key check
        const authHeader = request.headers.get('Authorization');
        const apiKey = authHeader?.replace('Bearer ', '');
        if (!apiKey || apiKey !== env.API_KEY) {
          return new Response(JSON.stringify({ error: 'Unauthorized' }), {
            status: 401,
            headers: { 'Content-Type': 'application/json', ...corsHeaders },
          });
        }

        // Rate limiting
        const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
        const rateLimit = checkRateLimit(clientIP);
        if (!rateLimit.allowed) {
          return new Response(JSON.stringify({
            error: 'Rate limit exceeded',
            retryAfter: '1 hour',
          }), {
            status: 429,
            headers: {
              'Content-Type': 'application/json',
              'X-RateLimit-Remaining': '0',
              ...corsHeaders,
            },
          });
        }

        const report = await request.json() as TalkieReport;

        // Validate
        const validation = validateReport(report);
        if (!validation.valid) {
          return new Response(JSON.stringify({ error: validation.error }), {
            status: 400,
            headers: { 'Content-Type': 'application/json', ...corsHeaders },
          });
        }

        // Generate short ID if not provided or use provided
        const reportId = report.id || generateShortId();
        const key = `${new Date().toISOString().split('T')[0]}/${reportId}.json`;

        // Store in R2
        await env.REPORTS.put(key, JSON.stringify(report, null, 2), {
          customMetadata: {
            source: report.context.source,
            timestamp: report.timestamp,
          },
        });

        return new Response(JSON.stringify({
          success: true,
          id: reportId,
          key: key,
        }), {
          status: 201,
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
        });
      }

      // GET /report/:id - Retrieve a report
      if (request.method === 'GET' && path.startsWith('/report/')) {
        const id = path.replace('/report/', '');

        // Search for the report (could be in any date folder)
        const list = await env.REPORTS.list();
        const match = list.objects.find(obj => obj.key.includes(id));

        if (!match) {
          return new Response(JSON.stringify({ error: 'Report not found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json', ...corsHeaders },
          });
        }

        const object = await env.REPORTS.get(match.key);
        if (!object) {
          return new Response(JSON.stringify({ error: 'Report not found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json', ...corsHeaders },
          });
        }

        return new Response(object.body, {
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
        });
      }

      // GET /reports - List recent reports
      if (request.method === 'GET' && path === '/reports') {
        const list = await env.REPORTS.list({ limit: 50 });
        const reports = list.objects.map(obj => ({
          key: obj.key,
          uploaded: obj.uploaded,
          size: obj.size,
          metadata: obj.customMetadata,
        }));

        return new Response(JSON.stringify({ reports }), {
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
        });
      }

      // GET / - Health check
      if (request.method === 'GET' && path === '/') {
        return new Response(JSON.stringify({
          service: 'talkie-reporter',
          status: 'ok',
          timestamp: new Date().toISOString(),
        }), {
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
        });
      }

      return new Response(JSON.stringify({ error: 'Not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      });

    } catch (error) {
      console.error('Error:', error);
      return new Response(JSON.stringify({
        error: 'Internal server error',
        message: error instanceof Error ? error.message : 'Unknown error',
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      });
    }
  },
};
