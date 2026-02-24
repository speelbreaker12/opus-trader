import path from "node:path";

export type ValidationIssue = {
  code: string;
  message: string;
};

export type ValidationReport = {
  ok: boolean;
  issues: ValidationIssue[];
};

type SchemaNode = {
  const?: string | number | boolean | null;
  enum?: Array<string | number | boolean | null>;
  type?: string | string[];
  minimum?: number;
  maximum?: number;
  minItems?: number;
  maxItems?: number;
  minLength?: number;
  contains?: SchemaNode;
  minContains?: number;
  uniqueItems?: boolean;
  items?: SchemaNode;
  anyOf?: SchemaNode[];
  $ref?: string;
  required?: string[];
  properties?: Record<string, SchemaNode>;
  additionalProperties?: boolean;
};

type SchemaDocument = {
  required?: string[];
  properties?: Record<string, SchemaNode>;
  $defs?: Record<string, SchemaNode>;
};

type Manifest = {
  contract_version?: string;
  registries?: {
    ModeReasonCode?: {
      Kill?: Array<{ code?: string } | string>;
      ReduceOnly?: Array<{ code?: string } | string>;
    };
    OpenPermissionReasonCode?: Array<{ code?: string } | string>;
    TradingMode?: { values?: Array<string> } | Array<string>;
    RiskState?: { values?: Array<string> } | Array<string>;
    F1CertState?: { values?: Array<string> } | Array<string>;
  };
};

const DEFAULT_REASON_MANIFEST: Manifest = (() => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const manifest = require(path.resolve(__dirname, "../../specs/status/status_reason_registries_manifest.json"));
  if (!manifest || typeof manifest !== "object") {
    throw new Error("unable to load status reason registry manifest");
  }
  return manifest as Manifest;
})();

const DEFAULT_STATUS_SCHEMA: SchemaDocument = (() => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const schema = require(path.resolve(__dirname, "../../python/schemas/status_csp_min.schema.json"));
  if (!schema || typeof schema !== "object") {
    throw new Error("unable to load status schema");
  }
  return schema as SchemaDocument;
})();

function toIssue(code: string, message: string): ValidationIssue {
  return { code, message };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && !Number.isNaN(value) && Number.isFinite(value);
}

function resolveSchemaNode(node: SchemaNode, schema: SchemaDocument): SchemaNode {
  if (!node.$ref || !node.$ref.startsWith("#/$defs/")) {
    return node;
  }

  const defs = schema.$defs ?? {};
  const ref = node.$ref.slice("#/$defs/".length);
  return defs[ref] ?? node;
}

function valueTypeName(value: unknown): string {
  return Array.isArray(value) ? "array" : value === null ? "null" : typeof value;
}

function emitPath(parent: string, segment: string | number): string {
  return typeof segment === "number" ? `${parent}[${segment}]` : `${parent}.${segment}`;
}

function coerceCodeList(raw: unknown): string[] {
  if (!Array.isArray(raw)) {
    if (raw && typeof raw === "object" && "values" in raw) {
      const values = (raw as { values?: unknown }).values;
      if (Array.isArray(values)) {
        return coerceCodeList(values);
      }
    }
    return [];
  }

  const out: string[] = [];
  for (const item of raw) {
    if (typeof item === "string") {
      out.push(item);
      continue;
    }

    if (item && typeof item === "object" && "code" in item) {
      const candidate = (item as { code?: unknown }).code;
      if (typeof candidate === "string") {
        out.push(candidate);
      }
    }
  }

  return out;
}

function isSubsequenceOrdered(candidate: string[], universe: string[]): boolean {
  if (candidate.length === 0) {
    return true;
  }

  const allowed = new Set(universe);
  if (!candidate.every((item) => allowed.has(item))) {
    return false;
  }

  const index = new Map<string, number>();
  for (let i = 0; i < universe.length; i++) {
    index.set(universe[i], i);
  }

  const observed = candidate.map((item) => index.get(item));
  for (let i = 1; i < observed.length; i++) {
    if ((observed[i] as number) < (observed[i - 1] as number)) {
      return false;
    }
  }
  return true;
}

