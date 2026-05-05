# Customer Segmentation Dashboard
**RFM Analysis · Online Retail UK · SQL + Power BI · 2026**

---

## Project Overview
End-to-end customer segmentation project using **RFM (Recency, Frequency, Monetary)** analysis on a real-world UK e-commerce dataset of 1 million+ transactions.

Built using **MySQL** for all data engineering and **Power BI** for a 3-page interactive dashboard.

---

## Tech Stack
| Tool | Purpose |
|------|---------|
| MySQL 8.0 | Database design, data import, cleaning, RFM scoring |
| Power BI Desktop | Data modelling (star schema), DAX, dashboard |
| SQL (CTEs, Window Functions) | NTILE(5) scoring, Views, JOINs |

---

## Dataset
- **Source:** [Online Retail II Dataset — Kaggle (UCI ML Repository)](https://www.kaggle.com/datasets/mashlyn/online-retail-ii-uci)
- **Size:** 1,067,371 rows, 8 columns
- **Period:** December 2009 – December 2011
- **Columns:** Invoice, StockCode, Description, Quantity, InvoiceDate, Price, CustomerID, Country

---

## Project Structure
```
Customer-Segmentation-RFM/
│
├── Customer_Segmentation_Dashboard.pbix    # Power BI dashboard (3 pages)
├── Customer_Segmentation_Dataset.csv       # Sample dataset
├── Customer_Segmentation_Presentation.pptx  # Presentation slides
│
└── sql/
    └── project.sql                          # All SQL: schema, cleaning, RFM
```

---

## Data Cleaning
**162,677 rows removed** in 3 passes:

| Issue | Rows Removed | Reason |
|-------|-------------|--------|
| NULL CustomerID | 243,007 | Cannot segment unknown customers |
| Negative Quantity | 22,950 | Returns and cancellations |
| Zero Price | 6,202 | Free samples / internal transfers |
| Corrupted Dates (year 2031) | 174 | Caused negative recency values |

**Final clean dataset: 904,607 rows**

---

## RFM Scoring Logic
Each customer is scored 1–5 on each dimension using `NTILE(5)` window function:

```sql
CREATE OR REPLACE VIEW rfm_scores AS
SELECT customer_id, recency_days, frequency, monetary,
    6 - NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
    NTILE(5) OVER (ORDER BY frequency ASC)         AS f_score,
    NTILE(5) OVER (ORDER BY monetary ASC)          AS m_score
FROM rfm_raw;
```

Scores are summed (range 3–15) and mapped to segments:

| Segment | Score Range | Business Action |
|---------|------------|-----------------|
| Champion | 13–15 | Reward, upsell, ask for reviews |
| Loyal | 10–12 | Loyalty programme, exclusive offers |
| At Risk | 7–9 | Win-back campaigns, discounts |
| Dormant | 4–6 | Re-engagement emails |
| New | 3 | Onboarding, first purchase incentive |

---

## Dashboard Pages
1. **Customer Overview** — Total revenue, KPIs, revenue by country, monthly trend
2. **RFM Segment Analysis** — Scatter plot, segment bar chart, top customers table
3. **Retention & Trends** — Area chart, retention funnel, revenue heatmap

---

## Key Insights
- **36.53M total revenue** across 4,300+ unique customers
- **Champions generate the highest revenue share** — 80/20 rule confirmed
- **Q4 spike every year** — Oct–Dec revenue surge (holiday retail effect)
- **UK dominates at 69%+** — international markets are growth opportunities

---

## Difficulties Faced
1. **Import Timeout (1M rows)** — MySQL Workbench GUI timed out. Fixed using `LOAD DATA INFILE` which completed in 30 seconds.
2. **Negative Recency Values** — Corrupted dates (year 2031) detected using `MAX(invoice_date)`. Deleted 174 rows and recreated RFM view.
3. **Power BI MySQL Connection Error** — MySQL Connector/NET was not installed. Downloaded and installed from mysql.com.
4. **LOAD DATA LOCAL INFILE Error 2068** — MySQL 8.0 restricts local file access. Moved CSV to secure uploads folder and used `LOAD DATA INFILE` (without LOCAL).
5. **DAX DATESMTD Error** — Function requires a unique-date calendar table. The `orders` table has duplicate dates. Replaced with Year slicer — more practical for historical data.

---

## Skills Demonstrated
- **SQL:** LOAD DATA INFILE, Data cleaning, EDA, CTEs, Window Functions (NTILE, PERCENT_RANK, SUM OVER PARTITION), Views, JOINs, CASE statements
- **Power BI:** Star schema, DAX measures, Multi-page dashboard, Navigation buttons, Conditional formatting, AI Visuals (Funnel, Heatmap)
- **Data Quality:** NULL handling, duplicate detection, date validation, outlier removal
- **Business Thinking:** RFM segmentation, CLV analysis, retention strategy, win-back identification

---

## Author
**Y Vishnu Reddy** | Data Analyst | 2026
