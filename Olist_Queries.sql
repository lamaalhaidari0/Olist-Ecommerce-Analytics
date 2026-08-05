-- ============================================================
-- OLIST E-COMMERCE SQL ANALYSIS
-- Database : Olist
-- Source   : Kaggle — Brazilian E-Commerce Public Dataset by Olist
-- ============================================================


-- ============================================================
-- SECTION 1 — IMPORT VERIFICATION
-- After importing each CSV, confirm the row count matches
-- the source file before doing any analysis.
-- ============================================================

-- orders  |  Expected: 99,441 rows
SELECT COUNT(*) AS orders_rows
FROM orders;


-- order_items  |  Expected: 112,650 rows
SELECT COUNT(*) AS order_items_rows
FROM order_items;


-- order_payments  |  Expected: 103,886 rows
-- Note: order_id repeats here — a single order can be paid with
--       more than one method (e.g. credit card + voucher), so this
--       table has no single-column primary key.
SELECT COUNT(*) AS order_payments_rows
FROM order_payments;


-- order_reviews  |  Expected: 99,224 rows
SELECT COUNT(*) AS order_reviews_rows
FROM order_reviews;


-- products  |  Expected: 32,951 rows
SELECT COUNT(*) AS products_rows
FROM products;


-- customers  |  Expected: 99,441 rows
-- Note: customer_id is unique (one row per order), while
--       customer_unique_id repeats (96,096 distinct people).
SELECT COUNT(*) AS customers_rows
FROM customers;


-- sellers  |  Expected: 3,095 rows
SELECT COUNT(*) AS sellers_rows
FROM sellers;


-- geolocation  |  Expected: 1,000,163 rows
-- Note: zip code prefix repeats (multiple coordinate points per
--       area), so this table has no primary key.
SELECT COUNT(*) AS geolocation_rows
FROM geolocation;


-- category_translation  |  Expected: 71 rows
-- Fix applied first: the CSV header row was imported as a data row
-- because the wizard did not detect the header. Remove it.
DELETE FROM category_translation
WHERE product_category_name = 'product_category_name';

SELECT COUNT(*) AS category_translation_rows
FROM category_translation;


-- ============================================================
-- SECTION 2 — DATA QUALITY CHECKS
-- ============================================================

-- Preview the orders table to confirm the data landed correctly
-- (dates read as dates, statuses look valid)
SELECT TOP 10 * FROM orders;


-- Orders with no delivery date
-- RESULT: 2,965  (matches the Excel finding — no rows lost on import)
SELECT COUNT(*) AS missing_delivery_date
FROM orders
WHERE order_delivered_customer_date IS NULL;


-- Orders that were never completed (status other than 'delivered')
-- RESULT: 2,963
SELECT COUNT(*) AS not_delivered_orders
FROM orders
WHERE order_status <> 'delivered';


-- Anomaly: orders marked 'delivered' but carrying no delivery date
-- RESULT: 8 rows — inconsistent in the source data
SELECT COUNT(*) AS delivered_without_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;


-- Is review_id unique? (tested before assigning a primary key)
-- RESULT: 99,224 total rows vs 98,410 distinct review_id values
--         => 814 duplicates; one review can span multiple orders
--         => review_id CANNOT be a primary key
--         => join reviews to orders on order_id, never on review_id
SELECT COUNT(*)                  AS total_rows,
       COUNT(DISTINCT review_id) AS unique_reviews
FROM order_reviews;


-- ============================================================
-- METHODOLOGY NOTE
-- Because of the anomaly above, every delivery-time calculation
-- in this project applies BOTH conditions:
--     order_status = 'delivered'm
--     AND order_delivered_customer_date IS NOT NULL
-- ============================================================



-- ============================================================
-- SECTION 3 — ANSWERING BUSINESS QUESTIONS WITH SQL
-- ============================================================

-- Q1: Monthly order trend
-- Analysis period: Jan 2017 to Aug 2018 (partial months excluded)
SELECT
    YEAR(order_purchase_timestamp) AS year,
    MONTH(order_purchase_timestamp) AS month,
    COUNT(*) AS total_orders
FROM orders
WHERE order_purchase_timestamp BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY
    YEAR(order_purchase_timestamp),
    MONTH(order_purchase_timestamp)
ORDER BY
    year, month;

-- Q2: Top and bottom product categories by revenue and order count
-- Note: 1,603 rows with no category (NULL) are excluded
SELECT
    p.product_category_name,
    COUNT(oi.order_id) AS total_orders,
    SUM(oi.price) AS total_revenue
FROM order_items oi
JOIN products p
    ON oi.product_id = p.product_id
WHERE p.product_category_name IS NOT NULL
GROUP BY
    p.product_category_name
ORDER BY
    total_revenue DESC;


-- Q3.1: Orders by state
SELECT
    c.customer_state,
    COUNT(o.order_id) AS total_orders
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
GROUP BY
    c.customer_state
ORDER BY
    total_orders DESC;


-- Q3.2: Repeat purchase analysis
-- How many orders does each unique customer have?
-- order_count = 1 means one-time buyer; >1 means repeat buyer
SELECT
    customer_unique_id,
    COUNT(customer_id) AS order_count
FROM customers
GROUP BY
    customer_unique_id
ORDER BY
    order_count DESC;


-- Q4: Average delivery days by state
-- Uses both conditions to exclude anomalous rows
SELECT
    c.customer_state,
    AVG(DATEDIFF(day, o.order_purchase_timestamp, o.order_delivered_customer_date)) AS avg_delivery_days
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY
    c.customer_state
ORDER BY
    avg_delivery_days ASC;

-- Q4.2: Late delivery rate
-- An order is "late" if it arrived AFTER the estimated date
SELECT
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN 'Late'
        ELSE 'On Time'
    END AS delivery_status,
    COUNT(*) AS total_orders
FROM orders o
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN 'Late'
        ELSE 'On Time'
    END
ORDER BY
    total_orders DESC;

-- Q4.3: Average gap vs estimated delivery date
-- Negative = orders arrive BEFORE the estimate (padded promises)
SELECT
    AVG(DATEDIFF(day, o.order_estimated_delivery_date, o.order_delivered_customer_date)) AS avg_gap_days
FROM orders o
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;


SELECT 
    CASE 
    WHEN O.order_delivered_customer_date > O.order_estimated_delivery_date 
    THEN 'Late'
    ELSE 'On Time'
    END AS delivery_status,
    AVG(R.review_score) AS avg_scores
FROM orders O JOIN order_reviews R ON O.order_id=R.order_id
WHERE order_status='delivered' AND O.order_delivered_customer_date IS NOT NULL
GROUP BY 
    CASE 
    WHEN order_delivered_customer_date > order_estimated_delivery_date 
    THEN 'Late'
    ELSE 'On Time'
    END
ORDER BY avg_scores;


-- Q6: Payment methods — usage count and average order value
-- 3 rows with 'not_defined' excluded (same as Excel)
SELECT
    payment_type,
    COUNT(order_id) AS total_payments,
    AVG(payment_value) AS avg_payment_value
FROM order_payments
WHERE payment_type <> 'not_defined'
GROUP BY payment_type
ORDER BY total_payments DESC;