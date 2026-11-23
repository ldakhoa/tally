"use strict";

const icons = {
  logo: '<path d="M5 18v-5m5 5V9m5 9V6m5 12V3"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  transactions: '<path d="M3 7h17m-4-4 4 4-4 4m5 6H4m4-4-4 4 4 4"/>',
  pie: '<path d="M21 12a9 9 0 1 1-9-9v9z"/><path d="M16 3.6a9 9 0 0 1 4.4 4.4H16z"/>',
  target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
  settings: '<circle cx="12" cy="12" r="4"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M5 19l2-2M17 7l2-2"/><circle cx="12" cy="12" r="7"/>',
  wallet: '<path d="M20 7V5H6a3 3 0 0 0 0 6h15v9H6a3 3 0 0 1-3-3V8m18 6h-6v3h6"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4m8-4v4"/>',
  "chevron-right": '<path d="m9 6 6 6-6 6"/>',
  "chevron-left": '<path d="m15 6-6 6 6 6"/>',
  plus: '<path d="M12 5v14m-7-7h14"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  up: '<path d="M12 19V5m-5 5 5-5 5 5"/>',
  down: '<path d="M12 5v14m-5-5 5 5 5-5"/>',
  trend: '<path d="m3 16 6-6 4 4 7-8m-5 0h5v5"/>',
  leaf: '<path d="M20 4c-7 0-14 2-14 9a5 5 0 0 0 5 5c7 0 9-7 9-14ZM4 20l9-9"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5m0-8h.01"/>',
  lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 1 1 8 0v3"/>',
  home: '<path d="m3 11 9-8 9 8m-16-2v12h14V9m-9 12v-6h4v6"/>',
  food: '<path d="M5 3v5a3 3 0 0 0 6 0V3M8 3v18m11 0V3c-3 2-4 5-4 9h4"/>',
  transport: '<path d="m4 11 2-6h12l2 6m-16 7v2m16-2v2M4 11h16v7H4zM7 14h1m8 0h1"/>',
  bag: '<path d="M5 7h14l2 14H3zM9 10V6a3 3 0 0 1 6 0v4"/>',
  bolt: '<path d="m13 2-9 12h7l-1 8 10-12h-7z"/>',
  heart: '<path d="M20 13c2-2 2-5 0-7s-5-2-8 1c-3-3-6-3-8-1s-2 5 0 7l8 8z"/>',
  play: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m10 9 5 3-5 3z"/>',
  dots: '<path d="M5 12h.01m6.99 0h.01m6.99 0h.01" stroke-width="3"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
  plane: '<path d="m22 2-7 20-4-9-9-4zM22 2 11 13"/>',
  laptop: '<path d="M5 5h14v12H5zM2 17h20v3H2z"/>',
  edit: '<path d="m5 16 11-11 3 3L8 19l-4 1zM14 7l3 3"/>',
  download: '<path d="M12 3v12m-4-4 4 4 4-4M4 16v5h16v-5"/>',
  upload: '<path d="M12 15V3m-4 4 4-4 4 4M4 16v5h16v-5"/>',
};

const categories = {
  housing: { label: "Housing", icon: "home", color: "#345f49", tint: "#e6f0e7" },
  food: { label: "Food & drink", icon: "food", color: "#73a282", tint: "#edf4e8", tone: "#426748" },
  transport: { label: "Transport", icon: "transport", color: "#e3bd70", tint: "#f8f0de", tone: "#775624" },
  shopping: { label: "Shopping", icon: "bag", color: "#a6a3c7", tint: "#efedf7", tone: "#625687" },
  bills: { label: "Bills & utilities", icon: "bolt", color: "#9bbb9c", tint: "#e9f1e7", tone: "#4c6c50" },
  health: { label: "Health", icon: "heart", color: "#d39783", tint: "#f8edeb", tone: "#8b5147" },
  entertainment: { label: "Entertainment", icon: "play", color: "#91b3c3", tint: "#eaf1f6", tone: "#426678" },
  other: { label: "Other", icon: "dots", color: "#b0bcad", tint: "#edf0eb", tone: "#526759" },
  salary: { label: "Salary", icon: "down", tint: "#e5f3e8", tone: "#285d44" },
  freelance: { label: "Freelance", icon: "down", tint: "#e5f3e8", tone: "#285d44" },
  income: { label: "Other income", icon: "down", tint: "#e5f3e8", tone: "#285d44" },
};
const expenseCategories = ["housing", "food", "transport", "shopping", "bills", "health", "entertainment", "other"];
const incomeCategories = ["salary", "freelance", "income"];
const currencies = {
  SGD: "Singapore Dollar", USD: "US Dollar", EUR: "Euro", GBP: "British Pound",
  AUD: "Australian Dollar", CAD: "Canadian Dollar", MYR: "Malaysian Ringgit", VND: "Vietnamese Dong",
};
const goalStyles = {
  shield: { tint: "#e8f4eb", tone: "#355e46", fill: "#5a8e6d" },
  plane: { tint: "#f5efdd", tone: "#785b24", fill: "#bc974d" },
  laptop: { tint: "#eeedf7", tone: "#5c537d", fill: "#8b81ae" },
  target: { tint: "#e8f4eb", tone: "#355e46", fill: "#5a8e6d" },
};
const pages = {
  overview: { title: "Overview", description: "See where your money goes and how much you’re saving." },
  transactions: { title: "Transactions", description: "Record and review your income and expenses." },
  budgets: { title: "Budgets", description: "Set spending limits for the month and see what’s left in each category." },
  savings: { title: "Savings goals", description: "Set a target, log contributions, and track what’s left to save." },
  settings: { title: "Settings", description: "Manage your currency and budget backups." },
};

