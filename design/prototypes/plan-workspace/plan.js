/* Local presentation fixtures only. This is not the product Plan state machine. */
(() => {
  'use strict';
  const scenarios = {
    workspace: { name: '会话中的计划卡', state: 'awaiting', confirm: true, workspace: true, width: 1200, height: 820, note: '计划卡负责查看与收起，反馈栏负责决定。待确认期间不显示工具等待条或交互详情；关闭正文保留意见。' },
    drafting: { name: '起草中', state: 'drafting', empty: true, note: '没有文档时只展示真实状态，不伪造正文或批准状态。' },
    awaiting: { name: '等待确认', state: 'awaiting', confirm: true, note: '详情只读；批准与提交修改仅位于底部反馈栏。' },
    feedback: { name: '填写修改意见', state: 'awaiting', confirm: true, feedback: true, note: '修改意见非空后开放提交；批准计划始终是明确的主操作。' },
    submitting: { name: '正在提交', state: 'awaiting', confirm: true, feedback: true, busy: true, note: '提交时保持输入与按钮位置，禁止重复决定，等待权威状态更新。' },
    error: { name: '提交失败', state: 'awaiting', confirm: true, feedback: true, error: true, note: '保留原意见，展示实际错误，允许重试；不靠清空或静默重试隐藏失败。' },
    revision: { name: '已请求修改', state: 'revision', note: '当前正文是已提交的版本，修改完成后重新确认；不显示审批操作。' },
    approved: { name: '已批准', state: 'approved', note: '获批后可只读重开，普通输入栏由会话恢复，计划内不再放确认操作。' },
    full: { name: '全宽阅读', state: 'approved', full: true, width: 1040, note: '头部动作靠右；正文占满实际阅读区域。' },
    narrow: { name: '窄窗口', state: 'awaiting', confirm: true, width: 360, height: 760, note: '宽度来自父组件；标题、状态与动作组自然换行，输入和按钮共用右边界。' },
    large: { name: '窄窗大字', state: 'awaiting', confirm: true, width: 360, height: 900, scale: 1.5, note: '文字放大后完整显示必要提示，操作换行，不缩小字号或命中区。' },
    short: { name: '短窗口', state: 'awaiting', confirm: true, width: 640, height: 480, note: '阅读与反馈区各自可滚动；短窗仍能访问计划和两项决定。' },
    history: { name: '历史回执', history: true, note: '冻结原版本、决定与反馈；只读展开，不提供批准或编辑入口。' }
  };
  const states = {
    drafting: { label: '起草中', icon: 'revise' },
    awaiting: { label: '等待确认', icon: 'clock' },
    revision: { label: '已请求修改', icon: 'revise' },
    approved: { label: '已批准', icon: 'check' }
  };
  const feedback = '请先保留当前选中的会话，再补充空结果提示。';
  const error = '提交失败，请重试。';
  const documentBody = `
    <h1>优化项目搜索体验</h1>
    <p>让项目与会话更容易查找，并保留当前阅读位置。</p>
    <h2>实施范围</h2>
    <ul><li>搜索时同时匹配项目名与会话标题。</li><li>保留最近使用的项目与当前选中会话。</li><li>覆盖空结果、长名称和窄窗口。</li></ul>
    <h2>实施步骤</h2>
    <ol><li>整理现有搜索入口与交互。</li><li>统一搜索结果和选中反馈。</li><li>验证键盘操作与窗口缩放。</li></ol>
    <h2>验证方式</h2>
    <p>检查搜索、切换和清空后的阅读位置，确保结果清楚、操作可达。</p>`;
  const icon = (name) => `<svg class="pw-icon" aria-hidden="true"><use href="#pw-${name}"></use></svg>`;
  const stage = document.querySelector('#plan-stage');
  const nav = document.querySelector('.pw-scenes');
  const params = new URLSearchParams(location.search);
  if (params.get('embed') === '1') document.body.classList.add('pw-embed');

  function render(key, draftOverride, fullOverride) {
    const scene = { ...scenarios[key] };
    scene.full = fullOverride ?? scene.full;
    if (scene.full) scene.width = 1040;
    else if (key === 'full') scene.width = 760;
    stage.style.width = `${scene.width || 760}px`;
    stage.style.height = `${scene.height || 720}px`;
    stage.style.setProperty('--pw-font-scale', scene.scale || 1);
    stage.toggleAttribute('data-narrow', (scene.width || 760) < 520);
    stage.toggleAttribute('data-short', (scene.height || 720) < 520);
    stage.classList.toggle('pw-workspace', !!scene.workspace);
    document.querySelector('#scene-name').textContent = scene.name;
    document.querySelector('#scene-note').textContent = scene.note;
    nav.innerHTML = Object.entries(scenarios).map(([id, value]) =>
      `<a href="?scenario=${id}" ${id === key ? 'aria-current="page"' : ''}>${value.name}</a>`).join('');
    nav.querySelectorAll('a').forEach((link) => link.addEventListener('click', (event) => {
      event.preventDefault();
      const id = new URL(link.href).searchParams.get('scenario');
      const url = new URL(location.href);
      url.searchParams.set('scenario', id);
      history.replaceState(null, '', url);
      render(id);
    }));
    if (scene.history) {
      stage.innerHTML = `<div class="pw-receipts">${[
        ['计划已批准', 'check', '你的回复', '已批准此计划并开始执行', true],
        ['已请求修改计划', 'revise', '你的修改意见', feedback, false],
        ['计划确认已取消', 'close', '', '', false],
        ['计划确认已回答', 'document', '', '', false]
      ].map(([label, glyph, replyLabel, reply, open], index) => `
        <details class="pw-receipt" ${open ? 'open' : ''}>
          <summary>${icon(glyph)}<span>${label}</span><small>v${index + 1}</small>${icon('down')}</summary>
          <article class="pw-document">${documentBody}${reply ? `<div class="pw-reply"><strong>${replyLabel}</strong>${reply}</div>` : ''}</article>
        </details>`).join('')}</div>`;
      return;
    }
    const state = states[scene.state];
    stage.innerHTML = `
      <section class="pw-sheet" aria-label="实施计划">
        <header class="pw-header">
          <div class="pw-header-title">${icon('document')}<h2>实施计划</h2>
            <span class="pw-badge" data-state="${scene.state}">${icon(state.icon)}${state.label}</span>
          </div>
          <div class="pw-header-actions">
            <button class="pw-icon-button" data-mode title="${scene.full ? '恢复并排' : '展开阅读'}" aria-label="${scene.full ? '恢复并排' : '展开阅读'}">${icon(scene.full ? 'split' : 'expand')}</button>
            <button class="pw-icon-button" data-close title="关闭" aria-label="关闭">${icon('close')}</button>
          </div>
        </header>
        <div class="pw-document-scroll">${scene.empty
          ? ''
          : `<article class="pw-document">${documentBody}</article>`}
        </div>
      </section>
      ${scene.confirm ? `
        <form class="pw-confirm">
          <label class="pw-field-label" for="plan-feedback">修改意见</label>
          <textarea class="pw-feedback" id="plan-feedback" rows="2" placeholder="写下你希望调整的内容…" ${scene.busy ? 'disabled' : ''}>${scene.feedback ? feedback : ''}</textarea>
          ${scene.error ? `<p class="pw-error" role="alert">${icon('alert')}<span>${error}</span></p>` : ''}
          <footer class="pw-confirm-footer">
            ${scene.busy ? '<p class="pw-hint" role="status"><span class="pw-spinner"></span>正在提交决定…</p>' : ''}
            <div class="pw-actions">
              <button class="pw-action" type="submit" data-revise ${scene.feedback && !scene.busy ? '' : 'disabled'}>${icon('send')}提交修改</button>
              <button class="pw-action pw-action-primary" type="button" data-approve ${scene.busy ? 'disabled' : ''}>${icon('check')}批准计划</button>
            </div>
          </footer>
        </form>` : ''}`;
    if (scene.workspace) {
      const sheet = stage.querySelector('.pw-sheet');
      sheet.id = 'workspace-plan';
      const conversation = document.createElement('section');
      conversation.className = 'pw-conversation';
      conversation.setAttribute('aria-label', '会话');
      conversation.innerHTML = `
        <header class="pw-conversation-header"><strong>优化项目搜索体验</strong><span>任务 · 主智能体</span></header>
        <div class="pw-conversation-scroll">
          <p class="pw-user-message">让搜索更顺手，也保留我正在阅读的位置。</p>
          <p class="pw-assistant-message">计划已整理好，包含搜索入口、选中反馈和窄窗口体验。请先阅读，再批准或提出修改意见。</p>
          <button class="pw-plan-card" type="button" aria-expanded="true" aria-controls="workspace-plan">
            <span class="pw-plan-emblem">${icon('document')}</span>
            <span class="pw-plan-content"><strong>优化项目搜索体验</strong>
              <span class="pw-plan-meta"><span class="pw-badge" data-state="awaiting">${icon('clock')}等待确认</span>
              <span class="pw-plan-action">收起计划 ${icon('down')}</span></span>
            </span>
          </button>
        </div>`;
      stage.prepend(conversation);
      stage.querySelector('.pw-confirm').classList.add('pw-workspace-feedback');
      const card = conversation.querySelector('.pw-plan-card');
      const mode = sheet.querySelector('[data-mode]');
      const updateMode = (full) => {
        stage.classList.toggle('pw-workspace-full', full);
        const label = full ? '恢复并排' : '展开阅读';
        mode.title = label;
        mode.setAttribute('aria-label', label);
        mode.innerHTML = icon(full ? 'split' : 'expand');
      };
      mode.addEventListener('click', () => updateMode(!stage.classList.contains('pw-workspace-full')));
      const setExpanded = (expanded) => {
        if (!expanded) updateMode(false);
        sheet.hidden = !expanded;
        card.setAttribute('aria-expanded', String(expanded));
        card.querySelector('.pw-plan-action').innerHTML = `${expanded ? '收起计划' : '查看计划'} ${icon('down')}`;
        stage.classList.toggle('pw-reading-closed', !expanded);
      };
      card.addEventListener('click', () => setExpanded(sheet.hidden));
      sheet.querySelector('[data-close]').addEventListener('click', () => setExpanded(false));
    }
    stage.querySelector('[data-mode]').addEventListener('click', () => {
      if (!scene.workspace) render(key, stage.querySelector('textarea')?.value, !scene.full);
    });
    stage.querySelector('[data-close]').addEventListener('click', () => {
      if (!scene.workspace) stage.querySelector('.pw-sheet').remove();
    });
    const form = stage.querySelector('form');
    if (!form) return;
    const field = form.querySelector('textarea');
    const revise = form.querySelector('[data-revise]');
    field.value = draftOverride ?? (scene.feedback ? feedback : '');
    revise.disabled = !field.value.trim() || scene.busy;
    field.addEventListener('input', () => { revise.disabled = !field.value.trim() || scene.busy; });
    form.addEventListener('submit', (event) => {
      event.preventDefault();
      if (field.value.trim() && !scene.busy) render('revision');
    });
    form.querySelector('[data-approve]').addEventListener('click', () => { if (!scene.busy) render('approved'); });
  }
  render(Object.hasOwn(scenarios, params.get('scenario')) ? params.get('scenario') : 'workspace');
})();
