# Customer Segmentation Project — Documentation Notes
**Y Vishnu Reddy | Online Retail UK Dataset | SQL + Power BI | 2026**

---

## Project Overview
End-to-end customer segmentation project using RFM (Recency, Frequency, Monetary) analysis on a real-world UK e-commerce dataset of 1 million+ transactions. Built using MySQL for data engineering, and Power BI for dashboarding.

---

## Dataset
- **Source:** Online Retail II Dataset — Kaggle (UCI Machine Learning Repository)
- **Size:** 1,067,371 rows, 8 columns
- **Period:** December 2009 – December 2011
- **Columns:** Invoice, StockCode, Description, Quantity, InvoiceDate, Price, CustomerID, Country

---

## Problems Faced & How I Solved Them

### Problem 1 — Importing 1 Million Rows (LOAD DATA ERROR)
**What happened:** MySQL Workbench's Table Data Import Wizard was extremely slow for 1 million rows and kept timing out.

**Solution:** Used `LOAD DATA INFILE` instead of the Wizard. This required:
1. Enabling `local_infile` on the MySQL server
2. Moving the CSV to MySQL's secure upload folder (`C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/`)
3. Using `LOAD DATA INFILE` (without LOCAL keyword) which completed in under 30 seconds

**Learning:** For large datasets always use LOAD DATA INFILE over the GUI wizard. It is 100x faster.

---

### Problem 2 — Data Cleaning (162,677 rows removed)
**What happened:** The raw dataset contained three types of bad data that would corrupt the RFM analysis.

**What was removed and why:**
- **243,007 rows with NULL CustomerID** — Cannot do customer analysis without knowing who the customer is
- **22,950 rows with negative Quantity** — These are returns/cancellations, not purchases
- **6,202 rows with zero Price** — These are free samples or internal transfers, not real sales

**Solution:**
```sql
DELETE FROM orders WHERE customer_id IS NULL OR TRIM(customer_id) = '';
DELETE FROM orders WHERE quantity <= 0;
DELETE FROM orders WHERE price <= 0;
```

**Result:** 904,607 clean rows ready for analysis.

---

### Problem 3 — Corrupted Date Values (Negative Recency)
**What happened:** During Power BI dashboard building, the Avg Recency Days KPI card showed a negative value (-260.03). 

**Root cause:** Some invoice dates in the dataset were corrupted — recorded as 2031 and 2012 instead of 2011. This caused DATEDIFF to return negative values when compared against the snapshot date of 2011-12-10.

**How I found it:**
```sql
SELECT COUNT(*) FROM rfm_raw WHERE recency_days < 0; -- returned 1,351
SELECT MAX(invoice_date) FROM orders; -- returned 2031-01-10
```

**Solution:** Removed the corrupted rows (174 total) as they had no valid business meaning, then recreated the rfm_raw view.
```sql
SET SQL_SAFE_UPDATES = 0;
DELETE FROM orders WHERE YEAR(invoice_date) > 2011;
SET SQL_SAFE_UPDATES = 1;
```

**Result:** All recency values became positive. Avg Recency Days showed correctly in Power BI.

**Learning:** Always validate date columns before building time-based metrics. Use MAX(date) and MIN(date) checks as part of the data cleaning phase.

---

### Problem 4 — Power BI MySQL Connection Error
**What happened:** Power BI could not connect to MySQL — showing "Internal connection fatal error. Error state: 18"

**Root cause:** MySQL Connector/NET was not installed on the machine. Power BI requires this additional driver to communicate with MySQL.

**Solution:** Downloaded and installed MySQL Connector/NET from mysql.com/products/connector, restarted Power BI, and reconnected successfully.

**Learning:** Always install the relevant database connector before attempting to connect Power BI to any external database.

---

### Problem 5 — LOAD DATA LOCAL INFILE Rejected (Error 2068)
**What happened:** Running LOAD DATA LOCAL INFILE returned "file request rejected due to restrictions on access."

**Root cause:** MySQL 8.0 has strict local file access restrictions by default.

**Solution:**
1. Added `OPT_LOCAL_INFILE=1` to MySQL Workbench connection Advanced settings
2. Ran `SET GLOBAL local_infile = 1;`
3. Switched to `LOAD DATA INFILE` (without LOCAL) using the secure uploads folder

---

## Key Analytical Decisions

### Why RFM over simple revenue sorting?
Sorting by revenue only tells you who spent the most historically. RFM adds recency and frequency — so a high spender who hasn't returned in 6 months (At Risk) is treated differently from one who buys every week (Champion). That distinction drives completely different business actions.

### Why NTILE(5)?
RFM scoring traditionally uses quintiles — 5 equal groups — because it gives a balanced 1–5 scale that is easy to combine and interpret. NTILE(5) divides all customers into 5 equal buckets using a window function without any manual threshold setting.

### Why snapshot date 2011-12-10?
This is approximately one week after the dataset's last valid transaction date. Using a date after the last transaction ensures all recency values are positive and the scores are stable and comparable.

### Why not delete data to fix the date issue?
In a production environment the better approach would be to adjust the snapshot date forward rather than deleting records. However since the affected rows (174) had clearly corrupted dates with no valid business meaning, removal was acceptable for this project.

---

## RFM Segment Definitions

| Segment | Score Range | Description | Business Action |
|---|---|---|---|
| Champion | 13–15 | High R + F + M. Best customers | Reward, upsell, ask for reviews |
| Loyal | 10–12 | Regular buyers, decent spend | Loyalty programme, exclusive offers |
| At Risk | 7–9 | Good history, recent drop-off | Win-back campaigns, discounts |
| Dormant | 4–6 | Haven't bought in long time | Re-engagement emails |
| New | 3 | Recently acquired, few orders | Onboarding, first purchase incentive |

---

## Skills Demonstrated
- SQL: Database design, LOAD DATA INFILE, Data cleaning, EDA, CTEs, Window Functions (NTILE, PERCENT_RANK, SUM OVER PARTITION), Views, JOINs, CASE statements
- Power BI: Data modelling (star schema), DAX measures, Multi-page dashboard, Navigation buttons, Conditional formatting, Slicers
- Data Quality: NULL handling, duplicate detection, date validation, outlier removal
- Business Thinking: RFM segmentation, CLV analysis, retention strategy, win-back identification
