# Platforma E-learningowa - System Zarządzania Kursami Online

> **Projekt zaliczeniowy / Dokumentacja Techniczna Bazy Danych PostgreSQL 16**

---

## Opis projektu
Projekt obejmuje projekt i implementację relacyjnej bazy danych dla platformy e-learningowej w środowisku PostgreSQL 16. System został stworzony w celu efektywnego zarządzania użytkownikami, tworzenia i prowadzenia kursów, przeprowadzania testów wiedzy oraz analizowania wyników studentów. Cała struktura bazy danych została rygorystycznie zoptymalizowana i w pełni znormalizowana do trzeciej postaci normalnej (3NF), co eliminuje redundancję danych i niepożądane zależności przechodnie.

## Główne funkcjonalności
* **Zarządzanie użytkownikami:** Rejestracja i przechowywanie danych uwierzytelniających z podziałem na role systemowe: student, nauczyciel, administrator.
* **Profile użytkowników:** Przechowywanie danych personalnych (imię, nazwisko, bio, awatar) w oddzielnej tabeli powiązanej relacją 1:1 z głównym kontem użytkownika.
* **Zarządzanie kursami:** Umożliwienie nauczycielom tworzenia kursów wraz ze śledzeniem daty ich utworzenia.
* **Zapisy na kursy:** Obsługa relacji wiele-do-wielu (M:N) między studentami a kursami z nałożonym mechanizmem kontroli unikalności zapisu.
* **Moduł edukacyjny:** Definiowanie uporządkowanych lekcji w ramach kursów oraz przypisywanie do nich testów wiedzy.
* **Ocenianie:** Rejestracja wyników studentów z dokładnością numeryczną do dwóch miejsc po przecinku (typ `NUMERIC`).

## Struktura Bazy Danych
System opiera się na siedmiu głównych tabelach:
* `users`: Dane uwierzytelniające i role systemowe.
* `user_profiles`: Profile personalne użytkowników.
* `courses`: Katalog kursów online.
* `course_enrollments`: Zapisy studentów na poszczególne kursy.
* `lessons`: Lekcje wchodzące w skład kursów.
* `tests`: Sprawdziany wiedzy.
* `grades`: Oceny i wyniki z testów.

## Zaawansowane mechanizmy 
* **Wyzwalacze (Triggers):** Baza wykorzystuje procedury w języku PL/pgSQL do sprawdzania, czy student jest zapisany na kurs przed wystawieniem oceny, blokowania duplikatów ocen dla tego samego sprawdzianu oraz automatycznego logowania nowych wyników.
* **Widoki analityczne:** Zaimplementowano gotowe widoki ułatwiające raportowanie, w tym dynamiczny ranking studentów (`v_ranking_studentow`), ogólne statystyki kursów (`v_statystyki_kursu`) oraz szczegółowe postępy studentów (`v_postepy_studenta`).
* **Transakcje i izolacja:** Operacje krytyczne dla integralności danych (np. rejestracja użytkownika, zapis na kurs, wystawienie oceny) ustrukturyzowano w bloki transakcyjne z jawnym przypisaniem dedykowanych poziomów izolacji, takich jak `REPEATABLE READ` oraz `SERIALIZABLE`.
* **Bezpieczeństwo i RBAC:** Wdrożono kompletny model bezpieczeństwa ról, odzwierciedlający zasadę najmniejszych uprawnień. Utworzono restrykcyjne role produkcyjne, na przykład konto nauczycielskie (tylko z prawem wprowadzania ocen) oraz konto wyłącznie do odczytu dla celów audytu.