const storageKey = "tally.personal-budget.v1";
const amountLimit = 999999999;
const main = document.querySelector("main");
const dialog = document.querySelector("#editor");
const editor = document.querySelector("#editor-form");
const toast = document.querySelector("#toast");
const today = dateKey(new Date());
let selectedMonth = today.slice(0, 7);
let page = pageFromHash();
let filter = { search: "", type: "all" };
let editContext = null;
let toastTimer;
let storageError = "";
let personal = readData();
const demo = exampleData(selectedMonth);

function dateKey(date) {
  return [date.getFullYear(), date.getMonth() + 1, date.getDate()].map(value => String(value).padStart(2, "0")).join("-");
}

function dateObject(value) {
  return new Date(`${value.length === 7 ? `${value}-01` : value}T12:00:00`);
}

function exampleData(month) {
  const rows = [
    [21, "Weekend groceries", "food", 9240], [20, "Metro top-up", "transport", 3000],
    [18, "Design project", "freelance", 85000], [16, "Running shoes", "shopping", 12900],
    [14, "Internet & mobile", "bills", 14400], [13, "Dinner with friends", "food", 8260],
    [12, "Groceries", "food", 16750], [11, "Ride fares", "transport", 7640],
    [9, "Household essentials", "shopping", 19500], [8, "Groceries & takeaway", "food", 27000],
    [3, "Monthly rent", "housing", 165000], [2, "Salary", "salary", 480000],
  ];
  return {
    version: 1,
    currency: "SGD",
    transactions: rows.map(([day, name, category, amount], index) => ({
      id: `demo-${index}`, date: `${month}-${String(day).padStart(2, "0")}`, name, category,
      type: incomeCategories.includes(category) ? "income" : "expense", amount,
    })),
    budgets: Object.fromEntries([[ "housing", 165000 ], [ "food", 67500 ], [ "transport", 18000 ], [ "shopping", 42500 ], [ "bills", 20000 ]].map(([category, amount]) => [`${month}/${category}`, amount])),
    goals: [
      { id: "demo-emergency", name: "Emergency fund", icon: "shield", target: 1000000, saved: 650000 },
      { id: "demo-trip", name: "Japan trip", icon: "plane", target: 300000, saved: 126000 },
      { id: "demo-laptop", name: "New laptop", icon: "laptop", target: 200000, saved: 58000 },
    ],
  };
}

function blankData(currency = "SGD") {
  return { version: 1, currency, transactions: [], budgets: {}, goals: [] };
}

function readData() {
  try {
    const stored = localStorage.getItem(storageKey);
    return stored === null ? null : validateBackup(JSON.parse(stored));
  } catch {
    storageError = "Tally couldn’t load browser data. Check browser storage or restore a backup in Settings.";
    return null;
  }
}

function saveData(next) {
  try {
    localStorage.setItem(storageKey, JSON.stringify(next));
    personal = next;
    storageError = "";
    return true;
  } catch {
    notify("Tally couldn’t save to this browser. Check that browser storage is available.");
    return false;
  }
}

function data() {
  return personal ?? demo;
}

function requirePersonal() {
  if (personal) return true;
  notify("Select Start tracking to enter your own records.");
  return false;
}

function notify(message) {
  clearTimeout(toastTimer);
  toast.textContent = message;
  toastTimer = setTimeout(() => { toast.textContent = ""; }, 4700);
}

function safe(value) {
  return String(value).replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
}

function icon(name, className = "") {
  return `<span class="${className}" data-icon="${name}">${iconMarkup(name)}</span>`;
}

function iconMarkup(name) {
  return `<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">${icons[name] ?? icons.dots}</svg>`;
}

function formatMoney(cents, compact = false) {
  const currency = data().currency;
  const digits = currency === "VND" ? 0 : 2;
  return new Intl.NumberFormat("en-SG", {
    style: "currency", currency, currencyDisplay: "narrowSymbol",
    notation: compact ? "compact" : "standard", minimumFractionDigits: compact ? 0 : digits,
    maximumFractionDigits: compact ? 1 : digits,
  }).format(cents / 100);
}

function formatMonth(month = selectedMonth) {
  return new Intl.DateTimeFormat("en-SG", { month: "long", year: "numeric" }).format(dateObject(month));
}

function formatDay(day) {
  return new Intl.DateTimeFormat("en-SG", { month: "short", day: "numeric" }).format(dateObject(day));
}

function pageFromHash() {
  const hash = location.hash.slice(1);
  return Object.hasOwn(pages, hash) ? hash : "overview";
}

function monthTransactions() {
  return data().transactions.filter(transaction => transaction.date.startsWith(selectedMonth))
    .sort((first, second) => second.date.localeCompare(first.date));
}

function monthlyData() {
  const transactions = monthTransactions();
  const expenses = {};
  let income = 0;
  let spending = 0;
  for (const transaction of transactions) {
    if (transaction.type === "income") {
      income += transaction.amount;
    } else {
      spending += transaction.amount;
      expenses[transaction.category] = (expenses[transaction.category] ?? 0) + transaction.amount;
    }
  }
  const budgets = Object.entries(data().budgets)
    .filter(([key]) => key.startsWith(`${selectedMonth}/`))
    .map(([key, limit]) => ({ category: key.split("/")[1], limit }));
  const budgetTotal = budgets.reduce((sum, budget) => sum + budget.limit, 0);
  const budgetSpent = budgets.reduce((sum, budget) => sum + (expenses[budget.category] ?? 0), 0);
  return { transactions, expenses, income, spending, budgets, budgetTotal, budgetSpent };
}

