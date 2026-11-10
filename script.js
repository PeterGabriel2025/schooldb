import { supabase, supabaseConfigError } from './supabaseClient.js';

document.addEventListener('DOMContentLoaded', () => {
  const splashScreen = document.querySelector('[data-splash-screen]');
  window.setTimeout(() => splashScreen?.classList.add('is-hidden'), 1800);
  const main = document.querySelector('.main-panel');
  const dashboard = document.querySelector('[data-view="dashboard"]');
  const pageTitles = {
    dashboard: ['Dashboard', 'Welcome back'],
    classes: ['My Classes', 'Your assigned classes and result progress'],
    'my-subjects': ['My Subjects', 'Assigned subjects and score entry'],
    students: ['Student Register', 'Manage students in the selected class'],
    scores: ['Enter Scores', 'Record assessment scores for your assigned subject'],
    master: ['Master Sheets', 'Class results by academic session and term'],
    results: ['Student Results', 'Individual student academic records'],
    reports: ['Reports & Exports', 'School reports and result summaries'],
    permissions: ['Permissions', 'Role-based access configuration'],
    management: ['Teachers & Subjects', 'School staff, classes and subject assignments'],
    settings: ['Sessions & Settings', 'Academic calendar, assessment and grading']
  };
  const navItems = [...document.querySelectorAll('.nav-item[data-page]')];
  const menuToggle = document.querySelector('.menu-toggle');
  const sidebar = document.querySelector('.sidebar');
  const menuSignOutButton = document.querySelector('[data-menu-sign-out]');
  const pages = [...document.querySelectorAll('.page-view[data-view]')];
  const title = document.querySelector('#page-title');
  const subtitle = document.querySelector('#page-subtitle');
  const toast = document.querySelector('.toast-message');
  const loginOverlay = document.querySelector('#login-overlay');
  const loginForm = document.querySelector('#login-form');
  const loginMessage = document.querySelector('#auth-message');
  const loginSubmit = document.querySelector('#login-submit');
  const studentClassSelect = document.querySelector('#student-class-select');
  const studentSessionSelect = document.querySelector('#student-session-select');
  const studentTableBody = document.querySelector('#students-table tbody');
  const studentDialog = document.querySelector('#student-dialog');
  const studentForm = document.querySelector('#student-form');
  const studentFormMessage = document.querySelector('[data-student-form-message]');
  const classCards = document.querySelector('[data-live-class-cards]');
  const dashboardClassCards = document.querySelector('[data-dashboard-class-cards]');
  const subjectCards = document.querySelector('[data-live-subject-cards]');
  const scoreClassSelect = document.querySelector('#score-class-select');
  const scoreSessionSelect = document.querySelector('#score-session-select');
  const scoreTermSelect = document.querySelector('#score-term-select');
  const scoreSubjectSelect = document.querySelector('#score-subject-select');
  const scoreHead = document.querySelector('[data-score-head]');
  const scoreBody = document.querySelector('[data-score-body]');
  const scoreActionDialog = document.querySelector('#score-action-dialog');
  const scoreActionForm = document.querySelector('#score-action-form');
  const scoreActionReason = document.querySelector('#score-action-reason');
  const scoreActionMessage = document.querySelector('[data-score-action-message]');
  let resolveScoreAction;
  const masterClassSelect = document.querySelector('#master-class-select');
  const masterSessionSelect = document.querySelector('#master-session-select');
  const masterTermSelect = document.querySelector('#master-term-select');
  const resultClassSelect = document.querySelector('#result-class-select');
  const resultSessionSelect = document.querySelector('#result-session-select');
  const resultTermSelect = document.querySelector('#result-term-select');
  const resultStudentSelect = document.querySelector('#result-student-select');
  const sectionAssessmentSelect = document.querySelector('[data-section-assessment-select]');
  const signOutButton = document.querySelector('[data-auth-action]');
  const sessionSignOutButton = document.querySelector('[data-session-sign-out]');
  const userName = document.querySelector('#user-name');
  const userRole = document.querySelector('#user-role');
  const userAvatar = document.querySelector('#user-avatar');
  const themeToggle = document.querySelector('.theme-toggle');
  const themeToggleIcon = document.querySelector('.theme-toggle-icon');
  let toastTimer;
  let profileRequest = 0;
  let dataRequest = 0;
  let currentProfile = null;
  let currentStudents = [];
  let studentRegisterCanManage = false;
  let editingStudentId = '';
  let currentClasses = [];
  let currentClassesAll = [];
  let currentScoreClasses = [];
  let currentSessions = [];
  let currentTeacherClassIds = new Set();
  let currentTeacherClassSessions = new Set();
  let currentTeacherClassSessionMap = new Map();
  let currentTeacherSubjectOfferingIds = new Set();
  let currentTeacherSubjectTerms = new Map();
  let currentTeacherSubjectOfferings = [];
  let currentTeacherRoles = new Set();
  let createTeacherClasses = [];
  let createTeacherOfferings = [];
  let sectionAssessmentSettings = [];
  let currentScoreComponents = [];
  let currentScoreOffering = null;
  let pendingScoreClassId = '';
  let pendingScoreSessionId = '';
  let pendingScoreOfferingId = '';
  let pendingScoreTermId = '';
  let currentScoreRows = [];
  let scoreRequestId = 0;
  let masterRequestId = 0;
  let resultRequestId = 0;

  const applyTheme = (theme) => {
    const isDark = theme === 'dark';
    document.documentElement.dataset.theme = isDark ? 'dark' : 'light';
    if (themeToggle) {
      themeToggle.setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode');
      themeToggle.setAttribute('title', isDark ? 'Switch to light mode' : 'Switch to dark mode');
    }
    if (themeToggleIcon) themeToggleIcon.textContent = isDark ? '☀' : '☾';
  };

  const savedTheme = window.localStorage.getItem('eduresults-theme');
  applyTheme(savedTheme === 'dark' ? 'dark' : 'light');
  themeToggle?.addEventListener('click', () => {
    const nextTheme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    applyTheme(nextTheme);
    window.localStorage.setItem('eduresults-theme', nextTheme);
  });

  const gallery = document.querySelector('[data-dashboard-gallery]');
  if (gallery) {
    const slides = [...gallery.querySelectorAll('[data-gallery-slide]')];
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    let activeSlide = 0;
    let rotationTimer;

    const showGallerySlide = (index) => {
      activeSlide = (index + slides.length) % slides.length;
      slides.forEach((slide, slideIndex) => {
        const isActive = slideIndex === activeSlide;
        slide.classList.toggle('is-active', isActive);
        slide.setAttribute('aria-hidden', String(!isActive));
        slide.inert = !isActive;
      });
    };

    const updateRotation = () => {
      window.clearInterval(rotationTimer);
      if (reducedMotion.matches
        || document.hidden
        || dashboard.hidden
        || document.body.classList.contains('auth-required')) return;
      rotationTimer = window.setInterval(() => showGallerySlide(activeSlide + 1, false), 5000);
    };

    document.addEventListener('visibilitychange', updateRotation);
    reducedMotion.addEventListener('change', updateRotation);
    const galleryObserver = new MutationObserver(updateRotation);
    galleryObserver.observe(dashboard, { attributes: true, attributeFilter: ['hidden'] });
    galleryObserver.observe(document.body, { attributes: true, attributeFilter: ['class'] });
    updateRotation();
  }

  ['.content-grid', '.dashboard-grid', '.master-grid'].forEach((selector) => {
    const section = main.querySelector(selector);
    if (section) {
      dashboard.append(section);
      section.hidden = true;
    }
  });

  const showToast = (message) => {
    if (!toast || !message) return;
    toast.textContent = message;
    toast.classList.add('visible');
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => toast.classList.remove('visible'), 3200);
  };

  const showPage = (pageName) => {
    if (!pageTitles[pageName]) return;
    const pageNav = navItems.find((item) => item.dataset.page === pageName);
    if (pageNav?.hidden) return;
    pages.forEach((page) => {
      const isActive = page.dataset.view === pageName;
      page.classList.toggle('active', isActive);
      page.hidden = !isActive;
    });
    navItems.forEach((item) => {
      const isActive = item.dataset.page === pageName;
      item.classList.toggle('active', isActive);
      if (isActive) item.setAttribute('aria-current', 'page');
      else item.removeAttribute('aria-current');
    });
    title.textContent = pageTitles[pageName][0];
    subtitle.textContent = pageTitles[pageName][1];
  };

  navItems.forEach((item) => item.addEventListener('click', () => {
    showPage(item.dataset.page);
    sidebar.classList.remove('menu-open');
    menuToggle.setAttribute('aria-expanded', 'false');
    menuToggle.setAttribute('aria-label', 'Open navigation menu');
  }));

  menuSignOutButton?.addEventListener('click', () => {
    sidebar.classList.remove('menu-open');
    menuToggle.setAttribute('aria-expanded', 'false');
    menuToggle.setAttribute('aria-label', 'Open navigation menu');
    void signOut();
  });

  menuToggle.addEventListener('click', () => {
    const isOpen = sidebar.classList.toggle('menu-open');
    menuToggle.setAttribute('aria-expanded', String(isOpen));
    menuToggle.setAttribute('aria-label', isOpen ? 'Close navigation menu' : 'Open navigation menu');
  });

  document.addEventListener('click', (event) => {
    if (sidebar.classList.contains('menu-open') && !sidebar.contains(event.target)) {
      sidebar.classList.remove('menu-open');
      menuToggle.setAttribute('aria-expanded', 'false');
      menuToggle.setAttribute('aria-label', 'Open navigation menu');
    }

    const goButton = event.target.closest('[data-go]');
    if (goButton) showPage(goButton.dataset.go);

    const noticeButton = event.target.closest('[data-notice]');
    if (noticeButton) showToast(noticeButton.dataset.notice);

    if (event.target.closest('[data-print]')) window.print();
  });

  document.querySelectorAll('[data-filter]').forEach((input) => {
    input.addEventListener('input', () => {
      const table = document.getElementById(input.dataset.filter);
      if (!table) return;
      const query = input.value.trim().toLocaleLowerCase();
      table.querySelectorAll('tbody tr').forEach((row) => {
        row.hidden = !row.textContent.toLocaleLowerCase().includes(query);
      });
    });
  });

  const setDashboardNotice = (message) => {
    const notice = document.querySelector('[data-dashboard-notice]');
    if (!notice) return;
    notice.textContent = message;
    notice.hidden = !message;
  };

  const setStudentNotice = (message) => {
    const notice = document.querySelector('[data-student-notice]');
    notice.textContent = message;
    notice.hidden = !message;
  };

  const setClassNotice = (message) => {
    const notice = document.querySelector('[data-class-notice]');
    notice.textContent = message;
    notice.hidden = !message;
  };

  const showDataError = (task, error, target) => {
    console.error(`${task} failed.`, error);
    target(error.message || `Could not ${task.toLocaleLowerCase()}. Please try again.`);
  };

  const refreshDashboard = async (profile, requestId) => {
    const teacherMetric = document.querySelector('[data-metric="teachers"]');
    teacherMetric.closest('.metric-card').hidden = profile.role !== 'administrator';
    const counts = await Promise.all([
      profile.role === 'administrator'
        ? supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_active', true).neq('role', 'administrator')
        : Promise.resolve({ count: null, error: null }),
      supabase.from('classes').select('id', { count: 'exact', head: true }).eq('is_active', true),
      supabase.from('student_subject_results').select('id', { count: 'exact', head: true }).in('status', ['submitted', 'under_review'])
    ]);
    if (requestId !== dataRequest) return;
    const failed = counts.find(({ error }) => error);
    if (failed) {
      setDashboardNotice(`Could not load live dashboard metrics: ${failed.error.message}`);
      console.error('Could not load live dashboard metrics.', failed.error);
      return;
    }
    if (profile.role === 'administrator') teacherMetric.textContent = String(counts[0].count ?? 0);
    document.querySelector('[data-metric="classes"]').textContent = String(counts[1].count ?? 0);
    document.querySelector('[data-metric="pending-results"]').textContent = String(counts[2].count ?? 0);
  };

  const addSelectOption = (select, value, label) => {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    select.append(option);
  };

  const replaceSelectOptions = (select, records, getLabel, selectedId = '') => {
    const previousId = selectedId || select.value;
    select.replaceChildren();
    records.forEach((record) => {
      addSelectOption(select, record.id, getLabel(record));
      const option = select.options[select.options.length - 1];
      const stage = record.stage || record.classes?.stage;
      if (stage) option.dataset.stage = stage;
    });
    if (records.some((record) => record.id === previousId)) select.value = previousId;
  };

  const loadTerms = async (sessionId, select, requestIsCurrent = () => true) => {
    const previousTermId = select.value;
    select.replaceChildren();
    if (!sessionId) return [];
    const { data, error } = await supabase
      .from('terms')
      .select('id, name, term_number, is_active')
      .eq('academic_session_id', sessionId)
      .order('term_number');
    if (!requestIsCurrent()) return [];
    if (error) throw error;
    const terms = data || [];
    const selectedTermId = terms.some((term) => term.id === previousTermId)
      ? previousTermId
      : terms.find((term) => term.is_active)?.id || '';
    replaceSelectOptions(select, terms, (term) => term.name,
      selectedTermId);
    return terms;
  };

  const sortClasses = (classes) => {
    const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });
    const order = (className) => {
      const name = className.trim();
      const patterns = [
        [/^PRE[-\s]?NURSERY(?:\s|$)/i, 0],
        [/^NURSERY\s*(\d+)/i, 1],
        [/^BASIC\s*(\d+)/i, 2],
        [/^JSS\s*(\d+)/i, 3],
        [/^SSS\s*(\d+)/i, 4]
      ];
      for (const [pattern, group] of patterns) {
        const match = name.match(pattern);
        if (match) return [group, Number(match[1] || 0)];
      }
      return [5, 0];
    };
    return [...classes].sort((left, right) => {
      const [leftGroup, leftLevel] = order(left.name);
      const [rightGroup, rightLevel] = order(right.name);
      return leftGroup - rightGroup
        || leftLevel - rightLevel
        || collator.compare(left.name, right.name);
    });
  };

  const copyClassOptions = (select) => {
    const isMasterScope = select === masterClassSelect || select === resultClassSelect;
    const classes = currentProfile?.role === 'administrator'
      && isMasterScope
      ? currentClassesAll
      : isMasterScope && currentProfile?.role !== 'administrator'
        ? currentClassesAll.filter((item) => currentTeacherClassIds.has(item.id))
        : currentClasses;
    replaceSelectOptions(select, sortClasses(classes), (item) => `${item.name}${item.is_active ? '' : ' · Archived'}`);
  };

  const copySessionOptions = (select) => {
    const isMasterScope = select === masterSessionSelect || select === resultSessionSelect;
    const showArchived = currentProfile?.role === 'administrator' && isMasterScope;
    let records = (showArchived
      ? currentSessions
      : currentSessions.filter((item) => item.is_active !== false))
      .filter((item) => item.name !== '2027/2028');
    if (currentProfile?.role !== 'administrator' && select === studentSessionSelect) {
      const classId = studentClassSelect.value;
      const assignedSessionIds = new Set(
        [...currentTeacherClassSessions]
          .filter((key) => key.startsWith(`${classId}:`))
          .map((key) => key.slice(classId.length + 1))
      );
      records = records.filter((item) => assignedSessionIds.has(item.id));
    }
    if (currentProfile?.role !== 'administrator' && select === scoreSessionSelect) {
      const classId = scoreClassSelect.value;
      const assignedSessionIds = new Set(
        currentTeacherSubjectOfferings
          .filter((offering) => offering.class_id === classId)
          .map((offering) => offering.academic_session_id)
      );
      records = records.filter((item) => assignedSessionIds.has(item.id));
    }
    if (isMasterScope && currentProfile?.role !== 'administrator') {
      const classSelect = select === masterSessionSelect ? masterClassSelect : resultClassSelect;
      const classId = classSelect.value;
      records = records.filter((item) => currentTeacherClassSessions.has(`${classId}:${item.id}`));
    }
    const defaultId = records.find((item) => item.name === '2026/2027')?.id
      || records.find((item) => item.is_current)?.id
      || records[0]?.id
      || '';
    replaceSelectOptions(select, records,
      (item) => `${item.name}${item.is_active === false ? ' · Archived' : ''}`,
      defaultId);
  };

  const clearTable = (tableBody, message, columnCount) => {
    tableBody.replaceChildren();
    const row = document.createElement('tr');
    const cell = document.createElement('td');
    cell.colSpan = columnCount;
    cell.className = 'muted-text';
    cell.textContent = message;
    row.append(cell);
    tableBody.append(row);
  };

  const renderSetupList = (container, records, emptyText, renderRecord) => {
    container.replaceChildren();
    if (!records.length) {
      const empty = document.createElement('p');
      empty.className = 'muted-text';
      empty.textContent = emptyText;
      container.append(empty);
      return;
    }
    records.forEach((record) => container.append(renderRecord(record)));
  };

  const sessionRow = (session) => {
    const row = document.createElement('div');
    row.className = 'session-row';
    const details = document.createElement('div');
    const name = document.createElement('strong');
    name.textContent = session.name;
    const dates = document.createElement('small');
    dates.textContent = `${session.starts_on} – ${session.ends_on}`;
    details.append(name, dates);
    const status = document.createElement('span');
    status.className = `badge ${session.is_current ? 'success' : session.is_active === false ? 'muted' : 'info'}`;
    status.textContent = session.is_current ? 'Current' : session.is_active === false ? 'Archived' : 'Active';
    const actions = document.createElement('div');
    actions.className = 'admin-row-actions';
    if (currentProfile?.role === 'administrator') {
      const edit = document.createElement('button');
      edit.className = 'btn-small';
      edit.type = 'button';
      edit.textContent = 'Edit';
      edit.dataset.editSession = session.id;
      const remove = document.createElement('button');
      remove.className = 'btn-small danger-action';
      remove.type = 'button';
      remove.textContent = session.is_active === false ? 'Restore' : 'Delete';
      remove.dataset.removeSession = session.id;
      remove.dataset.active = String(session.is_active !== false);
      actions.append(edit, remove);
    }
    row.append(details, status, actions);
    return row;
  };

  const schoolClassRow = (schoolClass) => {
    const row = document.createElement('div');
    row.className = 'session-row';
    const details = document.createElement('div');
    const name = document.createElement('strong');
    name.textContent = schoolClass.name;
    const stage = document.createElement('small');
    stage.textContent = schoolClass.stage.charAt(0).toLocaleUpperCase() + schoolClass.stage.slice(1);
    details.append(name, stage);
    const status = document.createElement('span');
    status.className = `badge ${schoolClass.is_active ? 'success' : 'muted'}`;
    status.textContent = schoolClass.is_active ? 'Active' : 'Inactive';
    const actions = document.createElement('div');
    actions.className = 'admin-row-actions';
    if (currentProfile?.role === 'administrator') {
      const edit = document.createElement('button');
      edit.className = 'btn-small';
      edit.type = 'button';
      edit.textContent = 'Edit';
      edit.dataset.editClass = schoolClass.id;
      const remove = document.createElement('button');
      remove.className = 'btn-small danger-action';
      remove.type = 'button';
      remove.textContent = schoolClass.is_active ? 'Delete' : 'Restore';
      remove.dataset.removeClass = schoolClass.id;
      remove.dataset.active = String(schoolClass.is_active);
      actions.append(edit, remove);
    }
    row.append(details, status, actions);
    return row;
  };

  const renderClassCards = (schoolClasses, session, enrollmentCounts, container = classCards, classSessions = currentTeacherClassSessionMap) => {
    container?.replaceChildren();
    if (!schoolClasses.length) {
      const empty = document.createElement('p');
      empty.className = 'muted-text';
      empty.textContent = currentProfile?.role === 'administrator'
        ? 'No classes yet. Add one in Sessions & Settings to get started.'
        : 'No classes are assigned to your account yet.';
      container?.append(empty);
      return;
    }
    schoolClasses.forEach((schoolClass) => {
      const card = document.createElement('article');
      card.className = 'panel class-card';
      const icon = document.createElement('span');
      icon.className = 'class-icon';
      icon.textContent = '🏫';
      const name = document.createElement('h3');
      name.textContent = schoolClass.name;
      const details = document.createElement('p');
      const classSession = classSessions.get(schoolClass.id) || session;
      const enrollmentCount = enrollmentCounts?.get(`${schoolClass.id}:${classSession?.id || ''}`)
        ?? enrollmentCounts?.get(schoolClass.id);
      details.textContent = `${enrollmentCount === undefined ? '—' : enrollmentCount} students · ${classSession?.name || 'No academic session'}`;
      card.append(icon, name, details);
      if (container !== dashboardClassCards) {
        const button = document.createElement('button');
        button.className = 'btn-small';
        button.type = 'button';
        button.textContent = 'Open student register';
        button.dataset.classRegister = schoolClass.id;
        button.dataset.sessionId = classSession?.id || '';
        card.append(button);
      }
      container?.append(card);
    });
  };

  const renderClassLoadError = (message) => {
    classCards.replaceChildren();
    const error = document.createElement('p');
    error.className = 'muted-text';
    error.textContent = message;
    classCards.append(error);
  };

  const renderSubjectCards = (offerings) => {
    subjectCards?.replaceChildren();
    if (!subjectCards || !offerings.length) {
      if (subjectCards) {
        const empty = document.createElement('p');
        empty.className = 'muted-text';
        empty.textContent = 'No subjects are assigned to your account yet.';
        subjectCards.append(empty);
      }
      return;
    }
    offerings.forEach((offering) => {
      const card = document.createElement('article');
      card.className = 'panel class-card';
      const icon = document.createElement('span');
      icon.className = 'class-icon';
      icon.textContent = '📖';
      const name = document.createElement('h3');
      name.textContent = offering.subjects?.name || 'Subject';
      const details = document.createElement('p');
      details.textContent = `${offering.classes?.name || 'Class'} · ${offering.academic_sessions?.name || 'Session'} · ${offering.terms?.name || 'Term'}`;
      const button = document.createElement('button');
      button.className = 'btn-small';
      button.type = 'button';
      button.textContent = 'Enter scores';
      button.dataset.subjectOffering = offering.id;
      card.append(icon, name, details, button);
      subjectCards.append(card);
    });
  };

  const applyStudentFilter = () => {
    const search = document.querySelector('[data-filter="students-table"]');
    const query = search.value.trim().toLocaleLowerCase();
    studentTableBody.querySelectorAll('tr[data-student-row]').forEach((row) => {
      row.hidden = !row.textContent.toLocaleLowerCase().includes(query);
    });
  };

  const renderStudents = (students) => {
    currentStudents = students;
    studentTableBody.replaceChildren();
    if (!students.length) {
      const row = document.createElement('tr');
      const cell = document.createElement('td');
      cell.colSpan = 7;
      cell.textContent = 'No students are enrolled in this class for the selected session yet.';
      row.append(cell);
      studentTableBody.append(row);
    } else {
      students.forEach(({ enrolled_on: enrolledOn, left_on: leftOn, students: student }, index) => {
        if (!student) return;
        const row = document.createElement('tr');
        row.dataset.studentRow = '';
        const fullName = [student.first_name, student.other_names, student.last_name].filter(Boolean).join(' ');
        const serialCell = document.createElement('td');
        serialCell.textContent = String(index + 1);
        const nameCell = document.createElement('td');
        const person = document.createElement('span');
        person.className = 'person-cell';
        const avatar = document.createElement('span');
        avatar.className = 'mini-avatar';
        avatar.textContent = fullName.split(/\s+/).slice(0, 2).map((part) => part.charAt(0)).join('').toLocaleUpperCase();
        person.append(avatar, document.createTextNode(fullName));
        nameCell.append(person);
        const admissionCell = document.createElement('td');
        admissionCell.textContent = student.admission_number;
        const genderCell = document.createElement('td');
        genderCell.textContent = student.gender
          ? student.gender.charAt(0).toLocaleUpperCase() + student.gender.slice(1)
          : '—';
        const enrolledCell = document.createElement('td');
        enrolledCell.textContent = enrolledOn ? new Date(`${enrolledOn}T00:00:00`).toLocaleDateString() : '—';
        const statusCell = document.createElement('td');
        const status = document.createElement('span');
        status.className = `badge ${student.is_active && !leftOn ? 'success' : 'muted'}`;
        status.textContent = student.is_active && !leftOn ? 'Active' : 'Inactive';
        statusCell.append(status);
        const actionsCell = document.createElement('td');
        const editButton = document.createElement('button');
        editButton.type = 'button';
        editButton.className = 'btn-small';
        editButton.textContent = 'Edit';
        editButton.dataset.editStudent = student.id;
        editButton.disabled = currentProfile?.role !== 'administrator' && !studentRegisterCanManage;
        const deleteButton = document.createElement('button');
        deleteButton.type = 'button';
        deleteButton.className = 'btn-small danger-action';
        deleteButton.textContent = 'Delete';
        deleteButton.dataset.deleteStudent = student.id;
        deleteButton.disabled = currentProfile?.role !== 'administrator' && !studentRegisterCanManage;
        deleteButton.setAttribute('aria-label', `Permanently delete ${fullName}`);
        actionsCell.append(editButton, deleteButton);
        row.append(serialCell, nameCell, admissionCell, genderCell, enrolledCell, statusCell, actionsCell);
        studentTableBody.append(row);
      });
    }
    document.querySelector('[data-student-count]').textContent =
      `${students.length} student${students.length === 1 ? '' : 's'} in this class`;
    applyStudentFilter();
  };

  const hydrateEnrollmentStudents = async (enrollments) => {
    const missingIds = [...new Set(
      enrollments.filter((enrollment) => !enrollment.students).map((enrollment) => enrollment.student_id)
    )];
    if (!missingIds.length) return enrollments;
    const { data: students, error } = await supabase
      .from('students')
      .select('id, admission_number, first_name, last_name, other_names, gender, is_active')
      .in('id', missingIds);
    if (error) throw error;
    const studentsById = new Map((students || []).map((student) => [student.id, student]));
    return enrollments.map((enrollment) => ({
      ...enrollment,
      students: enrollment.students || studentsById.get(enrollment.student_id) || null
    }));
  };

  const loadStudentRows = async (requestId = dataRequest) => {
    const classId = studentClassSelect.value;
    const sessionId = studentSessionSelect.value;
    if (!classId || !sessionId) {
      currentStudents = [];
      studentRegisterCanManage = false;
      renderStudents([]);
      setStudentNotice('Create an academic session and class before loading or registering students.');
      return;
    }
    setStudentNotice('');
    studentRegisterCanManage = currentProfile?.role === 'administrator';
    if (!studentRegisterCanManage) {
      const { data: canManage, error: permissionError } = await supabase.rpc('can_manage_class_register', {
        p_class_id: classId,
        p_academic_session_id: sessionId
      });
      if (permissionError) throw permissionError;
      studentRegisterCanManage = Boolean(canManage);
    }
    document.querySelector('[data-student-count]').textContent = 'Loading students…';
    try {
      const { data, error } = await supabase
        .from('class_enrollments')
        .select('enrolled_on, left_on, students (id, admission_number, first_name, last_name, other_names, gender, date_of_birth, is_active)')
        .eq('class_id', classId)
        .eq('academic_session_id', sessionId)
        .order('enrolled_on');
      if (requestId !== dataRequest) return;
      if (error) {
        showDataError('Loading the student register', error, setStudentNotice);
        document.querySelector('[data-student-count]').textContent = 'Student register unavailable';
        return;
      }
      renderStudents(await hydrateEnrollmentStudents(data || []));
      const selectedClass = studentClassSelect.selectedOptions[0]?.textContent;
      const selectedSession = studentSessionSelect.selectedOptions[0]?.textContent;
      document.querySelector('[data-student-context]').textContent =
        `${selectedClass || 'Class'} · ${selectedSession || 'Academic session'}`;
    } catch (error) {
      if (requestId !== dataRequest) return;
      showDataError('Loading the student register', error, setStudentNotice);
      document.querySelector('[data-student-count]').textContent = 'Student register unavailable';
    }
  };

  const setScreenNotice = (selector, message) => {
    const notice = document.querySelector(selector);
    notice.textContent = message;
    notice.hidden = !message;
  };

  const scoreCell = (text) => {
    const cell = document.createElement('td');
    cell.textContent = text;
    return cell;
  };

  const subjectClassRange = (classNames) => {
    const names = classNames.map((name) => name.trim().toUpperCase());
    const groups = [
      ['JSS', [1, 2, 3], 'JSS 1 - 3'],
      ['SSS', [1, 2, 3], 'SSS 1 - 3'],
      ['BASIC', [1, 2, 3], 'Basic 1 - 3'],
      ['BASIC', [4, 5, 6], 'Basic 4 - 6'],
      ['NURSERY', [1, 2, 3], 'Nursery 1 - 3']
    ];
    for (const [prefix, levels, label] of groups) {
      const found = new Set(
        names
          .map((name) => name.match(new RegExp(`^${prefix}\\s*([1-6])$`))?.[1])
          .filter(Boolean)
          .map(Number)
      );
      if (levels.every((level) => found.has(level))) return label;
    }
    if (names.some((name) => /PRE[-\s]?NURSERY/.test(name))) return 'Pre-nursery';
    return [...new Set(classNames)].sort().join(', ');
  };

  const subjectClassGroupKey = (className) => {
    const name = className.trim().toUpperCase();
    if (/^JSS\s*[1-3]$/.test(name)) return 'junior_secondary';
    if (/^SSS\s*[1-3]$/.test(name)) return 'senior_secondary';
    if (/^BASIC\s*[1-3]$/.test(name)) return 'lower_basic';
    if (/^BASIC\s*[4-6]$/.test(name)) return 'upper_basic';
    if (/^NURSERY\s*[1-3]$/.test(name)) return 'nursery';
    if (/^PRE[-\s]?NURSERY$/.test(name)) return 'pre_nursery';
    return name;
  };

  const createGradingBandRow = (band = {}) => {
    const row = document.createElement('tr');
    [
      ['grade', band.grade || '', 'Grade label'],
      ['minimum_score', band.minimum_score ?? '', 'Minimum score'],
      ['maximum_score', band.maximum_score ?? '', 'Maximum score'],
      ['remark', band.remark || '', 'Remark']
    ].forEach(([name, value, label]) => {
      const cell = document.createElement('td');
      const input = document.createElement('input');
      input.name = name;
      input.type = name.includes('score') ? 'number' : 'text';
      if (name.includes('score')) {
        input.min = '0';
        input.step = '0.01';
      } else {
        input.maxLength = name === 'grade' ? 12 : 120;
      }
      input.value = value;
      input.setAttribute('aria-label', label);
      cell.append(input);
      row.append(cell);
    });
    const actions = document.createElement('td');
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn-small danger-action';
    remove.textContent = 'Remove';
    remove.dataset.removeGrade = '';
    actions.append(remove);
    row.append(actions);
    return row;
  };

  const scoreGrade = (score, gradingBands) =>
    gradingBands.find((band) => score >= Number(band.minimum_score) && score <= Number(band.maximum_score))?.grade || '—';

  const updateScoreRowSummary = (row) => {
    const enteredScores = [...row.querySelectorAll('[data-score-component]')]
      .filter((input) => input.value !== '')
      .map((input) => ({ input, score: Number(input.value) }));
    const invalid = enteredScores.find(({ input, score }) =>
      !Number.isFinite(score) || score < 0 || score > Number(input.max));
    const total = enteredScores.reduce((sum, { input, score }) =>
      sum + (input.dataset.countsTowardTotal === 'true' ? score : 0), 0);
    const maxTotal = currentScoreComponents
      .filter((component) => component.counts_toward_total)
      .reduce((sum, component) => sum + Number(component.max_score), 0);
    row.querySelector('[data-score-total]').textContent = invalid ? 'Invalid' : String(total);
    row.querySelector('[data-score-grade]').textContent =
      invalid || enteredScores.length !== currentScoreComponents.length || maxTotal === 0
        ? '—'
        : scoreGrade(total / maxTotal * 100, currentScoreRows.gradingBands || []);
    if (invalid) invalid.input.setAttribute('aria-invalid', 'true');
    enteredScores.filter(({ input }) => input !== invalid?.input)
      .forEach(({ input }) => input.setAttribute('aria-invalid', 'false'));
    return !invalid;
  };

  const renderScoreTable = (enrollments, existingResults, components, gradingBands) => {
    currentScoreRows = enrollments
      .filter(({ left_on: leftOn, students: student }) => !leftOn && student)
      .map((enrollment) => ({
        student: enrollment.students,
        result: existingResults.find((result) => result.student_id === enrollment.student_id) || null
      }));
    currentScoreRows.gradingBands = gradingBands;
    currentScoreComponents = components;
    scoreHead.replaceChildren();
    scoreBody.replaceChildren();
    const header = document.createElement('tr');
    ['#', 'Student'].forEach((label) => header.append(scoreCell(label)));
    components.forEach((component) => {
      const cell = scoreCell(`${component.name} / ${component.max_score}`);
      header.append(cell);
    });
    ['Total', 'Grade', 'Status', 'Actions'].forEach((label) => header.append(scoreCell(label)));
    scoreHead.append(header);

    if (!currentScoreRows.length) {
      const message = currentProfile?.role === 'administrator'
        ? 'No active students are enrolled in this class for the selected session.'
        : 'No students have been uploaded for this class yet. Ask the class teacher or administrator to upload the student register before entering scores.';
      clearTable(scoreBody, message, components.length + 6);
      return;
    }

    currentScoreRows.forEach(({ student, result }, index) => {
      const row = document.createElement('tr');
      row.dataset.studentId = student.id;
      if (result) row.dataset.resultId = result.id;
      row.append(scoreCell(String(index + 1)));
      row.append(scoreCell([student.first_name, student.other_names, student.last_name].filter(Boolean).join(' ')));
      components.forEach((component) => {
        const cell = document.createElement('td');
        const input = document.createElement('input');
        input.className = 'score-input';
        input.type = 'number';
        input.min = '0';
        input.max = String(component.max_score);
        input.step = '0.01';
        input.dataset.scoreComponent = component.id;
        input.dataset.countsTowardTotal = String(component.counts_toward_total);
        const savedScore = result?.result_component_scores?.find((saved) => {
          if (saved.assessment_component_id === component.id) return true;
          const savedComponent = result.assessment_schemes?.assessment_components
            ?.find((item) => item.id === saved.assessment_component_id);
          return savedComponent?.code === component.code;
        });
        input.value = savedScore?.score ?? '';
        input.dataset.savedValue = input.value;
        input.disabled = Boolean(result && result.status !== 'draft');
        if (result?.status === 'draft') input.disabled = true;
        input.setAttribute('aria-label', `${student.first_name} ${student.last_name} ${component.name} score`);
        cell.append(input);
        row.append(cell);
      });
      const total = document.createElement('td');
      total.dataset.scoreTotal = '';
      const grade = document.createElement('td');
      grade.dataset.scoreGrade = '';
      const status = document.createElement('td');
      const statusBadge = document.createElement('span');
      statusBadge.className = `badge ${result?.status === 'draft' || !result ? 'warning' : 'success'}`;
      statusBadge.textContent = result?.status?.replaceAll('_', ' ') || 'Not started';
      status.append(statusBadge);
      const actions = document.createElement('td');
      if (result?.status === 'draft') {
        const editButton = document.createElement('button');
        editButton.className = 'btn-small';
        editButton.type = 'button';
        editButton.dataset.editScoreRow = '';
        editButton.textContent = 'Edit';
        editButton.setAttribute('aria-label', `Edit draft scores for ${student.first_name} ${student.last_name}`);
        actions.append(editButton);
      } else if (result?.status === 'submitted' && currentProfile?.role === 'administrator') {
        const reopenButton = document.createElement('button');
        reopenButton.className = 'btn-small';
        reopenButton.type = 'button';
        reopenButton.dataset.reopenSubmittedResult = '';
        reopenButton.textContent = 'Reopen';
        reopenButton.setAttribute('aria-label', `Reopen submitted result for ${student.first_name} ${student.last_name}`);
        actions.append(reopenButton);
      }
      if (result) {
        const deleteButton = document.createElement('button');
        deleteButton.className = 'btn-small danger-action';
        deleteButton.type = 'button';
        deleteButton.dataset.deleteScoreResult = '';
        deleteButton.textContent = 'Delete';
        deleteButton.setAttribute('aria-label', `Delete ${result.status.replaceAll('_', ' ')} result for ${student.first_name} ${student.last_name}`);
        if (currentProfile?.role !== 'administrator' && result.status !== 'draft') {
          deleteButton.disabled = true;
          deleteButton.title = 'Only administrators can delete results after submission.';
        }
        actions.append(deleteButton);
      }
      row.append(total, grade, status, actions);
      scoreBody.append(row);
      updateScoreRowSummary(row);
    });
  };

  const loadScoreScreen = async () => {
    const requestId = ++scoreRequestId;
    if (pendingScoreClassId) scoreClassSelect.value = pendingScoreClassId;
    if (pendingScoreSessionId) scoreSessionSelect.value = pendingScoreSessionId;
    const classId = scoreClassSelect.value;
    const sessionId = scoreSessionSelect.value;
    const teacherScoreContext = currentProfile?.role !== 'administrator';
    scoreClassSelect.disabled = teacherScoreContext;
    scoreSessionSelect.disabled = teacherScoreContext;
    scoreSubjectSelect.disabled = teacherScoreContext;
    const scoreTermLabel = scoreTermSelect.closest('label');
    if (scoreTermLabel) scoreTermLabel.hidden = teacherScoreContext;
    scoreTermSelect.disabled = teacherScoreContext;
    if (!classId || !sessionId) {
      currentScoreOffering = null;
      currentScoreRows = [];
      clearTable(scoreBody, 'Create or assign a class and academic session before entering scores.', 9);
      setScreenNotice('[data-scores-notice]', 'Scores are loaded from Supabase; setup is needed before this screen can be used.');
      return;
    }

    try {
      await loadTerms(sessionId, scoreTermSelect, () => requestId === scoreRequestId);
      if (requestId !== scoreRequestId) return;
      const { data: offerings, error: offeringError } = await supabase
        .from('class_subject_offerings')
        .select('id, class_id, academic_session_id, subject_id, subjects (id, name), classes (stage), assessment_schemes (id, name, is_current, assessment_components (id, code, name, max_score, display_order, is_required, counts_toward_total))')
        .eq('class_id', classId)
        .eq('academic_session_id', sessionId)
        .eq('is_active', true);
      if (requestId !== scoreRequestId) return;
      if (offeringError) throw offeringError;
      const offeringRecords = (offerings || []).filter((item) =>
        currentProfile?.role === 'administrator'
        || currentTeacherSubjectOfferingIds.has(item.id)
      ).map((item) => ({
        ...item,
        currentScheme: item.assessment_schemes?.find((scheme) => scheme.is_current)
      }));
      const configuredOfferings = offeringRecords.filter((item) =>
        item.currentScheme?.assessment_components?.length);
      const stage = offerings?.[0]?.classes?.stage
        || currentClassesAll.find((item) => item.id === classId)?.stage;
      if (!stage) throw new Error('Could not determine the selected class section.');
      const { data: sectionSettings, error: sectionSettingsError } = await supabase
        .from('section_assessment_settings')
        .select('stage')
        .eq('stage', stage)
        .maybeSingle();
      if (requestId !== scoreRequestId) return;
      if (sectionSettingsError) throw sectionSettingsError;
      const oldSubjectId = scoreSubjectSelect.value;
      scoreSubjectSelect.replaceChildren();
      configuredOfferings.forEach((item) => addSelectOption(scoreSubjectSelect, item.id, item.subjects?.name || 'Subject'));
      const selectedSubjectId = pendingScoreOfferingId || oldSubjectId;
      if (configuredOfferings.some((item) => item.id === selectedSubjectId)) scoreSubjectSelect.value = selectedSubjectId;
      currentScoreOffering = configuredOfferings.find((item) => item.id === scoreSubjectSelect.value) || configuredOfferings[0] || null;
      if (currentScoreOffering && !scoreSubjectSelect.value) scoreSubjectSelect.value = currentScoreOffering.id;
      if (teacherScoreContext) {
        const assignedTerm = currentTeacherSubjectOfferings.find((item) => item.id === currentScoreOffering?.id)?.term_id;
        const defaultTermId = pendingScoreTermId || assignedTerm || scoreTermSelect.value;
        if (defaultTermId && [...scoreTermSelect.options].some((option) => option.value === defaultTermId)) {
          scoreTermSelect.value = defaultTermId;
        }
      }
      pendingScoreOfferingId = '';
      pendingScoreTermId = '';

      if (!sectionSettings) {
        currentScoreOffering = null;
        currentScoreComponents = [];
        currentScoreRows = [];
        clearTable(scoreBody, 'The administrator needs to configure the shared assessment scheme for this section.', 9);
        document.querySelector('[data-score-scheme]').textContent = 'Section assessment setup required';
        setScreenNotice('[data-scores-notice]', 'Assessment is configured once per school section in Sessions & Settings.');
        return;
      }

      if (!currentScoreOffering || !scoreTermSelect.value) {
        currentScoreComponents = [];
        currentScoreRows = [];
        clearTable(scoreBody, !currentScoreOffering
          ? 'No current assessment scheme is configured for this subject. Check the shared section settings.'
          : 'No academic terms are configured for this session.', 9);
        document.querySelector('[data-score-scheme]').textContent = 'Assessment setup required';
        setScreenNotice('[data-scores-notice]', 'An administrator must set the shared assessment scheme for this section before scores can be entered.');
        return;
      }

      currentScoreComponents = currentScoreOffering.currentScheme.assessment_components
        .sort((a, b) => a.display_order - b.display_order);
      const [enrollmentResult, resultsResult, gradingResult] = await Promise.all([
        supabase.from('class_enrollments')
          .select('student_id, left_on, students (id, first_name, last_name, other_names, is_active)')
          .eq('class_id', classId)
          .eq('academic_session_id', sessionId)
          .order('enrolled_on'),
        supabase.from('student_subject_results')
          .select('id, student_id, status, assessment_scheme_id, assessment_schemes (assessment_components (id, code)), result_component_scores (assessment_component_id, score)')
          .eq('class_subject_offering_id', currentScoreOffering.id)
          .eq('term_id', scoreTermSelect.value),
        supabase.from('grading_bands')
          .select('grade, minimum_score, maximum_score, grading_scales!inner (is_active)')
          .eq('grading_scales.is_active', true)
      ]);
      if (requestId !== scoreRequestId) return;
      const failed = enrollmentResult.error || resultsResult.error || gradingResult.error;
      if (failed) throw failed;
      const gradingBands = (gradingResult.data || []).sort((a, b) =>
        Number(a.minimum_score) - Number(b.minimum_score));
      renderScoreTable(
        await hydrateEnrollmentStudents(enrollmentResult.data || []),
        resultsResult.data || [],
        currentScoreComponents,
        gradingBands
      );
      const maximum = currentScoreComponents.filter((item) => item.counts_toward_total)
        .reduce((sum, item) => sum + Number(item.max_score), 0);
      document.querySelector('[data-score-scheme]').textContent =
        `${currentScoreOffering.subjects?.name} · ${currentScoreOffering.currentScheme.name} · Maximum ${maximum}`;
      setScreenNotice('[data-scores-notice]', '');
    } catch (error) {
      if (requestId !== scoreRequestId) return;
      showDataError('Loading score-entry data', error, (message) => setScreenNotice('[data-scores-notice]', message));
      clearTable(scoreBody, 'Could not load score-entry data.', 9);
    }
  };

  const scoreInputsForRow = (row) => [...row.querySelectorAll('[data-score-component]')];

  const requestScoreActionReason = ({ title, description, submitLabel, destructive = false }) => {
    if (scoreActionDialog.open) return Promise.resolve(null);
    document.querySelector('#score-action-title').textContent = title;
    document.querySelector('[data-score-action-description]').textContent = description;
    document.querySelector('[data-score-action-submit]').textContent = submitLabel;
    document.querySelector('[data-score-action-submit]').classList.toggle('danger-action', destructive);
    scoreActionReason.value = '';
    scoreActionMessage.textContent = '';
    scoreActionDialog.showModal();
    scoreActionReason.focus();
    return new Promise((resolve) => {
      resolveScoreAction = resolve;
    });
  };

  scoreActionForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const reason = scoreActionReason.value.trim();
    if (reason.length < 10) {
      scoreActionMessage.textContent = 'Enter a reason of at least 10 characters.';
      scoreActionReason.focus();
      return;
    }
    scoreActionDialog.close('confirm');
  });
  scoreActionDialog.addEventListener('close', () => {
    const resolve = resolveScoreAction;
    resolveScoreAction = undefined;
    resolve?.(scoreActionDialog.returnValue === 'confirm' ? scoreActionReason.value.trim() : null);
  });
  document.querySelectorAll('[data-cancel-score-action]').forEach((button) => {
    button.addEventListener('click', () => scoreActionDialog.close('cancel'));
  });

  document.querySelector('[data-score-body]').addEventListener('input', (event) => {
    if (event.target.matches('[data-score-component]')) updateScoreRowSummary(event.target.closest('tr'));
  });
  scoreBody.addEventListener('click', async (event) => {
    const editButton = event.target.closest('[data-edit-score-row]');
    if (editButton) {
      const row = editButton.closest('tr[data-student-id]');
      if (!row) return;

      if (row.dataset.editing === 'true') {
        scoreInputsForRow(row).forEach((input) => {
          input.value = input.dataset.savedValue || '';
          input.disabled = true;
          input.removeAttribute('aria-invalid');
        });
        delete row.dataset.editing;
        editButton.textContent = 'Edit';
        updateScoreRowSummary(row);
        return;
      }

      row.dataset.editing = 'true';
      scoreInputsForRow(row).forEach((input) => { input.disabled = false; });
      editButton.textContent = 'Cancel';
      return;
    }

    const deleteButton = event.target.closest('[data-delete-score-result]');
    if (deleteButton) {
      const row = deleteButton.closest('tr[data-student-id][data-result-id]');
      if (!row || deleteButton.disabled || !currentScoreOffering) return;

      const studentName = row.children[1].textContent.trim();
      const context = {
        resultId: row.dataset.resultId,
        classId: scoreClassSelect.value,
        sessionId: scoreSessionSelect.value,
        offeringId: currentScoreOffering.id,
        termId: scoreTermSelect.value
      };
      const reason = await requestScoreActionReason({
        title: `Delete ${studentName}'s result?`,
        description: `Permanently delete the ${row.querySelector('.badge')?.textContent || ''} result for ${currentScoreOffering.subjects?.name || 'this subject'}. This cannot be undone.`,
        submitLabel: 'Delete result',
        destructive: true
      });
      if (reason === null) return;

      deleteButton.disabled = true;
      deleteButton.textContent = 'Deleting…';
      const message = document.querySelector('[data-score-message]');
      message.textContent = 'Deleting result…';
      try {
        const { error } = await supabase.rpc('delete_student_subject_result', {
          p_result_id: context.resultId,
          p_class_id: context.classId,
          p_academic_session_id: context.sessionId,
          p_class_subject_offering_id: context.offeringId,
          p_term_id: context.termId,
          p_reason: reason.trim()
        });
        if (error) throw error;

        await loadScoreScreen();
        message.textContent = `Deleted ${studentName}'s result. The action was recorded in the audit log.`;
        void refreshDashboard(currentProfile, dataRequest);
      } catch (error) {
        console.error('Deleting a student result failed.', error);
        message.textContent = error.message || 'Could not delete the student result.';
        deleteButton.disabled = false;
        deleteButton.textContent = 'Delete';
      }
      return;
    }

    const reopenButton = event.target.closest('[data-reopen-submitted-result]');
    if (!reopenButton || currentProfile?.role !== 'administrator') return;
    const row = reopenButton.closest('tr[data-student-id]');
    if (!row?.dataset.resultId) return;
    const reason = await requestScoreActionReason({
      title: 'Reopen result for correction?',
      description: `Reopen ${row.children[1].textContent.trim()}'s submitted result. It will return to draft so its scores can be corrected.`,
      submitLabel: 'Reopen result'
    });
    if (reason === null) return;

    reopenButton.disabled = true;
    const message = document.querySelector('[data-score-message]');
    message.textContent = 'Reopening result for correction…';
    try {
      const { error } = await supabase.rpc('reopen_submitted_result', {
        p_result_id: row.dataset.resultId,
        p_reason: reason
      });
      if (error) throw error;
    } catch (error) {
      console.error('Reopening a submitted result failed.', error);
      message.textContent = error.message || 'Could not reopen the submitted result.';
      reopenButton.disabled = false;
      return;
    }

    await loadScoreScreen();
    message.textContent = 'Result reopened as a draft. Edit the scores and save or resubmit when ready.';
  });
  [scoreClassSelect, scoreSessionSelect, scoreTermSelect, scoreSubjectSelect].forEach((select) => {
    select.addEventListener('change', () => {
      if (select === scoreClassSelect) copySessionOptions(scoreSessionSelect);
      void loadScoreScreen();
    });
  });

  const saveDraftScores = async () => {
    if (!currentScoreOffering || !scoreTermSelect.value) {
      setScreenNotice('[data-scores-notice]', 'Choose a configured subject and term before saving scores.');
      return;
    }
    const button = document.querySelector('[data-save-scores]');
    const message = document.querySelector('[data-score-message]');
    button.disabled = true;
    message.textContent = 'Saving draft scores…';
    const failures = [];
    let savedCount = 0;
    try {
      for (const row of [...scoreBody.querySelectorAll('tr[data-student-id]')]) {
        if (row.dataset.resultId && row.dataset.editing !== 'true') continue;
        const inputs = scoreInputsForRow(row);
        if (inputs.some((input) => input.getAttribute('aria-invalid') === 'true')) {
          failures.push('Correct scores that exceed their assessment maximums.');
          continue;
        }
        const scores = inputs.filter((input) => input.value !== '').map((input) => ({
          assessment_component_id: input.dataset.scoreComponent,
          score: Number(input.value)
        }));
        if (!scores.length) continue;
        const { error } = await supabase.rpc('save_result_scores', {
          p_student_id: row.dataset.studentId,
          p_class_id: scoreClassSelect.value,
          p_academic_session_id: scoreSessionSelect.value,
          p_class_subject_offering_id: currentScoreOffering.id,
          p_assessment_scheme_id: currentScoreOffering.currentScheme.id,
          p_term_id: scoreTermSelect.value,
          p_scores: scores
        });
        if (error) {
          console.error('Saving draft scores failed for a student.', error);
          failures.push(`${row.children[1].textContent}: ${error.message}`);
        } else {
          savedCount += 1;
        }
      }
      await loadScoreScreen();
      message.textContent = failures.length
        ? `${savedCount} student draft(s) saved. ${failures.join(' ')}`
        : `${savedCount} student draft(s) saved to Supabase.`;
    } catch (error) {
      showDataError('Saving draft scores', error, (text) => { message.textContent = text; });
    } finally {
      button.disabled = false;
    }
  };

  document.querySelector('[data-save-scores]').addEventListener('click', () => void saveDraftScores());
  document.querySelector('[data-submit-scores]').addEventListener('click', async () => {
    const message = document.querySelector('[data-score-message]');
    const submitButton = document.querySelector('[data-submit-scores]');
    const draftIds = currentScoreRows
      .filter(({ result }) => result?.status === 'draft')
      .map(({ result }) => result.id);
    if (!draftIds.length) {
      message.textContent = 'Save at least one draft before submitting results.';
      return;
    }
    submitButton.disabled = true;
    message.textContent = 'Submitting complete results…';
    const outcomes = await Promise.all(draftIds.map((id) => supabase.rpc('submit_result', { p_result_id: id })));
    const errors = outcomes.filter((item) => item.error);
    errors.forEach(({ error }) => console.error('Submitting a result failed.', error));
    message.textContent = errors.length
      ? `${draftIds.length - errors.length} result(s) submitted. ${errors.map(({ error }) => error.message).join(' ')}`
      : `${draftIds.length} result(s) submitted successfully.`;
    submitButton.disabled = false;
    await loadScoreScreen();
    void refreshDashboard(currentProfile, dataRequest);
  });

  const renderMasterSheet = (standings, offerings, calculationsByStudentSubject, stage) => {
    const head = document.querySelector('[data-master-head]');
    const body = document.querySelector('[data-master-body]');
    const statisticBar = document.querySelector('[data-master-statistics]');
    head.replaceChildren();
    body.replaceChildren();

    const header = document.createElement('tr');
    ['#', 'Student'].forEach((label) => {
      const cell = document.createElement('th');
      cell.textContent = label;
      header.append(cell);
    });
    offerings.forEach((offering) => {
      const cell = document.createElement('th');
      cell.textContent = offering.subjects?.name || 'Subject';
      header.append(cell);
    });
    ['Grand total', 'Average', 'Position', 'Status'].forEach((label) => {
      const cell = document.createElement('th');
      cell.textContent = label;
      header.append(cell);
    });
    head.append(header);

    if (!standings.length) {
      clearTable(body, 'No students or results are available for this class, session, and term.', offerings.length + 6);
      statisticBar.replaceChildren();
      return;
    }

    standings.forEach((standing, index) => {
      const row = document.createElement('tr');
      const cells = [
        String(index + 1),
        standing.student_name || standing.admission_number || 'Student'
      ];
      const studentSubjectResults = calculationsByStudentSubject.get(standing.student_id) || new Map();
      offerings.forEach((offering) => {
        const calculation = studentSubjectResults.get(offering.id);
        const componentCount = Object.keys(calculation?.component_scores || {}).length;
        const subjectAverage = ['primary', 'nursery'].includes(stage) && componentCount
          ? Number(calculation.subject_total) / componentCount
          : calculation?.subject_total;
        cells.push(calculation?.is_complete && calculation.subject_total !== null
          ? `${['primary', 'nursery'].includes(stage) ? subjectAverage.toFixed(1) : subjectAverage}${calculation.grade ? ` (${calculation.grade})` : ''}`
          : '—');
      });
      cells.push(
        standing.grand_total ?? '—',
        standing.average_score === null ? '—' : Number(standing.average_score).toFixed(1),
        standing.position ?? '—',
        standing.is_complete ? 'Complete' : 'Incomplete'
      );
      cells.forEach((value) => row.append(scoreCell(String(value))));
      body.append(row);
    });

    const averages = standings.map((item) => Number(item.average_score)).filter(Number.isFinite);
    const statistics = [
      `Students: ${standings.length}`,
      `Complete results: ${standings.filter((item) => item.is_complete).length}`,
      `Class average: ${averages.length ? (averages.reduce((sum, value) => sum + value, 0) / averages.length).toFixed(1) : '—'}`
    ];
    statisticBar.replaceChildren();
    statistics.forEach((text) => {
      const item = document.createElement('span');
      item.textContent = text;
      statisticBar.append(item);
    });
  };

  const loadMasterSheet = async () => {
    const requestId = ++masterRequestId;
    const classId = masterClassSelect.value;
    const sessionId = masterSessionSelect.value;
    if (!classId || !sessionId) {
      document.querySelector('[data-master-head]').replaceChildren();
      clearTable(document.querySelector('[data-master-body]'), 'Create or assign a class and academic session to view the master sheet.', 6);
      document.querySelector('[data-master-statistics]').replaceChildren();
      document.querySelector('[data-master-context]').textContent = 'Select a class, session, and term.';
      document.querySelector('[data-master-heading]').textContent = 'LIVE CLASS PERFORMANCE';
      document.querySelector('[data-master-status]').textContent = 'Live data';
      document.querySelector('[data-master-status]').className = 'badge info';
      setScreenNotice('[data-master-notice]', 'Master sheets are loaded from Supabase; no class/session is available yet.');
      return;
    }
    try {
      await loadTerms(sessionId, masterTermSelect, () => requestId === masterRequestId);
      if (requestId !== masterRequestId) return;
      const termId = masterTermSelect.value;
      if (!termId) {
        document.querySelector('[data-master-head]').replaceChildren();
        clearTable(document.querySelector('[data-master-body]'), 'No terms are configured for this academic session.', 6);
        document.querySelector('[data-master-statistics]').replaceChildren();
        setScreenNotice('[data-master-notice]', 'No terms are configured for this academic session.');
        return;
      }
      const [{ data: offerings, error: offeringError }, standingsResult] = await Promise.all([
        supabase.from('class_subject_offerings')
          .select('id, subject_id, is_active, subjects (name)')
          .eq('class_id', classId)
          .eq('academic_session_id', sessionId)
          .order('created_at'),
        supabase.rpc('get_class_standings', {
          p_class_id: classId,
          p_academic_session_id: sessionId,
          p_term_id: termId
        })
      ]);
      if (requestId !== masterRequestId) return;
      if (offeringError) throw offeringError;
      if (standingsResult.error) throw standingsResult.error;
      const standings = standingsResult.data || [];
      const { data: results, error: resultsError } = await supabase
        .from('student_subject_results')
        .select('id, student_id, class_subject_offering_id, status')
        .eq('class_id', classId)
        .eq('academic_session_id', sessionId)
        .eq('term_id', termId);
      if (requestId !== masterRequestId) return;
      if (resultsError) throw resultsError;
      const historicalOfferingIds = new Set((results || []).map((result) => result.class_subject_offering_id));
      const visibleOfferings = (offerings || []).filter((offering) =>
        offering.is_active || historicalOfferingIds.has(offering.id));
      const calculations = await Promise.all((results || []).map(async (result) => {
        const { data, error } = await supabase.rpc('get_result_calculation', { p_result_id: result.id });
        if (error) throw error;
        return { result, calculation: data?.[0] || null };
      }));
      if (requestId !== masterRequestId) return;
      const byStudent = new Map();
      calculations.forEach(({ result, calculation }) => {
        if (!calculation) return;
        if (!byStudent.has(result.student_id)) byStudent.set(result.student_id, new Map());
        byStudent.get(result.student_id).set(result.class_subject_offering_id, calculation);
      });
      const schoolClass = currentClassesAll.find((item) => item.id === classId);
      renderMasterSheet(standings, visibleOfferings, byStudent, schoolClass?.stage);
      const session = currentSessions.find((item) => item.id === sessionId);
      const term = masterTermSelect.selectedOptions[0]?.textContent || '';
      document.querySelector('[data-master-context]').textContent =
        `${schoolClass?.name || 'Class'} · ${term} · ${session?.name || 'Session'}`;
      document.querySelector('[data-master-heading]').textContent =
        `${schoolClass?.name || 'Class'} · ${term.toLocaleUpperCase()} · ${session?.name || ''}`;
      const complete = standings.length > 0 && standings.every((item) => item.is_complete);
      const badge = document.querySelector('[data-master-status]');
      badge.textContent = complete ? 'Complete results' : 'Results in progress';
      badge.className = `badge ${complete ? 'success' : 'warning'}`;
      setScreenNotice('[data-master-notice]', visibleOfferings.length
        ? ''
        : 'No subjects are configured for this class and session yet.');
    } catch (error) {
      if (requestId !== masterRequestId) return;
      showDataError('Loading the master sheet', error, (message) => setScreenNotice('[data-master-notice]', message));
      document.querySelector('[data-master-head]').replaceChildren();
      document.querySelector('[data-master-statistics]').replaceChildren();
      clearTable(document.querySelector('[data-master-body]'), 'Could not load master-sheet data.', 6);
    }
  };

  const loadResultScreen = async () => {
    const requestId = ++resultRequestId;
    const classId = resultClassSelect.value;
    const sessionId = resultSessionSelect.value;
    if (!classId || !sessionId) {
      resetResultView('Create or assign a class and academic session to view results.');
      return;
    }
    try {
      await loadTerms(sessionId, resultTermSelect, () => requestId === resultRequestId);
      if (requestId !== resultRequestId) return;
      const termId = resultTermSelect.value;
      const { data: enrollments, error: enrollmentError } = await supabase
        .from('class_enrollments')
        .select('student_id, students (id, first_name, other_names, last_name, admission_number)')
        .eq('class_id', classId)
        .eq('academic_session_id', sessionId)
        .order('enrolled_on');
      if (requestId !== resultRequestId) return;
      if (enrollmentError) throw enrollmentError;
      const previousStudentId = resultStudentSelect.value;
      resultStudentSelect.replaceChildren();
      (enrollments || []).filter((item) => item.students).forEach(({ students: student }) =>
        addSelectOption(resultStudentSelect, student.id,
          `${student.first_name} ${student.other_names || ''} ${student.last_name}`.replace(/\s+/g, ' ').trim()));
      if ([...resultStudentSelect.options].some((option) => option.value === previousStudentId)) {
        resultStudentSelect.value = previousStudentId;
      }
      if (!termId || !resultStudentSelect.value) {
        resetResultView('No result is available for the selected class, session, and term.');
        return;
      }
      const { data: results, error: resultsError } = await supabase
        .from('student_subject_results')
        .select('id, student_id, class_subject_offering_id, status, class_subject_offerings (subjects (name))')
        .eq('class_id', classId)
        .eq('academic_session_id', sessionId)
        .eq('term_id', termId)
        .eq('student_id', resultStudentSelect.value);
      if (requestId !== resultRequestId) return;
      if (resultsError) throw resultsError;
      const calculations = await Promise.all((results || []).map(async (result) => {
        const { data, error } = await supabase.rpc('get_result_calculation', { p_result_id: result.id });
        if (error) throw error;
        return { result, calculation: data?.[0] || null };
      }));
      if (requestId !== resultRequestId) return;
      renderResultView(calculations, enrollments || [], resultStudentSelect.value, classId, sessionId, termId);
    } catch (error) {
      if (requestId !== resultRequestId) return;
      showDataError('Loading the student result', error, (message) => setScreenNotice('[data-result-notice]', message));
      clearTable(document.querySelector('[data-result-body]'), 'Could not load this student result.', 7);
    }
  };

  const resetResultView = (message) => {
    document.querySelector('[data-result-name]').textContent = 'No result available';
    document.querySelector('[data-result-admission]').textContent = '';
    document.querySelector('[data-result-avatar]').textContent = '?';
    document.querySelector('[data-result-status]').textContent = 'No result';
    document.querySelector('[data-result-status]').className = 'badge muted';
    document.querySelector('[data-result-total]').textContent = '—';
    document.querySelector('[data-result-average]').textContent = '—';
    document.querySelector('[data-result-position]').textContent = '—';
    document.querySelector('[data-result-context]').textContent = '';
    document.querySelector('[data-result-head]').replaceChildren();
    clearTable(document.querySelector('[data-result-body]'), message, 7);
    setScreenNotice('[data-result-notice]', message);
  };

  const renderResultView = async (calculations, enrollments, studentId, classId, sessionId, termId) => {
    const enrollment = enrollments.find((item) => item.student_id === studentId);
    const student = enrollment?.students;
    if (!student) {
      resetResultView('No enrolled student matches the selection.');
      return;
    }
    const results = calculations.filter(({ calculation }) => calculation);
    const fullName = [student.first_name, student.other_names, student.last_name].filter(Boolean).join(' ');
    document.querySelector('[data-result-name]').textContent = fullName;
    document.querySelector('[data-result-admission]').textContent =
      `${student.admission_number} · ${currentClassesAll.find((item) => item.id === classId)?.name || ''}`;
    document.querySelector('[data-result-avatar]').textContent =
      fullName.split(/\s+/).slice(0, 2).map((part) => part.charAt(0)).join('').toLocaleUpperCase();
    document.querySelector('[data-result-context]').textContent =
      `${resultTermSelect.selectedOptions[0]?.textContent || ''} · ${currentSessions.find((item) => item.id === sessionId)?.name || ''}`;
    const status = document.querySelector('[data-result-status]');
    const allApproved = results.length > 0 && results.every(({ result }) => result.status === 'approved' || result.status === 'locked');
    status.textContent = results.length
      ? [...new Set(results.map(({ result }) => result.status.replaceAll('_', ' ')))].join(', ')
      : 'No results recorded';
    status.className = `badge ${allApproved ? 'success' : results.length ? 'warning' : 'muted'}`;
    document.querySelector('[data-result-head]').replaceChildren();
    const header = document.createElement('tr');
    ['Subject', 'Components', 'Total / Average', 'Grade', 'Status'].forEach((label) => {
      const cell = document.createElement('th');
      cell.textContent = label;
      header.append(cell);
    });
    document.querySelector('[data-result-head]').append(header);
    const body = document.querySelector('[data-result-body]');
    body.replaceChildren();
    results.forEach(({ result, calculation }) => {
      const row = document.createElement('tr');
      const subject = result.class_subject_offerings?.subjects?.name || 'Subject';
      const componentScores = Object.entries(calculation.component_scores || {})
        .map(([code, value]) => `${code}: ${value}`)
        .join(' · ') || 'No component scores';
      const classStage = currentClassesAll.find((item) => item.id === classId)?.stage;
      const componentCount = Object.keys(calculation.component_scores || {}).length;
      const subjectAverage = ['primary', 'nursery'].includes(classStage) && componentCount
        ? (Number(calculation.subject_total) / componentCount).toFixed(1)
        : calculation.subject_total;
      [
        subject,
        componentScores,
        calculation.is_complete
          ? ['primary', 'nursery'].includes(classStage)
            ? `${calculation.subject_total} / ${subjectAverage}`
            : calculation.subject_total
          : 'Incomplete',
        calculation.grade || '—',
        result.status.replaceAll('_', ' ')
      ].forEach((value) => row.append(scoreCell(String(value))));
      body.append(row);
    });
    if (!results.length) clearTable(body, 'No result records exist for this student in the selected term.', 5);
    try {
      const { data: standings, error } = await supabase.rpc('get_class_standings', {
        p_class_id: classId,
        p_academic_session_id: sessionId,
        p_term_id: termId
      });
      if (error) throw error;
      const standing = standings?.find((item) => item.student_id === studentId);
      document.querySelector('[data-result-total]').textContent =
        standing?.is_complete && standing.grand_total !== null ? String(standing.grand_total) : '—';
      document.querySelector('[data-result-average]').textContent =
        standing?.is_complete && standing.average_score !== null
          ? Number(standing.average_score).toFixed(1)
          : '—';
      document.querySelector('[data-result-position]').textContent = standing?.position
        ? String(standing.position)
        : '—';
      setScreenNotice('[data-result-notice]', results.length
        ? standing?.is_complete
          ? ''
          : 'The class total, average, and position appear after all required class results are complete.'
        : 'No result records exist for this student in the selected term yet.');
    } catch (error) {
      console.error('Could not load the class position for this result.', error);
      document.querySelector('[data-result-total]').textContent = '—';
      document.querySelector('[data-result-average]').textContent = '—';
      document.querySelector('[data-result-position]').textContent = '—';
      setScreenNotice('[data-result-notice]', `Subject results loaded, but class standings are unavailable: ${error.message}`);
    }
  };

  const populateSectionAssessmentForm = (stage) => {
    const form = document.querySelector('#section-assessment-form');
    const setting = sectionAssessmentSettings.find((item) => item.stage === stage);
    const components = new Map((setting?.components || []).map((component) => [component.code, component]));
    [
      ['CA', 'ca_name', 'Continuous assessment', 'ca_max', 20],
      ['TEST', 'test_name', 'Test', 'test_max', 20],
      ['EXAM', 'exam_name', 'Examination', 'exam_max', 60]
    ].forEach(([code, nameField, defaultName, maxField, defaultMax]) => {
      const component = components.get(code);
      form.elements.namedItem(nameField).value = component?.name
        || (['primary', 'nursery'].includes(stage) && code === 'CA'
          ? '1st Assessment'
          : ['primary', 'nursery'].includes(stage) && code === 'TEST'
            ? '2nd Assessment'
            : defaultName);
      form.elements.namedItem(maxField).value = component?.max_score ?? defaultMax;
    });
    const message = document.querySelector('[data-section-assessment-message]');
    document.querySelector('[data-delete-section-assessment]').disabled = !setting;
    message.dataset.state = 'info';
    message.textContent = setting
      ? `Current shared scheme for ${stage}. Saving changes updates every class and subject in this section.`
      : `No shared scheme is set for ${stage} yet.`;
  };

  const loadManagementData = async () => {
    try {
      const [profilesResult, teacherRolesResult, classAssignmentsResult, subjectAssignmentsResult, offeringsResult, gradingResult, sectionSettingsResult] = await Promise.all([
        supabase.from('profiles').select('id, full_name, role, is_active').order('full_name'),
        supabase.from('teacher_roles').select('teacher_id, role'),
        supabase.from('class_teacher_assignments').select('id, teacher_id, class_id, academic_session_id, term_id, classes (name), academic_sessions (name), terms (name)'),
        supabase.from('subject_teacher_assignments').select('id, teacher_id, class_subject_offering_id, term_id, class_subject_offerings (subjects (name), classes (name), academic_sessions (name)), terms (name, term_number)'),
        supabase.from('class_subject_offerings')
          .select('id, subject_id, class_id, academic_session_id, is_active, subjects (id, name, is_active), classes (name, stage), academic_sessions (name)')
          .order('created_at'),
        supabase.from('grading_scales').select('id, name, grading_bands (id, grade, minimum_score, maximum_score, remark)').eq('is_active', true).maybeSingle(),
        supabase.from('section_assessment_settings').select('stage, components, updated_at')
      ]);
      const failed = profilesResult.error || teacherRolesResult.error || classAssignmentsResult.error || subjectAssignmentsResult.error
        || offeringsResult.error || gradingResult.error || sectionSettingsResult.error;
      if (failed) throw failed;
      sectionAssessmentSettings = sectionSettingsResult.data || [];
      const teacherRoles = new Map();
      (teacherRolesResult.data || []).forEach((item) => {
        if (!teacherRoles.has(item.teacher_id)) teacherRoles.set(item.teacher_id, []);
        teacherRoles.get(item.teacher_id).push(item.role);
      });

      const assignmentLabels = new Map();
      (classAssignmentsResult.data || []).forEach((item) => {
        if (!assignmentLabels.has(item.teacher_id)) assignmentLabels.set(item.teacher_id, []);
        assignmentLabels.get(item.teacher_id).push({
          id: item.id,
          type: 'class',
          text: `${item.classes?.name || 'Class'} (${item.academic_sessions?.name || ''} · ${item.terms?.name || 'Term'})`
        });
      });
      (subjectAssignmentsResult.data || []).forEach((item) => {
        const offering = item.class_subject_offerings;
        if (!assignmentLabels.has(item.teacher_id)) assignmentLabels.set(item.teacher_id, []);
        assignmentLabels.get(item.teacher_id).push({
          id: item.id,
          type: 'subject',
          text: `${offering?.subjects?.name || 'Subject'} · ${offering?.classes?.name || 'Class'} (${offering?.academic_sessions?.name || ''} · ${item.terms?.name || 'Term'})`
        });
      });
      const teachersBody = document.querySelector('[data-teachers-body]');
      teachersBody.replaceChildren();
      (profilesResult.data || []).filter((profile) => profile.role !== 'administrator').forEach((profile) => {
        const row = document.createElement('tr');
        row.dataset.teacherId = profile.id;
        row.dataset.teacherName = profile.full_name;
        row.dataset.teacherRole = profile.role;
        row.dataset.teacherRoles = JSON.stringify(teacherRoles.get(profile.id) || [profile.role]);
        row.dataset.teacherActive = String(profile.is_active);
        row.append(scoreCell(profile.full_name), scoreCell((teacherRoles.get(profile.id) || [profile.role])
          .map((role) => role.replaceAll('_', ' ')).join(', ')));
        const assignmentCell = document.createElement('td');
        const assignments = assignmentLabels.get(profile.id) || [];
        const assignmentList = document.createElement('details');
        assignmentList.className = 'teacher-assignment-list';
        assignmentList.open = window.matchMedia('(min-width: 851px)').matches;
        const assignmentSummary = document.createElement('summary');
        assignmentSummary.textContent = `${assignments.length} assignment${assignments.length === 1 ? '' : 's'}`;
        const assignmentItems = document.createElement('div');
        assignmentItems.className = 'teacher-assignment-items';
        assignments.forEach((assignment) => {
          const item = document.createElement('div');
          item.className = 'assignment-item';
          item.append(document.createTextNode(assignment.text));
          if (currentProfile?.role === 'administrator') {
            const remove = document.createElement('button');
            remove.className = 'text-action danger-action';
            remove.type = 'button';
            remove.textContent = 'Remove';
            remove.dataset.removeAssignment = assignment.id;
            remove.dataset.assignmentType = assignment.type;
            item.append(remove);
          }
          assignmentItems.append(item);
        });
        if (assignments.length) {
          assignmentList.append(assignmentSummary, assignmentItems);
          assignmentCell.append(assignmentList);
        } else {
          assignmentCell.textContent = 'No assignments';
        }
        row.append(assignmentCell);
        const statusCell = document.createElement('td');
        const badge = document.createElement('span');
        badge.className = `badge ${profile.is_active ? 'success' : 'muted'}`;
        badge.textContent = profile.is_active ? 'Active' : 'Inactive';
        statusCell.append(badge);
        const actionsCell = document.createElement('td');
        if (currentProfile?.role === 'administrator') {
          const edit = document.createElement('button');
          edit.className = 'btn-small';
          edit.type = 'button';
          edit.textContent = 'Edit';
          edit.dataset.editTeacher = profile.id;
          const toggle = document.createElement('button');
          toggle.className = 'btn-small';
          toggle.type = 'button';
          toggle.textContent = profile.is_active ? 'Deactivate' : 'Reactivate';
          toggle.dataset.toggleTeacher = profile.id;
          toggle.dataset.active = String(profile.is_active);
          const remove = document.createElement('button');
          remove.className = 'btn-small danger-action';
          remove.type = 'button';
          remove.textContent = 'Delete teacher';
          remove.title = 'Delete this teacher account';
          remove.dataset.removeTeacher = profile.id;
          actionsCell.append(edit, toggle, remove);
        }
        row.append(statusCell, actionsCell);
        teachersBody.append(row);
      });
      if (!teachersBody.children.length) clearTable(teachersBody, 'No teacher profiles are available to this account.', 5);

      const subjectsBody = document.querySelector('[data-subjects-body]');
      subjectsBody.replaceChildren();
      const subjectGroups = new Map();
      (offeringsResult.data || []).forEach((offering) => {
        const key = `${offering.subject_id}:${offering.academic_session_id}:${subjectClassGroupKey(
          offering.classes?.name || 'Class'
        )}`;
        const group = subjectGroups.get(key) || [];
        group.push(offering);
        subjectGroups.set(key, group);
      });
      [...subjectGroups.values()].forEach((group) => {
        const offering = group[0];
        const row = document.createElement('tr');
        const subjectCell = document.createElement('td');
        const subjectInput = document.createElement('input');
        subjectInput.type = 'text';
        subjectInput.value = offering.subjects?.name || '';
        subjectInput.maxLength = 120;
        subjectInput.disabled = currentProfile?.role !== 'administrator';
        subjectInput.dataset.subjectName = offering.subject_id;
        subjectCell.append(subjectInput);
        row.append(subjectCell, scoreCell(subjectClassRange(
          group.map((item) => item.classes?.name || 'Class')
        )),
          scoreCell(offering.academic_sessions?.name || 'Session'));
        const statusCell = document.createElement('td');
        const status = document.createElement('span');
        const active = Boolean(
          offering.subjects?.is_active && group.every((item) => item.is_active)
        );
        status.className = `badge ${active ? 'success' : 'muted'}`;
        status.textContent = active ? 'Active' : 'Archived';
        statusCell.append(status);
        const actions = document.createElement('td');
        if (currentProfile?.role === 'administrator') {
          const saveName = document.createElement('button');
          saveName.className = 'btn-small';
          saveName.type = 'button';
          saveName.textContent = 'Save name';
          saveName.dataset.saveSubject = offering.subject_id;
          const toggle = document.createElement('button');
          toggle.className = 'btn-small';
          toggle.type = 'button';
          toggle.textContent = active ? 'Deactivate' : 'Reactivate';
          toggle.dataset.toggleOfferings = group.map((item) => item.id).join(',');
          toggle.dataset.active = String(active);
          toggle.dataset.subjectId = offering.subject_id;
          const remove = document.createElement('button');
          remove.className = 'btn-small danger-action';
          remove.type = 'button';
          remove.textContent = 'Delete';
          remove.dataset.removeOfferings = group.map((item) => item.id).join(',');
          const moveSession = document.createElement('select');
          moveSession.className = 'subject-session-select';
          moveSession.dataset.moveOfferings = group.map((item) => item.id).join(',');
          moveSession.setAttribute('aria-label', `Move ${offering.subjects?.name || 'subject'} to another session`);
          currentSessions.filter((session) => session.is_active && session.name !== '2027/2028').forEach((session) => {
            const option = document.createElement('option');
            option.value = session.id;
            option.textContent = session.name;
            option.selected = session.id === offering.academic_session_id;
            moveSession.append(option);
          });
          const moveButton = document.createElement('button');
          moveButton.className = 'btn-small';
          moveButton.type = 'button';
          moveButton.textContent = 'Move';
          moveButton.title = 'Move subject offerings to the selected session';
          moveButton.dataset.moveOfferings = group.map((item) => item.id).join(',');
          actions.append(saveName, toggle, remove, moveSession, moveButton);
        }
        row.append(statusCell, actions);
        subjectsBody.append(row);
      });
      if (!subjectsBody.children.length) clearTable(subjectsBody, 'No class subjects have been configured yet.', 5);

      const teachers = (profilesResult.data || []).filter((profile) =>
        profile.role !== 'administrator' && profile.is_active);
      replaceSelectOptions(
        document.querySelector('[data-permission-teacher]'),
        teachers,
        (item) => item.full_name
      );
      createTeacherClasses = currentClasses;
      createTeacherOfferings = (offeringsResult.data || []).filter((item) => item.is_active && item.subjects?.is_active);
      replaceSelectOptions(document.querySelector('[data-create-class-select]'), createTeacherClasses,
        (item) => item.name);
      replaceSelectOptions(document.querySelector('[data-create-session-select]'),
        currentSessions.filter((item) => item.name !== '2027/2028'),
        (item) => item.name);
      const createTermSelect = document.querySelector('[data-create-term-select]');
      await loadTerms(document.querySelector('[data-create-session-select]').value, createTermSelect);
      replaceSelectOptions(document.querySelector('[data-create-offering-select]'),
        createTeacherOfferings.filter((item) => item.academic_sessions?.name !== '2027/2028'),
        (item) => `${item.subjects.name} · ${item.classes?.name} (${item.academic_sessions?.name})`);
      refreshCreateTeacherAssignments();
      replaceSelectOptions(document.querySelector('[data-offering-session]'),
        currentSessions.filter((item) => item.is_active && item.name !== '2027/2028'), (item) => item.name);
      populateSectionAssessmentForm(sectionAssessmentSelect.value);

      renderSetupList(
        document.querySelector('[data-management-class-list]'),
        currentProfile?.role === 'administrator' ? currentClassesAll : currentClasses,
        'No classes are assigned to this account yet.',
        schoolClassRow
      );
      const gradingScale = gradingResult.data;
      document.querySelector('[data-grading-scale-name]').value = gradingScale?.name || '';
      const gradingBody = document.querySelector('[data-grading-bands-body]');
      gradingBody.replaceChildren();
      (gradingScale?.grading_bands || [])
        .sort((left, right) => Number(left.minimum_score) - Number(right.minimum_score))
        .forEach((band) => gradingBody.append(createGradingBandRow(band)));
      document.querySelector('[data-grading-message]').textContent = gradingScale
        ? ''
        : 'No grading scale exists yet. Add at least one grade band, then save.';
      setScreenNotice('[data-management-notice]', '');
    } catch (error) {
      showDataError('Loading teachers and subjects', error, (message) => setScreenNotice('[data-management-notice]', message));
    }
  };

  [masterClassSelect, masterSessionSelect, masterTermSelect].forEach((select) => {
    select.addEventListener('change', () => {
      if (select === masterClassSelect) copySessionOptions(masterSessionSelect);
      void loadMasterSheet();
    });
  });
  [resultClassSelect, resultSessionSelect, resultTermSelect, resultStudentSelect].forEach((select) => {
    select.addEventListener('change', () => {
      if (select === resultClassSelect) copySessionOptions(resultSessionSelect);
      void loadResultScreen();
    });
  });

  document.querySelector('[data-export-master]').addEventListener('click', () => {
    const rows = [...document.querySelectorAll('.master-table tr')]
      .filter((row) => !row.hidden)
      .map((row) => [...row.cells].map((cell) => {
        let value = cell.textContent.trim();
        if (/^[\s]*[=+\-@]/.test(value)) value = `'${value}`;
        return `"${value.replaceAll('"', '""')}"`;
      }).join(','));
    if (rows.length < 2 || document.querySelector('[data-master-body] .muted-text')) {
      showToast('There is no master-sheet data to export.');
      return;
    }
    const csv = rows.join('\r\n');
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = 'term-master-sheet.csv';
    link.click();
    URL.revokeObjectURL(url);
  });

  document.querySelector('#section-assessment-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (currentProfile?.role !== 'administrator') return;
    const form = event.currentTarget;
    const formData = new FormData(form);
    const message = document.querySelector('[data-section-assessment-message]');
    const submit = form.querySelector('[type="submit"]');
    const components = [
      { code: 'CA', name: String(formData.get('ca_name')).trim(), max_score: Number(formData.get('ca_max')) },
      { code: 'TEST', name: String(formData.get('test_name')).trim(), max_score: Number(formData.get('test_max')) },
      { code: 'EXAM', name: String(formData.get('exam_name')).trim(), max_score: Number(formData.get('exam_max')) }
    ];
    submit.disabled = true;
    message.dataset.state = 'pending';
    message.textContent = 'Saving the shared section assessment…';
    try {
      const savedComponents = components.map((component, index) => ({
          ...component,
          display_order: index + 1,
          counts_toward_total: true,
          is_required: true
        }));
      const stages = ['primary', 'nursery'].includes(formData.get('stage'))
        ? ['primary', 'nursery']
        : [formData.get('stage')];
      for (const stage of stages) {
        const { error } = await supabase.rpc('admin_save_section_assessment', {
          p_stage: stage,
          p_components: savedComponents
        });
        if (error) throw error;
      }
      message.dataset.state = 'success';
      message.textContent = stages.length > 1
        ? 'The shared Primary/Nursery assessment scheme was saved across all classes and sessions.'
        : 'Shared assessment scheme saved for the section across all sessions.';
      await Promise.all([loadManagementData(), loadScoreScreen()]);
    } catch (error) {
      message.dataset.state = 'error';
      showDataError('Saving the section assessment', error, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
    }
  });
  sectionAssessmentSelect.addEventListener('change', () =>
    populateSectionAssessmentForm(sectionAssessmentSelect.value));

  document.querySelector('[data-delete-section-assessment]').addEventListener('click', async (event) => {
    if (currentProfile?.role !== 'administrator') return;
    const stage = sectionAssessmentSelect.value;
    if (!window.confirm(
      `Delete the saved ${stage} assessment scheme? It will stop applying to new results. Existing results keep their saved assessment history. You can then enter and save the correct scheme.`
    )) return;

    const button = event.currentTarget;
    const message = document.querySelector('[data-section-assessment-message]');
    button.disabled = true;
    message.dataset.state = 'pending';
    message.textContent = 'Deleting the saved section assessment…';
    try {
      const { error } = await supabase.rpc('admin_delete_section_assessment', {
        p_stage: stage
      });
      if (error) throw error;
      await Promise.all([loadManagementData(), loadScoreScreen()]);
      message.dataset.state = 'success';
      message.textContent = `Saved ${stage} scheme deleted. Enter the correct values above and save to add the replacement. Existing result history is preserved.`;
    } catch (error) {
      message.dataset.state = 'error';
      showDataError('Deleting the section assessment', error, (text) => { message.textContent = text; });
      button.disabled = false;
    }
  });

  document.querySelector('[data-subject-offering-form]').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (currentProfile?.role !== 'administrator') return;
    const form = event.currentTarget;
    const values = new FormData(form);
    const message = document.querySelector('[data-subject-offering-message]');
    const submit = form.querySelector('[type="submit"]');
    submit.disabled = true;
    message.textContent = 'Adding subject…';
    try {
      const classGroup = String(values.get('class_group'));
      const subjectName = String(values.get('subject_name')).trim();
      const groupLabel = form.querySelector('[name="class_group"]').selectedOptions[0].textContent;
      const { data: addedCount, error } = await supabase.rpc('admin_add_subject_to_class_group', {
        p_class_group: classGroup,
        p_academic_session_id: values.get('academic_session_id'),
        p_subject_name: subjectName
      });
      if (error) throw error;
      await Promise.all([loadManagementData(), loadScoreScreen()]);
      form.querySelector('[name="subject_name"]').value = '';
      message.textContent = `${subjectName} added or updated in ${addedCount} active class(es) in ${groupLabel} for the selected session, using the section-wide assessment scheme.`;
    } catch (error) {
      showDataError('Adding the subject', error, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
    }
  });

  document.querySelectorAll('[data-close-class-edit]').forEach((button) =>
    button.addEventListener('click', () => document.querySelector('#class-edit-dialog').close()));
  document.querySelectorAll('[data-close-teacher-edit]').forEach((button) =>
    button.addEventListener('click', () => document.querySelector('#teacher-edit-dialog').close()));

  document.querySelector('#class-edit-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (currentProfile?.role !== 'administrator') return;
    const form = event.currentTarget;
    const values = new FormData(form);
    const message = document.querySelector('[data-class-edit-message]');
    const submit = form.querySelector('[type="submit"]');
    submit.disabled = true;
    try {
      const { error } = await supabase.from('classes').update({
        name: String(values.get('name')).trim(),
        stage: values.get('stage')
      }).eq('id', values.get('id'));
      if (error) throw error;
      document.querySelector('#class-edit-dialog').close();
      showToast('Class details updated.');
      await refreshLiveData(currentProfile);
    } catch (error) {
      showDataError('Updating the class', error, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
    }
  });

  document.querySelector('#teacher-edit-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (currentProfile?.role !== 'administrator') return;
    const form = event.currentTarget;
    const values = new FormData(form);
    const message = document.querySelector('[data-teacher-edit-message]');
    const submit = form.querySelector('[type="submit"]');
    const roles = [...form.querySelectorAll('[name="roles"]:checked')].map((input) => input.value);
    if (!roles.length) {
      message.textContent = 'Select at least one teacher role.';
      return;
    }
    submit.disabled = true;
    try {
      const { error } = await supabase.from('profiles').update({
        full_name: String(values.get('full_name')).trim(),
        role: roles[0]
      }).eq('id', values.get('id')).neq('role', 'administrator');
      if (error) throw error;
      const { error: clearRolesError } = await supabase.from('teacher_roles')
        .delete().eq('teacher_id', values.get('id'));
      if (clearRolesError) throw clearRolesError;
      const { error: addRolesError } = await supabase.from('teacher_roles')
        .insert(roles.map((role) => ({ teacher_id: values.get('id'), role })));
      if (addRolesError) throw addRolesError;
      const password = String(values.get('password') || '');
      if (password) {
        if (password !== String(values.get('confirm_password') || '')) {
          throw new Error('The new password entries do not match.');
        }
        const { data, error: passwordError } = await invokeTeacherManagement({
          action: 'reset_password',
          teacher_id: values.get('id'),
          password
        });
        if (passwordError) throw passwordError;
        if (data?.error) throw new Error(data.error);
      }
      document.querySelector('#teacher-edit-dialog').close();
      showToast(password ? 'Teacher profile and password updated.' : 'Teacher profile updated.');
      await loadManagementData();
    } catch (error) {
      showDataError('Updating the teacher profile', error, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
    }
  });

  document.querySelector('#password-setup-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const password = form.querySelector('[name="password"]').value;
    const confirmation = form.querySelector('[name="confirm_password"]').value;
    const message = document.querySelector('[data-password-setup-message]');
    const submit = form.querySelector('[type="submit"]');
    if (password.length < 8) {
      message.textContent = 'Use a password with at least 8 characters.';
      return;
    }
    if (password !== confirmation) {
      message.textContent = 'The password entries do not match.';
      return;
    }
    submit.disabled = true;
    message.textContent = 'Updating password…';
    try {
      const { error: passwordError } = await supabase.auth.updateUser({ password });
      if (passwordError) throw passwordError;
      const { error: profileError } = await supabase.rpc('complete_password_setup');
      if (profileError) {
        throw new Error(`Password changed, but the school profile could not be updated: ${profileError.message}`);
      }
      if (currentProfile) currentProfile.must_change_password = false;
      document.querySelector('#password-setup-dialog').close();
      form.reset();
      showToast('Password updated. Your school account is ready.');
    } catch (error) {
      showDataError('Updating your password', error, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
    }
  });

  document.querySelector('[data-teacher-invite-form]').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (currentProfile?.role !== 'administrator') return;
    const form = event.currentTarget;
    const values = new FormData(form);
    const message = document.querySelector('[data-teacher-invite-message]');
    const submit = form.querySelector('[type="submit"]');
    const roles = values.getAll('roles');
    const classIds = values.getAll('class_id');
    const sessionId = String(values.get('academic_session_id') || '');
    const termId = String(values.get('term_id') || '');
    const offeringIds = values.getAll('class_subject_offering_id');
    if (!roles.length) {
      message.textContent = 'Select at least one role for this teacher.';
      return;
    }
    submit.disabled = true;
    const password = String(values.get('password') || '');
    if (password.length < 8) {
      message.textContent = 'Use an initial password with at least 8 characters.';
      return;
    }
    if (password !== String(values.get('confirm_password') || '')) {
      message.textContent = 'The password entries do not match.';
      return;
    }
    if ((classIds.length || offeringIds.length) && (!sessionId || !termId)) {
      message.textContent = 'Select an academic session and term for the teacher assignment.';
      return;
    }
    message.textContent = 'Creating teacher account…';
    try {
      const { data, error } = await invokeTeacherManagement({
        action: 'create',
        full_name: String(values.get('full_name')).trim(),
        email: String(values.get('email')).trim(),
        password,
        roles,
        class_ids: classIds,
        academic_session_id: sessionId || null,
        term_id: termId || null,
        offering_ids: offeringIds
      });

      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      form.reset();
      message.textContent = 'Teacher account created. Give the login email and password to the teacher securely.';
      await loadManagementData();
    } catch (error) {
      let detail = error;
      if (error?.context instanceof Response) {
        try {
          const body = await error.context.json();
          if (body?.error) detail = new Error(body.error);
        } catch {
          detail = error;
        }
      }
      showDataError('Creating the teacher account', detail, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
    }
  });

  const refreshCreateTeacherAssignments = () => {
    const form = document.querySelector('[data-teacher-invite-form]');
    if (!form) return;
    const roles = new Set([...form.querySelectorAll('[name="roles"]:checked')].map((input) => input.value));
    const allowedStages = new Set();
    const hasClassTeacherRole = roles.has('secondary_class_teacher')
      || roles.has('primary_teacher')
      || roles.has('nursery_teacher');
    const hasSubjectTeacherRole = roles.has('secondary_subject_teacher')
      || roles.has('primary_teacher')
      || roles.has('nursery_teacher');
    if (roles.has('secondary_class_teacher') || roles.has('secondary_subject_teacher')) allowedStages.add('secondary');
    if (roles.has('primary_teacher')) allowedStages.add('primary');
    if (roles.has('nursery_teacher')) allowedStages.add('nursery');
    const classSelect = form.querySelector('[data-create-class-select]');
    const offeringSelect = form.querySelector('[data-create-offering-select]');
    const classLabel = classSelect.closest('label');
    const sessionSelect = form.querySelector('[data-create-session-select]');
    const sessionLabel = sessionSelect.closest('label');
    const termSelect = form.querySelector('[data-create-term-select]');
    const termLabel = termSelect.closest('label');
    const offeringLabel = offeringSelect.closest('label');
    classLabel.hidden = !hasClassTeacherRole;
    sessionLabel.hidden = !hasClassTeacherRole && !hasSubjectTeacherRole;
    termLabel.hidden = !hasClassTeacherRole && !hasSubjectTeacherRole;
    offeringLabel.hidden = !hasSubjectTeacherRole;
    if (!hasClassTeacherRole) {
      classSelect.replaceChildren();
    }
    if (!hasSubjectTeacherRole) offeringSelect.replaceChildren();
    if (!hasClassTeacherRole && !hasSubjectTeacherRole) return;
    const selectedSessionId = sessionSelect.value;
    if (selectedSessionId && !termSelect.options.length) {
      void loadTerms(selectedSessionId, termSelect);
    }
    const selectedClasses = new Set([...classSelect.selectedOptions].map((option) => option.value));
    const selectedOfferings = new Set([...offeringSelect.selectedOptions].map((option) => option.value));
    if (hasClassTeacherRole) {
      replaceSelectOptions(classSelect, createTeacherClasses.filter((item) => allowedStages.has(item.stage)), (item) => item.name);
    }
    replaceSelectOptions(
      offeringSelect,
      hasSubjectTeacherRole
        ? createTeacherOfferings.filter((item) =>
          allowedStages.has(item.classes?.stage)
          && (!sessionSelect.value || item.academic_session_id === sessionSelect.value)
        )
        : [],
      (item) => `${item.subjects.name} · ${item.classes?.name} (${item.academic_sessions?.name})`
    );
    if (hasClassTeacherRole) {
      [...classSelect.options].forEach((option) => { option.selected = selectedClasses.has(option.value); });
    }
    if (hasSubjectTeacherRole) {
      [...offeringSelect.options].forEach((option) => { option.selected = selectedOfferings.has(option.value); });
    }
  };

  document.querySelectorAll('[data-teacher-invite-form] [name="roles"]').forEach((input) => {
    input.addEventListener('change', refreshCreateTeacherAssignments);
  });
  document.querySelector('[data-create-session-select]')?.addEventListener('change', async (event) => {
    const termSelect = document.querySelector('[data-create-term-select]');
    await loadTerms(event.target.value, termSelect);
    refreshCreateTeacherAssignments();
  });

  const showManagementActionError = (message, error) => {
    showDataError('Saving the management change', error, (text) => {
      message.textContent = text;
      setScreenNotice('[data-management-notice]', text);
    });
  };

  document.addEventListener('click', async (event) => {
    const button = event.target.closest('button');
    if (!button || currentProfile?.role !== 'administrator') return;

    if (button.hasAttribute('data-add-grade')) {
      document.querySelector('[data-grading-bands-body]').append(createGradingBandRow());
      return;
    }

    if (button.hasAttribute('data-remove-grade')) {
      button.closest('tr').remove();
      return;
    }

    if (button.dataset.editSession) {
      const session = currentSessions.find((item) => item.id === button.dataset.editSession);
      if (!session) return;
      const { data: terms, error } = await supabase.from('terms')
        .select('term_number, is_active')
        .eq('academic_session_id', session.id)
        .order('term_number');
      if (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not load session terms for editing.', error);
        return;
      }
      const form = document.querySelector('#session-edit-form');
      form.querySelector('[name="id"]').value = session.id;
      form.querySelector('[name="name"]').value = session.name;
      form.querySelector('[name="starts_on"]').value = session.starts_on;
      form.querySelector('[name="ends_on"]').value = session.ends_on;
      form.querySelector('[name="active_term"]').value =
        String(terms?.find((term) => term.is_active)?.term_number || 1);
      form.querySelector('[name="make_current"]').checked = Boolean(session.is_current);
      document.querySelector('[data-session-edit-message]').textContent = '';
      document.querySelector('#session-edit-dialog').showModal();
      return;
    }

    if (button.dataset.removeSession) {
      const sessionId = button.dataset.removeSession;
      const isActive = button.dataset.active === 'true';
      if (isActive && !window.confirm('Delete this academic session? If enrollments, subjects, or assignments depend on it, it will be archived to preserve school history.')) return;
      try {
        if (isActive) {
          const { data, error } = await supabase.rpc('admin_remove_academic_session', {
            p_session_id: sessionId
          });
          if (error) throw error;
          showToast(data === 'archived' ? 'Academic session archived; its history was preserved.' : 'Unused academic session deleted.');
        } else {
          const { error } = await supabase.from('academic_sessions')
            .update({ is_active: true })
            .eq('id', sessionId);
          if (error) throw error;
          showToast('Academic session restored.');
        }
        await refreshLiveData(currentProfile);
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not remove or restore the academic session.', error);
      }
      return;
    }

    if (button.hasAttribute('data-save-grading-scale')) {
      const rows = [...document.querySelectorAll('[data-grading-bands-body] tr')];
      const bands = rows.map((row) => {
        const minimum = row.querySelector('[name="minimum_score"]').value;
        const maximum = row.querySelector('[name="maximum_score"]').value;
        return {
          grade: row.querySelector('[name="grade"]').value.trim(),
          minimum_score: minimum === '' ? null : Number(minimum),
          maximum_score: maximum === '' ? null : Number(maximum),
          remark: row.querySelector('[name="remark"]').value.trim()
        };
      });
      const scaleName = document.querySelector('[data-grading-scale-name]').value.trim();
      const message = document.querySelector('[data-grading-message]');
      if (!bands.length || bands.some((band) => !band.grade
        || !Number.isFinite(band.minimum_score) || !Number.isFinite(band.maximum_score))) {
        message.textContent = 'Add at least one grade band and enter a grade with valid minimum and maximum scores for each.';
        return;
      }
      button.disabled = true;
      message.textContent = 'Saving grading scale…';
      try {
        const { error } = await supabase.rpc('admin_save_grading_scale', {
          p_name: scaleName,
          p_bands: bands
        });
        if (error) throw error;
        message.textContent = 'Grading scale saved.';
        await loadManagementData();
      } catch (error) {
        showDataError('Saving the grading scale', error, (text) => { message.textContent = text; });
      } finally {
        button.disabled = false;
      }
      return;
    }

    if (button.dataset.editClass) {
      const schoolClass = currentClassesAll.find((item) => item.id === button.dataset.editClass);
      if (!schoolClass) return;
      const form = document.querySelector('#class-edit-form');
      form.querySelector('[name="id"]').value = schoolClass.id;
      form.querySelector('[name="name"]').value = schoolClass.name;
      form.querySelector('[name="stage"]').value = schoolClass.stage;
      document.querySelector('[data-class-edit-message]').textContent = '';
      document.querySelector('#class-edit-dialog').showModal();
      return;
    }

    if (button.dataset.removeClass) {
      const classId = button.dataset.removeClass;
      const isActive = button.dataset.active === 'true';
      if (isActive && !window.confirm('Delete this class? If enrollments or results depend on it, it will be archived so school history is preserved.')) return;
      try {
        if (isActive) {
          const { data, error } = await supabase.rpc('admin_remove_class', { p_class_id: classId });
          if (error) throw error;
          showToast(data === 'archived' ? 'Class archived; its history was preserved.' : 'Unused class deleted.');
        } else {
          const { error } = await supabase.from('classes').update({ is_active: true }).eq('id', classId);
          if (error) throw error;
          showToast('Class restored.');
        }
        await refreshLiveData(currentProfile);
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Class removal or restoration failed.', error);
      }
      return;
    }

    if (button.dataset.editTeacher) {
      const row = button.closest('tr');
      const form = document.querySelector('#teacher-edit-form');
      form.querySelector('[name="id"]').value = button.dataset.editTeacher;
      form.querySelector('[name="full_name"]').value = row.dataset.teacherName;
      const selectedRoles = JSON.parse(row.dataset.teacherRoles || '[]');
      form.querySelectorAll('[name="roles"]').forEach((input) => {
        input.checked = selectedRoles.includes(input.value);
      });
      document.querySelector('[data-teacher-edit-message]').textContent = '';
      document.querySelector('#teacher-edit-dialog').showModal();
      return;
    }

    if (button.dataset.toggleTeacher) {
      const nextActive = button.dataset.active !== 'true';
      try {
        const { error } = await supabase.from('profiles')
          .update({ is_active: nextActive })
          .eq('id', button.dataset.toggleTeacher)
          .neq('role', 'administrator');
        if (error) throw error;
        showToast(nextActive ? 'Teacher reactivated.' : 'Teacher deactivated.');
        await loadManagementData();
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not change teacher account status.', error);
      }
      return;
    }

    if (button.dataset.removeTeacher) {
      if (!window.confirm('Remove this teacher from the active Teachers area? Their assignments will be removed, while recorded result history is preserved.')) return;
      try {
        const { data, error } = await invokeTeacherManagement({
          action: 'remove',
          teacher_id: button.dataset.removeTeacher
        });
        if (error) throw error;
        if (data?.error) throw new Error(data.error);
        showToast(data.outcome === 'removed'
          ? 'Teacher removed from active teachers; result history was preserved.'
          : 'Unused teacher account deleted.');
        await loadManagementData();
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not remove the teacher account.', error);
      }
      return;
    }

    if (button.dataset.removeAssignment) {
      if (!window.confirm('Remove this teacher assignment? Existing results will be preserved.')) return;
      const table = button.dataset.assignmentType === 'class'
        ? 'class_teacher_assignments'
        : 'subject_teacher_assignments';
      try {
        const { error } = await supabase.from(table).delete().eq('id', button.dataset.removeAssignment);
        if (error) throw error;
        showToast('Teacher assignment removed.');
        await loadManagementData();
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not remove the teacher assignment.', error);
      }
      return;
    }

    if (button.dataset.saveSubject) {
      const input = button.closest('tr').querySelector('[data-subject-name]');
      const newName = input.value.trim();
      if (!newName) {
        setScreenNotice('[data-management-notice]', 'Subject names cannot be blank.');
        return;
      }
      try {
        const { error } = await supabase.from('subjects').update({ name: newName }).eq('id', button.dataset.saveSubject);
        if (error) throw error;
        showToast('Subject name updated.');
        await loadManagementData();
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not update the subject name.', error);
      }
      return;
    }

    if (button.dataset.moveOfferings) {
      const sessionId = button.closest('td').querySelector('[data-move-offerings]')?.value;
      if (!sessionId) return;
      try {
        const offeringIds = button.dataset.moveOfferings.split(',');
        const results = await Promise.all(offeringIds.map((id) =>
          supabase.from('class_subject_offerings')
            .update({ academic_session_id: sessionId })
            .eq('id', id)
        ));
        const updateError = results.find((result) => result.error)?.error;
        if (updateError) throw updateError;
        showToast('Subject offerings moved to the selected session.');
        await Promise.all([loadManagementData(), loadScoreScreen(), loadMasterSheet()]);
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not move subject offerings to another session.', error);
      }
      return;
    }

    if (button.dataset.toggleOfferings) {
      const active = button.dataset.active !== 'true';
      const offeringIds = button.dataset.toggleOfferings.split(',');
      try {
        const { error: subjectError } = active
          ? await supabase.from('subjects').update({ is_active: true }).eq('id', button.dataset.subjectId)
          : { error: null };
        if (subjectError) throw subjectError;
        const results = await Promise.all(offeringIds.map((id) =>
          supabase.from('class_subject_offerings')
            .update({ is_active: active })
            .eq('id', id)
        ));
        const offeringError = results.find((result) => result.error)?.error;
        if (offeringError) throw offeringError;
        showToast(active ? 'Subject offering reactivated.' : 'Subject offering deactivated.');
        await Promise.all([loadManagementData(), loadScoreScreen(), loadMasterSheet()]);
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not change subject offering status.', error);
      }
      return;
    }

    if (button.dataset.removeOfferings) {
      if (!window.confirm('Delete this subject offering? If it has result history, it will be archived.')) return;
      try {
        const offeringIds = button.dataset.removeOfferings.split(',');
        const results = await Promise.all(offeringIds.map((id) =>
          supabase.rpc('admin_remove_subject_offering', { p_offering_id: id })
        ));
        const rpcError = results.find((result) => result.error)?.error;
        if (rpcError) throw rpcError;
        const statuses = results.map((result) => result.data);
        showToast(statuses.includes('archived')
          ? 'Subject offering archived; its results were preserved.'
          : statuses.every((status) => status === 'deleted')
            ? 'Unused subject and offering deleted.'
            : 'Unused offering deleted; other class offerings remain.');
        await Promise.all([loadManagementData(), loadScoreScreen(), loadMasterSheet()]);
      } catch (error) {
        setScreenNotice('[data-management-notice]', error.message);
        console.error('Could not remove the subject offering.', error);
      }
    }
  });

  const loadStudentOptions = async (requestId) => {
    const profile = currentProfile;
    const [classesResult, sessionsResult, classAssignmentsResult, subjectAssignmentsResult, teacherRolesResult] = await Promise.all([
      supabase.from('classes').select('id, name, stage, is_active').order('name'),
      supabase.from('academic_sessions').select('id, name, starts_on, ends_on, is_current, is_active').order('is_current', { ascending: false }).order('starts_on', { ascending: false }),
      profile.role === 'administrator'
        ? Promise.resolve({ data: [], error: null })
        :         supabase.from('class_teacher_assignments').select('class_id, academic_session_id, term_id').eq('teacher_id', profile.id),
      profile.role === 'administrator'
        ? Promise.resolve({ data: [], error: null })
        : supabase.from('subject_teacher_assignments')
          .select('class_subject_offering_id, term_id, terms (id, name, term_number)')
          .eq('teacher_id', profile.id),
      profile.role === 'administrator'
        ? Promise.resolve({ data: [], error: null })
        : supabase.from('teacher_roles').select('role').eq('teacher_id', profile.id)
    ]);
    if (requestId !== dataRequest) return;
    if (classesResult.error || sessionsResult.error || classAssignmentsResult.error || subjectAssignmentsResult.error || teacherRolesResult.error) {
      const error = classesResult.error || sessionsResult.error || classAssignmentsResult.error || subjectAssignmentsResult.error || teacherRolesResult.error;
      showDataError('Loading classes and academic sessions', error, setStudentNotice);
      renderClassLoadError(`Could not load your assigned classes: ${error.message}`);
      document.querySelector('[data-session-list]').replaceChildren();
      document.querySelector('[data-school-class-list]').replaceChildren();
      return;
    }

    const sessions = sessionsResult.data || [];
    const allClasses = sortClasses(classesResult.data || []);
    const schoolClasses = allClasses.filter((item) => item.is_active);
    let assignedSubjectClasses = [];
    if (profile.role !== 'administrator' && subjectAssignmentsResult.data?.length) {
      const { data: subjectOfferings, error: subjectOfferingsError } = await supabase
        .from('class_subject_offerings')
        .select('id, class_id, academic_session_id, subjects (name), classes (name, stage), academic_sessions (name)')
        .in('id', subjectAssignmentsResult.data.map((item) => item.class_subject_offering_id));
      if (subjectOfferingsError) {
        renderClassLoadError(`Could not load your subject assignments: ${subjectOfferingsError.message}`);
        showDataError('Loading subject assignments', subjectOfferingsError, setStudentNotice);
        return;
      }
      const assignmentByOffering = new Map(
        (subjectAssignmentsResult.data || []).map((assignment) => [assignment.class_subject_offering_id, assignment])
      );
      assignedSubjectClasses = (subjectOfferings || [])
        .filter((offering) => offering.academic_sessions?.name !== '2027/2028')
        .map((offering) => ({
          ...offering,
          term_id: assignmentByOffering.get(offering.id)?.term_id || '',
          terms: assignmentByOffering.get(offering.id)?.terms || null
        }));
    }
    currentTeacherRoles = new Set((teacherRolesResult.data || []).map((item) => item.role));
    currentTeacherSubjectOfferings = assignedSubjectClasses;
    renderSubjectCards(currentTeacherSubjectOfferings);
    currentClassesAll = allClasses;
    currentSessions = sessions;
    currentTeacherClassIds = new Set((classAssignmentsResult.data || []).map((item) => item.class_id));
    currentTeacherClassSessionMap = new Map(
      (classAssignmentsResult.data || []).map((item) => [
        item.class_id,
        sessions.find((sessionItem) => sessionItem.id === item.academic_session_id) || null
      ])
    );
    currentTeacherClassSessions = new Set((classAssignmentsResult.data || [])
      .map((item) => `${item.class_id}:${item.academic_session_id}`));
    currentTeacherSubjectOfferingIds = new Set(
      (subjectAssignmentsResult.data || []).map((item) => item.class_subject_offering_id)
    );
    const isSecondaryTeacher = currentTeacherRoles.has('secondary_class_teacher')
      || currentTeacherRoles.has('secondary_subject_teacher');
    currentClasses = profile.role === 'administrator' || !isSecondaryTeacher
      ? schoolClasses.filter((item) => profile.role === 'administrator' || currentTeacherClassIds.has(item.id))
      : schoolClasses.filter((item) => currentTeacherClassIds.has(item.id));
    const assignedSubjectClassIds = new Set(assignedSubjectClasses.map((item) => item.class_id));
    currentScoreClasses = profile.role === 'administrator'
      ? schoolClasses
      : schoolClasses.filter((item) => currentTeacherClassIds.has(item.id) || assignedSubjectClassIds.has(item.id));
    renderSetupList(
      document.querySelector('[data-session-list]'),
      sessions,
      profile.role === 'administrator' ? 'No academic sessions yet. Add one to start registering students.' : 'No academic sessions have been configured yet.',
      sessionRow
    );
    renderSetupList(
      document.querySelector('[data-school-class-list]'),
      profile.role === 'administrator' ? allClasses : currentClasses,
      profile.role === 'administrator' ? 'No classes yet. Add a class to start building the student register.' : 'No classes are assigned to your account yet.',
      schoolClassRow
    );
    document.querySelectorAll('[data-admin-only]').forEach((button) => {
      button.hidden = profile.role !== 'administrator';
    });
    document.querySelectorAll('[data-teacher-only]').forEach((item) => {
      item.hidden = profile.role === 'administrator';
    });
    document.querySelector('[data-menu-sign-out]')?.removeAttribute('hidden');
    const activeSessions = sessions.filter((item) => item.is_active && item.name !== '2027/2028');
    const session = activeSessions.find((item) => item.name === '2026/2027')
      || activeSessions.find((item) => item.is_current)
      || activeSessions[0]
      || null;
    const dashboardClasses = profile.role === 'administrator'
      ? schoolClasses
      : currentScoreClasses.filter((schoolClass) =>
        Boolean(session && (
          currentTeacherClassSessions.has(`${schoolClass.id}:${session.id}`)
          || assignedSubjectClasses.some((offering) =>
            offering.class_id === schoolClass.id && offering.academic_session_id === session.id)
        )));
    const dashboardClassSessions = new Map(
      dashboardClasses.map((schoolClass) => [schoolClass.id, session])
    );
    let enrollmentCounts = new Map();
    const dashboardClassSessionKeys = new Set(dashboardClasses
      .map((schoolClass) => {
        const classSession = dashboardClassSessions.get(schoolClass.id);
        return classSession ? `${schoolClass.id}:${classSession.id}` : '';
      })
      .filter(Boolean));
    dashboardClassSessionKeys.forEach((key) => enrollmentCounts.set(key, 0));
    const countSessionIds = [...new Set([...dashboardClassSessions.values()]
      .filter(Boolean)
      .filter((assignedSession) => dashboardClasses.some((schoolClass) =>
        dashboardClassSessionKeys.has(`${schoolClass.id}:${assignedSession.id}`)))
      .map((assignedSession) => assignedSession.id))];
    if (countSessionIds.length) {
      const { data: enrollments, error } = await supabase
        .from('class_enrollments')
        .select('class_id, academic_session_id, left_on')
        .in('academic_session_id', countSessionIds);
      if (requestId !== dataRequest) return;
      if (error) {
        setClassNotice(`Could not load class enrollment counts: ${error.message}`);
        console.error('Could not load class enrollment counts.', error);
        enrollmentCounts = null;
        document.querySelector('[data-metric="students"]').textContent = '—';
      } else {
        (enrollments || [])
          .filter((item) => !item.left_on
            && dashboardClassSessionKeys.has(`${item.class_id}:${item.academic_session_id}`))
          .forEach(({ class_id: classId, academic_session_id: sessionId }) => {
          const key = `${classId}:${sessionId}`;
          enrollmentCounts.set(key, (enrollmentCounts.get(key) || 0) + 1);
        });
        const totalStudents = [...enrollmentCounts.values()].reduce((total, count) => total + count, 0);
        document.querySelector('[data-metric="students"]').textContent = String(totalStudents);
        const classContext = document.querySelector('[data-dashboard-class-context]');
        classContext.textContent = profile.role === 'administrator'
          ? `${session?.name || 'Current session'} · current student enrollments`
          : `${session?.name || 'Current session'} · current enrollments in your assigned classes`;
        setClassNotice('');
      }
    } else {
      document.querySelector('[data-metric="students"]').textContent = session ? '0' : '—';
      const classContext = document.querySelector('[data-dashboard-class-context]');
      classContext.textContent = profile.role === 'administrator'
        ? `${session?.name || 'No active session'} · current student enrollments`
        : `${session?.name || 'No active session'} · current enrollments in your assigned classes`;
      setClassNotice(profile.role === 'administrator' && schoolClasses.length && !session
        ? 'Create an academic session to see current class enrollments.'
        : !session
          ? 'No active academic session is available for your assigned classes.'
          : '');
    }
    renderClassCards(dashboardClasses, session, enrollmentCounts, classCards, dashboardClassSessions);
    renderClassCards(dashboardClasses, session, enrollmentCounts, dashboardClassCards, dashboardClassSessions);

    [
      studentClassSelect, scoreClassSelect, masterClassSelect, resultClassSelect
    ].forEach(copyClassOptions);
    replaceSelectOptions(scoreClassSelect, currentScoreClasses, (item) => item.name);
    [
      studentSessionSelect, scoreSessionSelect, masterSessionSelect,
      resultSessionSelect
    ].forEach(copySessionOptions);
    void loadManagementData();
    if (!studentClassSelect.options.length || !studentSessionSelect.options.length) {
      renderStudents([]);
      renderClassCards(dashboardClasses, session, enrollmentCounts, classCards, dashboardClassSessions);
      await Promise.all([loadScoreScreen(), loadMasterSheet(), loadResultScreen()]);
      const missing = [
        !studentClassSelect.options.length ? (profile.role === 'administrator' ? 'a class' : 'an assigned class') : null,
        !studentSessionSelect.options.length ? 'an academic session' : null
      ].filter(Boolean).join(' and ');
      setStudentNotice(profile.role === 'administrator'
        ? `Create ${missing} in Sessions & Settings before registering students.`
        : `The student register needs ${missing}. Ask your administrator to configure it.`);
      return;
    }
    await Promise.all([
      loadStudentRows(requestId),
      loadScoreScreen(),
      loadMasterSheet(),
      loadResultScreen()
    ]);
  };

  const refreshLiveData = async (profile) => {
    const requestId = ++dataRequest;
    setDashboardNotice('Loading live school data…');
    void refreshDashboard(profile, requestId).catch((error) => {
      if (requestId === dataRequest) showDataError('Loading dashboard metrics', error, setDashboardNotice);
    });
    try {
      await loadStudentOptions(requestId);
    } catch (error) {
      if (requestId === dataRequest) {
        renderClassLoadError('Could not load your assigned classes. Ask the administrator to verify the teacher assignments.');
        showDataError('Loading classes and academic sessions', error, setStudentNotice);
      }
    }
  };

  studentClassSelect.addEventListener('change', () => {
    copySessionOptions(studentSessionSelect);
    if (!studentSessionSelect.value) {
      const assignedSession = currentTeacherClassSessionMap.get(studentClassSelect.value);
      if (assignedSession && assignedSession.name !== '2027/2028') {
        addSelectOption(studentSessionSelect, assignedSession.id, assignedSession.name);
      }
    }
    void loadStudentRows();
  });
  studentSessionSelect.addEventListener('change', () => void loadStudentRows());
  document.addEventListener('click', (event) => {
    const registerButton = event.target.closest('[data-class-register]');
    if (!registerButton) return;
    studentClassSelect.value = registerButton.dataset.classRegister;
    copySessionOptions(studentSessionSelect);
    if (![...studentSessionSelect.options].some((option) => option.value === registerButton.dataset.sessionId)) {
      const assignedSession = currentSessions.find((item) => item.id === registerButton.dataset.sessionId);
      if (assignedSession && assignedSession.name !== '2027/2028') {
        addSelectOption(studentSessionSelect, assignedSession.id, assignedSession.name);
      }
    }
    if (![...studentSessionSelect.options].some((option) => option.value === registerButton.dataset.sessionId)) return;
    studentSessionSelect.value = registerButton.dataset.sessionId;
    showPage('students');
    void loadStudentRows();
  });
  document.addEventListener('click', (event) => {
    const subjectButton = event.target.closest('[data-subject-offering]');
    if (!subjectButton) return;
    const offering = currentTeacherSubjectOfferings.find((item) => item.id === subjectButton.dataset.subjectOffering);
    if (!offering) return;
    scoreClassSelect.value = offering.class_id;
    scoreSessionSelect.value = offering.academic_session_id;
    pendingScoreClassId = offering.class_id;
    pendingScoreSessionId = offering.academic_session_id;
    pendingScoreOfferingId = offering.id;
    pendingScoreTermId = offering.term_id || '';
    showPage('scores');
    void loadScoreScreen().then(() => {
      return undefined;
    });
  });
  document.querySelector('[data-open-student-form]').addEventListener('click', async () => {
    if (!studentClassSelect.value || !studentSessionSelect.value) {
      showToast('Create an academic session and class before registering students.');
      return;
    }
    if (currentProfile?.role !== 'administrator') {
      const { data: canManage, error } = await supabase.rpc('can_manage_class_register', {
        p_class_id: studentClassSelect.value,
        p_academic_session_id: studentSessionSelect.value
      });
      if (error) {
        showDataError('Checking register permission', error, setStudentNotice);
        return;
      }
      if (!canManage) {
        setStudentNotice('Your administrator has not granted you permission to edit this class register.');
        return;
      }
    }
    studentFormMessage.textContent = '';
    editingStudentId = '';
    document.querySelector('#student-dialog-title').textContent = 'Register student';
    studentForm.querySelector('.muted-text').textContent = 'Student and class enrollment will be saved together.';
    studentForm.querySelector('[type="submit"]').textContent = 'Save student';
    studentDialog.showModal();
    studentForm.querySelector('[name="first_name"]').focus();
  });
  studentTableBody.addEventListener('click', async (event) => {
    const deleteButton = event.target.closest('[data-delete-student]');
    if (deleteButton) {
      if (!studentRegisterCanManage) return;
      const enrollment = currentStudents.find((item) => item.students?.id === deleteButton.dataset.deleteStudent);
      const student = enrollment?.students;
      if (!student) return;
      const fullName = [student.first_name, student.other_names, student.last_name].filter(Boolean).join(' ');
      const confirmed = window.confirm(
        `Permanently delete ${fullName} and all of their class enrollments? This cannot be undone. Students with saved results cannot be deleted.`
      );
      if (!confirmed) return;

      deleteButton.disabled = true;
      deleteButton.textContent = 'Deleting…';
      try {
        const { error } = await supabase.rpc('delete_registered_student', {
          p_student_id: student.id,
          p_class_id: studentClassSelect.value,
          p_academic_session_id: studentSessionSelect.value
        });
        if (error) throw error;
        showToast('Student deleted permanently.');
        await Promise.all([
          loadStudentRows(),
          refreshDashboard(currentProfile, dataRequest)
        ]);
      } catch (error) {
        showDataError('Deleting the student', error, setStudentNotice);
        deleteButton.disabled = false;
        deleteButton.textContent = 'Delete';
      }
      return;
    }

    const editButton = event.target.closest('[data-edit-student]');
    if (!editButton || !studentRegisterCanManage) return;
    const enrollment = currentStudents.find((item) => item.students?.id === editButton.dataset.editStudent);
    const student = enrollment?.students;
    if (!student) return;
    editingStudentId = student.id;
    studentForm.querySelector('[name="first_name"]').value = student.first_name || '';
    studentForm.querySelector('[name="last_name"]').value = student.last_name || '';
    studentForm.querySelector('[name="other_names"]').value = student.other_names || '';
    studentForm.querySelector('[name="admission_number"]').value = student.admission_number || '';
    studentForm.querySelector('[name="gender"]').value = student.gender || '';
    studentForm.querySelector('[name="date_of_birth"]').value = student.date_of_birth || '';
    document.querySelector('#student-dialog-title').textContent = 'Edit student';
    studentForm.querySelector('.muted-text').textContent = 'Correct this student’s register details.';
    studentForm.querySelector('[type="submit"]').textContent = 'Save changes';
    studentFormMessage.textContent = '';
    studentDialog.showModal();
  });
  document.querySelectorAll('[data-close-student-dialog]').forEach((button) => {
    button.addEventListener('click', () => studentDialog.close());
  });
  document.querySelector('[data-open-session-form]').addEventListener('click', () => {
    document.querySelector('[data-session-form-message]').textContent = '';
    document.querySelector('#session-dialog').showModal();
  });
  document.querySelector('[data-open-class-form]').addEventListener('click', () => {
    document.querySelector('[data-class-form-message]').textContent = '';
    document.querySelector('#class-dialog').showModal();
  });
  document.querySelectorAll('[data-close-session-dialog]').forEach((button) => {
    button.addEventListener('click', () => document.querySelector('#session-dialog').close());
  });
  document.querySelectorAll('[data-close-session-edit]').forEach((button) => {
    button.addEventListener('click', () => document.querySelector('#session-edit-dialog').close());
  });
  document.querySelectorAll('[data-close-class-dialog]').forEach((button) => {
    button.addEventListener('click', () => document.querySelector('#class-dialog').close());
  });

  document.querySelector('#session-edit-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (currentProfile?.role !== 'administrator') return;
    const form = event.currentTarget;
    const values = new FormData(form);
    const submit = form.querySelector('[type="submit"]');
    const message = document.querySelector('[data-session-edit-message]');
    submit.disabled = true;
    try {
      const { error } = await supabase.rpc('admin_update_academic_session', {
        p_session_id: values.get('id'),
        p_name: String(values.get('name')).trim(),
        p_starts_on: values.get('starts_on'),
        p_ends_on: values.get('ends_on'),
        p_active_term: Number(values.get('active_term')),
        p_make_current: values.get('make_current') === 'on'
      });
      if (error) throw error;
      document.querySelector('#session-edit-dialog').close();
      showToast('Academic session updated.');
      await refreshLiveData(currentProfile);
    } catch (error) {
      showDataError('Updating the academic session', error, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
    }
  });

  document.querySelector('#session-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (currentProfile?.role !== 'administrator') return;
    const form = event.currentTarget;
    const formData = new FormData(form);
    const message = document.querySelector('[data-session-form-message]');
    const submit = form.querySelector('[type="submit"]');
    submit.disabled = true;
    submit.textContent = 'Saving…';
    message.textContent = '';
    try {
      const { error } = await supabase.rpc('create_academic_session', {
        p_name: String(formData.get('name')).trim(),
        p_starts_on: formData.get('starts_on'),
        p_ends_on: formData.get('ends_on'),
        p_active_term: Number(formData.get('active_term')),
        p_make_current: formData.get('make_current') === 'on'
      });
      if (error) {
        console.error('Academic session creation failed.', error);
        message.textContent = error.code === '42501'
          ? 'Only an active administrator can create academic sessions.'
          : error.code === '23505'
            ? 'A session with that name already exists.'
            : error.message || 'Could not create the academic session.';
        return;
      }
      document.querySelector('#session-dialog').close();
      form.reset();
      showToast('Academic session and its terms were created.');
      await refreshLiveData(currentProfile);
    } catch (error) {
      showDataError('Creating the academic session', error, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
      submit.textContent = 'Save session';
    }
  });

  document.querySelector('#class-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (currentProfile?.role !== 'administrator') return;
    const form = event.currentTarget;
    const formData = new FormData(form);
    const message = document.querySelector('[data-class-form-message]');
    const submit = form.querySelector('[type="submit"]');
    submit.disabled = true;
    submit.textContent = 'Saving…';
    message.textContent = '';
    try {
      const { error } = await supabase.from('classes').insert({
        name: String(formData.get('name')).trim(),
        stage: formData.get('stage')
      });
      if (error) {
        console.error('Class creation failed.', error);
        message.textContent = error.code === '42501'
          ? 'Only an active administrator can create classes.'
          : error.code === '23505'
            ? 'A class with that name and stage already exists.'
            : error.message || 'Could not create the class.';
        return;
      }
      document.querySelector('#class-dialog').close();
      form.reset();
      showToast('Class created.');
      await refreshLiveData(currentProfile);
    } catch (error) {
      showDataError('Creating the class', error, (text) => { message.textContent = text; });
    } finally {
      submit.disabled = false;
      submit.textContent = 'Save class';
    }
  });

  studentForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!supabase || !studentClassSelect.value || !studentSessionSelect.value) return;
    const formData = new FormData(studentForm);
    const submitButton = studentForm.querySelector('[type="submit"]');
    submitButton.disabled = true;
    submitButton.textContent = 'Saving…';
    studentFormMessage.textContent = '';
    try {
      if (editingStudentId) {
        const { error } = await supabase.rpc('update_registered_student', {
          p_student_id: editingStudentId,
          p_admission_number: String(formData.get('admission_number')).trim(),
          p_first_name: String(formData.get('first_name')).trim(),
          p_last_name: String(formData.get('last_name')).trim(),
          p_other_names: String(formData.get('other_names')).trim() || null,
          p_gender: String(formData.get('gender')) || null,
          p_date_of_birth: String(formData.get('date_of_birth')) || null
        });
        if (error) throw error;
        studentDialog.close();
        editingStudentId = '';
        studentForm.reset();
        showToast('Student details updated successfully.');
        await loadStudentRows();
        return;
      }
      const { error } = await supabase.rpc('register_student', {
        p_admission_number: String(formData.get('admission_number')).trim(),
        p_first_name: String(formData.get('first_name')).trim(),
        p_last_name: String(formData.get('last_name')).trim(),
        p_class_id: studentClassSelect.value,
        p_academic_session_id: studentSessionSelect.value,
        p_other_names: String(formData.get('other_names')).trim() || null,
        p_gender: String(formData.get('gender')) || null,
        p_date_of_birth: String(formData.get('date_of_birth')) || null
      });
      if (error) {
        console.error('Student registration failed.', error);
        studentFormMessage.textContent = error.code === '42501'
          ? 'Your account does not have permission to register students in this class.'
          : error.code === '23505'
            ? 'That admission number is already in use.'
            : error.message || 'Student registration failed. Please try again.';
        return;
      }
      studentDialog.close();
      studentForm.reset();
      showToast('Student registered and enrolled successfully.');
      await Promise.all([loadStudentRows(), refreshDashboard(currentProfile, dataRequest)]);
    } catch (error) {
      showDataError('Registering the student', error, (message) => { studentFormMessage.textContent = message; });
    } finally {
      submitButton.disabled = false;
      submitButton.textContent = 'Save student';
    }
  });

  document.querySelector('[data-export-students]').addEventListener('click', () => {
    const visibleStudents = currentStudents.filter(({ students: student }) => {
      if (!student) return false;
      const search = document.querySelector('[data-filter="students-table"]').value.trim().toLocaleLowerCase();
      return !search || [student.first_name, student.other_names, student.last_name, student.admission_number]
        .filter(Boolean).join(' ').toLocaleLowerCase().includes(search);
    });
    if (!visibleStudents.length) {
      showToast('There are no students to export for this class and session.');
      return;
    }
    const csvValue = (value) => `"${String(value ?? '').replaceAll('"', '""')}"`;
    const csv = [
      ['Admission number', 'First name', 'Other names', 'Last name', 'Gender', 'Enrolled on'],
      ...visibleStudents.map(({ enrolled_on: enrolledOn, students: student }) =>
        [student.admission_number, student.first_name, student.other_names, student.last_name, student.gender, enrolledOn])
    ].map((row) => row.map(csvValue).join(',')).join('\r\n');
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = 'student-register.csv';
    link.click();
    URL.revokeObjectURL(url);
  });

  const gradeFor = (score) => {
    if (score >= 80) return ['A', 'success'];
    if (score >= 70) return ['B', 'info'];
    if (score >= 60) return ['C', 'warning'];
    if (score >= 50) return ['D', 'muted'];
    return ['F', 'danger'];
  };

  const updateScoreRow = (row) => {
    const ca = row.querySelector('.ca-score');
    const test = row.querySelector('.test-score');
    const exam = row.querySelector('.exam-score');
    const inputs = [ca, test, exam];
    let invalid = false;

    inputs.forEach((input) => {
      const value = input.value === '' ? null : Number(input.value);
      const max = Number(input.max);
      const isInvalid = value !== null && (!Number.isFinite(value) || value < 0 || value > max);
      input.classList.toggle('invalid', isInvalid);
      input.setAttribute('aria-invalid', String(isInvalid));
      invalid ||= isInvalid;
    });

    const complete = inputs.every((input) => input.value !== '');
    const workCell = row.querySelector('.work-total');
    const totalCell = row.querySelector('.subject-total');
    const gradeCell = row.querySelector('.grade-cell');
    if (invalid) {
      workCell.textContent = '—';
      totalCell.textContent = '—';
      gradeCell.innerHTML = '<span class="badge danger">Invalid</span>';
      return false;
    }
    if (!complete) {
      workCell.textContent = '—';
      totalCell.textContent = '—';
      gradeCell.innerHTML = '<span class="badge muted">Missing</span>';
      return true;
    }

    const work = Number(ca.value) + Number(test.value);
    const total = work + Number(exam.value);
    const [grade, badgeClass] = gradeFor(total);
    workCell.textContent = String(work);
    totalCell.textContent = String(total);
    gradeCell.innerHTML = `<span class="badge ${badgeClass}">${grade}</span>`;
    return true;
  };

  document.querySelectorAll('.score-entry-table tbody tr').forEach((row) => {
    row.querySelectorAll('.score-input').forEach((input) => {
      input.addEventListener('input', () => {
        updateScoreRow(row);
        const formMessage = document.querySelector('.form-message');
        if (formMessage) {
          formMessage.textContent = row.querySelector('.score-input.invalid')
            ? 'Enter a score within the configured maximum.'
            : '';
        }
      });
    });
  });

  const roleDetails = {
    'secondary-subject': {
      title: 'Secondary School — Subject Teacher',
      description: 'Access is limited to assigned classes and subjects.',
      values: [false, false, false]
    },
    'secondary-class': {
      title: 'Secondary School — Class Teacher',
      description: 'Review the assigned class register and compiled results; score editing requires an explicit grant.',
      values: [false, false, false]
    },
    primary: {
      title: 'Primary / Nursery Teacher',
      description: 'Manage the assigned class register and all subjects for that class, subject to result status.',
      values: [false, false, false]
    }
  };
  const permissionTitle = document.querySelector('#permission-role-title');
  const permissionDescription = document.querySelector('#permission-role-description');
  const permissionInputs = [...document.querySelectorAll('.permission-list input')];
  const permissionTeacher = document.querySelector('[data-permission-teacher]');
  const permissionMessage = document.querySelector('[data-permission-message]');
  let selectedTeacherRoles = new Set();
  const permissionRoleRules = {
    'secondary-subject': { roles: ['secondary_subject_teacher'], allowed: ['results.read', 'results.edit'] },
    'secondary-class': { roles: ['secondary_class_teacher'], allowed: ['register.manage', 'results.read'] },
    primary: { roles: ['primary_teacher'], allowed: ['register.manage', 'results.read', 'results.edit'] },
    nursery: { roles: ['nursery_teacher'], allowed: ['register.manage', 'results.read', 'results.edit'] }
  };
  const getTeacherAllowedPermissions = () => {
    const allowed = new Set();
    Object.values(permissionRoleRules).forEach((rule) => {
      if (rule.roles.some((role) => selectedTeacherRoles.has(role))) {
        rule.allowed.forEach((permission) => allowed.add(permission));
      }
    });
    return allowed;
  };
  const refreshPermissionRoleUI = () => {
    const allowed = getTeacherAllowedPermissions();
    permissionInputs.forEach((input) => {
      const enabled = allowed.has(input.dataset.permissionKey);
      input.disabled = !enabled;
      if (!enabled) input.checked = false;
      input.closest('label')?.classList.toggle('is-disabled', !enabled);
    });
    document.querySelectorAll('.role-tab').forEach((tab) => {
      const rule = permissionRoleRules[tab.dataset.role];
      const visible = rule?.roles.some((role) => selectedTeacherRoles.has(role));
      tab.hidden = !visible;
      tab.disabled = !visible;
    });
    const activeTab = [...document.querySelectorAll('.role-tab')].find((tab) => !tab.hidden);
    if (activeTab && !activeTab.classList.contains('active')) activeTab.click();
  };
  const loadPermissions = async () => {
    if (!permissionTeacher?.value) {
      permissionInputs.forEach((input) => { input.checked = false; });
      return;
    }
    const [{ data, error }, { data: roleRows, error: roleError }] = await Promise.all([
      supabase
      .from('user_permission_overrides')
      .select('permission_key, allowed')
      .eq('user_id', permissionTeacher.value)
      .is('class_id', null)
      .is('subject_id', null)
      .is('academic_session_id', null),
      supabase.from('teacher_roles').select('role').eq('teacher_id', permissionTeacher.value)
    ]);
    if (error || roleError) {
      permissionMessage.textContent = `Could not load permissions: ${(error || roleError).message}`;
      return;
    }
    selectedTeacherRoles = new Set((roleRows || []).map((row) => row.role));
    refreshPermissionRoleUI();
    const saved = new Map((data || []).map((item) => [item.permission_key, item.allowed]));
    permissionInputs.forEach((input) => {
      input.checked = !input.disabled && saved.get(input.dataset.permissionKey) === true;
    });
    permissionMessage.textContent = '';
  };
  document.querySelector('[data-save-permissions]')?.addEventListener('click', async () => {
    if (currentProfile?.role !== 'administrator' || !permissionTeacher?.value) return;
    const permissions = permissionInputs.map((input) => ({
      permission_key: input.dataset.permissionKey,
      allowed: !input.disabled && input.checked
    }));
    const button = document.querySelector('[data-save-permissions]');
    button.disabled = true;
    permissionMessage.textContent = 'Saving permissions…';
    try {
      const { error } = await supabase.rpc('admin_set_user_permissions', {
        p_user_id: permissionTeacher.value,
        p_permissions: permissions
      });
      if (error) throw error;
      permissionMessage.textContent = 'Permissions saved and enforced for this teacher.';
    } catch (error) {
      showDataError('Saving permissions', error, (text) => { permissionMessage.textContent = text; });
    } finally {
      button.disabled = false;
    }
  });
  document.querySelectorAll('.role-tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.role-tab').forEach((roleTab) => {
        const selected = roleTab === tab;
        roleTab.classList.toggle('active', selected);
        roleTab.setAttribute('aria-selected', String(selected));
      });
      const details = roleDetails[tab.dataset.role];
      if (!details) return;
      permissionTitle.textContent = details.title;
      permissionDescription.textContent = details.description;
      void loadPermissions();
    });
  });
  permissionTeacher?.addEventListener('change', () => void loadPermissions());

  document.querySelectorAll('.management-tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.management-tab').forEach((item) => item.classList.toggle('active', item === tab));
      document.querySelectorAll('.management-panel').forEach((panel) => {
        panel.hidden = panel.id !== tab.dataset.panel;
      });
    });
  });

  const setAuthMessage = (message, state = 'error') => {
    loginMessage.textContent = message;
    loginMessage.dataset.state = state;
    loginMessage.hidden = !message;
  };

  const invokeTeacherManagement = async (body) => {
    const invoke = () => supabase.functions.invoke('admin-teacher-management', { body });
    const refreshAdministratorSession = async () => {
      const { data, error } = await supabase.auth.refreshSession();
      if (error || !data.session) {
        lockApp('Your administrator session has expired. Sign in again to continue.');
        throw new Error('Your administrator session has expired. Sign in again to continue.');
      }
      await loadProfile(data.session);
      return data.session;
    };

    const { data: sessionData } = await supabase.auth.getSession();
    let session = sessionData.session;
    if (!session || (session.expires_at && session.expires_at * 1000 <= Date.now() + 30_000)) {
      session = await refreshAdministratorSession();
    }
    let response = await invoke();
    if (response.error?.context?.status === 401) {
      await refreshAdministratorSession();
      response = await invoke();
    }
    return response;
  };

  const setAuthenticatedUser = (profile) => {
    currentProfile = profile;
    const displayName = profile.full_name || 'School user';
    const displayRole = profile.role.replaceAll('_', ' ');
    userName.textContent = displayName;
    userRole.textContent = displayRole;
    userAvatar.textContent = displayName.trim().charAt(0).toLocaleUpperCase();
    signOutButton.textContent = 'Sign out';
    signOutButton.dataset.authenticated = 'true';
    document.body.classList.remove('auth-required');
    document.querySelectorAll('[data-teacher-only]').forEach((item) => {
      item.hidden = profile.role === 'administrator';
    });
    loginOverlay.hidden = true;
    setAuthMessage('');
    void refreshLiveData(profile);
  };

  const lockApp = (message) => {
    currentProfile = null;
    dataRequest += 1;
    currentStudents = [];
    studentClassSelect.replaceChildren();
    studentSessionSelect.replaceChildren();
    studentTableBody.replaceChildren();
    document.querySelectorAll('[data-metric]').forEach((metric) => { metric.textContent = '—'; });
    document.body.classList.add('auth-required');
    loginOverlay.hidden = false;
    userName.textContent = 'Sign in required';
    userRole.textContent = 'Supabase authentication';
    userAvatar.textContent = '?';
    signOutButton.textContent = 'Sign in';
    delete signOutButton.dataset.authenticated;
    document.querySelectorAll('[data-admin-only]').forEach((button) => { button.hidden = true; });
    document.querySelectorAll('[data-teacher-only]').forEach((item) => { item.hidden = true; });
    document.querySelector('[data-menu-sign-out]')?.setAttribute('hidden', '');
    setAuthMessage(message || '');
  };

  document.querySelectorAll('[data-password-toggle]').forEach((toggle) => {
    toggle.addEventListener('click', () => {
      const input = toggle.closest('.password-input-wrap')?.querySelector('input');
      if (!input) return;
      const showPassword = input.type === 'password';
      input.type = showPassword ? 'text' : 'password';
      toggle.classList.toggle('is-visible', showPassword);
      toggle.setAttribute('aria-label', `${showPassword ? 'Hide' : 'Show'} password`);
      toggle.setAttribute('aria-pressed', String(showPassword));
      input.focus();
    });
  });

  const loadProfile = async (session) => {
    const requestId = ++profileRequest;
    if (!session?.user) {
      lockApp('');
      sessionSignOutButton.hidden = true;
      return;
    }

    setAuthMessage('Checking your school account…', 'loading');
    sessionSignOutButton.hidden = false;

    let profile;
    let error;
    try {
      ({ data: profile, error } = await supabase
        .from('profiles')
        .select('id, full_name, role, is_active, must_change_password')
        .eq('id', session.user.id)
        .maybeSingle());
    } catch (requestError) {
      if (requestId !== profileRequest) return;
      console.error('Could not reach Supabase while loading the school profile.', requestError);
      lockApp('Could not connect to the school database. Check your connection and try again.');
      return;
    }

    if (requestId !== profileRequest) return;

    if (error) {
      lockApp(
        error.code === 'PGRST205' || error.code === '42P01'
          ? 'The school database schema is not installed yet. Apply the Supabase migrations, then try again.'
          : 'Could not load your school account. Check that the database migrations and profile permissions are set up.'
      );
      return;
    }

    if (!profile) {
      lockApp('Your sign-in worked, but no school profile is assigned to this account. Ask an administrator to create your profile.');
      return;
    }

    if (!profile.is_active) {
      lockApp('This school account is inactive. Ask an administrator for help.');
      return;
    }

    setAuthenticatedUser(profile);
    if (profile.must_change_password) {
      document.querySelector('[data-password-setup-message]').textContent = '';
      const passwordDialog = document.querySelector('#password-setup-dialog');
      if (!passwordDialog.open) passwordDialog.showModal();
    }
  };

  document.querySelector('[data-login-close]')?.addEventListener('click', () => {
    if (!document.body.classList.contains('auth-required')) loginOverlay.hidden = true;
  });
  loginOverlay.addEventListener('click', (event) => {
    if (event.target === loginOverlay && !document.body.classList.contains('auth-required')) {
      loginOverlay.hidden = true;
    }
  });

  const signOut = async () => {
    if (!supabase) return;
    try {
      const { error } = await supabase.auth.signOut();
      if (error) {
        console.error('Supabase sign-out failed.', error);
        setAuthMessage('Sign out failed. Please try again.');
        showToast('Could not sign out. Please try again.');
        return;
      }
      lockApp('');
    } catch (requestError) {
      console.error('Could not reach Supabase while signing out.', requestError);
      setAuthMessage('Sign out failed. Please try again.');
      showToast('Could not sign out. Please try again.');
    }
  };

  signOutButton.addEventListener('click', () => {
    if (signOutButton.dataset.authenticated === 'true') {
      void signOut();
    } else {
      loginOverlay.hidden = false;
      document.querySelector('#login-email').focus();
    }
  });
  sessionSignOutButton.addEventListener('click', () => void signOut());

  loginForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!supabase) {
      setAuthMessage(supabaseConfigError);
      return;
    }

    loginSubmit.disabled = true;
    loginSubmit.textContent = 'Signing in…';
    setAuthMessage('');
    const email = document.querySelector('#login-email').value.trim();
    const password = document.querySelector('#login-password').value;
    try {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) {
        console.error('Supabase sign-in failed.', error);
        setAuthMessage(error.message === 'Invalid login credentials'
          ? 'Email or password is incorrect.'
          : 'Sign in failed. Check the email provider settings and try again.');
        return;
      }

      if (data.session) {
        await loadProfile(data.session);
      } else {
        setAuthMessage('Supabase did not return an active session. Please try again.');
      }
    } catch (requestError) {
      console.error('Could not reach Supabase while signing in.', requestError);
      setAuthMessage('Could not connect to Supabase. Check your connection and try again.');
    } finally {
      loginSubmit.disabled = false;
      loginSubmit.textContent = 'Sign in';
    }
  });

  showPage('dashboard');
  if (!supabase) {
    lockApp(supabaseConfigError);
    loginSubmit.disabled = true;
  } else {
    const { data: authSubscription } = supabase.auth.onAuthStateChange((_event, session) => {
      window.setTimeout(() => void loadProfile(session), 0);
    });
    window.addEventListener('pagehide', () => authSubscription.subscription.unsubscribe(), { once: true });
    setAuthMessage('Checking Supabase connection…', 'loading');
  }
});
