import { eventHandler, getHeader } from 'h3';
import { config } from '../../utils/config';
import { isLocalhost } from '../../utils/github';

export default eventHandler(async (event) => {
  const url = event.node.req.url || '';

  if (isLocalhost(url)) {
    return { isAdmin: true, reason: 'dev_mode' };
  }

  // Check API key
  const authHeader = getHeader(event, 'authorization');
  const apiKey = authHeader?.replace('Bearer ', '');

  if (apiKey && apiKey === config.apiKey) {
    return { isAdmin: true, reason: 'api_key' };
  }

  return { isAdmin: false, reason: 'not_authenticated' };
});
