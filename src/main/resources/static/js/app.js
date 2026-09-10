/**
 * LAN Share - Mobile-First Daily Driver Frontend
 */

document.addEventListener('DOMContentLoaded', () => {
  // State
  let filesData = [];
  let linksData = [];
  let activeFileCategory = 'all';
  let isSplitMode = localStorage.getItem('lan_share_split_mode') === 'true';
  let serverOrigin = window.location.origin;
  let primaryLanUrl = window.location.origin;
  let qrcodeInstance = null;
  let isInitialLoad = true;

  // DOM Elements - Header & Banners
  const statusBadge = document.getElementById('statusBadge');
  const serverIpDisplay = document.getElementById('serverIpDisplay');
  const bannerUrl = document.getElementById('bannerUrl');
  const offlineBanner = document.getElementById('offlineBanner');
  const statStorageFree = document.getElementById('statStorageFree');
  const statStorageQuota = document.getElementById('statStorageQuota');
  const storageProgressBar = document.getElementById('storageProgressBar');
  const statFilesCount = document.getElementById('statFilesCount');
  const statLinksCount = document.getElementById('statLinksCount');
  const filesTabBadge = document.getElementById('filesTabBadge');
  const linksTabBadge = document.getElementById('linksTabBadge');

  // DOM Elements - Navigation & Layout
  const tabButtons = document.querySelectorAll('.tab-btn');
  const tabPanes = document.querySelectorAll('.tab-pane');
  const dashboardGrid = document.getElementById('dashboardGrid');
  const splitToggleBtn = document.getElementById('splitToggleBtn');
  const mobileBottomBar = document.getElementById('mobileBottomBar');
  const mobileNavFiles = document.getElementById('mobileNavFiles');
  const mobileNavLinks = document.getElementById('mobileNavLinks');
  const mobileNavQr = document.getElementById('mobileNavQr');
  const mobileFabUpload = document.getElementById('mobileFabUpload');

  // DOM Elements - Files Section
  const fileInput = document.getElementById('fileInput');
  const dropzone = document.getElementById('dropzone');
  const mobileSelectBtn = document.getElementById('mobileSelectBtn');
  const windowDropOverlay = document.getElementById('windowDropOverlay');
  const uploadProgressContainer = document.getElementById('uploadProgressContainer');
  const uploadFileName = document.getElementById('uploadFileName');
  const uploadPercentage = document.getElementById('uploadPercentage');
  const uploadProgressFill = document.getElementById('uploadProgressFill');
  const uploadBytesText = document.getElementById('uploadBytesText');
  const uploadSpeedText = document.getElementById('uploadSpeedText');
  const uploadEtaText = document.getElementById('uploadEtaText');
  const fileSearchInput = document.getElementById('fileSearchInput');
  const clearFileSearchBtn = document.getElementById('clearFileSearchBtn');
  const filesFilterCount = document.getElementById('filesFilterCount');
  const fileTypeChips = document.getElementById('fileTypeChips');
  const filesSkeleton = document.getElementById('filesSkeleton');
  const filesListContainer = document.getElementById('filesListContainer');
  const refreshFilesBtn = document.getElementById('refreshFilesBtn');

  // DOM Elements - Links Section
  const saveLinkForm = document.getElementById('saveLinkForm');
  const linkUrl = document.getElementById('linkUrl');
  const linkTitle = document.getElementById('linkTitle');
  const pasteClipboardBtn = document.getElementById('pasteClipboardBtn');
  const linkSearchInput = document.getElementById('linkSearchInput');
  const clearLinkSearchBtn = document.getElementById('clearLinkSearchBtn');
  const linksFilterCount = document.getElementById('linksFilterCount');
  const linksSkeleton = document.getElementById('linksSkeleton');
  const linksListContainer = document.getElementById('linksListContainer');
  const refreshLinksBtn = document.getElementById('refreshLinksBtn');

  // DOM Elements - Modals
  const qrModal = document.getElementById('qrModal');
  const openQrBtn = document.getElementById('openQrBtn');
  const closeQrBtn = document.getElementById('closeQrBtn');
  const closeQrXBtn = document.getElementById('closeQrXBtn');
  const qrUrlDisplay = document.getElementById('qrUrlDisplay');
  const copyUrlBtn = document.getElementById('copyUrlBtn');

  const confirmModal = document.getElementById('confirmModal');
  const confirmTitle = document.getElementById('confirmTitle');
  const confirmMessage = document.getElementById('confirmMessage');
  const confirmCancelBtn = document.getElementById('confirmCancelBtn');
  const confirmDeleteBtn = document.getElementById('confirmDeleteBtn');
  let currentConfirmCallback = null;

  const previewModal = document.getElementById('previewModal');
  const previewFileName = document.getElementById('previewFileName');
  const previewBody = document.getElementById('previewBody');
  const previewDownloadBtn = document.getElementById('previewDownloadBtn');
  const closePreviewBtn = document.getElementById('closePreviewBtn');

  // DOM Elements - Password Protection & Quota
  const protectUploadCheckbox = document.getElementById('protectUploadCheckbox');
  const uploadPasswordGroup = document.getElementById('uploadPasswordGroup');
  const uploadPasswordInput = document.getElementById('uploadPasswordInput');
  const statStorageLocation = document.getElementById('statStorageLocation');

  const passwordModal = document.getElementById('passwordModal');
  const passwordModalTitle = document.getElementById('passwordModalTitle');
  const passwordModalSubtitle = document.getElementById('passwordModalSubtitle');
  const passwordPromptForm = document.getElementById('passwordPromptForm');
  const promptPasswordInput = document.getElementById('promptPasswordInput');
  const passwordModalError = document.getElementById('passwordModalError');
  const passwordCancelBtn = document.getElementById('passwordCancelBtn');
  const closePasswordXBtn = document.getElementById('closePasswordXBtn');
  const passwordSubmitBtn = document.getElementById('passwordSubmitBtn');

  let pendingPasswordAction = null; // { fileId, fileName, action: 'download' | 'preview', fileType }

  const toastContainer = document.getElementById('toastContainer');

  // Initialize App
  initNavigation();
  initUploadHandlers();
  initLinkHandlers();
  initModals();
  applySplitMode(isSplitMode);

  // Initial Data Load
  loadSystemInfo();
  loadFiles();
  loadLinks();

  // Background Auto-Sync (every 15s)
  setInterval(() => {
    loadFiles(true);
    loadLinks(true);
  }, 15000);

  /* -------------------------------------------------------------
     Navigation, Tabs & Split View
     ------------------------------------------------------------- */
  function initNavigation() {
    // Desktop Tab Switching
    tabButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const target = btn.getAttribute('data-target');
        switchTab(target);
      });
    });

    // Mobile Bottom Nav Switching
    mobileNavFiles.addEventListener('click', () => switchTab('tabFiles'));
    mobileNavLinks.addEventListener('click', () => switchTab('tabLinks'));
    mobileNavQr.addEventListener('click', () => openModal(qrModal));

    // Mobile Center Thumb Upload FAB
    mobileFabUpload.addEventListener('click', () => {
      hapticFeedback();
      fileInput.click();
    });

    // Split View Toggle on Desktop
    splitToggleBtn.addEventListener('click', () => {
      isSplitMode = !isSplitMode;
      localStorage.setItem('lan_share_split_mode', isSplitMode);
      applySplitMode(isSplitMode);
    });
  }

  function switchTab(tabId) {
    tabButtons.forEach(b => {
      if (b.getAttribute('data-target') === tabId) {
        b.classList.add('active');
      } else {
        b.classList.remove('active');
      }
    });

    tabPanes.forEach(p => {
      if (p.id === tabId) {
        p.classList.add('active');
      } else {
        p.classList.remove('active');
      }
    });

    // Sync mobile bottom nav active state
    if (tabId === 'tabFiles') {
      mobileNavFiles.classList.add('active');
      mobileNavLinks.classList.remove('active');
    } else {
      mobileNavFiles.classList.remove('active');
      mobileNavLinks.classList.add('active');
    }
  }

  function applySplitMode(enabled) {
    if (enabled && window.innerWidth >= 1024) {
      dashboardGrid.classList.add('split-mode');
      splitToggleBtn.classList.add('active');
      splitToggleBtn.querySelector('span').textContent = 'Tabbed View';
    } else {
      dashboardGrid.classList.remove('split-mode');
      splitToggleBtn.classList.remove('active');
      splitToggleBtn.querySelector('span').textContent = 'Side-by-Side';
    }
  }

  window.addEventListener('resize', () => {
    applySplitMode(isSplitMode);
  });

  /* -------------------------------------------------------------
     System Info, Offline State & Telemetry
     ------------------------------------------------------------- */
  async function loadSystemInfo() {
    try {
      const res = await fetch('/api/info');
      if (!res.ok) throw new Error('Status code: ' + res.status);
      const info = await res.json();

      offlineBanner.classList.remove('active');
      statusBadge.textContent = 'Online';
      statusBadge.style.color = '#34d399';

      const origin = window.location.origin;
      primaryLanUrl = (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
        ? (info.primaryLanUrl || origin)
        : origin;

      serverOrigin = primaryLanUrl;
      const cleanDisplay = primaryLanUrl.replace(/^https?:\/\//, '');

      serverIpDisplay.textContent = cleanDisplay;
      bannerUrl.textContent = primaryLanUrl;

      // Update storage quota indicator: e.g. "350 MB / 2 GB"
      const quotaText = info.storageQuotaText || `${info.formattedUsedStorage || '0 B'} / ${info.formattedMaxStorage || '2 GB'}`;
      if (statStorageQuota) {
        statStorageQuota.textContent = quotaText;
      }
      if (statStorageFree) {
        statStorageFree.textContent = quotaText;
      }
      if (storageProgressBar) {
        const pct = Math.min(100, Math.max(0, info.storageUsedPercent || 0));
        storageProgressBar.style.width = pct + '%';
        if (pct >= 90) {
          storageProgressBar.className = 'storage-progress-bar danger';
        } else if (pct >= 75) {
          storageProgressBar.className = 'storage-progress-bar warning';
        } else {
          storageProgressBar.className = 'storage-progress-bar';
        }
      }

      if (statStorageLocation && info.storageLocation) {
        statStorageLocation.textContent = `Location: ${info.storageLocation}`;
        statStorageLocation.title = `Shared Data Location: ${info.storageLocation}`;
      }

      qrUrlDisplay.textContent = primaryLanUrl;

      // Click on IP to copy
      serverIpDisplay.onclick = () => copyText(primaryLanUrl, 'Server address copied');
      bannerUrl.onclick = () => copyText(primaryLanUrl, 'Server address copied');

      generateQrCode(primaryLanUrl);
    } catch (err) {
      console.warn('Backend telemetry unreachable:', err);
      offlineBanner.classList.add('active');
      statusBadge.textContent = 'Reconnecting...';
      statusBadge.style.color = '#f87171';
    }
  }

  function generateQrCode(text) {
    const container = document.getElementById('qrcode');
    if (!container || typeof QRCode === 'undefined') return;
    container.innerHTML = '';
    qrcodeInstance = new QRCode(container, {
      text: text,
      width: 190,
      height: 190,
      colorDark: '#0f172a',
      colorLight: '#ffffff',
      correctLevel: QRCode.CorrectLevel.M
    });
  }

  /* -------------------------------------------------------------
     File Upload & Desktop Window Drag-and-Drop
     ------------------------------------------------------------- */
  function initUploadHandlers() {
    // Dropzone click triggers hidden file input
    dropzone.addEventListener('click', (e) => {
      // Don't trigger if clicked on the mobile button to avoid double triggers
      if (e.target.closest('#mobileSelectBtn')) return;
      fileInput.click();
    });

    mobileSelectBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      hapticFeedback();
      fileInput.click();
    });

    fileInput.addEventListener('change', () => {
      if (fileInput.files && fileInput.files.length > 0) {
        handleUpload(fileInput.files);
      }
    });

    // Dropzone Drag Events
    ['dragenter', 'dragover'].forEach(name => {
      dropzone.addEventListener(name, (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropzone.classList.add('dragover');
      });
    });

    ['dragleave', 'drop'].forEach(name => {
      dropzone.addEventListener(name, (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropzone.classList.remove('dragover');
      });
    });

    dropzone.addEventListener('drop', (e) => {
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        handleUpload(e.dataTransfer.files);
      }
    });

    // Desktop Window-Wide Drag and Drop Overlay
    let dragCounter = 0;
    window.addEventListener('dragenter', (e) => {
      e.preventDefault();
      dragCounter++;
      if (e.dataTransfer.types && Array.from(e.dataTransfer.types).includes('Files')) {
        windowDropOverlay.classList.add('active');
      }
    });

    window.addEventListener('dragleave', (e) => {
      e.preventDefault();
      dragCounter--;
      if (dragCounter <= 0) {
        dragCounter = 0;
        windowDropOverlay.classList.remove('active');
      }
    });

    window.addEventListener('dragover', (e) => {
      e.preventDefault();
    });

    window.addEventListener('drop', (e) => {
      e.preventDefault();
      dragCounter = 0;
      windowDropOverlay.classList.remove('active');
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        handleUpload(e.dataTransfer.files);
      }
    });

    // Search and Filter Handlers
    fileSearchInput.addEventListener('input', () => {
      clearFileSearchBtn.style.display = fileSearchInput.value ? 'block' : 'none';
      renderFilesList();
    });

    clearFileSearchBtn.addEventListener('click', () => {
      fileSearchInput.value = '';
      clearFileSearchBtn.style.display = 'none';
      renderFilesList();
      fileSearchInput.focus();
    });

    fileTypeChips.querySelectorAll('.chip').forEach(chip => {
      chip.addEventListener('click', () => {
        fileTypeChips.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
        chip.classList.add('active');
        activeFileCategory = chip.getAttribute('data-filter');
        renderFilesList();
      });
    });

    if (protectUploadCheckbox) {
      protectUploadCheckbox.addEventListener('change', () => {
        if (protectUploadCheckbox.checked) {
          uploadPasswordGroup.style.display = 'block';
          uploadPasswordInput.focus();
        } else {
          uploadPasswordGroup.style.display = 'none';
          uploadPasswordInput.value = '';
        }
      });
    }

    refreshFilesBtn.addEventListener('click', () => loadFiles());
  }

  function handleUpload(fileList) {
    if (!fileList || fileList.length === 0) return;

    let passwordVal = '';
    if (protectUploadCheckbox && protectUploadCheckbox.checked) {
      passwordVal = (uploadPasswordInput.value || '').trim();
      if (!passwordVal) {
        showToast('Please enter a password or uncheck "Password protect this file"', 'error');
        uploadPasswordInput.focus();
        return;
      }
    }

    const formData = new FormData();
    let totalBytes = 0;
    const names = [];

    for (let i = 0; i < fileList.length; i++) {
      formData.append('files', fileList[i]);
      totalBytes += fileList[i].size;
      names.push(fileList[i].name);
    }

    if (passwordVal) {
      formData.append('password', passwordVal);
    }

    const titleText = fileList.length === 1
      ? names[0]
      : `${fileList.length} files (${names[0]}, ...)`;

    uploadFileName.textContent = titleText;
    uploadPercentage.textContent = '0%';
    uploadProgressFill.style.width = '0%';
    uploadBytesText.textContent = `0 B / ${formatBytes(totalBytes)}`;
    uploadSpeedText.textContent = 'Calculating speed...';
    uploadEtaText.textContent = '';
    uploadProgressContainer.style.display = 'block';

    const startTime = Date.now();
    let lastLoaded = 0;
    let lastTime = startTime;

    const xhr = new XMLHttpRequest();

    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) {
        const percent = Math.min(100, Math.round((e.loaded / e.total) * 100));
        uploadProgressFill.style.width = percent + '%';
        uploadPercentage.textContent = percent + '%';
        uploadBytesText.textContent = `${formatBytes(e.loaded)} / ${formatBytes(e.total)}`;

        const now = Date.now();
        const interval = (now - lastTime) / 1000;
        if (interval > 0.4) {
          const bytesSince = e.loaded - lastLoaded;
          const currentSpeed = bytesSince / interval; // B/s
          uploadSpeedText.textContent = `${formatBytes(currentSpeed)}/s`;

          if (currentSpeed > 0) {
            const remainingSec = Math.max(0, Math.round((e.total - e.loaded) / currentSpeed));
            uploadEtaText.textContent = remainingSec > 0 ? `~${remainingSec}s left` : 'Finalizing...';
          }
          lastLoaded = e.loaded;
          lastTime = now;
        }
      }
    });

    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          const res = JSON.parse(xhr.responseText);
          uploadProgressFill.style.width = '100%';
          uploadPercentage.textContent = '100%';
          uploadSpeedText.textContent = 'Upload complete!';
          uploadEtaText.textContent = '';
          hapticFeedback();
          showToast(`Successfully uploaded ${res.uploadedCount || fileList.length} file(s)`, 'success');
          if (protectUploadCheckbox) {
            protectUploadCheckbox.checked = false;
            uploadPasswordGroup.style.display = 'none';
            uploadPasswordInput.value = '';
          }
          loadFiles();
          loadSystemInfo();
        } catch (e) {
          showToast('File uploaded successfully', 'success');
          if (protectUploadCheckbox) {
            protectUploadCheckbox.checked = false;
            uploadPasswordGroup.style.display = 'none';
            uploadPasswordInput.value = '';
          }
          loadFiles();
        }
      } else {
        let msg = 'Upload failed';
        try {
          const errRes = JSON.parse(xhr.responseText);
          msg = errRes.message || errRes.error || msg;
        } catch (_) {}
        showToast(msg, 'error');
        uploadSpeedText.textContent = 'Failed';
      }

      setTimeout(() => {
        uploadProgressContainer.style.display = 'none';
        fileInput.value = '';
      }, 1800);
    });

    xhr.addEventListener('error', () => {
      showToast('Network error during file upload', 'error');
      uploadSpeedText.textContent = 'Network error';
      setTimeout(() => {
        uploadProgressContainer.style.display = 'none';
        fileInput.value = '';
      }, 2500);
    });

    xhr.open('POST', '/api/files/upload', true);
    xhr.send(formData);
  }

  /* -------------------------------------------------------------
     File Listing, Rendering & Actions
     ------------------------------------------------------------- */
  async function loadFiles(silent = false) {
    if (isInitialLoad && !silent) {
      filesSkeleton.classList.add('active');
    }

    try {
      const res = await fetch('/api/files');
      if (!res.ok) throw new Error('Failed to fetch files');
      filesData = await res.json();
      statFilesCount.textContent = filesData.length;
      filesTabBadge.textContent = filesData.length;
      renderFilesList();
    } catch (err) {
      if (!silent) showToast('Could not load files: ' + err.message, 'error');
    } finally {
      filesSkeleton.classList.remove('active');
    }
  }

  function renderFilesList() {
    const query = (fileSearchInput.value || '').toLowerCase().trim();

    const filtered = filesData.filter(f => {
      // Category filter
      if (activeFileCategory !== 'all') {
        const cat = f.fileType || 'file';
        if (activeFileCategory === 'image' && cat !== 'image') return false;
        if (activeFileCategory === 'video' && cat !== 'video') return false;
        if (activeFileCategory === 'document' && cat !== 'document' && cat !== 'pdf' && cat !== 'code') return false;
        if (activeFileCategory === 'archive' && cat !== 'archive') return false;
      }
      // Query filter
      if (!query) return true;
      return f.originalFileName.toLowerCase().includes(query);
    });

    // Update count indicator
    if (filesData.length > 0 && (query || activeFileCategory !== 'all')) {
      filesFilterCount.textContent = `(${filtered.length} of ${filesData.length})`;
    } else {
      filesFilterCount.textContent = '';
    }

    if (filtered.length === 0) {
      if (filesData.length === 0) {
        filesListContainer.innerHTML = `
          <div class="empty-state">
            <div class="empty-icon">📂</div>
            <div class="empty-title">No files uploaded yet</div>
            <div class="empty-desc">Share photos, videos, or documents directly across your Wi-Fi network without cloud storage.</div>
            <button class="btn btn-primary" onclick="document.getElementById('fileInput').click()">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
              Select File to Upload
            </button>
          </div>
        `;
      } else {
        filesListContainer.innerHTML = `
          <div class="empty-state">
            <div class="empty-icon">🔍</div>
            <div class="empty-title">No matching files</div>
            <div class="empty-desc">No files match "${escapeHtml(query || activeFileCategory)}".</div>
            <button class="btn btn-secondary btn-sm" id="resetFilesFilterBtn">Clear Filters</button>
          </div>
        `;
        const resetBtn = document.getElementById('resetFilesFilterBtn');
        if (resetBtn) {
          resetBtn.addEventListener('click', () => {
            fileSearchInput.value = '';
            clearFileSearchBtn.style.display = 'none';
            activeFileCategory = 'all';
            fileTypeChips.querySelectorAll('.chip').forEach(c => {
              if (c.getAttribute('data-filter') === 'all') c.classList.add('active');
              else c.classList.remove('active');
            });
            renderFilesList();
          });
        }
      }
      return;
    }

    filesListContainer.innerHTML = filtered.map(f => {
      const icon = getFileIconSvg(f.fileType);
      const badgeClass = `badge-${f.fileType || 'file'}`;
      const relTime = formatRelativeTime(f.uploadTime);
      const fullDate = formatDateFull(f.uploadTime);
      const isPreviewable = ['image', 'video', 'audio', 'pdf'].includes(f.fileType);
      const isFileProtected = Boolean(f.protected || f.isProtected);
      const downloadUrl = `${serverOrigin}/api/files/${f.id}/download`;

      return `
        <div class="item-card" data-id="${f.id}">
          <div class="item-info">
            <div class="file-type-badge ${badgeClass}" title="${f.fileType}">
              ${icon}
            </div>
            <div class="item-details">
              <span class="item-name" title="${escapeHtml(f.originalFileName)}">
                ${escapeHtml(f.originalFileName)}
                ${isFileProtected ? '<span class="badge-locked" title="Password protected file">🔒 Locked</span>' : ''}
              </span>
              <div class="item-meta">
                <span class="item-meta-item">📦 ${f.formattedSize}</span>
                <span class="item-meta-item" title="${fullDate}">🕒 ${relTime}</span>
              </div>
            </div>
          </div>
          <div class="item-actions">
            ${isPreviewable ? `
              <button class="btn btn-secondary btn-icon preview-file-btn" data-id="${f.id}" data-name="${escapeHtml(f.originalFileName)}" data-type="${f.fileType}" data-protected="${isFileProtected}" title="${isFileProtected ? 'Password required to preview' : 'Preview in browser'}">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
              </button>
            ` : ''}
            <button class="btn btn-secondary btn-icon btn-copy copy-file-link-btn" data-url="${downloadUrl}" title="Copy download link">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
            </button>
            ${isFileProtected ? `
              <button class="btn btn-primary btn-sm protected-download-btn" data-id="${f.id}" data-name="${escapeHtml(f.originalFileName)}" title="Password required to download">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                <span>Download</span>
              </button>
            ` : `
              <a href="/api/files/${f.id}/download" class="btn btn-primary btn-sm" title="Download to this device">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                <span>Download</span>
              </a>
            `}
            <button class="btn btn-danger btn-icon delete-file-btn" data-id="${f.id}" data-name="${escapeHtml(f.originalFileName)}" title="Delete file">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            </button>
          </div>
        </div>
      `;
    }).join('');

    // Attach File Event Listeners
    filesListContainer.querySelectorAll('.copy-file-link-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const url = btn.getAttribute('data-url');
        copyText(url, 'Download link copied to clipboard', btn);
      });
    });

    filesListContainer.querySelectorAll('.preview-file-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btn.getAttribute('data-id');
        const name = btn.getAttribute('data-name');
        const type = btn.getAttribute('data-type');
        const isProt = btn.getAttribute('data-protected') === 'true';
        if (isProt) {
          promptFilePassword(id, name, 'preview', type);
        } else {
          openPreview(id, name, type);
        }
      });
    });

    filesListContainer.querySelectorAll('.protected-download-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btn.getAttribute('data-id');
        const name = btn.getAttribute('data-name');
        promptFilePassword(id, name, 'download');
      });
    });

    filesListContainer.querySelectorAll('.delete-file-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btn.getAttribute('data-id');
        const name = btn.getAttribute('data-name');
        showConfirmDialog({
          title: 'Delete File?',
          message: `Are you sure you want to permanently delete "${name}" from your Linux PC?`,
          onConfirm: async () => {
            await deleteFile(id);
          }
        });
      });
    });
  }

  async function deleteFile(id) {
    try {
      const res = await fetch(`/api/files/${id}`, { method: 'DELETE' });
      if (!res.ok) throw new Error('Delete request failed');
      showToast('File deleted successfully', 'info');
      await loadFiles();
      await loadSystemInfo();
    } catch (err) {
      showToast('Could not delete file: ' + err.message, 'error');
    }
  }

  /* -------------------------------------------------------------
     Link Sharing & Management
     ------------------------------------------------------------- */
  function initLinkHandlers() {
    pasteClipboardBtn.addEventListener('click', async () => {
      try {
        const text = await navigator.clipboard.readText();
        if (text) {
          linkUrl.value = text.trim();
          showToast('Pasted URL from clipboard', 'info');
          linkTitle.focus();
        }
      } catch (err) {
        showToast('Clipboard access was denied or unsupported in this browser', 'error');
      }
    });

    saveLinkForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const rawUrl = linkUrl.value.trim();
      const rawTitle = linkTitle.value.trim();
      if (!rawUrl) return;

      try {
        const res = await fetch('/api/links', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url: rawUrl, title: rawTitle })
        });

        if (!res.ok) {
          const errData = await res.json();
          throw new Error(errData.error || 'Failed to save link');
        }

        linkUrl.value = '';
        linkTitle.value = '';
        hapticFeedback();
        showToast('Link shared successfully', 'success');
        await loadLinks();
        await loadSystemInfo();
      } catch (err) {
        showToast(err.message, 'error');
      }
    });

    linkSearchInput.addEventListener('input', () => {
      clearLinkSearchBtn.style.display = linkSearchInput.value ? 'block' : 'none';
      renderLinksList();
    });

    clearLinkSearchBtn.addEventListener('click', () => {
      linkSearchInput.value = '';
      clearLinkSearchBtn.style.display = 'none';
      renderLinksList();
      linkSearchInput.focus();
    });

    refreshLinksBtn.addEventListener('click', () => loadLinks());
  }

  async function loadLinks(silent = false) {
    if (isInitialLoad && !silent) {
      linksSkeleton.classList.add('active');
    }

    try {
      const res = await fetch('/api/links');
      if (!res.ok) throw new Error('Failed to fetch links');
      linksData = await res.json();
      statLinksCount.textContent = linksData.length;
      linksTabBadge.textContent = linksData.length;
      renderLinksList();
    } catch (err) {
      if (!silent) showToast('Could not load links: ' + err.message, 'error');
    } finally {
      linksSkeleton.classList.remove('active');
      isInitialLoad = false;
    }
  }

  function renderLinksList() {
    const query = (linkSearchInput.value || '').toLowerCase().trim();
    const filtered = linksData.filter(l =>
      (l.title && l.title.toLowerCase().includes(query)) ||
      (l.url && l.url.toLowerCase().includes(query))
    );

    if (linksData.length > 0 && query) {
      linksFilterCount.textContent = `(${filtered.length} of ${linksData.length})`;
    } else {
      linksFilterCount.textContent = '';
    }

    if (filtered.length === 0) {
      if (linksData.length === 0) {
        linksListContainer.innerHTML = `
          <div class="empty-state">
            <div class="empty-icon">🔗</div>
            <div class="empty-title">No saved links yet</div>
            <div class="empty-desc">Quickly send links between your phone and laptop by pasting a URL above.</div>
          </div>
        `;
      } else {
        linksListContainer.innerHTML = `
          <div class="empty-state">
            <div class="empty-icon">🔍</div>
            <div class="empty-title">No matching links</div>
            <div class="empty-desc">No saved links match "${escapeHtml(query)}".</div>
            <button class="btn btn-secondary btn-sm" id="resetLinksFilterBtn">Clear Search</button>
          </div>
        `;
        const resetBtn = document.getElementById('resetLinksFilterBtn');
        if (resetBtn) {
          resetBtn.addEventListener('click', () => {
            linkSearchInput.value = '';
            clearLinkSearchBtn.style.display = 'none';
            renderLinksList();
          });
        }
      }
      return;
    }

    linksListContainer.innerHTML = filtered.map(l => {
      const relTime = formatRelativeTime(l.createdAt);
      const fullDate = formatDateFull(l.createdAt);
      const domain = extractDomain(l.url);

      return `
        <div class="item-card" data-id="${l.id}">
          <div class="item-info">
            <div class="file-type-badge badge-link">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>
            </div>
            <div class="item-details">
              <span class="item-name" title="${escapeHtml(l.title)}">
                ${escapeHtml(l.title)}
              </span>
              <div class="item-meta">
                <span class="item-meta-item" style="color: var(--accent); font-weight: 500;">
                  🌐 ${escapeHtml(domain)}
                </span>
                <span class="item-meta-item" title="${fullDate}">🕒 ${relTime}</span>
              </div>
            </div>
          </div>
          <div class="item-actions">
            <button class="btn btn-secondary btn-copy copy-link-btn" data-url="${escapeHtml(l.url)}" title="Copy URL">
              📋 <span>Copy</span>
            </button>
            <a href="${escapeHtml(l.url)}" target="_blank" rel="noopener noreferrer" class="btn btn-primary btn-sm" title="Open in new tab">
              ↗ <span>Open</span>
            </a>
            <button class="btn btn-danger btn-icon delete-link-btn" data-id="${l.id}" data-title="${escapeHtml(l.title)}" title="Delete link">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            </button>
          </div>
        </div>
      `;
    }).join('');

    // Attach Link Event Listeners
    linksListContainer.querySelectorAll('.copy-link-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const url = btn.getAttribute('data-url');
        copyText(url, 'Link copied to clipboard', btn);
      });
    });

    linksListContainer.querySelectorAll('.delete-link-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const id = btn.getAttribute('data-id');
        const title = btn.getAttribute('data-title');
        showConfirmDialog({
          title: 'Delete Link?',
          message: `Are you sure you want to delete "${title}"?`,
          onConfirm: async () => {
            await deleteLink(id);
          }
        });
      });
    });
  }

  async function deleteLink(id) {
    try {
      const res = await fetch(`/api/links/${id}`, { method: 'DELETE' });
      if (!res.ok) throw new Error('Failed to delete');
      showToast('Link deleted successfully', 'info');
      await loadLinks();
      await loadSystemInfo();
    } catch (err) {
      showToast('Could not delete link: ' + err.message, 'error');
    }
  }

  /* -------------------------------------------------------------
     Modals: QR Code, Confirmation Dialog & Preview Lightbox
     ------------------------------------------------------------- */
  function initModals() {
    // QR Modal
    openQrBtn.addEventListener('click', () => openModal(qrModal));
    closeQrBtn.addEventListener('click', () => closeModal(qrModal));
    closeQrXBtn.addEventListener('click', () => closeModal(qrModal));
    qrModal.addEventListener('click', (e) => {
      if (e.target === qrModal) closeModal(qrModal);
    });

    copyUrlBtn.addEventListener('click', () => {
      copyText(primaryLanUrl, 'Server address copied', copyUrlBtn);
    });
    qrUrlDisplay.addEventListener('click', () => {
      copyText(primaryLanUrl, 'Server address copied');
    });

    // Custom Confirmation Dialog
    confirmCancelBtn.addEventListener('click', () => {
      closeModal(confirmModal);
      currentConfirmCallback = null;
    });

    confirmDeleteBtn.addEventListener('click', async () => {
      const cb = currentConfirmCallback;
      closeModal(confirmModal);
      if (cb) await cb();
      currentConfirmCallback = null;
    });

    confirmModal.addEventListener('click', (e) => {
      if (e.target === confirmModal) {
        closeModal(confirmModal);
        currentConfirmCallback = null;
      }
    });

    // Media Preview Modal
    closePreviewBtn.addEventListener('click', () => closePreview());
    previewModal.addEventListener('click', (e) => {
      if (e.target === previewModal) closePreview();
    });

    // Password Prompt Modal
    if (passwordCancelBtn) {
      passwordCancelBtn.addEventListener('click', closePasswordPrompt);
    }
    if (closePasswordXBtn) {
      closePasswordXBtn.addEventListener('click', closePasswordPrompt);
    }
    if (passwordModal) {
      passwordModal.addEventListener('click', (e) => {
        if (e.target === passwordModal) closePasswordPrompt();
      });
    }
    if (passwordPromptForm) {
      passwordPromptForm.addEventListener('submit', handlePasswordSubmit);
    }

    // Escape Key Handler for all modals
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeModal(qrModal);
        closeModal(confirmModal);
        closePreview();
        closePasswordPrompt();
      }
    });
  }

  function openModal(modal) {
    modal.classList.add('active');
  }

  function closeModal(modal) {
    modal.classList.remove('active');
  }

  function showConfirmDialog({ title, message, onConfirm }) {
    confirmTitle.textContent = title;
    confirmMessage.textContent = message;
    currentConfirmCallback = onConfirm;
    openModal(confirmModal);
  }

  function promptFilePassword(fileId, fileName, action, fileType) {
    pendingPasswordAction = { fileId, fileName, action, fileType };
    passwordModalTitle.textContent = action === 'download' ? 'Download Protected File' : 'Preview Protected File';
    passwordModalSubtitle.textContent = `Enter password for "${fileName}":`;
    passwordSubmitBtn.textContent = action === 'download' ? 'Unlock & Download' : 'Unlock & Preview';
    promptPasswordInput.value = '';
    passwordModalError.style.display = 'none';
    passwordModalError.textContent = '';
    openModal(passwordModal);
    setTimeout(() => promptPasswordInput.focus(), 100);
  }

  function closePasswordPrompt() {
    closeModal(passwordModal);
    pendingPasswordAction = null;
    promptPasswordInput.value = '';
    passwordModalError.style.display = 'none';
    passwordModalError.textContent = '';
    passwordSubmitBtn.disabled = false;
    passwordSubmitBtn.textContent = 'Unlock & Proceed';
  }

  async function handlePasswordSubmit(e) {
    e.preventDefault();
    if (!pendingPasswordAction) return;

    const password = promptPasswordInput.value;
    if (!password) {
      passwordModalError.textContent = 'Please enter password.';
      passwordModalError.style.display = 'block';
      return;
    }

    const currentAction = pendingPasswordAction;
    passwordSubmitBtn.disabled = true;
    passwordSubmitBtn.textContent = 'Verifying...';

    try {
      const res = await fetch(`/api/files/${currentAction.fileId}/verify-password`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password })
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        passwordModalError.textContent = err.error || 'Incorrect password. Please try again.';
        passwordModalError.style.display = 'block';
        promptPasswordInput.select();
        return;
      }

      const data = await res.json();
      const token = data.token;
      closePasswordPrompt();

      if (currentAction.action === 'download') {
        const downloadUrl = `/api/files/${currentAction.fileId}/download?token=${encodeURIComponent(token)}`;
        const a = document.createElement('a');
        a.href = downloadUrl;
        a.download = currentAction.fileName || '';
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        setTimeout(() => {
          if (document.body.contains(a)) {
            document.body.removeChild(a);
          }
        }, 100);
        showToast('Download started', 'success');
      } else if (currentAction.action === 'preview') {
        openPreview(currentAction.fileId, currentAction.fileName, currentAction.fileType, token);
      }
    } catch (err) {
      passwordModalError.textContent = 'Connection error: ' + err.message;
      passwordModalError.style.display = 'block';
    } finally {
      if (pendingPasswordAction) {
        passwordSubmitBtn.disabled = false;
        passwordSubmitBtn.textContent = pendingPasswordAction.action === 'download' ? 'Unlock & Download' : 'Unlock & Preview';
      }
    }
  }

  function openPreview(fileId, fileName, fileType, token = null) {
    previewFileName.textContent = fileName;
    const tokenParam = token ? `?token=${encodeURIComponent(token)}` : '';
    previewDownloadBtn.href = `/api/files/${fileId}/download${tokenParam}`;
    previewDownloadBtn.setAttribute('download', fileName || '');
    previewBody.innerHTML = '';

    const previewUrl = `/api/files/${fileId}/preview${tokenParam}`;

    if (fileType === 'image') {
      const img = document.createElement('img');
      img.src = previewUrl;
      img.alt = fileName;
      previewBody.appendChild(img);
    } else if (fileType === 'video') {
      const video = document.createElement('video');
      video.src = previewUrl;
      video.controls = true;
      video.autoplay = true;
      previewBody.appendChild(video);
    } else if (fileType === 'audio') {
      const audio = document.createElement('audio');
      audio.src = previewUrl;
      audio.controls = true;
      audio.autoplay = true;
      previewBody.appendChild(audio);
    } else if (fileType === 'pdf') {
      const iframe = document.createElement('iframe');
      iframe.src = previewUrl;
      iframe.style.width = '100%';
      iframe.style.height = '60vh';
      iframe.style.border = 'none';
      previewBody.appendChild(iframe);
    }

    openModal(previewModal);
  }

  function closePreview() {
    // Stop any media playing
    const media = previewBody.querySelector('video, audio');
    if (media) media.pause();
    previewBody.innerHTML = '';
    previewDownloadBtn.href = '#';
    previewDownloadBtn.removeAttribute('download');
    closeModal(previewModal);
  }

  /* -------------------------------------------------------------
     Utilities: Clipboard, Toast, Formatters & Icons
     ------------------------------------------------------------- */
  async function copyText(text, successToastMsg = 'Copied!', targetButton = null) {
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text);
      } else {
        const temp = document.createElement('textarea');
        temp.value = text;
        document.body.appendChild(temp);
        temp.select();
        document.execCommand('copy');
        document.body.removeChild(temp);
      }

      hapticFeedback();
      showToast(successToastMsg, 'success');

      if (targetButton) {
        const originalHtml = targetButton.innerHTML;
        targetButton.classList.add('copied');
        targetButton.innerHTML = '✓ <span>Copied!</span>';
        setTimeout(() => {
          targetButton.classList.remove('copied');
          targetButton.innerHTML = originalHtml;
        }, 2000);
      }
    } catch (err) {
      showToast('Could not copy to clipboard', 'error');
    }
  }

  function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;

    let icon = 'ℹ️';
    if (type === 'success') icon = '✓';
    if (type === 'error') icon = '✕';

    toast.innerHTML = `
      <div style="display: flex; align-items: center; gap: 0.5rem;">
        <span style="font-weight: bold;">${icon}</span>
        <span>${escapeHtml(message)}</span>
      </div>
      <button style="background:none; border:none; color:var(--text-muted); cursor:pointer; font-size:1.1rem; padding:0 0.2rem;">✕</button>
    `;

    toast.querySelector('button').addEventListener('click', () => {
      toast.remove();
    });

    toastContainer.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(10px)';
      toast.style.transition = 'all 0.25s ease';
      setTimeout(() => toast.remove(), 250);
    }, 3500);
  }

  function hapticFeedback() {
    if (navigator.vibrate) {
      try { navigator.vibrate(40); } catch (_) {}
    }
  }

  function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(i > 1 ? 2 : 1)) + ' ' + sizes[i];
  }

  function formatRelativeTime(dateInput) {
    if (!dateInput) return '';
    const date = new Date(dateInput);
    const now = new Date();
    const diffSec = Math.floor((now - date) / 1000);

    if (diffSec < 45) return 'just now';
    if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
    if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h ago`;
    if (diffSec < 172800) return 'yesterday';
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  }

  function formatDateFull(dateInput) {
    if (!dateInput) return '';
    const d = new Date(dateInput);
    return d.toLocaleString(undefined, {
      dateStyle: 'medium',
      timeStyle: 'short'
    });
  }

  function extractDomain(url) {
    try {
      const u = new URL(url);
      return u.hostname.replace(/^www\./, '');
    } catch (_) {
      return url;
    }
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/[&<>'"]/g, tag => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      "'": '&#39;',
      '"': '&quot;'
    }[tag] || tag));
  }

  function getFileIconSvg(type) {
    switch (type) {
      case 'image':
        return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>';
      case 'video':
        return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>';
      case 'audio':
        return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>';
      case 'pdf':
        return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="9" y1="13" x2="15" y2="13"/></svg>';
      case 'archive':
        return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/></svg>';
      case 'code':
        return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>';
      case 'document':
        return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>';
      default:
        return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><polyline points="13 2 13 9 20 9"/></svg>';
    }
  }
});