function validateNode(value: unknown, schemaNode: SchemaNode, schema: SchemaDocument, path: string): ValidationIssue[] {
  const node = resolveSchemaNode(schemaNode, schema);
  const issues: ValidationIssue[] = [];
  const actualType = valueTypeName(value);

  const ifNode = (node as SchemaNode & { if?: SchemaNode; then?: SchemaNode; else?: SchemaNode }).if;
  const thenNode = (node as SchemaNode & { if?: SchemaNode; then?: SchemaNode }).then;
  const elseNode = (node as SchemaNode & { if?: SchemaNode; then?: SchemaNode; else?: SchemaNode }).else;

  if (ifNode && thenNode) {
    const ifIssues = validateNode(value, ifNode, schema, `${path}::if`);
    if (ifIssues.length === 0) {
      issues.push(...validateNode(value, thenNode, schema, `${path}::then`));
    } else if (elseNode) {
      issues.push(...validateNode(value, elseNode, schema, `${path}::else`));
    }
  }

  const allOf = (node as SchemaNode & { allOf?: SchemaNode[] }).allOf;
  if (allOf && Array.isArray(allOf)) {
    for (const schemaOverride of allOf) {
      issues.push(...validateNode(value, schemaOverride, schema, `${path}::allOf`));
    }
  }

  if (typeof node.const !== "undefined") {
    if (value !== node.const) {
      issues.push(toIssue("SCHEMA", `${path} must equal ${JSON.stringify(node.const)}`));
    }
    return issues;
  }

  if (node.anyOf) {
    const ok = node.anyOf.some((branch) => validateNode(value, branch, schema, path).length === 0);
    if (!ok) {
      issues.push(toIssue("SCHEMA", `${path} does not match any allowed variants`));
    }
    return issues;
  }

  if (node.enum && !node.enum.includes(value as never)) {
    issues.push(toIssue("SCHEMA", `${path} must be one of ${JSON.stringify(node.enum)}`));
  }

  if (node.type) {
    const allowed = Array.isArray(node.type) ? node.type : [node.type];
    const expectedTypes = new Set(allowed.map((entry) => (entry === "integer" ? "number" : entry)));
    const actualType = valueTypeName(value);

    if (!expectedTypes.has(actualType)) {
      issues.push(toIssue("SCHEMA", `${path} expects ${JSON.stringify(allowed)}, got ${actualType}`));
      return issues;
    }

    const isNumericType = allowed.includes("integer") || allowed.includes("number");
    if (isNumericType && isNumber(value) && node.type) {
      if (allowed.includes("integer") && value % 1 !== 0) {
        issues.push(toIssue("SCHEMA", `${path} must be integer`));
      }
      if (node.minimum !== undefined && isNumber(value) && value < node.minimum) {
        issues.push(toIssue("SCHEMA", `${path} minimum is ${node.minimum}`));
      }
    } else if (allowed.includes("number") && node.minimum !== undefined && isNumber(value) && value < node.minimum) {
      issues.push(toIssue("SCHEMA", `${path} minimum is ${node.minimum}`));
    }

    if (isNumericType && node.maximum !== undefined && isNumber(value) && value > node.maximum) {
      issues.push(toIssue("SCHEMA", `${path} maximum is ${node.maximum}`));
    }

    if (allowed.includes("string") && typeof node.minLength === "number") {
      if (typeof value === "string" && value.length < node.minLength) {
        issues.push(toIssue("SCHEMA", `${path} minLength is ${node.minLength}`));
      }
    }

    if ((allowed.includes("array") || node.items) && Array.isArray(value)) {
      const arrayValue = value;
      if (node.uniqueItems && new Set(arrayValue).size !== arrayValue.length) {
        issues.push(toIssue("SCHEMA", `${path} requires unique items`));
      }
      if (typeof node.minItems === "number" && arrayValue.length < node.minItems) {
        issues.push(toIssue("SCHEMA", `${path} minimum is ${node.minItems} items`));
      }
      if (typeof node.maxItems === "number" && arrayValue.length > node.maxItems) {
        issues.push(toIssue("SCHEMA", `${path} maximum is ${node.maxItems} items`));
      }

      if (node.contains && node.contains.const !== undefined) {
        const hasRequired = arrayValue.includes(node.contains.const as never);
        const minContains = node.minContains ?? 1;
        if (!hasRequired && minContains > 0) {
          issues.push(
            toIssue(
              "SCHEMA",
              `${path} must contain ${JSON.stringify(node.contains.const)} at least ${minContains} time(s)`,
            ),
          );
        }
      }

      if (node.contains && typeof node.contains.type === "string") {
        const itemType = node.contains.type === "integer" ? "number" : node.contains.type;
        const invalid = arrayValue.some((entry) => {
          const entryType = entry === null ? "null" : typeof entry;
          return entryType !== itemType;
        });
        if (invalid) {
          issues.push(toIssue("SCHEMA", `${path} contains must be ${JSON.stringify(node.contains.type)} values`));
        }
      }

      if (node.items) {
        const invalidItems =
          node.items.enum !== undefined
            ? arrayValue.filter((item) => typeof item !== "string" || !node.items!.enum!.includes(item as never))
            : [];
        if (invalidItems.length > 0) {
          issues.push(toIssue("SCHEMA", `${path} contains invalid entries: ${JSON.stringify(invalidItems)}`));
        }

        for (let i = 0; i < arrayValue.length; i++) {
          const itemPath = emitPath(path, i);
          const item = arrayValue[i];
          if (typeof node.items.type === "string") {
            const expectedItemType = node.items.type === "integer" ? "number" : node.items.type;
            const actualItemType = valueTypeName(item);
            if (actualItemType !== expectedItemType) {
              issues.push(
                toIssue("SCHEMA", `${itemPath} must be ${JSON.stringify(node.items.type)}: ${JSON.stringify(item)}`),
              );
              continue;
            }
          }

          if (
            node.items.type ||
            node.items.$ref ||
            node.items.enum ||
            node.items.properties ||
            node.items.anyOf ||
            node.items.required ||
            node.items.additionalProperties !== undefined
          ) {
            issues.push(...validateNode(item, node.items, schema, itemPath));
          }
        }
      }

      return issues;
    }

    if (allowed.includes("object") || node.required || node.properties) {
      if (!isObject(value)) {
        issues.push(toIssue("SCHEMA", `${path} expects object, got ${actualType}`));
        return issues;
      }

      const required = node.required ?? [];
      const properties = node.properties ?? {};
      for (const requiredKey of required) {
        if (!(requiredKey in value)) {
          issues.push(toIssue("SCHEMA", `required key missing: ${emitPath(path, requiredKey)}`));
        }
      }

      for (const [objKey, objValue] of Object.entries(value)) {
        const property = properties[objKey];
        if (!property) {
          if (node.additionalProperties === false) {
            issues.push(toIssue("SCHEMA", `${emitPath(path, objKey)} is not allowed`));
          }
          continue;
        }
        issues.push(...validateNode(objValue, property, schema, emitPath(path, objKey)));
      }

      return issues;
    }
  }

  if ((node.properties && isObject(value)) || node.required || node.additionalProperties === false) {
    if (!isObject(value)) {
      issues.push(toIssue("SCHEMA", `${path} expects object, got ${actualType}`));
      return issues;
    }

    const required = node.required ?? [];
    const properties = node.properties ?? {};
    for (const requiredKey of required) {
      if (!(requiredKey in value)) {
        issues.push(toIssue("SCHEMA", `required key missing: ${emitPath(path, requiredKey)}`));
      }
    }

    for (const [objKey, objValue] of Object.entries(value)) {
      const property = properties[objKey];
      if (!property) {
        if (node.additionalProperties === false) {
          issues.push(toIssue("SCHEMA", `${emitPath(path, objKey)} is not allowed`));
        }
        continue;
      }
      issues.push(...validateNode(objValue, property, schema, emitPath(path, objKey)));
    }
    return issues;
  }

  return issues;
}

