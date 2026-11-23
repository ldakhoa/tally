# Tally

A personal budget for tracking income, spending, monthly category limits, and savings goals.

## Run locally

From this directory, serve the static files with Python 3:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
```

Open http://127.0.0.1:4173 and select **Start tracking** to create a blank budget. The first view contains example data. SGD is the default currency and can be changed in Settings before entering records.

Transactions, budgets, and savings progress are stored in your current browser for the app's address. Use **Export data** and **Import backup** in Settings to move your budget or keep a copy. Record goal contributions separately from expenses. Net savings is monthly income minus expenses.
