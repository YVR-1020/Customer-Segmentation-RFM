CREATE DATABASE IF NOT EXISTS customer_segmentation;
USE customer_segmentation;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/online_retail_II.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(invoice, stock_code, description, quantity, @inv_date, price, customer_id, country)
SET invoice_date = STR_TO_DATE(@inv_date, '%Y-%m-%d %H:%i:%s');

SHOW VARIABLES LIKE 'secure_file_priv';

CREATE TABLE orders (
  invoice        VARCHAR(20),
  stock_code     VARCHAR(20),
  description    VARCHAR(200),
  quantity       INT,
  invoice_date   DATETIME,
  price          DECIMAL(10,2),
  customer_id    VARCHAR(20),
  country        VARCHAR(50)
);

-- Confirm row count
SELECT COUNT(*) AS total_rows FROM orders;

-- Preview first 5 rows
SELECT * FROM orders LIMIT 5;
SET SQL_SAFE_UPDATES = 0;
-- 1. Remove rows with no customer ID
DELETE FROM orders 
WHERE customer_id IS NULL OR TRIM(customer_id) = '';

-- 2. Remove returns and cancellations (negative quantity)
DELETE FROM orders 
WHERE quantity <= 0;

-- 3. Remove zero price rows
DELETE FROM orders 
WHERE price <= 0;

-- 4. Add total_amount column
ALTER TABLE orders ADD COLUMN total_amount DECIMAL(10,2);
UPDATE orders SET total_amount = quantity * price;

## Phase 3 EDA analysis
-- 1. Revenue by country (top 10)
SELECT 
  country,
  COUNT(DISTINCT customer_id)     AS customers,
  COUNT(*)                        AS total_orders,
  ROUND(SUM(total_amount), 2)     AS total_revenue
FROM orders
GROUP BY country
ORDER BY total_revenue DESC
LIMIT 10;

-- 2. Revenue by month
SELECT 
  YEAR(invoice_date)              AS yr,
  MONTH(invoice_date)             AS mth,
  COUNT(DISTINCT customer_id)     AS unique_customers,
  COUNT(DISTINCT invoice)         AS total_invoices,
  ROUND(SUM(total_amount), 2)     AS monthly_revenue
FROM orders
GROUP BY yr, mth
ORDER BY yr, mth;


-- 3. Top 10 customers by spend
SELECT 
  customer_id,
  COUNT(DISTINCT invoice)         AS total_orders,
  ROUND(SUM(total_amount), 2)     AS lifetime_value,
  MAX(invoice_date)               AS last_order_date
FROM orders
GROUP BY customer_id
ORDER BY lifetime_value DESC
LIMIT 10;

-- 4. Top 5 product categories by revenue
SELECT 
  description,
  COUNT(*)                        AS times_ordered,
  ROUND(SUM(total_amount), 2)     AS revenue
FROM orders
GROUP BY description
ORDER BY revenue DESC
LIMIT 10;

-- 5. Average Order Value by country
SELECT
  country,
  COUNT(DISTINCT invoice) AS orders,
  ROUND(SUM(total_amount) / COUNT(DISTINCT invoice), 2) AS avg_order_value
FROM orders
GROUP BY country
ORDER BY avg_order_value DESC
LIMIT 10;

-- 6. Repeat vs One-time customers
SELECT
  CASE 
    WHEN order_count = 1 THEN 'One-time buyer'
    WHEN order_count BETWEEN 2 AND 5 THEN 'Occasional buyer'
    ELSE 'Loyal buyer'
  END AS buyer_type,
  COUNT(*) AS customer_count
FROM (
  SELECT customer_id, COUNT(DISTINCT invoice) AS order_count
  FROM orders
  GROUP BY customer_id
) temp
GROUP BY buyer_type;

--  Use 1 week after the dataset's last transaction (2011-12-04)
--  so recency scores are stable and meaningful.
 
SET @snapshot_date = '2011-12-10';

-- 4.2  Raw RFM metrics per customer
CREATE OR REPLACE VIEW rfm_raw AS
SELECT
    customer_id,
    DATEDIFF('2011-12-10', MAX(invoice_date))   AS recency_days,
    COUNT(DISTINCT invoice)                      AS frequency,
    ROUND(SUM(total_amount), 2)                  AS monetary
FROM orders
GROUP BY customer_id;
-- Verify
SELECT * FROM rfm_raw ORDER BY monetary DESC LIMIT 10;

-- 4.3  Score each RFM dimension using NTILE(5) 
--  Each customer gets a score 1–5 per dimension.
--  R is reversed: fewer days since purchase = higher score.
CREATE OR REPLACE VIEW rfm_scores AS
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    6 - NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
    NTILE(5)     OVER (ORDER BY frequency    ASC)  AS f_score,
    NTILE(5)     OVER (ORDER BY monetary     ASC)  AS m_score
