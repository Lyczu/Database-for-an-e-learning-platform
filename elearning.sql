SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


-- ============================================================
--  ROLE
-- ============================================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'apokrzywa') THEN CREATE ROLE apokrzywa WITH LOGIN PASSWORD 'haslo123'; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'blyczak')   THEN CREATE ROLE blyczak WITH LOGIN PASSWORD 'haslo123';   END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bsnieg')    THEN CREATE ROLE bsnieg WITH LOGIN PASSWORD 'haslo123';    END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lbilski')   THEN CREATE ROLE lbilski WITH LOGIN PASSWORD 'haslo123';   END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'elearning_readonly') THEN CREATE ROLE elearning_readonly WITH LOGIN PASSWORD 'haslo123'; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'elearning_teacher')  THEN CREATE ROLE elearning_teacher WITH LOGIN PASSWORD 'haslo123';  END IF;
END $$;


-- ============================================================
--  FUNKCJE PL/pgSQL
-- ============================================================


-- Funkcja 1: Sprawdza, czy student jest zapisany na kurs przed dodaniem oceny
CREATE FUNCTION public.sprawdz_zapis_na_kurs() RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    v_course_id INTEGER;
    v_enrolled  BOOLEAN;
BEGIN
    -- Pobierz id kursu, do którego należy test
    SELECT l.course_id INTO v_course_id
      FROM public.tests t
      JOIN public.lessons l ON t.lesson_id = l.id
     WHERE t.id = NEW.test_id;

    -- Sprawdź, czy student jest zapisany na ten kurs
    SELECT EXISTS (
        SELECT 1 FROM public.course_enrollments
         WHERE user_id = NEW.user_id
           AND course_id = v_course_id
    ) INTO v_enrolled;

    IF NOT v_enrolled THEN
        RAISE EXCEPTION 'Błąd: Student (user_id=%) nie jest zapisany na kurs (course_id=%), do którego należy ten test.', NEW.user_id, v_course_id;
    END IF;

    RETURN NEW;
END;
$$;
ALTER FUNCTION public.sprawdz_zapis_na_kurs() OWNER TO apokrzywa;


-- Funkcja 2: Blokuje wielokrotne ocenianie tego samego testu przez tego samego studenta
CREATE FUNCTION public.blokuj_duplikat_oceny() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.grades
         WHERE test_id = NEW.test_id
           AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'Błąd: Student (user_id=%) już posiada ocenę z testu (test_id=%). Duplikaty nie są dozwolone.', NEW.user_id, NEW.test_id;
    END IF;

    RETURN NEW;
END;
$$;
ALTER FUNCTION public.blokuj_duplikat_oceny() OWNER TO apokrzywa;


-- Funkcja 3: Loguje aktualizację statystyk kursu po wystawieniu oceny
CREATE FUNCTION public.loguj_nowa_ocene() RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    v_course_title VARCHAR(255);
    v_student_email VARCHAR(255);
    v_test_title VARCHAR(255);
    v_max_points INTEGER;
    v_procent NUMERIC(5,2);
BEGIN
    -- Pobierz informacje o teście i kursie
    SELECT c.title, t.title, t.max_points
      INTO v_course_title, v_test_title, v_max_points
      FROM public.tests t
      JOIN public.lessons l ON t.lesson_id = l.id
      JOIN public.courses c ON l.course_id = c.id
     WHERE t.id = NEW.test_id;

    -- Pobierz email studenta
    SELECT email INTO v_student_email
      FROM public.users
     WHERE id = NEW.user_id;

    -- Oblicz procent
    IF v_max_points > 0 THEN
        v_procent := ROUND((NEW.points_scored / v_max_points) * 100, 2);
    ELSE
        v_procent := 0;
    END IF;

    -- Loguj informację (NOTICE, widoczne w logach PostgreSQL)
    RAISE NOTICE '[OCENA] Kurs: "%" | Test: "%" | Student: % | Wynik: %/% (%%)',
        v_course_title, v_test_title, v_student_email,
        NEW.points_scored, v_max_points, v_procent;

    RETURN NEW;
END;
$$;
ALTER FUNCTION public.loguj_nowa_ocene() OWNER TO apokrzywa;


-- ============================================================
--  TABELE
-- ============================================================

SET default_tablespace = '';
SET default_table_access_method = heap;


