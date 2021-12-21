-- создание таблиц
CREATE TABLE departments
(id_dep serial, 
name_dep text NOT NULL,
deleted boolean NOT NULL DEFAULT false, 
id_leader integer NULL, 
PRIMARY KEY (id_dep));

CREATE TABLE employees 
(id_emp serial, 
full_name text NOT NULL, 
login varchar(50) NULL, 
email varchar(255) NULL, 
id_dep integer NOT NULL, 
quited boolean NOT NULL DEFAULT false, 
phone varchar(255) NULL, 
PRIMARY KEY (id_emp), 
FOREIGN KEY (id_dep) REFERENCES departments (id_dep) ON DELETE CASCADE);

CREATE TABLE forms 
(id_form serial, 
code varchar(12) NOT NULL, 
name_form varchar(255) NOT NULL, 
processing_csod boolean NULL, 
PRIMARY KEY (id_form));

CREATE TABLE roles 
(id_role serial PRIMARY KEY, 
name_role  text NOT NULL );

CREATE TABLE employee_role 
(id_emp integer NOT NULL, 
id_role integer NOT NULL, 
PRIMARY KEY (id_emp, id_role), 
FOREIGN KEY (id_emp) REFERENCES employees (id_emp) ON DELETE CASCADE,
FOREIGN KEY (id_role) REFERENCES roles (id_role) ON DELETE CASCADE);

CREATE TABLE employee_form 
(id_emp integer NOT NULL, 
id_form integer NOT NULL, 
PRIMARY KEY (id_emp, id_form), 
FOREIGN KEY (id_emp) REFERENCES employees (id_emp) ON DELETE CASCADE,
FOREIGN KEY (id_form) REFERENCES forms (id_form) ON DELETE CASCADE);

-- добавление ограничений
ALTER TABLE departments ADD FOREIGN KEY (id_leader) REFERENCES employees (id_emp) ON DELETE CASCADE;

ALTER TABLE departments ADD CONSTRAINT id_leader_unique UNIQUE (id_leader);

-- создание триггерных функций

-- проверка при добавлении начальника отдела - 
-- работает ли он в отделе, где будет начальником
CREATE OR REPLACE FUNCTION check_leader_trfunc()
RETURNS trigger AS
$$
BEGIN
	IF (NEW.id_dep = NULL) THEN
		RETURN NEW;
	ELSIF ( (SELECT id_dep FROM employees WHERE id_emp=NEW.id_leader) != NEW.id_dep) THEN
		RAISE NOTICE 'Сотрудник не работает в данном отделе!';
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END;
$$ language plpgsql;

-- проверка, можно ли пользователю выдавать доступ к определенной форме
-- если в таблице у него нет доступа ни на редактирование(пользователь), ни на чтение - то доступ запрещен
CREATE OR REPLACE FUNCTION check_roles_trfunc()
RETURNS trigger AS
$$
DECLARE
	e integer;
	flag boolean;
BEGIN
	flag :=  false;
	FOR e IN SELECT id_emp FROM employee_role WHERE id_role in (2,3)  
	LOOP
		IF (NEW.id_emp = e) THEN
			flag := true;
		END IF;
	END LOOP;
	
	IF flag = false THEN
		RAISE NOTICE 'У сотрудника c id % нет роли, чтобы можно было предоставить доступ к форме. Назначьте роль для сотрудника', NEW.id_emp;
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
	
END;
$$ language plpgsql;

-- если удаляем роль пользователь или только чтение, 
-- то проверяем не осталось ли в таблице employee_form записей по данному сотруднику
CREATE OR REPLACE FUNCTION check_del_roles_trfunc()
RETURNS trigger AS
$$
BEGIN
	IF (OLD.id_role = 2 OR OLD.id_role = 3) THEN
		IF EXISTS (SELECT id_emp FROM employee_form WHERE id_emp = OLD.id_emp) THEN
			RAISE NOTICE 'Невозможно удалить роль у данного пользователя, так как пользователь обрабатывает формы. Удалите необходимые записи из таблицы employee_form';
			RETURN NULL;
		ELSE 
			RETURN OLD;
		END IF;
	ELSE
		RETURN OLD;
	END IF;
END;
$$ language plpgsql;

-- Сотрудник не может одновременно иметь роли: Пользователь и Только чтение
CREATE OR REPLACE FUNCTION check_access_trfunc()
RETURNS trigger AS
$$
BEGIN
	IF NEW.id_role = 2 THEN
		IF EXISTS (SELECT id_role FROM employee_role WHERE id_emp = NEW.id_emp AND id_role = 3) THEN
			RAISE NOTICE 'Сотрудник не может одновременно осуществлять роли "Пользователь" и "Только чтение"';
			RETURN NULL;
		ELSE 
			RETURN NEW;
		END IF;
	ELSIF NEW.id_role = 3 THEN
		IF EXISTS (SELECT id_role FROM employee_role WHERE id_emp = NEW.id_emp AND id_role = 2) THEN
			RAISE NOTICE 'Сотрудник не может одновременно осуществлять роли "Пользователь" и "Только чтение"';
			RETURN NULL;
		ELSE 
			RETURN NEW;
		END IF;
	ELSE
		RETURN NEW;
	END IF;