function button(label, action, { symbol = "", style = "", key = "", aria = "" } = {}) {
  return `<button type="button" class="button ${style}" data-action="${action}"${key ? ` data-key="${safe(key)}"` : ""}${aria ? ` aria-label="${safe(aria)}"` : ""}>${symbol ? icon(symbol) : ""}${safe(label)}</button>`;
}

function monthControl() {
  return `<div class="month-control" aria-label="Selected month">
    <button type="button" data-action="previous-month" aria-label="Previous month" ${selectedMonth === "2000-01" ? "disabled" : ""}>${icon("chevron-left")}</button>
    <span class="month-name">${icon("calendar")} ${formatMonth()}</span>
    <button type="button" data-action="next-month" aria-label="Next month" ${selectedMonth === "2099-12" ? "disabled" : ""}>${icon("chevron-right")}</button>
  </div>`;
}

function pageHeader(actions = "") {
  return `<div class="page-header"><div class="page-heading"><h1>${pages[page].title}</h1><p>${pages[page].description}</p></div>${actions ? `<div class="page-tools">${actions}</div>` : ""}</div>`;
}

function panelHeading(title, subtitle = "", aside = "") {
  return `<div class="panel-head"><div><h2>${title}</h2>${subtitle ? `<p>${subtitle}</p>` : ""}</div>${aside}</div>`;
}

function pageLink(label, hash) {
  return `<a class="panel-link" href="#${hash}">${label}</a>`;
}

function empty(title, description, action = "") {
  return `<div class="empty"><strong>${title}</strong><p>${description}</p>${action}</div>`;
}

function metric(label, note, value, symbol, style = "") {
  return `<article class="metric ${style === "featured" ? style : ""}">
    <div class="metric-label">${icon(symbol, `metric-icon ${style}`)} ${label}</div>
    <p class="metric-value">${value}</p>
    <p class="metric-note">${note}</p>
  </article>`;
}

function cashFlow(transactions) {
  const month = dateObject(selectedMonth);
  const days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
  const weeks = Array.from({ length: Math.ceil(days / 7) }, (_, index) => ({
    label: `${index * 7 + 1}–${Math.min(index * 7 + 7, days)}`, income: 0, expense: 0,
  }));
  for (const transaction of transactions) {
    const week = Math.floor((Number(transaction.date.slice(8)) - 1) / 7);
    weeks[week][transaction.type] += transaction.amount;
  }
  const largest = Math.max(...weeks.flatMap(week => [week.income, week.expense]), 10000);
  const rawStep = largest / 4;
  const magnitude = 10 ** Math.floor(Math.log10(rawStep));
  const step = Math.ceil(rawStep / magnitude) * magnitude;
  const max = step * 4;
  const legend = '<div class="legend"><span><i class="legend-income"></i>Income</span><span><i class="legend-spending"></i>Spending</span></div>';
  const bars = weeks.map(week => {
    const label = `Days ${week.label}. Income ${formatMoney(week.income)}. Spending ${formatMoney(week.expense)}.`;
    return `<div class="bar-group" tabindex="0" role="img" aria-label="${safe(label)}">
      ${week.income ? `<span class="bar income" style="--bar-height:${100 * week.income / max}%"></span>` : '<span class="bar" style="--bar-height:0"></span>'}
      ${week.expense ? `<span class="bar spending" style="--bar-height:${100 * week.expense / max}%"></span>` : '<span class="bar" style="--bar-height:0"></span>'}
      <span class="chart-tooltip" aria-hidden="true">Income ${formatMoney(week.income)}<br>Spending ${formatMoney(week.expense)}</span>
    </div>`;
  }).join("");
  return `<section class="panel chart-panel">${panelHeading("Cash flow", "Weekly income and spending", legend)}
    <div class="chart" style="--weeks:${weeks.length}" role="group" aria-label="Cash flow for ${formatMonth()}">
      <div class="chart-axis" aria-hidden="true">${[4, 3, 2, 1, 0].map(value => `<span>${formatMoney(step * value, true)}</span>`).join("")}</div>
      <div class="chart-plot">${bars}</div>
      <div class="chart-labels" aria-hidden="true">${weeks.map(week => `<span>${week.label}</span>`).join("")}</div>
    </div>
  </section>`;
}

