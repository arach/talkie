import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

type ContentCollectionKind =
  | "catalog"
  | "knowledge-base"
  | "prompt"
  | "runtime";

type ContentConsumer =
  | "agents"
  | "console-profile"
  | "developers"
  | "sync-script"
  | "validation-script"
  | "workspace-generator"
  | "workspace-tools";

export type AgentKitContentCollection = {
  id: string;
  path: string;
  kind: ContentCollectionKind;
  bundleToApp: boolean;
  description: string;
};

export type AgentKitContentAsset = {
  id: string;
  collection: string;
  path: string;
  title: string;
  consumers: ContentConsumer[];
  description: string;
};

export type AgentKitContentCatalog = {
  version: number;
  description: string;
  collections: AgentKitContentCollection[];
  assets: AgentKitContentAsset[];
};

export const agentKitPackageRoot = resolve(import.meta.dir, "..");
export const agentKitContentCatalogPath = join(
  agentKitPackageRoot,
  "catalogs",
  "content-catalog.json",
);

export function loadContentCatalog(): AgentKitContentCatalog {
  const rawCatalog = readFileSync(agentKitContentCatalogPath, "utf8");
  return JSON.parse(rawCatalog) as AgentKitContentCatalog;
}

export function bundledCollectionPaths(
  catalog: AgentKitContentCatalog,
): string[] {
  return catalog.collections
    .filter((collection) => collection.bundleToApp)
    .map((collection) => collection.path);
}

export function filesInCollection(relativeCollectionPath: string): string[] {
  const absoluteCollectionPath = join(agentKitPackageRoot, relativeCollectionPath);
  return walkFiles(absoluteCollectionPath).map((absolutePath) =>
    relative(agentKitPackageRoot, absolutePath),
  );
}

function walkFiles(directoryPath: string): string[] {
  const entries = readdirSync(directoryPath, { withFileTypes: true })
    .filter((entry) => !entry.name.startsWith("."))
    .sort((left, right) => left.name.localeCompare(right.name));

  const files: string[] = [];

  for (const entry of entries) {
    const entryPath = join(directoryPath, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkFiles(entryPath));
      continue;
    }

    if (entry.isFile() || statSync(entryPath).isFile()) {
      files.push(entryPath);
    }
  }

  return files;
}