END;
$$ language plpgsql;

-- триггеры

CREATE TRIGGER check_leader_trigger
BEFORE UPDATE OR INSERT ON departments
FOR EACH ROW EXECUTE FUNCTION check_leader_trfunc();

CREATE TRIGGER check_roles_trigger
BEFORE UPDATE OR INSERT ON employee_form
FOR EACH ROW EXECUTE FUNCTION check_roles_trfunc();

CREATE TRIGGER check_roles_del_trigger
BEFORE DELETE ON employee_role
FOR EACH ROW EXECUTE FUNCTION check_del_roles_trfunc();

CREATE TRIGGER check_access_trigger
BEFORE UPDATE OR INSERT ON employee_role
FOR EACH ROW EXECUTE FUNCTION check_access_trfunc();

-- хранимые функции 
-- функция для присвоения сотруднику роли
CREATE OR REPLACE FUNCTION role_to_employee ( name text, role text)
	RETURNS VOID AS
$$
BEGIN
	IF NOT EXISTS (SELECT full_name FROM employees WHERE full_name=name) THEN
		RAISE EXCEPTION 'Сотрудника с именем % нет в базe', name;
	END IF;
	
	IF NOT EXISTS (SELECT name_role FROM roles WHERE name_role=role) THEN
		RAISE EXCEPTION 'Роль % не существует в базе', role;
	END IF;
	
	INSERT INTO employee_role (id_emp, id_role) VALUES(
		(SELECT emp.id_emp FROM employees emp WHERE emp.full_name = name),
		(SELECT r.id_role FROM roles r WHERE r.name_role = role)
	);
        
	EXCEPTION
		WHEN OTHERS THEN
			RAISE NOTICE '%', SQLERRM;
END;
$$ language plpgsql;


-- функция для предоставления доступа к нескольким формам для сотрудника
CREATE OR REPLACE FUNCTION forms_to_employee (name text, VARIADIC nforms char[])
	RETURNS TABLE(id_emp integer, id_form integer) AS
$$
DECLARE
	i varchar(255);
BEGIN
	IF NOT EXISTS (SELECT full_name FROM employees WHERE full_name=name) THEN
		RAISE EXCEPTION 'Сотрудника с именем % нет в базe', name;
	END IF;
	
	FOREACH i IN ARRAY nforms
	LOOP
		IF NOT EXISTS (SELECT name_form FROM forms WHERE name_form = i) THEN
			RAISE EXCEPTION 'Формы с названием % нет в базe', i;
		END IF;
	END LOOP;
	
	FOREACH i IN ARRAY nforms
	LOOP
		RETURN QUERY INSERT INTO employee_form (id_emp, id_form) VALUES(
			(SELECT emp.id_emp FROM employees emp WHERE emp.full_name = name),
			(SELECT f.id_form FROM forms f WHERE f.name_form = i)
		) RETURNING *;
	END LOOP;
	
	EXCEPTION
		WHEN OTHERS THEN
			RAISE NOTICE '%', SQLERRM;
END;
$$ language plpgsql;

-- функция для предоставления доступа ко всем формам
CREATE OR REPLACE FUNCTION allforms_to_employee (name text)
	RETURNS VOID AS
$$
DECLARE
	i integer; 
BEGIN
	IF NOT EXISTS (SELECT full_name FROM employees WHERE full_name=name) THEN
		RAISE EXCEPTION 'Сотрудника с именем % нет в базe', name;
	END IF;
	FOR i IN SELECT id_form FROM forms
	LOOP
		INSERT INTO employee_form (id_emp, id_form) VALUES(
			(SELECT emp.id_emp FROM employees emp WHERE emp.full_name = name),
			(SELECT f.id_form FROM forms f WHERE f.id_form = i)
		);
	END LOOP;
	EXCEPTION
		WHEN OTHERS THEN
			RAISE NOTICE '%', SQLERRM;
END;
$$ language plpgsql;

-- добавление записей
INSERT INTO departments (name_dep)
VALUES ('Руководство'),
	   ('Отдел кадров'),
	   ('Бухгалтерия'),
	   ('IT-отдел'),
	   ('Отдел статистики населения'),
	   ('Отдел статистики финансов'),
	   ('Отдел статистики сельского хозяйства');

