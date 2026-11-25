import type { CurrencyCode, ExchangeRateTablePayload } from "./types.ts";

interface CurrencyMeta {
  code: CurrencyCode;
  isZeroDecimal: boolean;
  narrowSymbol: string;
}

const CURRENCY_LIST: CurrencyMeta[] = [
  { code: "SGD", isZeroDecimal: false, narrowSymbol: "S$" },
  { code: "VND", isZeroDecimal: true, narrowSymbol: "₫" },
  { code: "USD", isZeroDecimal: false, narrowSymbol: "$" },
  { code: "EUR", isZeroDecimal: false, narrowSymbol: "€" },
  { code: "GBP", isZeroDecimal: false, narrowSymbol: "£" },
  { code: "AUD", isZeroDecimal: false, narrowSymbol: "A$" },
  { code: "CAD", isZeroDecimal: false, narrowSymbol: "CA$" },
  { code: "MYR", isZeroDecimal: false, narrowSymbol: "RM" },
  { code: "HKD", isZeroDecimal: false, narrowSymbol: "HK$" },
  { code: "CNY", isZeroDecimal: false, narrowSymbol: "¥" },
  { code: "JPY", isZeroDecimal: true, narrowSymbol: "¥" },
  { code: "KRW", isZeroDecimal: true, narrowSymbol: "₩" },
  { code: "THB", isZeroDecimal: false, narrowSymbol: "฿" },
  { code: "TWD", isZeroDecimal: false, narrowSymbol: "NT$" },
  { code: "IDR", isZeroDecimal: true, narrowSymbol: "Rp" },
  { code: "PHP", isZeroDecimal: false, narrowSymbol: "₱" },
  { code: "NZD", isZeroDecimal: false, narrowSymbol: "NZ$" },
  { code: "CHF", isZeroDecimal: false, narrowSymbol: "CHF " },
  { code: "INR", isZeroDecimal: false, narrowSymbol: "₹" },
];

export const CURRENCY_MAP = new Map<string, CurrencyMeta>(
  CURRENCY_LIST.map((item) => [item.code, item])
);

const EXTRA_ZERO_DECIMAL_CODES = new Set([
  "BIF",
  "CLP",
  "DJF",
  "GNF",
  "ISK",
  "KMF",
  "PYG",
  "RWF",
  "UGX",
  "VUV",
  "XAF",
  "XOF",
  "XPF",
]);

const CODE_ALIASES: Record<string, string> = {
  RMB: "CNY",
  CNH: "CNY",
  NTD: "TWD",
  "S$": "SGD",
  "HK$": "HKD",
  "US$": "USD",
  "NT$": "TWD",
  "A$": "AUD",
  "AU$": "AUD",
  "CA$": "CAD",
  "NZ$": "NZD",
  RM: "MYR",
  RP: "IDR",
  "VNĐ": "VND",
  "Đ": "VND",
};

export const FALLBACK_RATES_PER_SGD: Record<string, number> = {
  SGD: 1.0,
  VND: 19000.0,
  USD: 0.75,
  EUR: 0.69,
  GBP: 0.59,
  AUD: 1.15,
  CAD: 1.04,
  MYR: 3.3,
  HKD: 5.85,
  CNY: 5.42,
  JPY: 114.0,
  KRW: 1040.0,
  THB: 25.8,
  TWD: 24.2,
  IDR: 11900.0,
  PHP: 43.5,
  NZD: 1.26,
  CHF: 0.66,
  INR: 63.5,
  AED: 2.75,
  BND: 1.0,
  MOP: 6.03,
  SEK: 8.0,
  NOK: 8.2,
  DKK: 5.15,
  PLN: 3.0,
  TRY: 26.0,
  MXN: 15.0,
  BRL: 4.3,
  ZAR: 13.5,
  SAR: 2.81,
  QAR: 2.73,
  KHR: 3050.0,
  LAK: 16400.0,
  MMK: 1575.0,
  LKR: 220.0,
  CZK: 17.5,
  HUF: 280.0,
  ILS: 2.75,
  KWD: 0.23,
  BHD: 0.28,
  OMR: 0.29,
};

let validISOCodesCache: Set<string> | null = null;
function getValidISOCodes(): Set<string> {
  if (validISOCodesCache) return validISOCodesCache;
  const set = new Set<string>(Object.keys(FALLBACK_RATES_PER_SGD));
  for (const item of CURRENCY_LIST) set.add(item.code);
  try {
    const intl = Intl as unknown as { supportedValuesOf?: (key: string) => string[] };
    if (typeof intl.supportedValuesOf === "function") {
      for (const code of intl.supportedValuesOf("currency")) {
        set.add(code.toUpperCase());
      }
    }
  } catch {
    // Fallback set already includes all household and common currencies.
  }
  validISOCodesCache = set;
  return set;
}