FROM rfm_raw;

-- Verify scoring distribution
SELECT
    r_score, COUNT(*) AS customers
FROM rfm_scores
GROUP BY r_score ORDER BY r_score;

-- 4.4  Combine scores → assign segment labels
--  Total RFM Score = R + F + M  (range: 3 to 15)
--  Champion  ≥ 13  |  Loyal ≥ 10  |  At Risk ≥ 7
--  Dormant   ≥ 4   |  New = 3
CREATE OR REPLACE VIEW rfm_segments AS
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score)   AS total_rfm_score,
    CASE
        WHEN (r_score + f_score + m_score) >= 13 THEN 'Champion'
        WHEN (r_score + f_score + m_score) >= 10 THEN 'Loyal'
        WHEN (r_score + f_score + m_score) >= 7  THEN 'At Risk'
        WHEN (r_score + f_score + m_score) >= 4  THEN 'Dormant'
        ELSE                                          'New'
    END AS segment
FROM rfm_scores;
SELECT * FROM rfm_segments LIMIT 10;

-- 4.5  Segment summary — the core business output 
SELECT
    segment,
    COUNT(customer_id)                                     AS customer_count,
    ROUND(COUNT(customer_id) * 100.0 / 5860, 1)           AS pct_of_customers,
    ROUND(AVG(recency_days), 0)                            AS avg_recency_days,
    ROUND(AVG(frequency), 1)                               AS avg_orders,
    ROUND(AVG(monetary), 2)                                AS avg_lifetime_value,
    ROUND(SUM(monetary), 2)                                AS segment_total_revenue
FROM rfm_segments
GROUP BY segment
ORDER BY avg_lifetime_value DESC;

-- 4.6  RFM score distribution (histogram data for Power BI) 
SELECT
    total_rfm_score,
    segment,
    COUNT(*) AS customer_count
FROM rfm_segments
GROUP BY total_rfm_score, segment
ORDER BY total_rfm_score;

-- 5.1  Champion customer full profile 
 
WITH champions AS (
    SELECT customer_id
    FROM rfm_segments
    WHERE segment = 'Champion'
)
SELECT
    c.customer_id,
    r.frequency                              AS total_orders,
    ROUND(r.monetary, 2)                     AS lifetime_value,
    r.recency_days                           AS days_since_last_order,
    o.country,
    r.r_score,
    r.f_score,
    r.m_score,
    r.total_rfm_score
FROM champions c
JOIN rfm_segments r  ON c.customer_id = r.customer_id
JOIN (
    SELECT customer_id, country
    FROM orders
    GROUP BY customer_id, country
) o ON c.customer_id = o.customer_id
ORDER BY r.monetary DESC
LIMIT 20;

-- 5.2  Dormant customers with historically high spend
 
WITH dormant AS (
    SELECT customer_id
    FROM rfm_segments
    WHERE segment = 'Dormant'
)
SELECT
    d.customer_id,
    r.monetary                               AS lifetime_value,
    r.recency_days                           AS days_inactive,
    r.frequency                              AS past_orders,
    o.country
FROM dormant d
JOIN rfm_segments r ON d.customer_id = r.customer_id
JOIN (
    SELECT customer_id, country
    FROM orders
    GROUP BY customer_id, country
) o ON d.customer_id = o.customer_id
WHERE r.monetary > 1000
ORDER BY r.monetary DESC
LIMIT 30;

-- 5.3  At Risk customers — good history, recent drop-off 
 
SELECT
    s.customer_id,
    o.country,
    ROUND(s.monetary, 2)                     AS lifetime_value,
    s.frequency                              AS past_orders,
    s.recency_days                           AS days_since_last_order,
    s.total_rfm_score
FROM rfm_segments s
JOIN (
    SELECT customer_id, country
    FROM orders
    GROUP BY customer_id, country
) o ON s.customer_id = o.customer_id
WHERE s.segment = 'At Risk'
  AND s.monetary > 2000
ORDER BY s.monetary DESC
LIMIT 30;

-- 5.4  Top 10 products by revenue (post-cleaning) 
SELECT
    stock_code,
    description,
    COUNT(*)                                AS times_ordered,
    SUM(quantity)                           AS total_units_sold,
    ROUND(SUM(total_amount), 2)             AS total_revenue,
    ROUND(AVG(price), 2)                    AS avg_unit_price
FROM orders
WHERE description IS NOT NULL
GROUP BY stock_code, description
ORDER BY total_revenue DESC
LIMIT 10;

-- 5.5  Monthly revenue contribution % by segment
 
SELECT
    YEAR(o.invoice_date)                     AS yr,
    MONTH(o.invoice_date)                    AS mth,
    seg.segment,
    ROUND(SUM(o.total_amount), 2)            AS segment_revenue,
    ROUND(
        SUM(o.total_amount) * 100.0 /
        SUM(SUM(o.total_amount)) OVER (
            PARTITION BY YEAR(o.invoice_date), MONTH(o.invoice_date)
        ),
    1)                                       AS pct_of_month
