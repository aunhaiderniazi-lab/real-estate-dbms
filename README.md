# Real Estate Property & Installment Management System (3NF DBMS)

**Author:** Aun Haider Niazi  
**Domain:** Capital Property Desk (Real Estate Brokerage & Housing Inventory Management)  
**Target RDBMS:** MySQL 8.0+ / MariaDB 10.6+

---

## Overview
An enterprise relational database system designed in **Third Normal Form (3NF)** to manage real estate inventory (residential plots, commercial shops, houses, apartments), client profiles, sales agents, customizable installment payment plans, automated triggers, ACID-compliant payment transactions, and executive reporting views.

---

## Entity-Relationship Architecture

```text
+----------+ 1       * +------------+ *       1 +-----------+
|  Agents  |───────────|  Bookings  |───────────|  Clients  |
+----------+           +------------+           +-----------+
                         │    │    │
               1:1       │    │    │ *:1
          ┌──────────────┘    │    └──────────────┐
          ▼                   │ 1:*               ▼
  +--------------+            ▼          +-----------------+
  |  Properties  |    +--------------+   |  Payment_Plans  |
  +--------------+    | Installments |   +-----------------+
                      +--------------+
                              │ 1:*
                              ▼
                       +------------+
                       |  Payments  |
                       +------------+

  [Audit_Logs]  ◄── Automatically populated by AFTER INSERT / UPDATE triggers
```

---

## Normalization Proof (1NF → 3NF)

1. **First Normal Form (1NF):**
   * Every column holds atomic values (`project_name`, `sector_block`, `plot_number` are separated rather than stored as a single string).
   * All tables define explicit primary keys (`AUTO_INCREMENT`) and contain zero repeating groups.
2. **Second Normal Form (2NF):**
   * Every table uses a single-attribute surrogate primary key, eliminating partial dependencies.
   * Natural business uniqueness is enforced via composite `UNIQUE` keys (`uk_property_unit` on `(project_name, sector_block, plot_number)` and `uk_booking_inst` on `(booking_id, installment_no)`).
3. **Third Normal Form (3NF):**
   * **Zero Transitive Dependencies:** Client contact info (`phone`, `email`, `city`) resides strictly in `Clients`, agent commission rates reside in `Agents`, and installment plan rules (`down_payment_pct`, `interval_months`, `late_fee_pct`) reside in `Payment_Plans`—never duplicated inside `Bookings` or `Installments`.

---

## Database Features & Logic Verification

### 1. Automated Triggers
* **`trg_after_booking_insert`:** Automatically updates `Properties.status` from `'Available'` to `'Booked'` when a booking is inserted and logs the transaction to `Audit_Logs`.
* **`trg_after_property_price_update`:** Captures any `UPDATE` to `Properties.total_price` and writes an immutable before/after price audit record into `Audit_Logs`.

### 2. ACID Stored Procedure (`sp_RecordPayment`)
Wraps payment processing inside an explicit `START TRANSACTION ... COMMIT` block with a `SQLEXCEPTION` `ROLLBACK` handler and row-level locking (`SELECT ... FOR UPDATE`):
1. Validates that `p_amount >= (amount_due + late_fee)` (rejecting partial installment payments with `SQLSTATE '45000'`).
2. Inserts the payment receipt into `Payments`.
3. Updates `Installments.status` to `'Paid'`.
4. Deducts `p_amount` from `Bookings.remaining_balance`.
5. Automatically marks `Bookings.booking_status = 'Completed'` and `Properties.status = 'Sold'` when `remaining_balance` reaches `0`.

### 3. Executive Views & Performance Indexes
* **`vw_AgentCommissionSummary`:** Aggregates total deals, sales volume, and earned commission per agent using `LEFT JOIN` and `COALESCE`.
* **`vw_OverdueInstallments`:** Joins `Installments`, `Bookings`, `Clients`, and `Properties` to surface unpaid past-due installments with exact `DATEDIFF` overdue day counts.
* **Composite Indexes:** `idx_property_status (status, property_type)` and `idx_installment_due (status, due_date)` accelerate inventory filtering and defaulter scans.

---

## How to Run & Verify

```bash
# 1. Load the 3NF schema, triggers, stored procedure, and views
mysql -u root -p < schema.sql

# 2. Load sample Capital Property Desk records and execute verification queries
mysql -u root -p < seed_and_queries.sql
```

### Expected Verification Output (`seed_and_queries.sql`)
* **`Properties`:** `Plot-14` automatically transitions to `'Booked'`; `Shop-05` reflects updated price `18500000.00`.
* **`Bookings`:** `remaining_balance` drops from `12,500,000.00` to `9,375,000.00` after `CALL sp_RecordPayment(1, 3125000.00, ...)`.
* **`vw_AgentCommissionSummary`:** `Aun Haider Niazi` shows `1` deal, `12,500,000.00` sales volume, and `375,000.00` earned commission (`3.00%`).
* **`vw_OverdueInstallments`:** Flags Installment `#2` (`2026-11-01`) for `Tariq Mahmood` with exact overdue days.
* **`Audit_Logs`:** Contains two automated trigger entries (`Bookings` `INSERT` and `Properties` `PRICE_CHANGE`).

---

## License
Licensed under the MIT License — see [LICENSE.txt](./LICENSE.txt).