export function normalizeCurrencyCode(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const upper = trimmed.toUpperCase();
  const mapped = CODE_ALIASES[upper] ?? upper;
  if (mapped.length !== 3 || !getValidISOCodes().has(mapped)) return null;
  return mapped;
}

export function isKnownCurrencyCode(raw: string): raw is CurrencyCode {
  return CURRENCY_MAP.has(raw.toUpperCase());
}

export function isZeroDecimalCurrency(code: string): boolean {
  const upper = code.trim().toUpperCase();
  const known = CURRENCY_MAP.get(upper);
  if (known) return known.isZeroDecimal;
  return EXTRA_ZERO_DECIMAL_CODES.has(upper);
}

export function fractionDigitsForCurrency(code: string): number {
  return isZeroDecimalCurrency(code) ? 0 : 2;
}

export function toStorageMinor(major: number, currencyCode: string): number {
  if (isZeroDecimalCurrency(currencyCode)) {
    return Math.round(major) * 100;
  }
  return Math.round(major * 100);
}

export function toMajor(storageMinor: number): number {
  return storageMinor / 100.0;
}

function formatGroupedDecimal(absMajor: number, currencyCode: string): string {
  const upper = currencyCode.toUpperCase();
  const isVND = upper === "VND";
  const digits = fractionDigitsForCurrency(upper);
  const fixed = absMajor.toFixed(digits);
  const [intPart, decPart] = fixed.split(".");
  const groupedInt = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, isVND ? "." : ",");
  if (digits === 0) return groupedInt;
  return `${groupedInt}${isVND ? "," : "."}${decPart}`;
}

export function formatMoney(
  minor: number,
  currencyCode: string,
  options: { signed?: boolean } = {}
): string {
  const upper = normalizeCurrencyCode(currencyCode) ?? currencyCode.trim().toUpperCase();
  const absMajor = Math.abs(toMajor(minor));
  const signPrefix = minor < 0 ? "−" : options.signed && minor > 0 ? "+" : "";
  const number = formatGroupedDecimal(absMajor, upper);

  const known = CURRENCY_MAP.get(upper);
  if (known) {
    if (known.code === "VND") {
      return `${signPrefix}${number} ₫`;
    }
    return `${signPrefix}${known.narrowSymbol}${number}`;
  }
  return `${signPrefix}${upper} ${number}`;
}

export function formatRateNumber(value: number): string {
  let digits = 4;
  if (value >= 100) digits = 0;
  else if (value >= 10) digits = 2;
  const fixed = value.toFixed(digits);
  const [intPart, decPart] = fixed.split(".");
  const groupedInt = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return decPart !== undefined ? `${groupedInt}.${decPart}` : groupedInt;
}

export function formatExchangeRate(
  rate: number,
  fromCode: string,
  toCurrency: CurrencyCode
): string {
  if (!(rate > 0 && Number.isFinite(rate))) return "";
  const src = normalizeCurrencyCode(fromCode) ?? fromCode.trim().toUpperCase();
  if (rate < 0.001) {
    return `1 ${toCurrency} = ${formatRateNumber(1 / rate)} ${src}`;
  }
  return `1 ${src} = ${formatRateNumber(rate)} ${toCurrency}`;
}