function spendingBreakdown(expenses, spending) {
  const sorted = Object.entries(expenses).sort((first, second) => second[1] - first[1]);
  const listed = sorted.slice(0, 5).map(([key, amount]) => ({ ...categories[key], amount }));
  if (sorted.length > 5) {
    listed.splice(4, 1, { label: "Remaining categories", color: "#b0bcad", amount: sorted.slice(4).reduce((sum, [, amount]) => sum + amount, 0) });
  }
  let start = 0;
  const segments = listed.map(({ color, amount }) => {
    const left = start;
    start += 100 * amount / spending;
    return `${color} ${left}% ${start}%`;
  });
  const chart = segments.length ? `conic-gradient(${segments.join(", ")})` : "#e8eee8";
  const rows = listed.map(({ label, color, amount }) => `<li><i class="category-dot" style="background:${color}"></i><span>${safe(label)}</span><strong>${formatMoney(amount)}</strong></li>`).join("");
  return `<section class="panel">${panelHeading("Spending breakdown", "Where your money went")}
    <div class="breakdown">
      <div class="donut" style="--donut:${chart}"><div class="donut-center"><strong>${formatMoney(spending, true)}</strong><span>Total spent</span></div></div>
      ${rows ? `<ul class="category-list" aria-label="Spending by category">${rows}</ul>` : '<p class="metric-note">Expenses will appear here as you record them.</p>'}
    </div>
    <div class="category-footer"><span>${sorted.length} ${sorted.length === 1 ? "category" : "categories"}</span><strong>${formatMoney(spending)} total</strong></div>
  </section>`;
}

function badge(category) {
  return `<span style="--tint:${category.tint};--tone:${category.tone ?? category.color}">${icon(category.icon, "tx-icon")}</span>`;
}

function transactionsTable(transactions, { editable = false, filtered = false } = {}) {
  if (transactions.length === 0) {
    return filtered ? empty("No matching transactions", "Try a different search or type.") : empty("No transactions this month", "Add an expense or income entry to get started.");
  }
  return `<div class="table-wrap"><table aria-label="Transactions">
    <thead><tr><th scope="col">Transaction</th><th scope="col">Category</th><th scope="col">Date</th><th scope="col" class="amount">Amount</th>${editable ? '<th scope="col" class="row-actions">Actions</th>' : ""}</tr></thead>
    <tbody>${transactions.map(transaction => {
      const category = categories[transaction.category];
      const income = transaction.type === "income";
      return `<tr><td><div class="tx-name">${badge(category)}<span class="tx-text">${safe(transaction.name)}</span></div></td>
        <td class="tx-category">${safe(category.label)}</td><td class="tx-date"><time datetime="${transaction.date}">${formatDay(transaction.date)}</time></td>
        <td class="amount ${income ? "income" : ""}">${income ? "+" : "−"}${formatMoney(transaction.amount)}</td>
        ${editable ? `<td class="row-actions">${button("", "edit-transaction", { key: transaction.id, symbol: "edit", style: "small icon-only", aria: `Edit ${transaction.name}` })}</td>` : ""}</tr>`;
    }).join("")}</tbody>
  </table></div>`;
}

function progress(value, label, color = "#609275") {
  const bounded = Math.min(100, value);
  return `<div class="progress" role="progressbar" aria-label="${safe(label)}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${bounded}"><span class="progress-fill" style="--progress:${bounded}%;--fill:${color}"></span></div>`;
}

function goalSummary(goal) {
  const style = goalStyles[goal.icon];
  const percentage = Math.floor(goal.saved * 100 / goal.target);
  return `<div class="goal-head"><span style="--tint:${style.tint};--tone:${style.tone}">${icon(goal.icon, "goal-icon")}</span><h3>${safe(goal.name)}</h3><span class="goal-percent">${percentage}%</span></div>
    ${progress(percentage, `${goal.name} progress`, style.fill)}
    <p class="goal-meta">${formatMoney(goal.saved)} of ${formatMoney(goal.target)}</p>`;
}

function renderOverview() {
  const { transactions, expenses, income, spending, budgetTotal, budgetSpent } = monthlyData();
  const savings = income - spending;
  const budgetLeft = budgetTotal - budgetSpent;
  const savingsNote = income ? `${Math.round(savings / income * 100)}% of income` : "Income minus spending";
  const budgetNote = budgetTotal ? `of ${formatMoney(budgetTotal)} in limits` : "Set a monthly budget";
  const action = button("Add transaction", "new-transaction", { symbol: "plus", style: "primary" });
  return `${pageHeader(monthControl() + action)}
    <section class="metrics" aria-label="Monthly totals">
      ${metric("Net savings", savingsNote, formatMoney(savings), "leaf", "featured")}
      ${metric("Income", "Received this month", formatMoney(income), "down")}
      ${metric("Spending", "Spent this month", formatMoney(spending), "up", "expense")}
      ${metric(budgetLeft < 0 ? "Over budget" : "Budget left", budgetNote, budgetTotal ? formatMoney(Math.abs(budgetLeft)) : "—", "wallet", "budget")}
    </section>
    <div class="dashboard-grid">
      ${cashFlow(transactions)}
      ${spendingBreakdown(expenses, spending)}
      <section class="panel">${panelHeading("Recent transactions", "Latest activity this month", pageLink("View all", "transactions"))}
        ${transactionsTable(transactions.slice(0, 4))}
      </section>
      <section class="panel">${panelHeading("Savings goals", "Progress toward your targets", pageLink("View goals", "savings"))}
        ${data().goals.length ? `<div class="goals">${data().goals.slice(0, 3).map(goal => `<article class="goal">${goalSummary(goal)}</article>`).join("")}</div>` : empty("No savings goals yet", "Pick something you’d like to save for.")}
      </section>
    </div>`;
}

function renderFilteredTransactions() {
  const search = filter.search.trim().toLocaleLowerCase();
  const transactions = monthTransactions().filter(transaction =>
    (filter.type === "all" || transaction.type === filter.type) &&
    (!search || `${transaction.name} ${categories[transaction.category].label}`.toLocaleLowerCase().includes(search))
  );
  return transactionsTable(transactions, { editable: Boolean(personal), filtered: Boolean(search) || filter.type !== "all" });
}

