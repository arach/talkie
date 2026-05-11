import { serve } from '@hono/node-server';
import app from '../api/_lib/app.js';

// Start server
const port = parseInt(process.env.PORT || '8787');
console.log(`talkie.to starting on http://localhost:${port}`);

serve({ fetch: app.fetch, port });

export default app;
