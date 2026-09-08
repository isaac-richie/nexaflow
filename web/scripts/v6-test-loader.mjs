import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const require = createRequire(import.meta.url);
const web = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export function loadV6(path, mocks = {}, globals = {}) {
  const filename = resolve(web, path);
  const source = readFileSync(filename, "utf8");
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, jsx: ts.JsxEmit.ReactJSX, esModuleInterop: true } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(compiled, { module, exports: module.exports, console, setTimeout, clearTimeout, URLSearchParams, process: { env: {} },
    require: name => {
      if (name in mocks) return mocks[name];
      if (name.startsWith(".")) return loadV6(resolve(dirname(filename), /\.[cm]?tsx?$/.test(name) ? name : name + ".ts"), mocks);
      return require(name);
    },
    ...globals,
  }, { filename });
  return module.exports;
}
