-- ============================================================================
-- Seed Data & Analytical Verification Queries
-- Project: Real Estate Property & Installment Management System
-- Author: Aun Haider Niazi
-- ============================================================================

USE capital_property_db;

-- 1. Seed Agents
INSERT INTO Agents (full_name, phone, email, commission_rate, hire_date) VALUES
('Aun Haider Niazi', '0300-5550101', 'aun@capitalpropertydesk.pk', 3.00, '2025-01-15'),
('Fayyaz Malik', '0300-5550102', 'fayyaz@capitalpropertydesk.pk', 2.75, '2025-02-01');

-- 2. Seed Clients
INSERT INTO Clients (cnic, full_name, phone, email, city) VALUES
('37405-1234567-1', 'Tariq Mahmood', '0321-5112233', 'tariq.m@gmail.com', 'Rawalpindi'),
('61101-9876543-2', 'Sara Qureshi', '0333-5998877', 'sara.q@outlook.com', 'Islamabad');

-- 3. Seed Properties
INSERT INTO Properties (project_name, sector_block, plot_number, property_type, area_marla, total_price) VALUES
('Capital Enclave', 'Block A', 'Plot-14', 'Residential Plot', 10.00, 12500000.00),
('Capital Enclave', 'Commercial Hub', 'Shop-05', 'Commercial Plot', 4.00, 18000000.00),
('Bahria Phase 8', 'Sector G', 'House-22', 'House', 7.00, 24500000.00);

-- 4. Seed Payment Plans
INSERT INTO Payment_Plans (plan_name, down_payment_pct, total_installments, interval_months, late_fee_pct) VALUES
('1-Year Quarterly Plan', 25.00, 4, 3, 2.00),
('2-Year Bi-Annual Plan', 20.00, 4, 6, 2.50);

-- 5. Create Booking (Fires trg_after_booking_insert -> Properties.status = 'Booked' + Audit_Logs)
INSERT INTO Bookings (property_id, client_id, agent_id, plan_id, booking_date, agreed_price, remaining_balance)
VALUES (1, 1, 1, 1, '2026-08-01', 12500000.00, 12500000.00);

-- 6. Schedule Installments (4 Quarterly Installments of PKR 3,125,000)
INSERT INTO Installments (booking_id, installment_no, due_date, amount_due, status) VALUES
(1, 1, '2026-08-01', 3125000.00, 'Pending'),
(1, 2, '2026-11-01', 3125000.00, 'Overdue'),
(1, 3, '2027-02-01', 3125000.00, 'Pending'),
(1, 4, '2027-05-01', 3125000.00, 'Pending');

-- 7. Test Price Audit Trigger (Fires trg_after_property_price_update)
UPDATE Properties SET total_price = 18500000.00 WHERE property_id = 2;

-- 8. Execute ACID Stored Procedure to Record Installment #1 Payment
CALL sp_RecordPayment(1, 3125000.00, 'Bank Transfer', 'TXN-HBL-998811');

-- ============================================================================
-- VERIFICATION & ANALYTICAL QUERIES
-- ============================================================================

-- A. Check Property Inventory & Triggered Status Change
SELECT property_id, project_name, sector_block, plot_number, total_price, status
FROM Properties;

-- B. Check Remaining Balance & Installment Status After Stored Procedure
SELECT b.booking_id, c.full_name AS buyer, b.agreed_price, b.remaining_balance, b.booking_status
FROM Bookings b
JOIN Clients c ON b.client_id = c.client_id;

SELECT installment_no, due_date, amount_due, status
FROM Installments
WHERE booking_id = 1;

-- C. Executive Views
SELECT * FROM vw_AgentCommissionSummary;
SELECT * FROM vw_OverdueInstallments;

-- D. Audit Trail Verification
SELECT log_id, table_name, record_id, action_type, details, logged_at
FROM Audit_Logs;