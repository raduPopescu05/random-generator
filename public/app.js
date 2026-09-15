const buttons = document.querySelectorAll('.generate-button');
const historyBody = document.getElementById('history-body');
const historyStatus = document.getElementById('history-status');

const formatType = (type) => type.replaceAll('-', ' ');

const formatDate = (value) => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Unknown';
  return date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
};

const renderHistory = (generations) => {
  historyBody.replaceChildren();

  if (!generations.length) {
    const row = document.createElement('tr');
    row.className = 'history-empty';
    const cell = document.createElement('td');
    cell.colSpan = 3;
    cell.textContent = 'No generations yet. Try one of the generators above.';
    row.append(cell);
    historyBody.append(row);
    return;
  }

  generations.forEach((generation) => {
    const row = document.createElement('tr');
    const typeCell = document.createElement('td');
    const typeBadge = document.createElement('span');
    typeBadge.className = `type-badge type-${generation.type}`;
    typeBadge.textContent = formatType(generation.type);
    typeCell.append(typeBadge);

    const valueCell = document.createElement('td');
    valueCell.className = 'history-value';
    valueCell.textContent = generation.value;

    const dateCell = document.createElement('td');
    dateCell.className = 'history-date';
    dateCell.textContent = formatDate(generation.created_at);

    row.append(typeCell, valueCell, dateCell);
    historyBody.append(row);
  });
};

const loadHistory = async () => {
  historyStatus.textContent = 'Loading history...';
  try {
    const response = await fetch('/history?limit=10');
    if (!response.ok) throw new Error('History request failed');
    const data = await response.json();
    renderHistory(Array.isArray(data.generations) ? data.generations : []);
    historyStatus.textContent = `${data.generations?.length ?? 0} most recent`;
  } catch {
    historyBody.replaceChildren();
    const row = document.createElement('tr');
    row.className = 'history-empty history-error';
    const cell = document.createElement('td');
    cell.colSpan = 3;
    cell.textContent = 'History is unavailable right now.';
    row.append(cell);
    historyBody.append(row);
    historyStatus.textContent = 'Unable to load';
  }
};

buttons.forEach((button) => {
  button.addEventListener('click', async () => {
    const result = document.getElementById(button.dataset.target);
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');

    try {
      const response = await fetch(button.dataset.endpoint);
      if (!response.ok) throw new Error('Request failed');
      const data = await response.json();
      result.textContent = data.value;
      result.classList.remove('is-new');
      void result.offsetWidth;
      result.classList.add('is-new');
      await loadHistory();
    } catch {
      result.textContent = 'Oops';
    } finally {
      button.disabled = false;
      button.removeAttribute('aria-busy');
    }
  });
});

loadHistory();
