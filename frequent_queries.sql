-- частые запросы

-- перечислить уволенных сотрудников
SELECT id_emp, full_name FROM employees WHERE quited=true;

-- составить список сотрудников, работающих в отделе статистики финансов
-- со статусами (уволен и является ли начальником)
-- чтобы посмотреть информацию по другим отделам, достаточно просто изменить название отдела
SELECT e.full_name, e.login, e.email, e.quited, d.id_leader 
FROM employees e LEFT JOIN departments d ON e.id_emp=d.id_leader
WHERE e.id_dep = (SELECT id_dep 
				  FROM departments 
				  WHERE name_dep='Отдел статистики финансов');
				  
-- перечислить формы, обрабатываемые отделом статистики населения
-- чтобы посмотреть информацию по другим отделам, достаточно просто изменить название отдела
WITH emps AS
( SELECT id_emp FROM employee_role 
  WHERE id_role = ( SELECT id_role 
		 			FROM roles 
		 			WHERE name_role='Пользователь')
  AND id_emp IN ( SELECT id_emp FROM employees 
  			     WHERE id_dep = (SELECT id_dep 
  			     				 FROM departments 
  			     				 WHERE name_dep='Отдел статистики населения'))
)
SELECT distinct(f.name_form) FROM forms f 
JOIN employee_form e ON e.id_form=f.id_form 
JOIN emps ON e.id_emp=emps.id_emp
WHERE e.id_emp = emps.id_emp;

-- вывести информацию о сотрудниках, которые обрабатывают форму PP1
-- чтобы посмотреть информацию по другим формам, достаточно просто изменить название формы
SELECT e.full_name, e.login, e.email, d.name_dep FROM employees e 
JOIN employee_form ef ON e.id_emp=ef.id_emp
JOIN employee_role er ON e.id_emp=er.id_emp
JOIN departments d ON e.id_dep=d.id_dep
WHERE ef.id_form=(SELECT id_form FROM forms 
				  WHERE name_form='PP1')
AND er.id_role = (SELECT id_role FROM roles
				  WHERE name_role='Пользователь');
				  
-- информация о пользователе по ФИО			  
WITH fr AS
	( SELECT e.id_emp AS employee, array_agg( distinct r.name_role) AS roles, array_agg( distinct f.name_form) AS forms
	  FROM employee_form ef JOIN forms f ON ef.id_form=f.id_form
	  RIGHT JOIN employees e ON ef.id_emp=e.id_emp
	  JOIN employee_role er ON e.id_emp=er.id_emp
	  JOIN roles r ON er.id_role=r.id_role
	  GROUP BY e.id_emp
	  ORDER BY e.id_emp	  
	)
SELECT e.login, e.email, d.name_dep, fr.roles, fr.forms  
FROM employees e LEFT JOIN fr ON e.id_emp=fr.employee
JOIN departments d ON e.id_dep=d.id_dep
WHERE e.full_name='Поршнева Елена Дмитриевна';

-- список сотрудников, обрабатывающих определенную форму, и в каком отделе они работают, 
-- группировка производится по форме
SELECT f.name_form AS form,
       e.full_name,
       d.name_dep,
       ROW_NUMBER() OVER(PARTITION BY f.name_form ORDER BY e.full_name) AS row_number
FROM employees e
JOIN employee_form ef ON e.id_emp=ef.id_emp
JOIN employee_role er ON e.id_emp=er.id_emp
JOIN departments d ON e.id_dep=d.id_dep
JOIN forms f ON ef.id_form=f.id_form
WHERE er.id_role = (SELECT id_role FROM roles
                    WHERE name_role='Пользователь');
					