function renderTransactions() {
  const add = button("Add transaction", "new-transaction", { symbol: "plus", style: "primary" });
  return `${pageHeader(monthControl() + add)}<section class="panel">
    ${panelHeading("Transaction history", formatMonth())}
    <div class="filter-bar">
      <input type="search" id="transaction-search" aria-label="Search transactions" placeholder="Search transactions" value="${safe(filter.search)}">
      <select id="transaction-type" aria-label="Transaction type">
        ${[["all", "All types"], ["expense", "Expenses"], ["income", "Income"]].map(([value, label]) => `<option value="${value}"${filter.type === value ? " selected" : ""}>${label}</option>`).join("")}
      </select>
    </div>
    <div id="filtered-transactions">${renderFilteredTransactions()}</div>
  </section>`;
}

function renderBudgets() {
  const { budgets, expenses } = monthlyData();
  const add = button("Set budget", "new-budget", { symbol: "plus", style: "primary" });
  return `${pageHeader(monthControl() + add)}${budgets.length ? `<div class="items-grid">${budgets.map(budget => {
    const category = categories[budget.category];
    const used = expenses[budget.category] ?? 0;
    const remaining = budget.limit - used;
    const percent = Math.floor(used * 100 / budget.limit);
    return `<article class="panel"><div class="goal-head">${badge(category)}<h3>${safe(category.label)}</h3><span class="goal-percent">${percent}%</span></div>
      <div class="item-summary"><strong>${formatMoney(used)} spent</strong><span>of ${formatMoney(budget.limit)}</span></div>
      ${progress(percent, `${category.label} budget used`, remaining < 0 ? "#ae5444" : "#609275")}
      <div class="item-summary"><span class="${remaining < 0 ? "over" : ""}">${formatMoney(Math.abs(remaining))} ${remaining < 0 ? "over budget" : "left"}</span></div>
      ${personal ? `<div class="item-actions">${button("Edit budget", "edit-budget", { key: budget.category, symbol: "edit", style: "small" })}</div>` : ""}
    </article>`;
  }).join("")}</div>` : `<section class="panel">${empty("No budgets this month", "Set a limit for a category such as food or transport.", add)}</section>`}`;
}

function renderSavings() {
  const add = button("New goal", "new-goal", { symbol: "plus", style: "primary" });
  const goals = data().goals;
  return `${pageHeader(add)}${goals.length ? `<div class="items-grid">${goals.map(goal => `<article class="panel">
    ${goalSummary(goal)}
    ${personal ? `<div class="item-actions">
      ${button("Add contribution", "contribute", { key: goal.id, symbol: "plus", style: "small primary" })}
      ${button("Edit goal", "edit-goal", { key: goal.id, symbol: "edit", style: "small" })}
    </div>` : ""}
  </article>`).join("")}</div>` : `<section class="panel">${empty("No goals yet", "Create a goal and add contributions as you save.", add)}</section>`}`;
}

function renderSettings() {
  const currency = data().currency;
  const hasRecords = personal && (personal.transactions.length || personal.goals.length || Object.keys(personal.budgets).length);
  return `${pageHeader()}<div class="page-content">
    <section class="panel">
      ${panelHeading("Currency")}
      <p class="settings-copy">${hasRecords ? "Currency is fixed after you add records to keep your amounts consistent." : "Choose the currency you use for your budget before adding records."}</p>
      <form id="currency-form" class="settings-form">
        <label class="field">Budget currency <select name="currency" ${hasRecords ? "disabled" : ""}>
          ${Object.entries(currencies).map(([code, name]) => `<option value="${code}"${currency === code ? " selected" : ""}>${code} · ${name}</option>`).join("")}
        </select></label>
        ${hasRecords ? "" : '<button class="button primary" type="submit">Save currency</button>'}
      </form>
    </section>
    <section class="panel">
      ${panelHeading("Budget data")}
      <p class="settings-copy">Tally saves your records in this browser. Export a backup to keep a copy or move it to another browser.</p>
      <div class="item-actions">
        ${personal ? button("Export data", "export", { symbol: "download" }) : button("Start tracking", "start", { style: "primary" })}
        ${button("Import backup", "import", { symbol: "upload" })}
        <input type="file" id="backup-file" accept=".json,application/json" hidden>
      </div>
    </section>
  </div>`;
}

