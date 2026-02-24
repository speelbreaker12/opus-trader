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
};

type SchemaDocument = {
  required?: string[];
  properties?: Record<string, SchemaNode>;
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

function validatePrimitiveBranch(value: unknown, branch: SchemaNode): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  if (typeof branch.const !== "undefined") {
    if (value !== branch.const) {
      return [toIssue("SCHEMA", `value must equal ${JSON.stringify(branch.const)}`)];
    }
    return issues;
  }

  if (branch.enum && !branch.enum.includes(value as never)) {
    return [toIssue("SCHEMA", `value must be one of ${JSON.stringify(branch.enum)}`)];
  }

  if (branch.type) {
    const allowed = Array.isArray(branch.type) ? branch.type : [branch.type];
    const valueType = Array.isArray(value) ? "array" : value === null ? "null" : typeof value;
    const normalized = new Set(allowed.map((entry) => (entry === "integer" ? "number" : entry)));

    if (!normalized.has(valueType)) {
      return [toIssue("SCHEMA", `value expects ${JSON.stringify(allowed)}, got ${valueType}`)];
    }

    if (branch.type.includes("integer") && isNumber(value) && value % 1 !== 0) {
      issues.push(toIssue("SCHEMA", `value must be integer`));
    }
  }

  if (typeof branch.minimum === "number" && isNumber(value) && value < branch.minimum) {
    issues.push(toIssue("SCHEMA", `minimum is ${branch.minimum}`));
  }
  if (typeof branch.maximum === "number" && isNumber(value) && value > branch.maximum) {
    issues.push(toIssue("SCHEMA", `maximum is ${branch.maximum}`));
  }

  return issues;
}

function validateAgainstSimpleSchema(payload: Record<string, unknown>, schema: SchemaDocument): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  const required = schema.required ?? [];
  for (const key of required) {
    if (!(key in payload)) {
      issues.push(toIssue("SCHEMA", `required key missing: ${key}`));
    }
  }

  const properties = schema.properties ?? {};
  for (const [key, value] of Object.entries(payload)) {
    const prop = properties[key];
    if (!prop) {
      continue;
    }

    const valueIsArray = Array.isArray(value);

    if (typeof prop.const !== "undefined") {
      if (value !== prop.const) {
        issues.push(toIssue("SCHEMA", `\"${key}\" must equal ${JSON.stringify(prop.const)}`));
      }
      continue;
    }

    if (prop.anyOf) {
      const ok = prop.anyOf.some((branch) => validatePrimitiveBranch(value, branch).length === 0);
      if (!ok) {
        issues.push(toIssue("SCHEMA", `\"${key}\" does not match any allowed variants`));
      }
      continue;
    }

    if (prop.enum && !prop.enum.includes(value as never)) {
      issues.push(toIssue("SCHEMA", `\"${key}\" must be one of ${JSON.stringify(prop.enum)}`));
    }

    if (prop.type) {
      const allowed = Array.isArray(prop.type) ? prop.type : [prop.type];
      const expectedTypes = new Set(
        allowed.map((entry) => (entry === "integer" ? "number" : entry)),
      );
      const actualType = Array.isArray(value) ? "array" : value === null ? "null" : typeof value;
      if (!expectedTypes.has(actualType)) {
        issues.push(toIssue("SCHEMA", `\"${key}\" expects ${JSON.stringify(allowed)}, got ${actualType}`));
      } else if (actualType === "number") {
        if (Array.isArray(allowed) && allowed.includes("integer") && isNumber(value) && value % 1 !== 0) {
          issues.push(toIssue("SCHEMA", `\"${key}\" must be integer`));
        }
      } else if (actualType !== "number" && prop.minimum !== undefined) {
        issues.push(toIssue("SCHEMA", `\"${key}\" minimum requires number`));
      }
    }

    if (typeof prop.minLength === "number" && typeof value === "string") {
      if (value.length < prop.minLength) {
        issues.push(toIssue("SCHEMA", `\"${key}\" minLength is ${prop.minLength}`));
      }
    }

    if (typeof prop.minimum === "number" && isNumber(value) && value < prop.minimum) {
      issues.push(toIssue("SCHEMA", `\"${key}\" minimum is ${prop.minimum}`));
    }
    if (typeof prop.maximum === "number" && isNumber(value) && value > prop.maximum) {
      issues.push(toIssue("SCHEMA", `\"${key}\" maximum is ${prop.maximum}`));
    }

    if (Array.isArray(value) && prop.uniqueItems) {
      if (new Set(value).size !== value.length) {
        issues.push(toIssue("SCHEMA", `\"${key}\" requires unique items`));
      }
    }

    if (valueIsArray && prop.items && prop.items.enum) {
      const invalidItems = value.filter((item) => typeof item !== "string" || !prop.items!.enum!.includes(item as never));
      if (invalidItems.length > 0) {
        issues.push(toIssue("SCHEMA", `\"${key}\" contains invalid entries: ${JSON.stringify(invalidItems)}`));
      }
    }

    if (valueIsArray && prop.items && typeof prop.items.type === "string") {
      const expectedItemType = prop.items.type === "integer" ? "number" : prop.items.type;
      const invalidItems = value.filter((item) => {
        const actualType = item === null ? "null" : typeof item;
        return actualType !== expectedItemType;
      });
      if (invalidItems.length > 0) {
        issues.push(
          toIssue("SCHEMA", `\"${key}\" items must be ${JSON.stringify(prop.items.type)}: ${JSON.stringify(invalidItems)}`),
        );
      }
    }

    if (valueIsArray && typeof prop.minItems === "number" && value.length < prop.minItems) {
      issues.push(toIssue("SCHEMA", `\"${key}\" minimum is ${prop.minItems} items`));
    }

    if (valueIsArray && typeof prop.maxItems === "number" && value.length > prop.maxItems) {
      issues.push(toIssue("SCHEMA", `\"${key}\" maximum is ${prop.maxItems} items`));
    }

    if (valueIsArray && prop.contains && prop.contains.const) {
      const hasRequired = value.includes(prop.contains.const as never);
      const minContains = prop.minContains ?? 1;
      if (!hasRequired && minContains > 0) {
        issues.push(
          toIssue("SCHEMA", `\"${key}\" must contain ${JSON.stringify(prop.contains.const)} at least ${minContains} time(s)`),
        );
      }
    }

    if (valueIsArray && prop.contains && typeof prop.contains.type === "string") {
      const itemType = prop.contains.type === "integer" ? "number" : prop.contains.type;
      const invalid = value.some((entry) => {
        const actualType = entry === null ? "null" : typeof entry;
        return actualType !== itemType;
      });
      if (invalid) {
        issues.push(toIssue("SCHEMA", `\"${key}\" contains must be ${JSON.stringify(prop.contains.type)} values`));
      }
    }
  }

  return issues;
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
