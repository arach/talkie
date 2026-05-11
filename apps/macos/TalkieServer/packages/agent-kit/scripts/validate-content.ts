import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import {
  agentKitPackageRoot,
  filesInCollection,
  loadContentCatalog,
} from "./content-catalog.ts";

const catalog = loadContentCatalog();
const errors: string[] = [];

if (!Number.isInteger(catalog.version) || catalog.version < 1) {
  errors.push(`Catalog version must be a positive integer. Received '${catalog.version}'.`);
}

const collectionIds = new Set<string>();
const collectionPaths = new Set<string>();
const collectionsByID = new Map(catalog.collections.map((collection) => [collection.id, collection]));

for (const collection of catalog.collections) {
  if (collectionIds.has(collection.id)) {
    errors.push(`Duplicate collection id '${collection.id}'.`);
  }
  collectionIds.add(collection.id);

  if (collectionPaths.has(collection.path)) {
    errors.push(`Duplicate collection path '${collection.path}'.`);
  }
  collectionPaths.add(collection.path);

  const absoluteCollectionPath = join(agentKitPackageRoot, collection.path);
  if (!existsSync(absoluteCollectionPath)) {
    errors.push(`Collection path is missing: ${collection.path}`);
    continue;
  }

  if (!statSync(absoluteCollectionPath).isDirectory()) {
    errors.push(`Collection path is not a directory: ${collection.path}`);
  }
}

const assetIDs = new Set<string>();
const assetPaths = new Set<string>();

for (const asset of catalog.assets) {
  if (assetIDs.has(asset.id)) {
    errors.push(`Duplicate asset id '${asset.id}'.`);
  }
  assetIDs.add(asset.id);

  if (assetPaths.has(asset.path)) {
    errors.push(`Duplicate asset path '${asset.path}'.`);
  }
  assetPaths.add(asset.path);

  const collection = collectionsByID.get(asset.collection);
  if (!collection) {
    errors.push(`Asset '${asset.id}' references unknown collection '${asset.collection}'.`);
    continue;
  }

  if (!asset.path.startsWith(`${collection.path}/`)) {
    errors.push(
      `Asset '${asset.id}' is cataloged under '${asset.collection}' but path '${asset.path}' does not live inside '${collection.path}/'.`,
    );
  }

  const absoluteAssetPath = join(agentKitPackageRoot, asset.path);
  if (!existsSync(absoluteAssetPath)) {
    errors.push(`Catalog asset is missing on disk: ${asset.path}`);
    continue;
  }

  if (!statSync(absoluteAssetPath).isFile()) {
    errors.push(`Catalog asset is not a file: ${asset.path}`);
  }
}

for (const collection of catalog.collections) {
  const catalogedFiles = new Set(
    catalog.assets
      .filter((asset) => asset.collection === collection.id)
      .map((asset) => asset.path),
  );
  const discoveredFiles = filesInCollection(collection.path);

  for (const discoveredFile of discoveredFiles) {
    if (!catalogedFiles.has(discoveredFile)) {
      errors.push(
        `Managed file '${discoveredFile}' exists on disk but is missing from catalogs/content-catalog.json.`,
      );
    }
  }

  for (const catalogedFile of catalogedFiles) {
    if (!discoveredFiles.includes(catalogedFile)) {
      errors.push(
        `Catalog asset '${catalogedFile}' is listed under '${collection.id}' but was not discovered in that collection.`,
      );
    }
  }
}

if (errors.length > 0) {
  throw new Error(`AgentKit content validation failed:\n- ${errors.join("\n- ")}`);
}

console.log(
  `Validated AgentKit content catalog: ${catalog.collections.length} collections, ${catalog.assets.length} assets.`,
);
