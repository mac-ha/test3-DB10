CREATE SCHEMA scholarship_lab;
CREATE TABLE scholarship_lab.students (
    student_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_number VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL
);

CREATE TABLE scholarship_lab.applications (
    application_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    student_id INTEGER NOT NULL,

    age_at_application INTEGER NOT NULL
        CHECK (age_at_application > 0),

    monthly_income NUMERIC(12,2) NOT NULL
        CHECK (monthly_income >= 0),

    average_mark NUMERIC(5,2) NOT NULL
        CHECK (average_mark BETWEEN 0 AND 100),

    submitted_on DATE NOT NULL,

    status VARCHAR(20) NOT NULL
        CHECK (status IN
        ('PENDING','APPROVED','REJECTED')),

    CONSTRAINT fk_application_student
        FOREIGN KEY (student_id)
        REFERENCES scholarship_lab.students(student_id)
);

CREATE TABLE scholarship_lab.decision_audit (
    audit_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    application_id INTEGER NOT NULL,

    old_status VARCHAR(20),

    new_status VARCHAR(20),

    changed_at TIMESTAMP NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_audit_application
        FOREIGN KEY (application_id)
        REFERENCES scholarship_lab.applications(application_id)
);

--seed students
INSERT INTO scholarship_lab.students
(student_number, full_name)
VALUES
('20260001','John Banda'),
('20260002','Mary Phiri'),
('20260003','Peter Zulu');

--seed applications
INSERT INTO scholarship_lab.applications
(
 student_id,
 age_at_application,
 monthly_income,
 average_mark,
 submitted_on,
 status
)
VALUES

-- Qualifies
(1,20,2500,75,'2026-11-01','PENDING'),

-- Boundary qualifies
(1,18,3000,70,'2026-11-02','PENDING'),

-- Age too low
(2,17,2000,85,'2026-11-03','PENDING'),

-- Income too high
(2,21,3500,90,'2026-11-04','PENDING'),

-- Mark too low
(3,22,2500,65,'2026-11-05','PENDING'),

-- Boundary qualifies
(3,25,3000,70,'2026-11-06','PENDING');

--B

CREATE OR REPLACE FUNCTION
scholarship_lab.fn_scholarship_eligible(
    p_age INTEGER,
    p_income NUMERIC,
    p_mark NUMERIC
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN

    IF p_age IS NULL
       OR p_income IS NULL
       OR p_mark IS NULL
    THEN
        RAISE EXCEPTION
        'Inputs cannot be NULL';
    END IF;

    IF p_age <= 0 THEN
        RAISE EXCEPTION
        'Age must be positive';
    END IF;

    IF p_income < 0 THEN
        RAISE EXCEPTION
        'Income cannot be negative';
    END IF;

    IF p_mark < 0 OR p_mark > 100 THEN
        RAISE EXCEPTION
        'Mark must be between 0 and 100';
    END IF;

    RETURN
    (
        p_age BETWEEN 18 AND 25
        AND p_income <= 3000
        AND p_mark >= 70
    );

END;
$$;

--C

CREATE OR REPLACE PROCEDURE
scholarship_lab.pr_assess_application(
    p_application_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_age INTEGER;
    v_income NUMERIC;
    v_mark NUMERIC;
    v_status VARCHAR(20);
BEGIN

    SELECT
        age_at_application,
        monthly_income,
        average_mark,
        status
    INTO
        v_age,
        v_income,
        v_mark,
        v_status
    FROM scholarship_lab.applications
    WHERE application_id = p_application_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
        'Application not found';
    END IF;

    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION
        'Application already assessed';
    END IF;

    IF scholarship_lab.fn_scholarship_eligible(
        v_age,
        v_income,
        v_mark
    )
    THEN

        UPDATE scholarship_lab.applications
        SET status = 'APPROVED'
        WHERE application_id = p_application_id;

    ELSE

        UPDATE scholarship_lab.applications
        SET status = 'REJECTED'
        WHERE application_id = p_application_id;

    END IF;

END;
$$;

--D

CREATE OR REPLACE FUNCTION
scholarship_lab.fn_decision_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status <> NEW.status THEN

        INSERT INTO scholarship_lab.decision_audit
        (
            application_id,
            old_status,
            new_status,
            changed_at
        )
        VALUES
        (
            NEW.application_id,
            OLD.status,
            NEW.status,
            CURRENT_TIMESTAMP
        );

    END IF;

    RETURN NEW;

END;
$$;

--trigger

CREATE TRIGGER trg_decision_audit
AFTER UPDATE
ON scholarship_lab.applications
FOR EACH ROW
EXECUTE FUNCTION
scholarship_lab.fn_decision_audit();

--E

CREATE OR REPLACE VIEW
scholarship_lab.v_approved_applicants AS
SELECT
    s.student_number,
    s.full_name,
    a.average_mark,
    a.status
FROM scholarship_lab.applications a
JOIN scholarship_lab.students s
ON a.student_id = s.student_id
WHERE a.status = 'APPROVED';

--F

CREATE INDEX idx_application_status_date
ON scholarship_lab.applications
(
    status,
    submitted_on
);

EXPLAIN

SELECT *
FROM scholarship_lab.applications
WHERE status = 'PENDING'
AND submitted_on BETWEEN
    DATE '2026-11-01'
AND DATE '2026-11-30';

--G

CREATE OR REPLACE PROCEDURE
scholarship_lab.pr_assess_pending()
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
BEGIN

    FOR rec IN

        SELECT application_id
        FROM scholarship_lab.applications
        WHERE status = 'PENDING'

    LOOP

        CALL scholarship_lab.pr_assess_application(
            rec.application_id
        );

    END LOOP;

END;
$$;