-- Tabela 1: users (Użytkownicy)
CREATE TABLE public.users (
    id            SERIAL       NOT NULL,
    email         VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(50)  NOT NULL,
    created_at    TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT users_role_check CHECK (role IN ('student', 'teacher', 'admin'))
);
ALTER TABLE public.users OWNER TO apokrzywa;


-- Tabela 2: user_profiles (Profile użytkowników)
CREATE TABLE public.user_profiles (
    id         SERIAL       NOT NULL,
    user_id    INTEGER      NOT NULL,
    first_name VARCHAR(100),
    last_name  VARCHAR(100),
    bio        TEXT,
    avatar_url VARCHAR(500)
);
ALTER TABLE public.user_profiles OWNER TO apokrzywa;


-- Tabela 3: courses (Baza kursów)
CREATE TABLE public.courses (
    id            SERIAL       NOT NULL,
    instructor_id INTEGER,
    title         VARCHAR(255) NOT NULL,
    description   TEXT,
    created_at    TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.courses OWNER TO apokrzywa;


-- Tabela 4: course_enrollments (Zapisy na kursy)
CREATE TABLE public.course_enrollments (
    id          SERIAL  NOT NULL,
    user_id     INTEGER,
    course_id   INTEGER,
    enrolled_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.course_enrollments OWNER TO apokrzywa;


-- Tabela 5: lessons (Lekcje)
CREATE TABLE public.lessons (
    id          SERIAL       NOT NULL,
    course_id   INTEGER      NOT NULL,
    title       VARCHAR(255) NOT NULL,
    content     TEXT,
    order_index INTEGER
);
ALTER TABLE public.lessons OWNER TO apokrzywa;


-- Tabela 6: tests (Testy)
CREATE TABLE public.tests (
    id        SERIAL       NOT NULL,
    lesson_id INTEGER      NOT NULL,
    title     VARCHAR(255) NOT NULL,
    max_points INTEGER
);
ALTER TABLE public.tests OWNER TO apokrzywa;


-- Tabela 7: grades (Oceny i wyniki)
CREATE TABLE public.grades (
    id            SERIAL       NOT NULL,
    test_id       INTEGER      NOT NULL,
    user_id       INTEGER      NOT NULL,
    points_scored NUMERIC(5,2),
    graded_at     TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.grades OWNER TO apokrzywa;


-- ============================================================
--  KLUCZE GŁÓWNE I UNIKALNE
-- ============================================================

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey      PRIMARY KEY (id),
    ADD CONSTRAINT users_email_key UNIQUE (email);

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_pkey         PRIMARY KEY (id),
    ADD CONSTRAINT user_profiles_user_id_key  UNIQUE (user_id);

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.course_enrollments
    ADD CONSTRAINT course_enrollments_pkey              PRIMARY KEY (id),
    ADD CONSTRAINT course_enrollments_user_course_key   UNIQUE (user_id, course_id);

ALTER TABLE ONLY public.lessons
    ADD CONSTRAINT lessons_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tests
    ADD CONSTRAINT tests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.grades
    ADD CONSTRAINT grades_pkey PRIMARY KEY (id);


-- ============================================================
--  KLUCZE OBCE
-- ============================================================

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_instructor_id_fkey
        FOREIGN KEY (instructor_id)
        REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.course_enrollments
    ADD CONSTRAINT course_enrollments_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT course_enrollments_course_id_fkey
        FOREIGN KEY (course_id)
        REFERENCES public.courses(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.lessons
    ADD CONSTRAINT lessons_course_id_fkey
        FOREIGN KEY (course_id)
        REFERENCES public.courses(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tests
    ADD CONSTRAINT tests_lesson_id_fkey
        FOREIGN KEY (lesson_id)
        REFERENCES public.lessons(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.grades
    ADD CONSTRAINT grades_test_id_fkey
        FOREIGN KEY (test_id)
        REFERENCES public.tests(id) ON DELETE CASCADE,
    ADD CONSTRAINT grades_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES public.users(id) ON DELETE CASCADE;


-- ============================================================
--  INDEKSY
-- ============================================================

CREATE INDEX idx_profiles_user       ON public.user_profiles(user_id);
CREATE INDEX idx_courses_instructor  ON public.courses(instructor_id);
CREATE INDEX idx_enrollments_user    ON public.course_enrollments(user_id);
CREATE INDEX idx_enrollments_course  ON public.course_enrollments(course_id);
CREATE INDEX idx_lessons_course      ON public.lessons(course_id);
CREATE INDEX idx_lessons_order       ON public.lessons(course_id, order_index);
CREATE INDEX idx_tests_lesson        ON public.tests(lesson_id);
CREATE INDEX idx_grades_test         ON public.grades(test_id);
CREATE INDEX idx_grades_user         ON public.grades(user_id);
CREATE INDEX idx_grades_test_user    ON public.grades(test_id, user_id);


-- ============================================================
--  TRIGGERY
-- ============================================================

CREATE TRIGGER trg_sprawdz_zapis
    BEFORE INSERT ON public.grades
    FOR EACH ROW EXECUTE FUNCTION public.sprawdz_zapis_na_kurs();

CREATE TRIGGER trg_blokuj_duplikat_oceny
    BEFORE INSERT ON public.grades
    FOR EACH ROW EXECUTE FUNCTION public.blokuj_duplikat_oceny();

CREATE TRIGGER trg_loguj_ocene
    AFTER INSERT ON public.grades
    FOR EACH ROW EXECUTE FUNCTION public.loguj_nowa_ocene();


-- ============================================================
--  WIDOKI
-- ============================================================


-- Widok 1: Ranking studentów z łącznymi punktami i procentem
CREATE VIEW public.v_ranking_studentow AS
SELECT
    u.id AS student_id,
    up.first_name || ' ' || up.last_name AS imie_nazwisko,
    u.email,
    COUNT(g.id)                           AS liczba_testow,
    ROUND(SUM(g.points_scored), 2)        AS suma_punktow,
    ROUND(SUM(t.max_points), 2)           AS max_punktow,
    CASE
        WHEN SUM(t.max_points) > 0
        THEN ROUND((SUM(g.points_scored) / SUM(t.max_points)) * 100, 2)
        ELSE 0
    END                                   AS procent_poprawnych
FROM public.users u
JOIN public.user_profiles up ON u.id = up.user_id
JOIN public.grades g         ON u.id = g.user_id
JOIN public.tests t          ON g.test_id = t.id
WHERE u.role = 'student'
GROUP BY u.id, up.first_name, up.last_name, u.email
ORDER BY procent_poprawnych DESC;
ALTER VIEW public.v_ranking_studentow OWNER TO blyczak;


-- Widok 2: Statystyki kursów
CREATE VIEW public.v_statystyki_kursu AS
SELECT
    c.id AS kurs_id,
    c.title AS tytul_kursu,
    ui.first_name || ' ' || ui.last_name AS instruktor,
    COUNT(DISTINCT l.id)                  AS liczba_lekcji,
    COUNT(DISTINCT t.id)                  AS liczba_testow,
    COUNT(DISTINCT ce.user_id)            AS liczba_studentow,
    COALESCE(ROUND(AVG(g.points_scored), 2), 0) AS srednia_punktow,
    COALESCE(
        CASE
            WHEN SUM(t2.max_points) > 0
            THEN ROUND((SUM(g.points_scored) / SUM(t2.max_points)) * 100, 2)
            ELSE 0
        END, 0)                           AS sredni_procent
FROM public.courses c
LEFT JOIN public.users u            ON c.instructor_id = u.id
LEFT JOIN public.user_profiles ui   ON u.id = ui.user_id
LEFT JOIN public.lessons l          ON c.id = l.course_id
LEFT JOIN public.tests t            ON l.id = t.lesson_id
LEFT JOIN public.course_enrollments ce ON c.id = ce.course_id
LEFT JOIN public.grades g           ON t.id = g.test_id
LEFT JOIN public.tests t2           ON g.test_id = t2.id
GROUP BY c.id, c.title, ui.first_name, ui.last_name
ORDER BY liczba_studentow DESC;
ALTER VIEW public.v_statystyki_kursu OWNER TO blyczak;


-- Widok 3: Postępy studenta w poszczególnych kursach
CREATE VIEW public.v_postepy_studenta AS
SELECT
    u.id AS student_id,
    up.first_name || ' ' || up.last_name AS imie_nazwisko,
    c.title AS kurs,
    COUNT(DISTINCT t.id)                  AS testy_w_kursie,
    COUNT(DISTINCT g.test_id)             AS testy_rozwiazane,
    CASE
        WHEN COUNT(DISTINCT t.id) > 0
        THEN ROUND(
            (COUNT(DISTINCT g.test_id)::NUMERIC / COUNT(DISTINCT t.id)) * 100, 1
        )
        ELSE 0
    END                                   AS procent_ukonczenia,
    COALESCE(ROUND(AVG(g.points_scored), 2), 0) AS srednia_punktow
FROM public.users u
JOIN public.user_profiles up        ON u.id = up.user_id
JOIN public.course_enrollments ce   ON u.id = ce.user_id
JOIN public.courses c               ON ce.course_id = c.id
LEFT JOIN public.lessons l          ON c.id = l.course_id
LEFT JOIN public.tests t            ON l.id = t.lesson_id
LEFT JOIN public.grades g           ON t.id = g.test_id AND g.user_id = u.id
WHERE u.role = 'student'
GROUP BY u.id, up.first_name, up.last_name, c.title
ORDER BY u.id, c.title;
ALTER VIEW public.v_postepy_studenta OWNER TO blyczak;


-- ============================================================
--  DANE TESTOWE
-- ============================================================

SET session_replication_role = replica;  -- wyłącza triggery tymczasowo


-- Użytkownicy (8 osób: 1 admin, 2 nauczycieli, 5 studentów)
INSERT INTO public.users (id, email, password_hash, role, created_at) VALUES
(1, 'admin@elearning.pl',        '$2b$12$LJ3m5ZQxKcG2rI8sXUqK.O4v9ZQ6kV2wT5mJhPqL', 'admin',   '2026-01-10 08:00:00'),
(2, 'jan.kowalski@edu.pl',       '$2b$12$XK9wP3rY1mZ7nO2qW4sR6.J8hB5cV3xT9nMjKqP', 'teacher',  '2026-01-15 09:30:00'),
(3, 'anna.nowak@edu.pl',         '$2b$12$RQ7mN1pY5kZ3vO8qW2sT4.L6hD9cX1xR7nMjFqE', 'teacher',  '2026-02-01 10:00:00'),
(4, 'marek.wisniewski@mail.pl',  '$2b$12$YT5mK8pW2nZ1vO6qR4sX3.H9hF7cL3xP5nMjDqB', 'student',  '2026-02-10 11:00:00'),
(5, 'katarzyna.zielinska@mail.pl','$2b$12$WP3mJ6pR8nZ5vO4qT2sY1.G7hE5cK1xN3nMjCqA', 'student', '2026-02-15 12:30:00'),
(6, 'piotr.lewandowski@mail.pl', '$2b$12$VO1mH4pT6nZ9vO2qY8sW5.F5hC3cI9xL1nMjBqZ', 'student',  '2026-03-01 14:00:00'),
(7, 'agnieszka.kaminska@mail.pl','$2b$12$UN9mG2pY4nZ7vO8qW6sR3.E3hA1cG7xJ9nMjAqX', 'student',  '2026-03-10 15:30:00'),
(8, 'tomasz.wojcik@mail.pl',     '$2b$12$SM7mF8pW2nZ5vO6qR4sT1.D1hZ9cE5xH7nMjZqV', 'student',  '2026-03-20 16:00:00');


-- Profile użytkowników
INSERT INTO public.user_profiles (id, user_id, first_name, last_name, bio, avatar_url) VALUES
(1, 1, 'Admin',      'Systemu',      'Administrator platformy e-learningowej',                     NULL),
(2, 2, 'Jan',        'Kowalski',     'Doświadczony programista Python i SQL. Uczy od 10 lat.',    'https://example.com/avatars/jan.jpg'),
(3, 3, 'Anna',       'Nowak',        'Specjalistka od analizy danych i Machine Learning.',         'https://example.com/avatars/anna.jpg'),
(4, 4, 'Marek',      'Wiśniewski',   'Student informatyki, pasjonat baz danych.',                  'https://example.com/avatars/marek.jpg'),
(5, 5, 'Katarzyna',  'Zielińska',    'Studentka 3. roku, interesuje się AI.',                      'https://example.com/avatars/kasia.jpg'),
(6, 6, 'Piotr',      'Lewandowski',  'Początkujący programista, uczę się Pythona.',                'https://example.com/avatars/piotr.jpg'),
(7, 7, 'Agnieszka',  'Kamińska',     'Studentka matematyki, fan data science.',                    'https://example.com/avatars/agnieszka.jpg'),
(8, 8, 'Tomasz',     'Wójcik',       'Student zaoczny, pracuję jako tester oprogramowania.',       'https://example.com/avatars/tomasz.jpg');


-- Kursy (3 kursy prowadzone przez 2 nauczycieli)
INSERT INTO public.courses (id, instructor_id, title, description, created_at) VALUES
(1, 2, 'Podstawy SQL i Baz Danych',
    'Kurs wprowadzający do relacyjnych baz danych. Nauczysz się tworzyć tabele, pisać zapytania SELECT, JOIN, GROUP BY oraz zarządzać danymi.',
    '2026-02-01 10:00:00'),
(2, 2, 'Zaawansowany Python',
    'Pogłębiony kurs Pythona obejmujący dekoratory, generatory, programowanie asynchroniczne, wzorce projektowe i optymalizację kodu.',
    '2026-03-01 12:00:00'),
(3, 3, 'Wprowadzenie do Machine Learning',
    'Praktyczny kurs ML: regresja liniowa, drzewa decyzyjne, sieci neuronowe, walidacja krzyżowa. Projekty w scikit-learn i TensorFlow.',
    '2026-03-15 09:00:00');


-- Zapisy na kursy (studenci zapisani na różne kursy)
INSERT INTO public.course_enrollments (id, user_id, course_id, enrolled_at) VALUES
(1,  4, 1, '2026-02-11 08:00:00'),   -- Marek -> SQL
(2,  4, 2, '2026-03-02 09:00:00'),   -- Marek -> Python
(3,  5, 1, '2026-02-16 10:00:00'),   -- Katarzyna -> SQL
(4,  5, 3, '2026-03-16 11:00:00'),   -- Katarzyna -> ML
(5,  6, 1, '2026-03-02 12:00:00'),   -- Piotr -> SQL
(6,  6, 2, '2026-03-05 13:00:00'),   -- Piotr -> Python
(7,  7, 1, '2026-03-11 14:00:00'),   -- Agnieszka -> SQL
(8,  7, 3, '2026-03-17 15:00:00'),   -- Agnieszka -> ML
(9,  8, 2, '2026-03-21 16:00:00'),   -- Tomasz -> Python
(10, 8, 3, '2026-03-22 16:30:00');   -- Tomasz -> ML


-- Lekcje (po 4 lekcje na kurs = 12 lekcji)
INSERT INTO public.lessons (id, course_id, title, content, order_index) VALUES
-- Kurs 1: SQL
(1,  1, 'Wprowadzenie do baz danych',    'Czym jest baza danych? Modele danych: relacyjny, dokumentowy, grafowy. Historia SQL.',         1),
(2,  1, 'Tworzenie tabel i typy danych', 'CREATE TABLE, ALTER TABLE, DROP TABLE. Typy danych w PostgreSQL: INTEGER, VARCHAR, TEXT, TIMESTAMP.', 2),
(3,  1, 'Zapytania SELECT i JOIN',       'SELECT, WHERE, ORDER BY, LIMIT. Rodzaje JOIN: INNER, LEFT, RIGHT, FULL OUTER, CROSS.',       3),
(4,  1, 'Agregacje i grupowanie',         'COUNT, SUM, AVG, MIN, MAX. GROUP BY, HAVING. Podzapytania i CTE.',                           4),
-- Kurs 2: Python
(5,  2, 'Dekoratory i metaklasy',         'Funkcje wyższego rzędu, dekoratory @, klasy jako dekoratory, metaklasy w Pythonie.',          1),
(6,  2, 'Generatory i iteratory',         'yield, send(), throw(). Protokół iteratora. itertools i functools.',                          2),
(7,  2, 'Programowanie asynchroniczne',   'asyncio, await, aiohttp. Event loop. Współbieżność vs równoległość.',                        3),
(8,  2, 'Wzorce projektowe w Pythonie',   'Singleton, Factory, Observer, Strategy, Decorator. SOLID w Pythonie.',                       4),
-- Kurs 3: ML
(9,  3, 'Czym jest Machine Learning?',    'Uczenie nadzorowane vs nienadzorowane. Workflow ML: dane, cechy, trening, ewaluacja.',        1),
(10, 3, 'Regresja liniowa i logistyczna', 'Funkcja kosztu, gradient descent, regularyzacja L1/L2. Metryki: MSE, R², accuracy.',          2),
(11, 3, 'Drzewa decyzyjne i lasy losowe','Entropia, information gain, pruning. Random Forest, Gradient Boosting, XGBoost.',             3),
(12, 3, 'Sieci neuronowe',                'Perceptron, backpropagation, aktywacje (ReLU, sigmoid). Keras i TensorFlow basics.',          4);


-- Testy (po 3 testy w wybranych lekcjach = 9 testów)
INSERT INTO public.tests (id, lesson_id, title, max_points) VALUES
-- Kurs 1: SQL
(1, 1, 'Quiz: Podstawy baz danych',         20),
(2, 3, 'Test: Zapytania SELECT i JOIN',      30),
(3, 4, 'Egzamin końcowy: SQL',               50),
-- Kurs 2: Python
(4, 5, 'Quiz: Dekoratory',                   20),
(5, 7, 'Test: Asyncio',                      25),
(6, 8, 'Egzamin końcowy: Python',            50),
-- Kurs 3: ML
(7, 9,  'Quiz: Wstęp do ML',                 15),
(8, 10, 'Test: Regresja',                     30),
(9, 12, 'Egzamin końcowy: Sieci neuronowe',  50);


-- Oceny (wyniki studentów w testach)
INSERT INTO public.grades (id, test_id, user_id, points_scored, graded_at) VALUES
-- Marek (user 4) – SQL + Python
( 1, 1, 4, 18.00, '2026-02-20 10:00:00'),  -- Quiz SQL: 18/20
( 2, 2, 4, 25.50, '2026-03-05 11:00:00'),  -- Test JOIN: 25.5/30
( 3, 3, 4, 42.00, '2026-03-20 12:00:00'),  -- Egzamin SQL: 42/50
( 4, 4, 4, 17.00, '2026-03-25 10:00:00'),  -- Quiz dekoratory: 17/20
( 5, 5, 4, 20.00, '2026-04-10 11:00:00'),  -- Test asyncio: 20/25
-- Katarzyna (user 5) – SQL + ML
( 6, 1, 5, 20.00, '2026-02-22 09:00:00'),  -- Quiz SQL: 20/20 (ideał!)
( 7, 2, 5, 28.00, '2026-03-08 10:00:00'),  -- Test JOIN: 28/30
( 8, 3, 5, 47.50, '2026-03-22 11:00:00'),  -- Egzamin SQL: 47.5/50
( 9, 7, 5, 14.00, '2026-04-01 12:00:00'),  -- Quiz ML: 14/15
(10, 8, 5, 27.00, '2026-04-15 13:00:00'),  -- Test regresja: 27/30
-- Piotr (user 6) – SQL + Python
(11, 1, 6, 12.00, '2026-03-10 14:00:00'),  -- Quiz SQL: 12/20
(12, 2, 6, 18.50, '2026-03-18 15:00:00'),  -- Test JOIN: 18.5/30
(13, 4, 6, 15.00, '2026-03-28 16:00:00'),  -- Quiz dekoratory: 15/20
-- Agnieszka (user 7) – SQL + ML
(14, 1, 7, 19.00, '2026-03-15 09:00:00'),  -- Quiz SQL: 19/20
(15, 2, 7, 26.00, '2026-03-25 10:00:00'),  -- Test JOIN: 26/30
(16, 7, 7, 13.00, '2026-04-05 11:00:00'),  -- Quiz ML: 13/15
(17, 8, 7, 24.50, '2026-04-18 12:00:00'),  -- Test regresja: 24.5/30
-- Tomasz (user 8) – Python + ML
(18, 4, 8,  9.00, '2026-04-01 14:00:00'),  -- Quiz dekoratory: 9/20
(19, 7, 8, 11.00, '2026-04-08 15:00:00'),  -- Quiz ML: 11/15
(20, 9, 8, 35.00, '2026-04-25 16:00:00'),  -- Egzamin sieci: 35/50
(21, 5, 6, 22.00, '2026-04-30 10:00:00'),  -- Test asyncio: 22/25
(22, 9, 7, 41.00, '2026-05-02 11:00:00'),  -- Egzamin ML: 41/50
(23, 6, 8, 19.50, '2026-05-04 12:00:00');  -- Test asyncio: 19.5/25


SET session_replication_role = DEFAULT;  -- włącza triggery z powrotem


-- ============================================================
--  SEKWENCJE – ustawienie po wstawieniu danych
-- ============================================================

SELECT pg_catalog.setval('public.users_id_seq',               8, true);
SELECT pg_catalog.setval('public.user_profiles_id_seq',       8, true);
SELECT pg_catalog.setval('public.courses_id_seq',             3, true);
SELECT pg_catalog.setval('public.course_enrollments_id_seq', 10, true);
SELECT pg_catalog.setval('public.lessons_id_seq',            12, true);
SELECT pg_catalog.setval('public.tests_id_seq',               9, true);
SELECT pg_catalog.setval('public.grades_id_seq',             23, true);


-- ============================================================
--  ZAAWANSOWANE ZAPYTANIA SQL
-- ============================================================


-- Zapytanie 1 (zagnieżdżone): Studenci, którzy nie ukończyli żadnego testu
-- Wykorzystuje NOT IN z podzapytaniem
SELECT u.email, up.first_name, up.last_name
FROM public.users u
JOIN public.user_profiles up ON u.id = up.user_id
WHERE u.role = 'student'
  AND u.id NOT IN (
      SELECT DISTINCT g.user_id
      FROM public.grades g
  );


-- Zapytanie 2 (wielokrotny JOIN + agregacja): Statystyki sesji per student
SELECT
    up.first_name || ' ' || up.last_name AS student,
    c.title AS kurs,
    COUNT(g.id) AS liczba_testow,
    ROUND(SUM(g.points_scored), 2) AS suma_punktow,
    ROUND(SUM(t.max_points), 2) AS max_punktow,
    ROUND(AVG(g.points_scored), 2) AS srednia_punktow,
    CASE
        WHEN SUM(t.max_points) > 0
        THEN ROUND((SUM(g.points_scored) / SUM(t.max_points)) * 100, 1)
        ELSE 0
    END AS procent
FROM public.users u
JOIN public.user_profiles up        ON u.id = up.user_id
JOIN public.grades g                ON u.id = g.user_id
JOIN public.tests t                 ON g.test_id = t.id
JOIN public.lessons l               ON t.lesson_id = l.id
JOIN public.courses c               ON l.course_id = c.id
GROUP BY up.first_name, up.last_name, c.title
ORDER BY procent DESC;


-- Zapytanie 3 (funkcje okienkowe): Ranking studentów w kursie z RANK()
SELECT
    c.title AS kurs,
    up.first_name || ' ' || up.last_name AS student,
    ROUND(SUM(g.points_scored), 2) AS suma_punktow,
    RANK() OVER (
        PARTITION BY c.id
        ORDER BY SUM(g.points_scored) DESC
    ) AS pozycja_w_kursie
FROM public.grades g
JOIN public.tests t                 ON g.test_id = t.id
JOIN public.lessons l               ON t.lesson_id = l.id
JOIN public.courses c               ON l.course_id = c.id
JOIN public.users u                 ON g.user_id = u.id
JOIN public.user_profiles up        ON u.id = up.user_id
GROUP BY c.id, c.title, up.first_name, up.last_name
ORDER BY c.title, pozycja_w_kursie;


-- Zapytanie 4 (HAVING + podzapytanie): Kursy ze średnią powyżej 70%
SELECT
    c.title,
    COUNT(DISTINCT g.user_id) AS liczba_studentow,
    ROUND(AVG(
        (g.points_scored / t.max_points) * 100
    ), 2) AS sredni_procent
FROM public.courses c
JOIN public.lessons l   ON c.id = l.course_id
JOIN public.tests t     ON l.id = t.lesson_id
JOIN public.grades g    ON t.id = g.test_id
WHERE t.max_points > 0
GROUP BY c.id, c.title
HAVING AVG((g.points_scored / t.max_points) * 100) > 70
ORDER BY sredni_procent DESC;


-- ============================================================
--  TRANSAKCJE I POZIOMY IZOLACJI
-- ============================================================


-- Scenariusz 1: Rejestracja użytkownika z profilem (atomowa)
-- Poziom: domyślny READ COMMITTED
BEGIN;

INSERT INTO public.users (email, password_hash, role)
VALUES ('nowy.student@mail.pl', '$2b$12$EXAMPLE_HASH_FOR_NEW_USER', 'student');

INSERT INTO public.user_profiles (user_id, first_name, last_name, bio)
VALUES (
    currval('public.users_id_seq'),
    'Nowy',
    'Student',
    'Właśnie dołączyłem do platformy!'
);

COMMIT;


-- Scenariusz 2: Zapis na kurs z weryfikacją (REPEATABLE READ)
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Weryfikuj, że kurs istnieje i student nie jest już zapisany
INSERT INTO public.course_enrollments (user_id, course_id)
SELECT currval('public.users_id_seq'), 1
WHERE NOT EXISTS (
    SELECT 1 FROM public.course_enrollments
    WHERE user_id = currval('public.users_id_seq')
      AND course_id = 1
);

COMMIT;


-- Scenariusz 3: Wystawienie oceny (SERIALIZABLE – najwyższy poziom)
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;

INSERT INTO public.grades (test_id, user_id, points_scored)
VALUES (1, currval('public.users_id_seq'), 16.50);

COMMIT;


-- ============================================================
--  UPRAWNIENIA ZESPOŁU
-- ============================================================


-- apokrzywa – właściciel bazy (ma już pełne prawa jako OWNER)

-- blyczak – analityk danych (pełny dostęp do tabel + właściciel widoków)
GRANT ALL ON TABLE public.users              TO blyczak;
GRANT ALL ON TABLE public.user_profiles      TO blyczak;
GRANT ALL ON TABLE public.courses            TO blyczak;
GRANT ALL ON TABLE public.course_enrollments TO blyczak;
GRANT ALL ON TABLE public.lessons            TO blyczak;
GRANT ALL ON TABLE public.tests              TO blyczak;
GRANT ALL ON TABLE public.grades             TO blyczak;

-- Uprawnienia zwrotne do widoków (właścicielem widoków jest blyczak)
GRANT ALL ON TABLE public.v_ranking_studentow  TO apokrzywa;
GRANT ALL ON TABLE public.v_statystyki_kursu   TO apokrzywa;
GRANT ALL ON TABLE public.v_postepy_studenta   TO apokrzywa;

-- bsnieg – programista bazy danych (tworzenie triggerów i funkcji)
GRANT SELECT, INSERT, UPDATE, TRIGGER ON TABLE public.users              TO bsnieg;
GRANT SELECT, INSERT, UPDATE, TRIGGER ON TABLE public.user_profiles      TO bsnieg;
GRANT SELECT, INSERT, UPDATE, TRIGGER ON TABLE public.courses            TO bsnieg;
GRANT SELECT, INSERT, UPDATE, TRIGGER ON TABLE public.course_enrollments TO bsnieg;
GRANT SELECT, INSERT, UPDATE, TRIGGER ON TABLE public.lessons            TO bsnieg;
GRANT SELECT, INSERT, UPDATE, TRIGGER ON TABLE public.tests              TO bsnieg;
GRANT SELECT, INSERT, UPDATE, TRIGGER ON TABLE public.grades             TO bsnieg;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO bsnieg;

-- lbilski – administrator (zarządzanie transakcjami, pełen DML)
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.users              TO lbilski;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_profiles      TO lbilski;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.courses            TO lbilski;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.course_enrollments TO lbilski;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.lessons            TO lbilski;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.tests              TO lbilski;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.grades             TO lbilski;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO lbilski;


-- ============================================================
--  ROLE PRODUKCYJNE (zasada najmniejszych uprawnień)
-- ============================================================

-- Rola tylko do odczytu (monitoring, audyt)
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO elearning_readonly;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO elearning_readonly;

-- Rola nauczyciela (może wystawiać i modyfikować oceny)
GRANT SELECT, INSERT, UPDATE ON TABLE public.grades  TO elearning_teacher;
GRANT SELECT                 ON TABLE public.users   TO elearning_teacher;
GRANT SELECT                 ON TABLE public.tests   TO elearning_teacher;
GRANT SELECT                 ON TABLE public.lessons TO elearning_teacher;
GRANT SELECT                 ON TABLE public.courses TO elearning_teacher;
GRANT SELECT                 ON TABLE public.course_enrollments TO elearning_teacher;
GRANT USAGE, SELECT ON SEQUENCE public.grades_id_seq TO elearning_teacher;