INSERT INTO employees (full_name, login, email, id_dep, phone)
VALUES ('Филатов Виктор Артемович', 'FilatovVA', 'FilatovVA@mail.ru', 1, '00000'),
	   ('Авдеева Валентина Игоревна', 'AvdeevaVI', 'AvdeevaVI@mail.ru', 1, '00007'),
	   ('Иванова Анна Сергеевна', 'IvanovaAS', 'IvanovaAS@mail.ru', 2, '12345'),
	   ('Новиков Леонид Андреевич', 'NovikovLA', 'NovikovLA@mail.ru', 2, '67890'),
	   ('Поршнева Елена Дмитриевна', 'PorshnevaED', 'PorshnevaED@mail.ru', 2, '12333'),
	   ('Самойлов Олег Владимирович', 'SamoylovOV', 'SamoylovOV@mail.ru', 3, '11111'),
	   ('Черкасова Александра Афанасьевна', 'CherkasovaAA', 'CherkasovaAA@mail.ru', 3, '22222'),
	   ('Лапкина Алена Александровна', 'LapkinaAA', 'LapkinaAA@mail.ru', 3, '21212'),
	   ('Галкин Максим Константинович', 'GalkinMK', 'GalkinMK@mail.ru', 4, '33333'),
	   ('Петров Егор Петрович', 'PetrovEP', 'PetrovEP@mail.ru', 4, '33331'),
	   ('Козлова Мария Вадимовна', 'KozlovaMV', 'KozlovaMV@mail.ru', 4, '33332'),
	   ('Иванов Денис Евгеньевич', 'IvanovDE', 'IvanovDE@mail.ru', 5, '44444'),
	   ('Романова Дарья Ивановна', 'RomanovaDI', 'RomanovaDI@mail.ru', 5, '44441'),
	   ('Романов Роман Григорьевич', 'RomanovRG', 'RomanovRG@mail.ru', 6, '55555'),
	   ('Кричун Елена Олеговна', 'KrichunEO', 'KrichunEO@mail.ru', 6, '55525'),
	   ('Цветков Александр Алексеевич', 'TsvetkovAA', 'TsvetkovAA@mail.ru', 6, '55522'),
	   ('Логинова Алевтина Александровна', 'LoginovaAA', 'LoginovaAA@mail.ru', 7, '66660' ),
	   ('Сергеева Александра Эдуардовна', 'SergeevaAE', 'SergeevaAE@mail.ru', 7, '66665' );
	   
INSERT INTO forms (code, name_form, processing_csod)
VALUES ('012345678', 'PP1', 't'),
	   ('014343434', 'PP2', 't'),
	   ('014343455', 'PL1', 't'),
	   ('014343333', 'PL3', 't'),
	   ('014344444', 'DD1', 't');
	   
INSERT INTO roles (name_role)
VALUES ('Администратор регионального уровня'),
	   ('Пользователь'),
	   ('Только чтение');
	   
-- назначение начальников
UPDATE departments SET id_leader = 1 WHERE name_dep = 'Руководство';
UPDATE departments SET id_leader = 3 WHERE name_dep = 'Отдел кадров';
UPDATE departments SET id_leader = 6 WHERE name_dep = 'Бухгалтерия';
UPDATE departments SET id_leader = 9 WHERE name_dep = 'IT-отдел';
UPDATE departments SET id_leader = 12 WHERE name_dep = 'Отдел статистики населения';
UPDATE departments SET id_leader = 14 WHERE name_dep = 'Отдел статистики финансов';
UPDATE departments SET id_leader = 17 WHERE name_dep = 'Отдел статистики сельского хозяйства';

-- присвоение ролей
SELECT * FROM role_to_employee('Филатов Виктор Артемович', 'Администратор регионального уровня');   
SELECT * FROM role_to_employee('Филатов Виктор Артемович', 'Пользователь');
SELECT * FROM role_to_employee('Галкин Максим Константинович', 'Администратор регионального уровня');
SELECT * FROM role_to_employee('Петров Егор Петрович', 'Администратор регионального уровня');
SELECT * FROM role_to_employee('Козлова Мария Вадимовна', 'Администратор регионального уровня');
SELECT * FROM role_to_employee('Козлова Мария Вадимовна', 'Пользователь');
SELECT * FROM role_to_employee('Иванов Денис Евгеньевич', 'Пользователь');
SELECT * FROM role_to_employee('Романова Дарья Ивановна', 'Пользователь');
SELECT * FROM role_to_employee('Романов Роман Григорьевич', 'Пользователь');
SELECT * FROM role_to_employee('Кричун Елена Олеговна', 'Только чтение');
SELECT * FROM role_to_employee('Цветков Александр Алексеевич', 'Пользователь');
SELECT * FROM role_to_employee('Логинова Алевтина Александровна', 'Пользователь');
SELECT * FROM role_to_employee('Сергеева Александра Эдуардовна', 'Только чтение');

-- формы для каждого сотрудника
SELECT * FROM allforms_to_employee('Филатов Виктор Артемович');
SELECT * FROM allforms_to_employee('Козлова Мария Вадимовна');
SELECT * FROM forms_to_employee('Иванов Денис Евгеньевич', 'PP1', 'PP2');
SELECT * FROM forms_to_employee('Романова Дарья Ивановна', 'PP1');
SELECT * FROM forms_to_employee('Романов Роман Григорьевич', 'PL1', 'PL3');
SELECT * FROM forms_to_employee('Кричун Елена Олеговна', 'PL1', 'PL3');
SELECT * FROM forms_to_employee('Цветков Александр Алексеевич', 'PL3');
SELECT * FROM forms_to_employee('Логинова Алевтина Александровна', 'PP1', 'PP2', 'DD1');
SELECT * FROM forms_to_employee('Сергеева Александра Эдуардовна', 'PL3');