export function resolveTransactionAmount(params: {
  amountMajor: number;
  statedCurrencyCode: string | null;
  convertedAmountMajor: number | null;
  household: CurrencyCode;
  note: string;
  rates?: ExchangeRateTablePayload;
}): {
  amountMinor: number;
  note: string;
  originalAmountMinor: number | null;
  originalCurrencyCode: string | null;
  exchangeRate: number | null;
  isLiveRate: boolean;
  rateDate: string | null;
  usedFallbackUnavailableRate: boolean;
} {
  const step = isZeroDecimalCurrency(params.household) ? 100 : 1;
  const code = params.statedCurrencyCode ? normalizeCurrencyCode(params.statedCurrencyCode) : null;
  const cleanNote = params.note.trim();

  if (code && code !== params.household) {
    const originalMinor = toStorageMinor(params.amountMajor, code);
    const origFormatted = formatMoney(originalMinor, code);
    const fxTag = `Orig: ${origFormatted}`;
    const combinedNote = !cleanNote
      ? fxTag
      : cleanNote.includes(origFormatted)
        ? cleanNote
        : `${cleanNote} · ${fxTag}`;

    if (params.convertedAmountMajor && params.convertedAmountMajor > 0 && Number.isFinite(params.convertedAmountMajor)) {
      const householdMinor = Math.max(step, toStorageMinor(params.convertedAmountMajor, params.household));
      const impliedRate = params.amountMajor > 0 ? params.convertedAmountMajor / params.amountMajor : null;
      return {
        amountMinor: householdMinor,
        note: combinedNote,
        originalAmountMinor: originalMinor,
        originalCurrencyCode: code,
        exchangeRate: impliedRate && Number.isFinite(impliedRate) && impliedRate > 0 ? impliedRate : null,
        isLiveRate: false,
        rateDate: null,
        usedFallbackUnavailableRate: false,
      };
    }

    const ratesMap = params.rates?.ratesPerSGD ?? FALLBACK_RATES_PER_SGD;
    const isLive = Boolean(params.rates?.fetchedAt);
    const rateDate = params.rates?.rateDate ?? null;

    let rateInfo: { rate: number; isLive: boolean; rateDate: string | null } | null = null;
    const s = ratesMap[code];
    const t = ratesMap[params.household];
    if (s && s > 0 && Number.isFinite(s) && t && t > 0 && Number.isFinite(t)) {
      const ratio = t / s;
      if (ratio > 0 && Number.isFinite(ratio)) {
        rateInfo = { rate: ratio, isLive, rateDate };
      }
    }
    if (!rateInfo) {
      const fs = FALLBACK_RATES_PER_SGD[code];
      const ft = FALLBACK_RATES_PER_SGD[params.household];
      if (fs && fs > 0 && ft && ft > 0) {
        rateInfo = { rate: ft / fs, isLive: false, rateDate: null };
      }
    }

    if (rateInfo) {
      const raw = params.amountMajor * rateInfo.rate;
      const convertedMajor = isZeroDecimalCurrency(params.household)
        ? Math.round(raw)
        : Math.round(raw * 100) / 100;
      const householdMinor = Math.max(step, toStorageMinor(convertedMajor, params.household));
      return {
        amountMinor: householdMinor,
        note: combinedNote,
        originalAmountMinor: originalMinor,
        originalCurrencyCode: code,
        exchangeRate: rateInfo.rate,
        isLiveRate: rateInfo.isLive,
        rateDate: rateInfo.rateDate,
        usedFallbackUnavailableRate: false,
      };
    }

    return {
      amountMinor: Math.max(step, toStorageMinor(params.amountMajor, params.household)),
      note: combinedNote,
      originalAmountMinor: originalMinor,
      originalCurrencyCode: code,
      exchangeRate: null,
      isLiveRate: false,
      rateDate: null,
      usedFallbackUnavailableRate: true,
    };
  }

  return {
    amountMinor: Math.max(step, toStorageMinor(params.amountMajor, params.household)),
    note: cleanNote,
    originalAmountMinor: null,
    originalCurrencyCode: null,
    exchangeRate: null,
    isLiveRate: false,
    rateDate: null,
    usedFallbackUnavailableRate: false,
  };
}

// MARK: - DateKey helpers (matches TallyCore/DateKey.swift)

export function todayKeyForOffsetMinutes(offsetMinutes: number, now: Date = new Date()): string {
  const shifted = new Date(now.getTime() + offsetMinutes * 60_000);
  const y = shifted.getUTCFullYear();
  const m = shifted.getUTCMonth() + 1;
  const d = shifted.getUTCDate();
  return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

export function parseDayKey(key: string): { year: number; month: number; day: number } | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  const dt = new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
  if (
    dt.getUTCFullYear() !== year ||
    dt.getUTCMonth() + 1 !== month ||
    dt.getUTCDate() !== day
  ) {
    return null;
  }
  return { year, month, day };
}

export function isValidDayKey(key: string): boolean {
  return parseDayKey(key) !== null;
}

export function parseMonthKey(key: string): { year: number; month: number } | null {
  const match = /^(\d{4})-(\d{2})$/.exec(key);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  if (year < 2000 || year > 2099 || month < 1 || month > 12) return null;
  return { year, month };
}

export function monthKeyFromDayKey(dayKey: string): string {
  return dayKey.slice(0, 7);
}

export function monthKeyFromYearMonth(year: number, month: number): string {
  return `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}`;
}

