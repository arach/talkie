import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import {
  agentKitPackageRoot,
  bundledCollectionPaths,
  loadContentCatalog,
} from "./content-catalog.ts";

const sourceRoot = join(agentKitPackageRoot);
const destinationRoot = resolve(
  agentKitPackageRoot,
  "../../../Talkie/Resources/AgentKit",
);
const contentCatalog = loadContentCatalog();
const bundledPaths = bundledCollectionPaths(contentCatalog);

function ensureCleanDirectory(path: string) {
  rmSync(path, { recursive: true, force: true });
  mkdirSync(path, { recursive: true });
}

function copyDirectory(relativePath: string) {
  const source = join(sourceRoot, relativePath);
  if (!existsSync(source)) {
    throw new Error(`Missing source directory: ${source}`);
  }

  const destination = join(destinationRoot, relativePath);
  mkdirSync(dirname(destination), { recursive: true });
  cpSync(source, destination, { recursive: true });
}

ensureCleanDirectory(destinationRoot);

for (const relativePath of bundledPaths) {
  copyDirectory(relativePath);
}

console.log(
  `Synced AgentKit resources (${bundledPaths.join(", ")}) to ${destinationRoot}`,
);
