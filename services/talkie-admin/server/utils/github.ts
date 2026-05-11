import { config } from './config';

// Cache collaborator status (5 min TTL)
const collaboratorCache = new Map<string, { result: boolean; ts: number }>();

export async function isRepoCollaborator(username: string): Promise<boolean> {
  if (!config.githubToken || !username) return false;

  try {
    const res = await fetch(
      `https://api.github.com/repos/${config.repoOwner}/${config.repoName}/collaborators/${username}`,
      {
        headers: {
          'Authorization': `Bearer ${config.githubToken}`,
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      }
    );
    return res.status === 204;
  } catch {
    return false;
  }
}

export async function isCollaboratorCached(username: string): Promise<boolean> {
  const cached = collaboratorCache.get(username);
  if (cached && Date.now() - cached.ts < 5 * 60 * 1000) return cached.result;

  const result = await isRepoCollaborator(username);
  collaboratorCache.set(username, { result, ts: Date.now() });
  return result;
}

export function isLocalhost(url: string): boolean {
  // Check if URL contains localhost indicators
  // Note: In Nitro, event.node.req.url is just the path, not full URL
  // So we check for common localhost patterns in any form
  const lowerUrl = url.toLowerCase();
  return lowerUrl.includes('localhost') ||
         lowerUrl.includes('127.0.0.1') ||
         url.startsWith('/'); // Relative paths are from local dev server
}