export function dayKeyFromYearMonthDay(year: number, month: number, day: number): string {
  return `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

export function dayOfMonth(dayKey: string): number {
  const parts = dayKey.split("-");
  return parts.length === 3 ? Number(parts[2]) || 1 : 1;
}

export function daysInMonth(monthKey: string): number {
  const ym = parseMonthKey(monthKey);
  if (!ym) return 30;
  return new Date(Date.UTC(ym.year, ym.month, 0)).getUTCDate();
}

export function dayRangeForMonth(monthKey: string): { start: string; end: string } {
  const count = daysInMonth(monthKey);
  return {
    start: `${monthKey}-01`,
    end: `${monthKey}-${String(count).padStart(2, "0")}`,
  };
}

export function shiftMonth(monthKey: string, delta: number): string {
  const ym = parseMonthKey(monthKey);
  if (!ym) return monthKey;
  const totalMonths = ym.year * 12 + (ym.month - 1) + delta;
  const year = Math.floor(totalMonths / 12);
  const month = (totalMonths % 12) + 1;
  const next = monthKeyFromYearMonth(year, month);
  if (next < "2000-01" || next > "2099-12") return monthKey;
  return next;
}

export function shiftDay(dayKey: string, delta: number): string {
  const p = parseDayKey(dayKey);
  if (!p) return dayKey;
  const dt = new Date(Date.UTC(p.year, p.month - 1, p.day + delta, 12, 0, 0));
  const next = dayKeyFromYearMonthDay(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
  if (next < "2000-01-01" || next > "2099-12-31") return dayKey;
  return next;
}

export function daysBetween(startDayKey: string, endDayKey: string): number {
  const s = parseDayKey(startDayKey);
  const e = parseDayKey(endDayKey);
  if (!s || !e) return 0;
  const msS = Date.UTC(s.year, s.month - 1, s.day);
  const msE = Date.UTC(e.year, e.month - 1, e.day);
  return Math.round((msE - msS) / 86_400_000);
}

const WEEKDAY_NAMES = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

/** 1 = Sunday ... 7 = Saturday */
export function weekday(dayKey: string): number {
  const p = parseDayKey(dayKey);
  if (!p) return 1;
  return new Date(Date.UTC(p.year, p.month - 1, p.day, 12, 0, 0)).getUTCDay() + 1;
}

export function weekdayName(dayKey: string): string {
  return WEEKDAY_NAMES[Math.max(0, Math.min(6, weekday(dayKey) - 1))];
}

export function weekStart(dayKey: string): string {
  const wd = weekday(dayKey);
  return shiftDay(dayKey, -((wd + 5) % 7));
}

export function dateContextLines(todayKey: string): string[] {
  const recent: string[] = [];
  for (let offset = 1; offset <= 14; offset++) {
    const key = shiftDay(todayKey, -offset);
    recent.push(`${key} ${weekdayName(key)}${offset === 1 ? " (yesterday)" : ""}`);
  }
  const thisWeek = weekStart(todayKey);
  const lastWeek = shiftDay(thisWeek, -7);
  const month = monthKeyFromDayKey(todayKey);
  const lastMonth = shiftMonth(month, -1);
  const thisRange = dayRangeForMonth(month);
  const lastRange = dayRangeForMonth(lastMonth);
  return [
    `Today: ${todayKey} (${weekdayName(todayKey)}). Tomorrow: ${shiftDay(todayKey, 1)}. Weeks start on Monday.`,
    `Previous 14 days: ${recent.join(", ")}.`,
    `This week: ${thisWeek} to ${shiftDay(thisWeek, 6)}; last week: ${lastWeek} to ${shiftDay(lastWeek, 6)}.`,
    `This month: ${month} (${thisRange.start} to ${thisRange.end}); last month: ${lastMonth} (${lastRange.start} to ${lastRange.end}); next month: ${shiftMonth(month, 1)}.`,
  ];
}

export function monthKeyFromDateOrMonthInput(raw: string): string | null {
  if (raw.length === 7 && parseMonthKey(raw)) return raw;
  if (isValidDayKey(raw)) return monthKeyFromDayKey(raw);
  return null;
}

export function dayKeyFromIsoTimestamp(iso: string, offsetMinutes: number): string {
  const parsed = Date.parse(iso);
  if (!Number.isFinite(parsed)) return todayKeyForOffsetMinutes(offsetMinutes);
  return todayKeyForOffsetMinutes(offsetMinutes, new Date(parsed));
}