FROM orders o
JOIN rfm_segments seg ON o.customer_id = seg.customer_id
GROUP BY yr, mth, seg.segment
ORDER BY yr, mth, segment_revenue DESC;

-- 5.6  Revenue by country — full breakdown 
SELECT
    o.country,
    COUNT(DISTINCT o.customer_id)            AS unique_customers,
    COUNT(DISTINCT o.invoice)                AS total_invoices,
    SUM(o.quantity)                          AS units_sold,
    ROUND(SUM(o.total_amount), 2)            AS total_revenue,
    ROUND(AVG(o.total_amount), 2)            AS avg_transaction_value
FROM orders o
GROUP BY o.country
ORDER BY total_revenue DESC
LIMIT 15;

-- 5.7  Customer percentile ranking (for Power BI tooltip) 
SELECT
    customer_id,
    segment,
    ROUND(monetary, 2)                       AS lifetime_value,
    ROUND(
        PERCENT_RANK() OVER (ORDER BY monetary) * 100,
    1)                                       AS spend_percentile,
    frequency                                AS total_orders,
    recency_days
FROM rfm_segments
ORDER BY monetary DESC
LIMIT 20;

-- 5.8  New customer onboarding priority list 
 
SELECT
    s.customer_id,
    o.country,
    ROUND(s.monetary, 2)                     AS total_spent,
    s.frequency                              AS orders_so_far,
    s.recency_days                           AS days_since_last_order
FROM rfm_segments s
JOIN (
    SELECT customer_id, country
    FROM orders
    GROUP BY customer_id, country
) o ON s.customer_id = o.customer_id
WHERE s.segment = 'New'
ORDER BY s.monetary DESC;

-- 5.9  Product repurchase rate by segment 
 
SELECT
    seg.segment,
    o.stock_code,
    o.description,
    COUNT(DISTINCT o.customer_id)            AS unique_buyers,
    COUNT(*)                                 AS total_orders,
    ROUND(
        COUNT(*) * 1.0 / COUNT(DISTINCT o.customer_id),
    2)                                       AS repurchase_rate
FROM orders o
JOIN rfm_segments seg ON o.customer_id = seg.customer_id
WHERE o.description IS NOT NULL
GROUP BY seg.segment, o.stock_code, o.description
HAVING unique_buyers > 10
ORDER BY seg.segment, repurchase_rate DESC
LIMIT 30;

-- 5.10  Cohort: UK vs International Champions 
SELECT
    CASE
        WHEN o.country = 'United Kingdom' THEN 'UK'
        ELSE 'International'
    END                                      AS market,
    seg.segment,
    COUNT(DISTINCT seg.customer_id)          AS customers,
    ROUND(AVG(seg.monetary), 2)              AS avg_clv,
    ROUND(SUM(seg.monetary), 2)              AS total_revenue
FROM rfm_segments seg
JOIN (
    SELECT customer_id, country
    FROM orders
    GROUP BY customer_id, country
) o ON seg.customer_id = o.customer_id
GROUP BY market, seg.segment
ORDER BY market, total_revenue DESC;

SELECT
    s.customer_id,
    s.segment,
    s.r_score,
    s.f_score,
    s.m_score,
    s.total_rfm_score,
    s.recency_days,
    s.frequency,
    ROUND(s.monetary, 2)     AS monetary,
    o.country
FROM rfm_segments s
JOIN (
    SELECT customer_id, country
    FROM orders
    GROUP BY customer_id, country
) o ON s.customer_id = o.customer_id
ORDER BY s.monetary DESC;

ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '1020';
FLUSH PRIVILEGES;

-- Step 1: Check for negative recency values
SELECT COUNT(*) FROM rfm_raw WHERE recency_days < 0;

-- Step 2: Find the actual last date in the dataset
SELECT MAX(invoice_date) FROM orders;

-- Step 3: Remove corrupted future dates (2031 and 2012)
SET SQL_SAFE_UPDATES = 0;
DELETE FROM orders WHERE YEAR(invoice_date) > 2011;
SET SQL_SAFE_UPDATES = 1;

-- Step 4: Recreate rfm_raw view with correct snapshot date
CREATE OR REPLACE VIEW rfm_raw AS
SELECT
    customer_id,
    DATEDIFF('2011-12-10', MAX(invoice_date))  AS recency_days,
    COUNT(DISTINCT invoice)                     AS frequency,
    ROUND(SUM(total_amount), 2)                AS monetary
FROM orders
GROUP BY customer_id;

-- Step 5: Verify fix
SELECT COUNT(*) FROM rfm_raw WHERE recency_days < 0;
-- Result: 0 ✓