function render() {
  document.querySelector("#current-page").textContent = pages[page].title;
  document.querySelector("#workspace-currency").textContent = `${data().currency} · ${currencies[data().currency]}`;
  document.querySelector("#data-mode").innerHTML = personal
    ? `<span class="mode-label is-local">${icon("lock")} This browser</span>`
    : `<span class="mode-label">${icon("info")} Example data</span>${button("Start tracking", "start", { style: "small" })}`;
  for (const link of document.querySelectorAll("[data-page]")) {
    if (link.dataset.page === page) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  document.title = `${pages[page].title} · Tally`;
  const views = { overview: renderOverview, transactions: renderTransactions, budgets: renderBudgets, savings: renderSavings, settings: renderSettings };
  main.innerHTML = views[page]();
}

function options(entries, selected) {
  return entries.map(([value, label]) => `<option value="${safe(value)}"${value === selected ? " selected" : ""}>${safe(label)}</option>`).join("");
}

function categoryOptions(type, selected) {
  const keys = type === "income" ? incomeCategories : expenseCategories;
  return options(keys.map(key => [key, categories[key].label]), selected);
}

function amountField(label, name, value, allowZero = false) {
  const step = data().currency === "VND" ? 1 : 0.01;
  return `<label class="field">${label} (${data().currency})
    <input name="${name}" type="number" inputmode="decimal" min="${allowZero ? 0 : step}" max="${amountLimit / 100}" step="${step}" value="${value === undefined ? "" : value / 100}" required>
  </label>`;
}

function openEditor(context, title, fields, submitLabel = "Save", deleteLabel = "") {
  editContext = context;
  editor.innerHTML = `<div class="dialog-head"><h2 id="dialog-title">${title}</h2>
    ${button("", "close-editor", { symbol: "close", style: "small icon-only", aria: "Close dialog" })}
  </div>
  <div class="dialog-fields">${fields}<p class="form-error" role="alert"></p></div>
  <div class="dialog-foot">
    ${deleteLabel ? button(deleteLabel, "delete-record", { style: "danger" }) : ""}
    ${button("Cancel", "close-editor")}
    <button type="submit" class="button ${context.kind === "delete" ? "danger" : "primary"}">${submitLabel}</button>
  </div>`;
  if (!dialog.open) dialog.showModal();
  (editor.querySelector("input, select") ?? editor.querySelector(".dialog-foot [data-action=close-editor]")).focus();
}

function openTransaction(id) {
  const item = personal?.transactions.find(transaction => transaction.id === id);
  const type = item?.type ?? "expense";
  const prospectiveDate = selectedMonth === today.slice(0, 7) ? today : `${selectedMonth}-01`;
  const fields = `<label class="field">Name <input name="name" placeholder="e.g. Groceries" value="${safe(item?.name ?? "")}" maxlength="70" required></label>
    <div class="fields-pair">
      <label class="field">Type <select name="type">${options([["expense", "Expense"], ["income", "Income"]], type)}</select></label>
      <label class="field">Category <select name="category">${categoryOptions(type, item?.category)}</select></label>
    </div>
    <div class="fields-pair">
      ${amountField("Amount", "amount", item?.amount)}
      <label class="field">Date <input name="date" type="date" min="2000-01-01" max="2099-12-31" value="${item?.date ?? prospectiveDate}" required></label>
    </div>`;
  openEditor({ kind: "transaction", id }, item ? "Edit transaction" : "Add transaction", fields, "Save transaction", item ? "Delete" : "");
}

function openBudget(category) {
  const month = selectedMonth;
  const budgets = personal?.budgets ?? {};
  const limit = budgets[`${month}/${category}`];
  const available = category ? [category] : expenseCategories.filter(key => budgets[`${month}/${key}`] === undefined);
  if (!available.length) return notify("Every category has a budget this month. Select Edit budget to update a limit.");
  const fields = `<p class="settings-copy">${formatMonth(month)}</p>
    <label class="field">Category <select name="category">${options(available.map(key => [key, categories[key].label]), category)}</select></label>
    ${amountField("Monthly limit", "amount", limit)}`;
  openEditor({ kind: "budget", id: category, month }, category ? "Edit budget" : "Set a budget", fields, "Save budget", category ? "Delete" : "");
}

function openGoal(id) {
  const goal = personal?.goals.find(item => item.id === id);
  const fields = `<label class="field">Goal name <input name="name" maxlength="70" value="${safe(goal?.name ?? "")}" placeholder="e.g. Emergency fund" required></label>
    <label class="field">Icon <select name="icon">${options([["target", "Target"], ["shield", "Shield"], ["plane", "Plane"], ["laptop", "Laptop"]], goal?.icon)}</select></label>
    <div class="fields-pair">
      ${amountField("Target amount", "target", goal?.target)}
      ${amountField("Already saved", "saved", goal?.saved ?? 0, true)}
    </div>`;
  openEditor({ kind: "goal", id }, goal ? "Edit savings goal" : "New savings goal", fields, "Save goal", goal ? "Delete" : "");
}

function openContribution(id) {
  const goal = personal.goals.find(item => item.id === id);
  if (!goal) return notify("This goal is no longer available.");
  openEditor({ kind: "contribution", id }, "Add contribution",
    `<p class="settings-copy">${safe(goal.name)} · ${formatMoney(goal.saved)} saved so far</p>${amountField("Contribution", "amount")}`,
    "Save contribution");
}

function openDelete() {
  const record = editContext;
  const labels = { transaction: "transaction", budget: "budget", goal: "goal" };
  const label = labels[record.kind];
  if (!label) return;
  openEditor({ kind: "delete", record }, `Delete ${label}?`,
    `<p class="settings-copy">This ${label} will be removed from your budget.</p>`, `Delete ${label}`);
}

function getAmount(values, name, allowZero = false) {
  const raw = values.get(name);
  const value = typeof raw === "string" && /^(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$/.test(raw) ? Math.round(Number(raw) * 100) : NaN;
  if (!validAmount(value, allowZero, data().currency)) throw new Error("Enter a valid amount.");
  return value;
}

function getName(values) {
  const name = values.get("name").trim();
  if (!validName(name)) throw new Error("Enter a name of 1 to 70 characters.");
  return name;
}

function saveEditor(event) {
  event.preventDefault();
  const values = new FormData(editor);
  const context = editContext;
  if (!context) return;
  const next = structuredClone(personal ?? blankData());
  let message;
  let transactionMonth;
  try {
    switch (context.kind) {
      case "start":
        if (personal) throw new Error("Your budget is already set up.");
        break;
      case "transaction": {
        const type = values.get("type");
        const category = values.get("category");
        const date = values.get("date");
        if (!validDate(date) || !validCategory(type, category)) throw new Error("Choose a valid date, type, and category.");
        const record = { id: context.id ?? crypto.randomUUID(), name: getName(values), type, category, date, amount: getAmount(values, "amount") };
        if (context.id) {
          if (!next.transactions.some(transaction => transaction.id === context.id)) throw new Error("This transaction is no longer available.");
          next.transactions = next.transactions.map(transaction => transaction.id === context.id ? record : transaction);
        } else {
          next.transactions.unshift(record);
        }
        transactionMonth = date.slice(0, 7);
        message = "Transaction saved.";
        break;
      }
      case "budget": {
        const category = values.get("category");
        if (!expenseCategories.includes(category)) throw new Error("Choose a spending category.");
        const key = `${context.month}/${category}`;
        if (!context.id && next.budgets[key] !== undefined) throw new Error("This category already has a budget for the month.");
        next.budgets[key] = getAmount(values, "amount");
        message = "Budget saved.";
        break;
      }
      case "goal": {
        const symbol = values.get("icon");
        if (!Object.hasOwn(goalStyles, symbol)) throw new Error("Select a goal icon.");
        const record = { id: context.id ?? crypto.randomUUID(), name: getName(values), icon: symbol, target: getAmount(values, "target"), saved: getAmount(values, "saved", true) };
        if (context.id) {
          if (!next.goals.some(goal => goal.id === context.id)) throw new Error("This goal is no longer available.");
          next.goals = next.goals.map(goal => goal.id === context.id ? record : goal);
        } else {
          next.goals.push(record);
        }
        message = "Goal saved.";
        break;
      }
      case "contribution": {
        const goal = next.goals.find(item => item.id === context.id);
        if (!goal) throw new Error("This goal is no longer available.");
        const total = goal.saved + getAmount(values, "amount");
        if (total > amountLimit) throw new Error("This contribution would take the saved amount above the supported maximum.");
        goal.saved = total;
        message = "Contribution added.";
        break;
      }
      case "delete": {
        const { kind, id, month } = context.record;
        if (kind === "transaction") next.transactions = next.transactions.filter(item => item.id !== id);
        if (kind === "goal") next.goals = next.goals.filter(item => item.id !== id);
        if (kind === "budget") delete next.budgets[`${month}/${id}`];
        message = "Record deleted.";
        break;
      }
      case "import":
        if (saveData(context.backup)) {
          selectedMonth = monthForBackup(context.backup);
          finishEditor("Backup restored.");
        }
        return;
      default:
        return;
    }
    if (!saveData(next)) {
      throw new Error("Couldn’t save to this browser. Check browser storage and try again.");
    }
    if (transactionMonth) selectedMonth = transactionMonth;
    finishEditor(message);
  } catch (error) {
    editor.querySelector(".form-error").textContent = error.message;
  }
}

function finishEditor(message) {
  dialog.close();
  render();
  main.querySelector("h1").setAttribute("tabindex", "-1");
  main.querySelector("h1").focus({ preventScroll: true });
  if (message) notify(message);
}

function validName(value) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= 70;
}

function validDate(value) {
  if (typeof value !== "string" || !/^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/.test(value)) return false;
  return dateKey(dateObject(value)) === value;
}

function validCategory(type, category) {
  return (type === "expense" && expenseCategories.includes(category)) ||
    (type === "income" && incomeCategories.includes(category));
}

function validAmount(value, allowZero, currency) {
  return Number.isSafeInteger(value) && value >= (allowZero ? 0 : 1) && value <= amountLimit &&
    (currency !== "VND" || value % 100 === 0);
}

function validRecords(records, validateItem) {
  if (!Array.isArray(records)) return false;
  const keys = new Set();
  for (const record of records) {
    if (!record || typeof record.id !== "string" || !/^[\w-]{1,80}$/.test(record.id) || keys.has(record.id) || !validateItem(record)) return false;
    keys.add(record.id);
  }
  return true;
}

function validateBackup(backup) {
  const invalid = () => new Error("This file isn’t a valid Tally backup.");
  if (!backup || backup.version !== 1 || !Object.hasOwn(currencies, backup.currency)) throw invalid();
  const { currency, transactions, budgets, goals } = backup;
  if (!validRecords(transactions, item => validName(item.name) && validDate(item.date) &&
    validCategory(item.type, item.category) && validAmount(item.amount, false, currency))) throw invalid();
  if (!budgets || typeof budgets !== "object" || Array.isArray(budgets)) throw invalid();
  for (const [key, value] of Object.entries(budgets)) {
    const [month, category, extra] = key.split("/");
    if (extra !== undefined || !/^20\d{2}-(0[1-9]|1[0-2])$/.test(month) ||
      !expenseCategories.includes(category) || !validAmount(value, false, currency)) throw invalid();
  }
  if (!validRecords(goals, item => validName(item.name) && Object.hasOwn(goalStyles, item.icon) &&
    validAmount(item.target, false, currency) && validAmount(item.saved, true, currency))) throw invalid();
  return {
    version: 1, currency, budgets,
    transactions: transactions.map(({ id, date, name, category, type, amount }) => ({ id, date, name, category, type, amount })),
    goals: goals.map(({ id, name, icon: symbol, target, saved }) => ({ id, name, icon: symbol, target, saved })),
  };
}

function monthForBackup(backup) {
  const months = new Set([
    ...backup.transactions.map(item => item.date.slice(0, 7)),
    ...Object.keys(backup.budgets).map(key => key.slice(0, 7)),
  ]);
  const currentMonth = today.slice(0, 7);
  return months.has(currentMonth) ? currentMonth : [...months].sort().at(-1) ?? currentMonth;
}

function exportData() {
  const file = new Blob([JSON.stringify(personal, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(file);
  const link = document.createElement("a");
  link.href = url;
  link.download = `tally-backup-${today}.json`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  notify("Backup downloaded.");
}

async function importData(input) {
  const file = input.files[0];
  input.value = "";
  if (!file) return;
  try {
    if (file.size > 10_000_000) throw new Error("Choose a Tally backup smaller than 10 MB.");
    let parsed;
    try {
      parsed = JSON.parse(await file.text());
    } catch {
      throw new Error("This file isn’t a valid Tally backup.");
    }
    const backup = validateBackup(parsed);
    const description = personal ? "Restoring this backup will replace the budget in this browser." : "The backup will become your budget in this browser.";
    openEditor({ kind: "import", backup }, "Restore backup?", `<p class="settings-copy">${description}</p>`, "Restore backup");
  } catch (error) {
    notify(error.message);
  }
}

function changeMonth(direction) {
  const month = dateObject(selectedMonth);
  month.setMonth(month.getMonth() + direction);
  const next = dateKey(month).slice(0, 7);
  if (next < "2000-01" || next > "2099-12") return;
  selectedMonth = next;
  render();
  const action = direction > 0 ? "next-month" : "previous-month";
  const oppositeAction = direction > 0 ? "previous-month" : "next-month";
  (document.querySelector(`[data-action="${action}"]:enabled`) ?? document.querySelector(`[data-action="${oppositeAction}"]`))?.focus();
}

function startTracking() {
  if (personal) return;
  if (!saveData(blankData())) return;
  render();
  notify("Your budget is ready.");
  main.focus();
}

function performAction(action, key) {
  switch (action) {
    case "previous-month": changeMonth(-1); break;
    case "next-month": changeMonth(1); break;
    case "start":
      if (storageError) {
        openEditor({ kind: "start" }, "Start a blank budget?", `<p class="settings-copy">${safe(storageError)} Starting fresh will replace the current browser data.</p>`, "Start tracking");
      } else {
        startTracking();
      }
      break;
    case "new-transaction":
    case "new-budget":
    case "new-goal":
      if (storageError) {
        notify(storageError);
        break;
      }
      if (action === "new-transaction") openTransaction();
      if (action === "new-budget") openBudget();
      if (action === "new-goal") openGoal();
      break;
    case "edit-transaction": if (requirePersonal()) openTransaction(key); break;
    case "edit-budget": if (requirePersonal()) openBudget(key); break;
    case "edit-goal": if (requirePersonal()) openGoal(key); break;
    case "contribute": if (requirePersonal()) openContribution(key); break;
    case "delete-record": openDelete(); break;
    case "close-editor": dialog.close(); break;
    case "export": if (requirePersonal()) exportData(); break;
    case "import": document.querySelector("#backup-file")?.click(); break;
    default:
      break;
  }
}

document.querySelectorAll("[data-icon]").forEach(element => {
  element.innerHTML = iconMarkup(element.dataset.icon);
});
document.querySelector(".skip-link").addEventListener("click", event => {
  event.preventDefault();
  main.focus();
});
document.addEventListener("click", event => {
  const target = event.target.closest("[data-action]");
  if (target) performAction(target.dataset.action, target.dataset.key);
});
document.addEventListener("input", event => {
  if (event.target.id !== "transaction-search") return;
  filter.search = event.target.value;
  document.querySelector("#filtered-transactions").innerHTML = renderFilteredTransactions();
});
document.addEventListener("change", event => {
  if (event.target.id === "transaction-type") {
    filter.type = event.target.value;
    document.querySelector("#filtered-transactions").innerHTML = renderFilteredTransactions();
  }
  if (event.target.id === "backup-file") void importData(event.target);
});
document.addEventListener("submit", event => {
  if (event.target.id !== "currency-form") return;
  event.preventDefault();
  const currency = new FormData(event.target).get("currency");
  if (!Object.hasOwn(currencies, currency)) return;
  if (storageError) return notify(storageError);
  if (saveData({ ...(personal ?? blankData()), currency })) {
    render();
    document.querySelector("#currency-form select").focus();
    notify("Currency saved.");
  }
});
editor.addEventListener("change", event => {
  if (editContext?.kind === "transaction" && event.target.name === "type") {
    editor.elements.category.innerHTML = categoryOptions(event.target.value);
  }
});
editor.addEventListener("submit", saveEditor);
dialog.addEventListener("close", () => { if (!dialog.open) editContext = null; });
window.addEventListener("hashchange", () => {
  page = pageFromHash();
  render();
  window.scrollTo(0, 0);
  main.focus({ preventScroll: true });
});
window.addEventListener("storage", event => {
  if (event.key !== storageKey && event.key !== null) return;
  if (dialog.open) {
    dialog.close();
    notify("Your budget changed in another tab. Reopen the editor to continue.");
  }
  personal = readData();
  render();
});
render();
if (storageError) notify(storageError);
