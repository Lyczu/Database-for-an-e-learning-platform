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

---

## 🛠 Wymagania wstępne
Aby uruchomić projekt na swoim środowisku lokalnym, będziesz potrzebować:
* **PostgreSQL** w wersji 16 lub nowszej.
* Dowolnego klienta bazy danych (np. pgAdmin, DBeaver, DataGrip) lub dostępu do psql z poziomu wiersza poleceń.

## 🚀 Uruchomienie projektu
1. Sklonuj repozytorium na swój dysk lokalny:
   ```bash
   git clone [https://github.com/TwojLogin/nazwa-repozytorium.git](https://github.com/TwojLogin/nazwa-repozytorium.git)
   ```

2. Utwórz nową, pustą bazę danych w PostgreSQL.
3. Zaimportuj strukturę i dane w podanej kolejności, wykonując skrypty SQL znajdujące się w folderze `/sql`:
* `01_schema.sql` - tworzenie tabel i relacji
* `02_views.sql` - tworzenie widoków analitycznych
* `03_functions_triggers.sql` - logika biznesowa, funkcje i wyzwalacze
* `04_roles_security.sql` - tworzenie ról i nadawanie uprawnień
* `05_seed_data.sql` - (Opcjonalnie) przykładowe dane testowe



---

## 🤝 Wkład w projekt (Contributing)

Projekt ma charakter otwarty i zachęcam do jego współtworzenia! Jeśli masz pomysł na optymalizację zapytań, dodanie nowych widoków lub rozszerzenie logiki biznesowej, zastosuj się do poniższych kroków:

### Jak zacząć?

1. Zrób **Fork** tego repozytorium.
2. Utwórz nową gałąź na swoją funkcjonalność: `git checkout -b feature/nowa-funkcjonalnosc` (lub `fix/naprawa-bledu`).
3. Wprowadź swoje zmiany w kodzie SQL.
4. Zatwierdź zmiany (Commit): `git commit -m 'Dodano nowy widok ze statystykami logowań'`.
5. Wypchnij gałąź do swojego forka: `git push origin feature/nowa-funkcjonalnosc`.
6. Utwórz **Pull Request (PR)** do oryginalnego repozytorium, dokładnie opisując, co zostało dodane lub zmienione.

### Zasady pisania kodu SQL w tym projekcie:

* **Nazewnictwo:** Używaj notacji `snake_case` dla nazw tabel, kolumn, widoków (np. `v_nazwa_widoku`) i funkcji.
* **Normalizacja:** Pilnuj, aby nowe tabele zachowywały 3NF. Zawsze definiuj klucze główne (`PRIMARY KEY`) i obce (`FOREIGN KEY`).
* **Komentarze:** Każdą nową funkcję w PL/pgSQL lub skomplikowany widok opatrz krótkim komentarzem wyjaśniającym jego działanie.
* **Testowanie:** Upewnij się, że modyfikacje nie psują istniejących wyzwalaczy ani mechanizmów izolacji transakcji.