function validateAgainstSimpleSchema(payload: Record<string, unknown>, schema: SchemaDocument): ValidationIssue[] {
  return validateNode(payload, schema as SchemaNode, schema, "$");
}

function validateManifestRegistry(payload: Record<string, unknown>, manifest: Manifest): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  const modeReasons = manifest.registries?.ModeReasonCode;
  const openPermissionReasons = coerceCodeList(manifest.registries?.OpenPermissionReasonCode);
  const reduceOnlyReasons = coerceCodeList(modeReasons?.ReduceOnly);
  const killReasons = coerceCodeList(modeReasons?.Kill);

  const tradingMode = payload.trading_mode;
  const modeReasonsValue = payload.mode_reasons;
  const latch = payload.open_permission_blocked_latch;
  const latchReasonsValue = payload.open_permission_reason_codes;
  const requiresReconcile = payload.open_permission_requires_reconcile;
  const f1ExpiresAt = payload.f1_cert_expires_at;

  if (manifest.contract_version && payload.contract_version !== manifest.contract_version) {
    issues.push(toIssue("CONTRACT", `contract_version mismatch (expected ${manifest.contract_version})`));
  }

  const modeReasonsAreStrings = Array.isArray(modeReasonsValue) && modeReasonsValue.every((item) => typeof item === "string");
  if (!modeReasonsAreStrings) {
    issues.push(toIssue("INVARIANT", "mode_reasons must be an array of strings"));
  }

  const latchReasonsAreStrings = Array.isArray(latchReasonsValue) && latchReasonsValue.every((item) => typeof item === "string");
  if (!latchReasonsAreStrings) {
    issues.push(toIssue("INVARIANT", "open_permission_reason_codes must be an array of strings"));
  }

  const modeReasonsList = modeReasonsAreStrings ? (modeReasonsValue as string[]) : [];
  const latchReasonsList = latchReasonsAreStrings ? (latchReasonsValue as string[]) : [];

  if (tradingMode === "Active") {
    if (modeReasonsList.length !== 0) {
      issues.push(toIssue("INVARIANT", "Decision A: trading_mode=Active requires mode_reasons=[]"));
    }
  }

  if (tradingMode === "ReduceOnly" || tradingMode === "Kill") {
    if (modeReasonsList.length === 0) {
      issues.push(toIssue("INVARIANT", `${tradingMode} requires non-empty mode_reasons`));
    }
  }

  if (tradingMode === "ReduceOnly") {
    const invalid = modeReasonsList.filter((code) => !reduceOnlyReasons.includes(code));
    if (invalid.length > 0) {
      issues.push(toIssue("TIER", `ReduceOnly mode_reasons invalid: ${JSON.stringify(invalid)}`));
    }
    if (!isSubsequenceOrdered(modeReasonsList, reduceOnlyReasons)) {
      issues.push(toIssue("ORDER", "ReduceOnly mode_reasons violate tier order"));
    }
  }

  if (tradingMode === "Kill") {
    const invalid = modeReasonsList.filter((code) => !killReasons.includes(code));
    if (invalid.length > 0) {
      issues.push(toIssue("TIER", `Kill mode_reasons invalid: ${JSON.stringify(invalid)}`));
    }
    if (!isSubsequenceOrdered(modeReasonsList, killReasons)) {
      issues.push(toIssue("ORDER", "Kill mode_reasons violate tier order"));
    }
  }

  const riskState = payload.risk_state;
  const f1State = payload.f1_cert_state;
  const tradingModeEnum = coerceCodeList(manifest.registries?.TradingMode);
  const riskStateEnum = coerceCodeList(manifest.registries?.RiskState);
  const f1StateEnum = coerceCodeList(manifest.registries?.F1CertState);

  if (!tradingModeEnum.includes(String(tradingMode))) {
    issues.push(toIssue("ENUM", `trading_mode unknown in manifest: ${String(tradingMode)}`));
  }
  if (!riskStateEnum.includes(String(riskState))) {
    issues.push(toIssue("ENUM", `risk_state unknown in manifest: ${String(riskState)}`));
  }
  if (!f1StateEnum.includes(String(f1State))) {
    issues.push(toIssue("ENUM", `f1_cert_state unknown in manifest: ${String(f1State)}`));
  }

  if (latch === true) {
    if (requiresReconcile !== true) {
      issues.push(toIssue("LATCH", "latch=true requires open_permission_requires_reconcile=true"));
    }
    if (latchReasonsList.length === 0) {
      issues.push(toIssue("LATCH", "latch=true requires non-empty open_permission_reason_codes"));
    }
    if (tradingMode === "Active") {
      issues.push(
        toIssue("DECISION-A", "latch=true requires trading_mode=ReduceOnly or trading_mode=Kill"),
      );
    }
    if (tradingMode === "ReduceOnly" && !modeReasonsList.includes("REDUCEONLY_OPEN_PERMISSION_LATCHED")) {
      issues.push(
        toIssue(
          "DECISION-A",
          "latch=true with ReduceOnly requires REDUCEONLY_OPEN_PERMISSION_LATCHED in mode_reasons",
        ),
      );
    }
  }

  if (latch === false) {
    if (requiresReconcile !== false) {
      issues.push(toIssue("LATCH", "latch=false requires open_permission_requires_reconcile=false"));
    }
    if (latchReasonsList.length !== 0) {
      issues.push(toIssue("LATCH", "latch=false requires open_permission_reason_codes=[]"));
    }
  }

  if (latch !== false && latch !== true) {
    issues.push(toIssue("LATCH", "open_permission_blocked_latch must be boolean"));
  }

  if (payload.f1_cert_state === "MISSING") {
    if (f1ExpiresAt !== null) {
      issues.push(toIssue("SCHEMA", "f1_cert_expires_at must be null when f1_cert_state is MISSING"));
    }
  } else if (!isNumber(f1ExpiresAt as unknown)) {
    issues.push(toIssue("SCHEMA", "f1_cert_expires_at must be integer when f1_cert_state is not MISSING"));
  }

  const unknownOpenPerm = latchReasonsList.filter((code) => !openPermissionReasons.includes(code));
  if (unknownOpenPerm.length > 0) {
    issues.push(toIssue("ENUM", `open_permission_reason_codes contain unknown values: ${JSON.stringify(unknownOpenPerm)}`));
  }

  return issues;
}

export function validateCspPayload(payload: unknown): ValidationReport {
  if (!isObject(payload)) {
    return {
      ok: false,
      issues: [toIssue("SCHEMA", "payload must be an object")],
    };
  }

  const issues = [
    ...validateAgainstSimpleSchema(payload, DEFAULT_STATUS_SCHEMA),
    ...validateManifestRegistry(payload, DEFAULT_REASON_MANIFEST),
  ];

  return {
    ok: issues.length === 0,
    issues,
  };
}

export function assertValidCspPayload(payload: unknown): void {
  const report = validateCspPayload(payload);
  if (!report.ok) {
    throw new Error(`status payload validation failed: ${JSON.stringify(report.issues)}`);
  }
}
