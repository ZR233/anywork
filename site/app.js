(() => {
  "use strict";

  const LATEST_RELEASE_PAGE = "https://github.com/ZR233/anywork/releases/latest";
  const LATEST_RELEASE_API = "https://api.github.com/repos/ZR233/anywork/releases/latest";
  const CACHE_KEY = "anywork_latest_release_v1";
  const CACHE_TTL_MS = 10 * 60 * 1000;

  const TRUSTED_PREFIXES = [
    "https://github.com/ZR233/anywork/releases/",
    "https://github.com/ZR233/pure-lang/releases/",
  ];

  const SHOWCASE_SLIDES = [
    {
      tabId: "tab-workspace",
      src: "./assets/readme-workspace.png",
      alt: "糊来帮主工作台：主智能体自动选模并依次调度探索者、执行者与审查者",
      caption:
        "主智能体拆解任务并自动选模，依次派出探索者摸底、执行者修复、审查者独立运行测试把关；右上角下拉菜单可随时查看每位成员的任务与模型。",
    },
    {
      tabId: "tab-eval",
      src: "./assets/readme-agent-evaluation.png",
      alt: "任务收尾后，主智能体给探索者、执行者与审查者逐一打分点评",
      caption:
        "交付、审查与返修全部完成后，主智能体按成果质量与指令遵循为每位子智能体出具结构化最终评价。",
    },
    {
      tabId: "tab-archive",
      src: "./assets/readme-model-evaluations.png",
      alt: "模型详情页：跨会话长期积累的任务评价分布与历史评语",
      caption:
        "评价按“账号 + 模型”跨会话长期保存，结合实时价格与实测吞吐率，让下一次自动选模越用越懂行。",
    },
    {
      tabId: "tab-workflow",
      src: "./assets/readme-workflow-editor.png",
      alt: "工作模式编辑器：在流程图画布上编排阶段、完成标准与跳转条件",
      caption:
        "工作模式编辑器：每个节点是一个阶段、连线是允许的跳转；复制内置模式或从头创建，校验通过后可零费用离线预演。",
    },
  ];

  function isTrustedReleaseUrl(url) {
    return typeof url === "string" && TRUSTED_PREFIXES.some((prefix) => url.startsWith(prefix));
  }

  function formatMegabytes(bytes) {
    if (typeof bytes !== "number" || !Number.isFinite(bytes) || bytes <= 0) {
      return "";
    }
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  function formatDate(isoString) {
    if (typeof isoString !== "string") {
      return "";
    }
    const match = /^(\d{4}-\d{2}-\d{2})/.exec(isoString);
    return match ? match[1] : "";
  }

  function detectVisitorPlatform() {
    const ua = (navigator.userAgent || "").toLowerCase();
    if (ua.includes("linux") && !ua.includes("android")) {
      return "linux";
    }
    if (ua.includes("win")) {
      return "windows";
    }
    return "other";
  }

  function initShowcaseTabs() {
    const tabs = Array.from(document.querySelectorAll("[data-tab-index]"));
    const panel = document.getElementById("showcase-panel");
    const img = document.getElementById("showcase-img");
    const caption = document.getElementById("showcase-caption-text");
    if (!tabs.length || !panel || !img || !caption) {
      return;
    }

    let currentIndex = 0;

    function activateTab(index, focusTab) {
      const slide = SHOWCASE_SLIDES[index];
      if (!slide) {
        return;
      }
      currentIndex = index;
      tabs.forEach((btn, idx) => {
        const active = idx === index;
        btn.classList.toggle("is-active", active);
        btn.setAttribute("aria-selected", active ? "true" : "false");
        btn.setAttribute("tabindex", active ? "0" : "-1");
        if (active && focusTab) {
          btn.focus();
        }
      });
      panel.setAttribute("aria-labelledby", slide.tabId);
      img.src = slide.src;
      img.alt = slide.alt;
      caption.textContent = slide.caption;
    }

    tabs.forEach((btn, idx) => {
      btn.addEventListener("click", () => activateTab(idx, false));
      btn.addEventListener("keydown", (event) => {
        let next = null;
        if (event.key === "ArrowRight") {
          next = (currentIndex + 1) % SHOWCASE_SLIDES.length;
        } else if (event.key === "ArrowLeft") {
          next = (currentIndex - 1 + SHOWCASE_SLIDES.length) % SHOWCASE_SLIDES.length;
        } else if (event.key === "Home") {
          next = 0;
        } else if (event.key === "End") {
          next = SHOWCASE_SLIDES.length - 1;
        }
        if (next !== null) {
          event.preventDefault();
          activateTab(next, true);
        }
      });
    });

    const lightbox = document.getElementById("lightbox");
    const lightboxImg = document.getElementById("lightbox-img");
    const lightboxTitle = document.getElementById("lightbox-title");
    const openBtn = document.querySelector("[data-open-lightbox]");
    const closeBtn = document.querySelector("[data-close-lightbox]");

    if (lightbox && typeof lightbox.showModal === "function" && openBtn && lightboxImg && lightboxTitle) {
      openBtn.addEventListener("click", () => {
        const slide = SHOWCASE_SLIDES[currentIndex];
        lightboxImg.src = slide.src;
        lightboxImg.alt = slide.alt;
        lightboxTitle.textContent = slide.alt;
        lightbox.showModal();
      });

      if (closeBtn) {
        closeBtn.addEventListener("click", () => lightbox.close());
      }

      lightbox.addEventListener("click", (event) => {
        if (event.target === lightbox) {
          lightbox.close();
        }
      });
    }
  }

  function initCopyButtons() {
    document.querySelectorAll("[data-copy-cmd]").forEach((btn) => {
      const originalLabel = btn.textContent;
      let timerId = null;

      btn.addEventListener("click", async () => {
        const cmd = btn.getAttribute("data-copy-cmd");
        if (!cmd || !navigator.clipboard) {
          return;
        }
        try {
          await navigator.clipboard.writeText(cmd);
          btn.textContent = "已复制";
          if (timerId) {
            clearTimeout(timerId);
          }
          timerId = setTimeout(() => {
            btn.textContent = originalLabel;
          }, 1800);
        } catch {
          // Leave default label if clipboard permission is denied.
        }
      });
    });
  }

  function parseReleasePayload(raw) {
    if (!raw || typeof raw !== "object" || raw.draft || raw.prerelease) {
      return null;
    }
    const tag = typeof raw.tag_name === "string" ? raw.tag_name.trim() : "";
    if (!/^v\d+\.\d+\.\d+$/.test(tag)) {
      return null;
    }
    const htmlUrl = isTrustedReleaseUrl(raw.html_url) ? raw.html_url : LATEST_RELEASE_PAGE;
    const publishedDate = formatDate(raw.published_at);
    const assets = Array.isArray(raw.assets) ? raw.assets : [];

    let windowsAsset = null;
    let linuxAsset = null;
    let sha256Url = null;

    for (const item of assets) {
      if (!item || typeof item.name !== "string" || !isTrustedReleaseUrl(item.browser_download_url)) {
        continue;
      }
      if (/^anywork-\d+\.\d+\.\d+-windows-x86_64-setup\.exe$/.test(item.name)) {
        windowsAsset = {
          name: item.name,
          url: item.browser_download_url,
          sizeText: formatMegabytes(item.size),
        };
      } else if (/^anywork-\d+\.\d+\.\d+-linux-x86_64\.deb$/.test(item.name)) {
        linuxAsset = {
          name: item.name,
          url: item.browser_download_url,
          sizeText: formatMegabytes(item.size),
        };
      } else if (item.name === "SHA256SUMS.txt") {
        sha256Url = item.browser_download_url;
      }
    }

    return { tag, htmlUrl, publishedDate, windowsAsset, linuxAsset, sha256Url };
  }

  function applyLatestRelease(info) {
    if (!info) {
      return;
    }

    document.querySelectorAll("[data-release-notes]").forEach((el) => {
      el.setAttribute("href", info.htmlUrl);
    });

    if (info.sha256Url) {
      document.querySelectorAll("[data-sha256-link]").forEach((el) => {
        el.setAttribute("href", info.sha256Url);
      });
    }

    const pillText = document.querySelector("[data-release-pill-text]");
    if (pillText) {
      pillText.textContent = info.publishedDate
        ? `最新稳定版 ${info.tag} · 发布于 ${info.publishedDate}`
        : `最新稳定版 ${info.tag} · 查看发行说明`;
    }

    const versionTag = document.querySelector("[data-release-version-tag]");
    if (versionTag) {
      versionTag.textContent = info.tag;
    }

    const releaseSummary = document.querySelector("[data-release-summary]");
    if (releaseSummary) {
      releaseSummary.textContent = info.publishedDate
        ? `当前最新正式版为 ${info.tag}（${info.publishedDate} 发布），直连 GitHub Release 官方签名安装包。`
        : `当前最新正式版为 ${info.tag}，直连 GitHub Release 官方签名安装包。`;
    }

    if (info.windowsAsset) {
      document.querySelectorAll('[data-download="windows"]').forEach((el) => {
        el.setAttribute("href", info.windowsAsset.url);
      });

      const winMeta = document.querySelector("[data-windows-meta]");
      if (winMeta) {
        winMeta.textContent = info.windowsAsset.sizeText
          ? `${info.tag} · ${info.windowsAsset.sizeText}`
          : info.tag;
      }

      const winDetail = document.querySelector("[data-windows-asset-detail]");
      if (winDetail) {
        winDetail.textContent = info.windowsAsset.sizeText
          ? `${info.windowsAsset.name} · ${info.windowsAsset.sizeText}`
          : info.windowsAsset.name;
      }

      const sizeMetric = document.querySelector("[data-installer-size-metric]");
      if (sizeMetric && info.windowsAsset.sizeText) {
        sizeMetric.textContent = `~${Math.round(parseFloat(info.windowsAsset.sizeText))} MB`;
      }
    }

    const secondaryHeroBtn = document.querySelector('[data-download="linux-or-all"]');
    const secondaryHeroLabel = document.querySelector("[data-secondary-cta-label]");
    const linuxCardBtn = document.querySelector('[data-download="linux-card"]');
    const linuxCardBtnText = document.querySelector("[data-linux-card-btn-text]");
    const linuxDetail = document.querySelector("[data-linux-asset-detail]");

    if (info.linuxAsset) {
      if (secondaryHeroBtn) {
        secondaryHeroBtn.setAttribute("href", info.linuxAsset.url);
      }
      if (secondaryHeroLabel) {
        secondaryHeroLabel.textContent = info.linuxAsset.sizeText
          ? `下载 Linux DEB 包 (${info.linuxAsset.sizeText})`
          : `下载 Linux DEB 包 (${info.tag})`;
      }
      if (linuxCardBtn) {
        linuxCardBtn.setAttribute("href", info.linuxAsset.url);
      }
      if (linuxCardBtnText) {
        linuxCardBtnText.textContent = "下载 .deb";
      }
      if (linuxDetail) {
        linuxDetail.textContent = info.linuxAsset.sizeText
          ? `${info.linuxAsset.name} · ${info.linuxAsset.sizeText}`
          : info.linuxAsset.name;
      }
    } else {
      if (secondaryHeroBtn) {
        secondaryHeroBtn.setAttribute("href", info.htmlUrl);
      }
      if (linuxCardBtn) {
        linuxCardBtn.setAttribute("href", info.htmlUrl);
      }
    }

    const headerCta = document.querySelector('[data-download="header"]');
    if (headerCta) {
      const platform = detectVisitorPlatform();
      if (platform === "linux" && info.linuxAsset) {
        headerCta.setAttribute("href", info.linuxAsset.url);
        headerCta.textContent = `下载 ${info.tag} (.deb)`;
      } else if (platform === "windows" && info.windowsAsset) {
        headerCta.setAttribute("href", info.windowsAsset.url);
        headerCta.textContent = `下载 ${info.tag}`;
      } else {
        headerCta.setAttribute("href", info.htmlUrl);
        headerCta.textContent = `下载 ${info.tag}`;
      }
    }
  }

  function readCachedRelease() {
    try {
      const raw = sessionStorage.getItem(CACHE_KEY);
      if (!raw) {
        return null;
      }
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed.savedAt !== "number" || Date.now() - parsed.savedAt > CACHE_TTL_MS) {
        return null;
      }
      return parsed.info || null;
    } catch {
      return null;
    }
  }

  function writeCachedRelease(info) {
    try {
      sessionStorage.setItem(CACHE_KEY, JSON.stringify({ savedAt: Date.now(), info }));
    } catch {
      // Ignore storage quota errors.
    }
  }

  async function hydrateLatestRelease() {
    const cached = readCachedRelease();
    if (cached) {
      applyLatestRelease(cached);
      return;
    }

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 6000);
    try {
      const response = await fetch(LATEST_RELEASE_API, {
        headers: { Accept: "application/vnd.github+json" },
        signal: controller.signal,
      });
      if (!response.ok) {
        return;
      }
      const data = await response.json();
      const info = parseReleasePayload(data);
      if (info) {
        writeCachedRelease(info);
        applyLatestRelease(info);
      }
    } catch {
      // Static hrefs already point to https://github.com/ZR233/anywork/releases/latest.
    } finally {
      clearTimeout(timeoutId);
    }
  }

  initShowcaseTabs();
  initCopyButtons();
  hydrateLatestRelease();
})();
