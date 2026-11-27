-- ============================================================================
-- Project: Real Estate Property & Installment Management System (3NF)
-- Author: Aun Haider Niazi
-- Database: MySQL 8.0+ / MariaDB
-- ============================================================================

DROP DATABASE IF EXISTS capital_property_db;
CREATE DATABASE capital_property_db;
USE capital_property_db;

-- 1. Sales Agents
CREATE TABLE Agents (
    agent_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    commission_rate DECIMAL(4,2) NOT NULL DEFAULT 2.50 CHECK (commission_rate BETWEEN 0.50 AND 15.00),
    hire_date DATE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

-- 2. Clients / Buyers
CREATE TABLE Clients (
    client_id INT AUTO_INCREMENT PRIMARY KEY,
    cnic VARCHAR(15) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100),
    city VARCHAR(50) DEFAULT 'Rawalpindi',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Properties Inventory (Plots, Houses, Commercial Shops)
CREATE TABLE Properties (
    property_id INT AUTO_INCREMENT PRIMARY KEY,
    project_name VARCHAR(100) NOT NULL,
    sector_block VARCHAR(50) NOT NULL,
    plot_number VARCHAR(30) NOT NULL,
    property_type ENUM('Residential Plot', 'Commercial Plot', 'House', 'Apartment') NOT NULL,
    area_marla DECIMAL(6,2) NOT NULL CHECK (area_marla > 0),
    total_price DECIMAL(14,2) NOT NULL CHECK (total_price > 0),
    status ENUM('Available', 'Booked', 'Sold', 'Hold') DEFAULT 'Available',
    UNIQUE KEY uk_property_unit (project_name, sector_block, plot_number)
);

-- 4. Installment Plan Templates
CREATE TABLE Payment_Plans (
    plan_id INT AUTO_INCREMENT PRIMARY KEY,
    plan_name VARCHAR(80) NOT NULL,
    down_payment_pct DECIMAL(5,2) NOT NULL CHECK (down_payment_pct BETWEEN 10.00 AND 100.00),
    total_installments INT NOT NULL CHECK (total_installments >= 1),
    interval_months INT NOT NULL DEFAULT 3,
    late_fee_pct DECIMAL(4,2) NOT NULL DEFAULT 2.00
);

-- 5. Property Bookings (Core Transaction Entity)
CREATE TABLE Bookings (
    booking_id INT AUTO_INCREMENT PRIMARY KEY,
    property_id INT UNIQUE NOT NULL,
    client_id INT NOT NULL,
    agent_id INT NOT NULL,
    plan_id INT NOT NULL,
    booking_date DATE NOT NULL,
    agreed_price DECIMAL(14,2) NOT NULL,
    remaining_balance DECIMAL(14,2) NOT NULL,
    booking_status ENUM('Active', 'Completed', 'Cancelled') DEFAULT 'Active',
    FOREIGN KEY (property_id) REFERENCES Properties(property_id),
    FOREIGN KEY (client_id) REFERENCES Clients(client_id),
    FOREIGN KEY (agent_id) REFERENCES Agents(agent_id),
    FOREIGN KEY (plan_id) REFERENCES Payment_Plans(plan_id)
);

-- 6. Scheduled Installments
CREATE TABLE Installments (
    installment_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id INT NOT NULL,
    installment_no INT NOT NULL,
    due_date DATE NOT NULL,
    amount_due DECIMAL(12,2) NOT NULL,
    late_fee DECIMAL(10,2) DEFAULT 0.00,
    status ENUM('Pending', 'Paid', 'Overdue') DEFAULT 'Pending',
    FOREIGN KEY (booking_id) REFERENCES Bookings(booking_id) ON DELETE CASCADE,
    UNIQUE KEY uk_booking_inst (booking_id, installment_no)
);

-- 7. Actual Payments Ledger
CREATE TABLE Payments (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    installment_id INT NOT NULL,
    payment_date DATE NOT NULL,
    amount_paid DECIMAL(12,2) NOT NULL CHECK (amount_paid > 0),
    payment_method ENUM('Bank Transfer', 'Cheque', 'Cash', 'Online') NOT NULL,
    reference_no VARCHAR(60) UNIQUE NOT NULL,
    FOREIGN KEY (installment_id) REFERENCES Installments(installment_id)
);

-- 8. Security & Price Audit Trail
CREATE TABLE Audit_Logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    record_id INT NOT NULL,
    action_type VARCHAR(20) NOT NULL,
    details VARCHAR(255) NOT NULL,
    logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Performance Indexes
CREATE INDEX idx_property_status ON Properties(status, property_type);
CREATE INDEX idx_installment_due ON Installments(status, due_date);

-- ============================================================================
-- TRIGGERS
-- ============================================================================
DELIMITER //

CREATE TRIGGER trg_after_booking_insert
AFTER INSERT ON Bookings
FOR EACH ROW
BEGIN
    UPDATE Properties
    SET status = 'Booked'
    WHERE property_id = NEW.property_id;

    INSERT INTO Audit_Logs (table_name, record_id, action_type, details)
    VALUES ('Bookings', NEW.booking_id, 'INSERT',
            CONCAT('Property ID ', NEW.property_id, ' booked for PKR ', NEW.agreed_price));
END//

CREATE TRIGGER trg_after_property_price_update
AFTER UPDATE ON Properties
FOR EACH ROW
BEGIN
    IF OLD.total_price <> NEW.total_price THEN
        INSERT INTO Audit_Logs (table_name, record_id, action_type, details)
        VALUES ('Properties', NEW.property_id, 'PRICE_CHANGE',
                CONCAT('Price changed from ', OLD.total_price, ' to ', NEW.total_price));
    END IF;
END//

-- ============================================================================
-- STORED PROCEDURE (ACID Payment Processing)
-- ============================================================================
CREATE PROCEDURE sp_RecordPayment(
    IN p_installment_id INT,
    IN p_amount DECIMAL(12,2),
    IN p_method VARCHAR(20),
    IN p_ref VARCHAR(60)
)
BEGIN
    DECLARE v_booking_id INT;
    DECLARE v_due DECIMAL(12,2);
    DECLARE v_property_id INT;
    DECLARE v_new_balance DECIMAL(14,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT booking_id, (amount_due + late_fee)
    INTO v_booking_id, v_due
    FROM Installments
    WHERE installment_id = p_installment_id FOR UPDATE;

    IF p_amount < v_due THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Partial installment payment not permitted';
    END IF;

    INSERT INTO Payments (installment_id, payment_date, amount_paid, payment_method, reference_no)
    VALUES (p_installment_id, CURDATE(), p_amount, p_method, p_ref);

    UPDATE Installments
    SET status = 'Paid'
    WHERE installment_id = p_installment_id;

    UPDATE Bookings
    SET remaining_balance = GREATEST(0, remaining_balance - p_amount)
    WHERE booking_id = v_booking_id;

    SELECT remaining_balance, property_id
    INTO v_new_balance, v_property_id
    FROM Bookings
    WHERE booking_id = v_booking_id;

    IF v_new_balance = 0 THEN
        UPDATE Bookings SET booking_status = 'Completed' WHERE booking_id = v_booking_id;
        UPDATE Properties SET status = 'Sold' WHERE property_id = v_property_id;
    END IF;

    COMMIT;
END//

DELIMITER ;

-- ============================================================================
-- EXECUTIVE REPORTING VIEWS
-- ============================================================================
CREATE VIEW vw_AgentCommissionSummary AS
SELECT
    a.agent_id,
    a.full_name AS agent_name,
    COUNT(b.booking_id) AS total_deals,
    COALESCE(SUM(b.agreed_price), 0) AS total_sales_volume,
    ROUND(COALESCE(SUM(b.agreed_price * (a.commission_rate / 100)), 0), 2) AS earned_commission
FROM Agents a
LEFT JOIN Bookings b ON a.agent_id = b.agent_id AND b.booking_status <> 'Cancelled'
GROUP BY a.agent_id, a.full_name;

CREATE VIEW vw_OverdueInstallments AS
SELECT
    b.booking_id,
    c.full_name AS client_name,
    c.phone,
    CONCAT(p.project_name, ' - ', p.sector_block, ' (', p.plot_number, ')') AS unit,
    i.installment_no,
    i.due_date,
    DATEDIFF(CURDATE(), i.due_date) AS days_overdue,
    (i.amount_due + i.late_fee) AS total_payable
FROM Installments i
JOIN Bookings b ON i.booking_id = b.booking_id
JOIN Clients c ON b.client_id = c.client_id
JOIN Properties p ON b.property_id = p.property_id
WHERE i.status <> 'Paid' AND i.due_date < CURDATE();