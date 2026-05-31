/**
 * Liquid Glass — per-element physics displacement map.
 *
 * 思路：
 *   1. 每个可悬停容器单独算一张 displacement map（按它自身宽×高×圆角×bezel）。
 *      算法：圆角矩形里，离边缘 d 像素以内的像素，沿"内法线"方向给一个位移
 *      magnitude = (1 - d/bezel)^1.5；中心区位移 = 0。
 *      → 视觉上是"边缘折射环 + 中心几乎不变形"，模拟厚玻璃透镜。
 *   2. 把 RGBA 写到 canvas，toDataURL，喂给 SVG <feImage> → <feDisplacementMap>。
 *   3. 每个元素一份 <filter>，inline backdrop-filter 指向自己的 filter id。
 *   4. hover 时 rAF 缓动 feDisplacementMap@scale，从 base 推高到 hover。
 *      其他元素完全不动。
 *   5. 同尺寸+同形状 cache：dataURL 复用，避免重复生成。
 *   6. ResizeObserver 监听尺寸变化（debounced），必要时重生成。
 *
 * 兼容性：仅 Chromium 系。其他浏览器 data-liquid-glass-supported="false"，
 * CSS 自动回退到无折射的伪液态玻璃。
 */
(() => {
  const SVG_NS = "http://www.w3.org/2000/svg";

  // 每种容器的形状参数（圆角、bezel 宽度——bezel 越宽折射环越厚）
  // 注意：.header 故意不在这里。给 header 加 backdrop-filter 会让它成为
  // 子节点 .preference-panel 的合成层父级，触发 Chromium 嵌套 backdrop-filter
  // 的 bug（panel 采样不到真实背景）。顶栏的玻璃感由半透明背景 + 颜色变量提供。
  const SHAPE_CONFIG = [
    { selector: ".nav-item",         radius: 15, bezel: 18, hoverBoost: 1.7 },
    { selector: ".nav-section-title",radius: 10, bezel: 12, hoverBoost: 1.25 },
    { selector: ".preference-toggle",radius: 10, bezel: 12, hoverBoost: 1.5 },
    { selector: ".segmented-control",radius: 8,  bezel: 10, hoverBoost: 1.4 },
    { selector: ".search-box",       radius: 10, bezel: 16, hoverBoost: 1.5 },
    { selector: ".search-engine",    radius: 5,  bezel: 14, hoverBoost: 1.3 },
    { selector: ".preference-panel", radius: 10, bezel: 14, hoverBoost: 1.3 }
  ];
  const HOVER_SELECTOR = SHAPE_CONFIG.map((c) => c.selector).join(", ");
  const EASE_HALF_LIFE = 0.09; // 秒

  const probeSupport = () => {
    if (typeof CSS === "undefined" || !CSS.supports) return false;
    const hasBackdrop =
      CSS.supports("backdrop-filter", "blur(1px)") ||
      CSS.supports("-webkit-backdrop-filter", "blur(1px)");
    if (!hasBackdrop) return false;
    return (
      CSS.supports("backdrop-filter", "url(#x)") ||
      CSS.supports("-webkit-backdrop-filter", "url(#x)")
    );
  };

  // ---- displacement map 生成 ----
  const dataUrlCache = new Map();
  const pendingWarmups = new Map();
  let warmupWorker = null;
  let warmupWorkerUrl = "";
  let warmupWorkerBroken = false;
  let warmupWorkerSeq = 0;

  const normalizeMapParams = (width, height, radius, bezel) => {
    const w = Math.max(2, Math.round(width));
    const h = Math.max(2, Math.round(height));
    // bezel / radius 不能超过短边的一半
    const halfShort = Math.floor(Math.min(w, h) / 2);
    const r = Math.min(radius, halfShort);
    const b = Math.min(bezel, halfShort);

    return {
      w,
      h,
      r,
      b,
      cacheKey: `${w}x${h}r${r}b${b}`
    };
  };

  const fillDisplacementData = (data, w, h, r, b) => {
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let dist;       // 离最近边的距离
        let nx = 0, ny = 0; // 内法线（指向中心方向的单位向量）

        // 判断 corner / edge
        const inLeft   = x < r;
        const inRight  = x >= w - r;
        const inTop    = y < r;
        const inBottom = y >= h - r;

        if (inLeft && inTop) {
          // top-left corner
          const cx = r, cy = r;
          const dx = x - cx, dy = y - cy;
          const dr = Math.sqrt(dx * dx + dy * dy);
          dist = r - dr;
          if (dr > 0.001) { nx = -dx / dr; ny = -dy / dr; }
        } else if (inRight && inTop) {
          const cx = w - 1 - r, cy = r;
          const dx = x - cx, dy = y - cy;
          const dr = Math.sqrt(dx * dx + dy * dy);
          dist = r - dr;
          if (dr > 0.001) { nx = -dx / dr; ny = -dy / dr; }
        } else if (inLeft && inBottom) {
          const cx = r, cy = h - 1 - r;
          const dx = x - cx, dy = y - cy;
          const dr = Math.sqrt(dx * dx + dy * dy);
          dist = r - dr;
          if (dr > 0.001) { nx = -dx / dr; ny = -dy / dr; }
        } else if (inRight && inBottom) {
          const cx = w - 1 - r, cy = h - 1 - r;
          const dx = x - cx, dy = y - cy;
          const dr = Math.sqrt(dx * dx + dy * dy);
          dist = r - dr;
          if (dr > 0.001) { nx = -dx / dr; ny = -dy / dr; }
        } else {
          // 矩形主体：到上下左右的距离取最小
          const dL = x;
          const dR = w - 1 - x;
          const dT = y;
          const dB = h - 1 - y;
          const dH = Math.min(dL, dR);
          const dV = Math.min(dT, dB);
          if (dH < dV) {
            dist = dH;
            nx = (dL < dR) ? 1 : -1;
            ny = 0;
          } else {
            dist = dV;
            nx = 0;
            ny = (dT < dB) ? 1 : -1;
          }
        }

        // bezel 范围之外（中心区）位移 = 0；负距离（角外侧）也 = 0
        // Apple Liquid Glass 风格：边缘折射环 + 中心透镜（基本不变形）。
        // hover 反馈交给 CSS 的 transform: scale 处理，displacement 保持静态。
        let mag = 0;
        if (dist >= 0 && dist < b) {
          const t = dist / b;
          mag = Math.pow(1 - t, 1.5);
        }

        const dx = nx * mag;
        const dy = ny * mag;
        const idx = (y * w + x) * 4;
        // round + clamp
        data[idx]     = Math.max(0, Math.min(255, Math.round(128 + dx * 127)));
        data[idx + 1] = Math.max(0, Math.min(255, Math.round(128 + dy * 127)));
        data[idx + 2] = 128;
        data[idx + 3] = 255;
      }
    }
  };

  const createWarmupWorkerSource = () => `
    const fillDisplacementData = ${fillDisplacementData.toString()};

    self.onmessage = async (event) => {
      const { id, cacheKey, w, h, r, b } = event.data;

      try {
        if (typeof OffscreenCanvas === "undefined") {
          throw new Error("OffscreenCanvas is not available");
        }

        const canvas = new OffscreenCanvas(w, h);
        const ctx = canvas.getContext("2d");
        const imageData = ctx.createImageData(w, h);

        fillDisplacementData(imageData.data, w, h, r, b);
        ctx.putImageData(imageData, 0, 0);

        const blob = await canvas.convertToBlob({ type: "image/png" });
        self.postMessage({ id, cacheKey, blob });
      } catch (error) {
        self.postMessage({
          id,
          cacheKey,
          error: error && error.message ? error.message : String(error)
        });
      }
    };
  `;

  const disableWarmupWorker = () => {
    warmupWorkerBroken = true;
    pendingWarmups.clear();

    if (warmupWorker) {
      warmupWorker.terminate();
      warmupWorker = null;
    }

    if (warmupWorkerUrl) {
      URL.revokeObjectURL(warmupWorkerUrl);
      warmupWorkerUrl = "";
    }
  };

  const getWarmupWorker = () => {
    if (warmupWorkerBroken || warmupWorker) return warmupWorker;
    if (
      typeof Worker === "undefined" ||
      typeof Blob === "undefined" ||
      typeof URL === "undefined"
    ) {
      return null;
    }

    try {
      warmupWorkerUrl = URL.createObjectURL(
        new Blob([createWarmupWorkerSource()], { type: "text/javascript" })
      );
      warmupWorker = new Worker(warmupWorkerUrl, { name: "liquid-glass-map-warmup" });

      warmupWorker.onmessage = (event) => {
        const { id, cacheKey, blob, error } = event.data;
        const pending = pendingWarmups.get(id);
        if (!pending) return;
        pendingWarmups.delete(id);

        if (error || !blob) {
          disableWarmupWorker();
          return;
        }

        if (!dataUrlCache.has(cacheKey)) {
          dataUrlCache.set(cacheKey, URL.createObjectURL(blob));
        }
      };

      warmupWorker.onerror = () => {
        disableWarmupWorker();
      };
    } catch {
      disableWarmupWorker();
    }

    return warmupWorker;
  };

  const warmDisplacementMap = (width, height, radius, bezel) => {
    const params = normalizeMapParams(width, height, radius, bezel);
    if (dataUrlCache.has(params.cacheKey)) return;

    for (const pending of pendingWarmups.values()) {
      if (pending.cacheKey === params.cacheKey) return;
    }

    const worker = getWarmupWorker();
    if (!worker) return;

    try {
      warmupWorkerSeq += 1;
      pendingWarmups.set(warmupWorkerSeq, { cacheKey: params.cacheKey });
      worker.postMessage({ id: warmupWorkerSeq, ...params });
    } catch {
      pendingWarmups.delete(warmupWorkerSeq);
      disableWarmupWorker();
    }
  };

  /**
   * 生成圆角矩形的 displacement map。
   * 返回 dataURL；同一组参数从 cache 复用。
   *
   * 编码：feDisplacementMap 公式 P'(x,y) = P(x + s*(R-0.5), y + s*(G-0.5))
   *   想让"内部像素去采样更外侧"做出折射环，因此每个像素的位移向量方向 = 内法线
   *   （从该像素指向卡片内部）。R = 128 + nx*mag*127, G = 128 + ny*mag*127。
   */
  const makeDisplacementMap = (width, height, radius, bezel) => {
    const { w, h, r, b, cacheKey } = normalizeMapParams(width, height, radius, bezel);
    const cached = dataUrlCache.get(cacheKey);
    if (cached) return cached;

    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    const imageData = ctx.createImageData(w, h);

    fillDisplacementData(imageData.data, w, h, r, b);
    ctx.putImageData(imageData, 0, 0);
    const url = canvas.toDataURL();
    dataUrlCache.set(cacheKey, url);
    return url;
  };

  const matchConfig = (el) => {
    for (const cfg of SHAPE_CONFIG) {
      if (el.matches(cfg.selector)) return cfg;
    }
    return null;
  };

  const init = () => {
    if (!probeSupport()) {
      document.documentElement.dataset.liquidGlassSupported = "false";
      return;
    }

    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    svg.setAttribute("width", "0");
    svg.setAttribute("height", "0");
    svg.style.cssText =
      "position:absolute;width:0;height:0;overflow:hidden;pointer-events:none;";
    const defs = document.createElementNS(SVG_NS, "defs");
    svg.appendChild(defs);
    document.body.appendChild(svg);

    document.documentElement.dataset.liquidGlassSupported = "true";

    const elementMap = new WeakMap();
    let seq = 0;
    // 提前声明：click 兜底监听器在下面会读 active；放这里避免 TDZ。
    let active = document.body.dataset.surface === "liquid";
    let currentHover = null;

    /**
     * 给一个元素分配 / 更新独立 filter。
     * 元素尺寸为 0（display:none 或还没 layout）时直接跳过，等下一次再试。
     * 仅在 surface=liquid 时才写 inline backdrop-filter；否则只更新内部缓存。
     */
    const setupElement = (el) => {
      const cfg = matchConfig(el);
      if (!cfg) return;
      const rect = el.getBoundingClientRect();
      const w = Math.round(rect.width);
      const h = Math.round(rect.height);
      if (w < 4 || h < 4) return;

      const isLiquidActive = document.body.dataset.surface === "liquid";

      let entry = elementMap.get(el);
      if (entry && entry.width === w && entry.height === h) {
        // 已经分配过且尺寸没变。如果当前是液态玻璃，确保 inline filter 还在；
        // 如果不是，确保 inline filter 已被清空。
        if (isLiquidActive) {
          const chain = `url(#${entry.id}) blur(2px) saturate(150%) brightness(1.02)`;
          if (el.style.backdropFilter !== chain) {
            el.style.backdropFilter = chain;
            el.style.webkitBackdropFilter = chain;
          }
        } else {
          if (el.style.backdropFilter) {
            el.style.backdropFilter = "";
            el.style.webkitBackdropFilter = "";
          }
        }
        return;
      }

      const url = makeDisplacementMap(w, h, cfg.radius, cfg.bezel);
      const baseScale = Math.min(cfg.bezel * 2.0, 36);
      const hoverScale = baseScale * cfg.hoverBoost;

      if (!entry) {
        seq += 1;
        const id = `lg-${seq}`;
        const filter = document.createElementNS(SVG_NS, "filter");
        filter.setAttribute("id", id);
        filter.setAttribute("x", "0%");
        filter.setAttribute("y", "0%");
        filter.setAttribute("width", "100%");
        filter.setAttribute("height", "100%");
        filter.setAttribute("filterUnits", "objectBoundingBox");
        filter.setAttribute("primitiveUnits", "userSpaceOnUse");
        filter.setAttribute("color-interpolation-filters", "sRGB");

        const feImage = document.createElementNS(SVG_NS, "feImage");
        feImage.setAttributeNS("http://www.w3.org/1999/xlink", "xlink:href", url);
        feImage.setAttribute("href", url);
        feImage.setAttribute("x", "0");
        feImage.setAttribute("y", "0");
        feImage.setAttribute("width", String(w));
        feImage.setAttribute("height", String(h));
        feImage.setAttribute("result", "dispMap");
        feImage.setAttribute("preserveAspectRatio", "none");

        const feDisp = document.createElementNS(SVG_NS, "feDisplacementMap");
        feDisp.setAttribute("in", "SourceGraphic");
        feDisp.setAttribute("in2", "dispMap");
        feDisp.setAttribute("scale", String(baseScale));
        feDisp.setAttribute("xChannelSelector", "R");
        feDisp.setAttribute("yChannelSelector", "G");

        filter.appendChild(feImage);
        filter.appendChild(feDisp);
        defs.appendChild(filter);

        const filterChain = `url(#${id}) blur(2px) saturate(150%) brightness(1.02)`;
        // 仅在液态玻璃模式下写 inline；其他模式只准备好 filter 备用
        if (isLiquidActive) {
          el.style.backdropFilter = filterChain;
          el.style.webkitBackdropFilter = filterChain;
        }

        entry = {
          id,
          width: w,
          height: h,
          feImage,
          feDisp,
          baseScale,
          hoverScale,
          currentScale: baseScale,
          targetScale: baseScale,
          animId: 0,
          lastT: 0
        };
        elementMap.set(el, entry);
      } else {
        // 尺寸变了：换 dataURL，更新 feImage 大小
        entry.width = w;
        entry.height = h;
        entry.baseScale = baseScale;
        entry.hoverScale = hoverScale;
        entry.feImage.setAttributeNS("http://www.w3.org/1999/xlink", "xlink:href", url);
        entry.feImage.setAttribute("href", url);
        entry.feImage.setAttribute("width", String(w));
        entry.feImage.setAttribute("height", String(h));
        const isHover = entry.targetScale === entry.hoverScale;
        entry.targetScale = isHover ? hoverScale : baseScale;
      }
    };

    const warmElement = (el) => {
      const cfg = matchConfig(el);
      if (!cfg || el.closest("[hidden]")) return;

      const rect = el.getBoundingClientRect();
      const w = Math.round(rect.width);
      const h = Math.round(rect.height);
      if (w < 4 || h < 4) return;

      warmDisplacementMap(w, h, cfg.radius, cfg.bezel);
    };

    const warmupQueue = new Set();
    let warmupFlush = 0;

    const flushWarmupQueue = (deadline) => {
      warmupFlush = 0;
      const frameStart = performance.now();
      const hasIdleBudget = deadline && typeof deadline.timeRemaining === "function";

      while (warmupQueue.size) {
        if (hasIdleBudget) {
          if (deadline.timeRemaining() < 4) break;
        } else if (performance.now() - frameStart > 4) {
          break;
        }

        const el = warmupQueue.values().next().value;
        warmupQueue.delete(el);

        if (el.isConnected) {
          warmElement(el);
        }
      }

      if (warmupQueue.size) {
        requestWarmupFlush();
      }
    };

    const requestWarmupFlush = () => {
      if (warmupFlush) return;

      if ("requestIdleCallback" in window) {
        warmupFlush = requestIdleCallback(flushWarmupQueue, { timeout: 1200 });
      } else {
        warmupFlush = requestAnimationFrame(() => flushWarmupQueue());
      }
    };

    const scheduleWarmup = (elements) => {
      for (const el of elements) {
        warmupQueue.add(el);
      }

      if (warmupQueue.size) {
        requestWarmupFlush();
      }
    };

    // ---- 启动时给所有可悬停元素分配 filter（仅在液态玻璃下） ----
    if (document.body.dataset.surface === "liquid") {
      document.querySelectorAll(HOVER_SELECTOR).forEach(setupElement);
    } else {
      scheduleWarmup(document.querySelectorAll(HOVER_SELECTOR));
    }

    // ---- ResizeObserver：尺寸变化重新生成 ----
    let resizeFlush = 0;
    const pendingResize = new Set();
    const flushResize = () => {
      if (active) {
        pendingResize.forEach(setupElement);
      } else {
        scheduleWarmup(pendingResize);
      }
      pendingResize.clear();
      resizeFlush = 0;
    };
    if ("ResizeObserver" in window) {
      const ro = new ResizeObserver((entries) => {
        for (const e of entries) {
          pendingResize.add(e.target);
        }
        if (!resizeFlush) {
          resizeFlush = requestAnimationFrame(flushResize);
        }
      });
      document.querySelectorAll(HOVER_SELECTOR).forEach((el) => ro.observe(el));
    }

    // 默认 hidden 的浮窗（搜索引擎下拉、偏好面板）：监听 hidden 属性变化，
    // 一变成可见立即 setup，避免"展开瞬间没玻璃"的空窗。
    const setupElementWithRetry = (el, retriesLeft = 3) => {
      setupElement(el);
      // 没拿到尺寸（display:none 残留 / layout 未完成）就 rAF 重试几次
      if (!elementMap.has(el) && retriesLeft > 0) {
        requestAnimationFrame(() => setupElementWithRetry(el, retriesLeft - 1));
      }
    };

    const hiddenWatchTargets = document.querySelectorAll(".search-engine, .preference-panel");
    if (hiddenWatchTargets.length) {
      const hiddenMo = new MutationObserver((entries) => {
        for (const m of entries) {
          if (m.type === "attributes" && m.attributeName === "hidden") {
            const el = m.target;
            if (!el.hidden) {
              // 浮窗刚展开。同步尝试 + rAF 兜底，并把它内部的可悬停后代一起带上。
              if (active) {
                setupElementWithRetry(el);
                el.querySelectorAll(HOVER_SELECTOR).forEach((child) =>
                  setupElementWithRetry(child)
                );
              } else {
                scheduleWarmup([el]);
                scheduleWarmup(el.querySelectorAll(HOVER_SELECTOR));
              }
            }
          }
        }
      });
      hiddenWatchTargets.forEach((el) =>
        hiddenMo.observe(el, { attributes: true, attributeFilter: ["hidden"] })
      );
    }

    // 兜底：如果偏好面板在 setup 时仍然没拿到尺寸（极少数浏览器
    // 在 hidden->false 后第一次 getBoundingClientRect 会得到 0），
    // 把 click 事件一并 hook，给浏览器一帧时间渲染再试。
    document.addEventListener("click", (event) => {
      if (!active) return;
      const toggle = event.target.closest && event.target.closest(
        ".preference-toggle, #search-engine-toggle"
      );
      if (!toggle) return;
      // 等浏览器渲染面板后再 setup
      requestAnimationFrame(() => {
        document.querySelectorAll(
          ".preference-panel:not([hidden]), .search-engine:not([hidden])"
        ).forEach((el) => {
          setupElementWithRetry(el);
          el.querySelectorAll(HOVER_SELECTOR).forEach((c) =>
            setupElementWithRetry(c)
          );
        });
      });
    }, true);

    // ---- hover 反馈：交给 CSS 的 transform: scale 处理 ----
    // Apple Liquid Glass 的 hover/press 是"gel-like" 的整体弹性形变，
    // 不是改 displacement——displacement 保持静态最像玻璃透镜。
    // 这里 setHovered 不再驱动 scale 动画，但保留接口给将来需要时使用。
    const setHovered = () => {
      // no-op：交由 CSS :hover 控制
    };

    // ---- 鼠标交互 ----

    const clearHover = () => {
      if (currentHover) {
        setHovered(currentHover, false);
        currentHover = null;
      }
    };

    new MutationObserver(() => {
      active = document.body.dataset.surface === "liquid";
      if (!active) {
        clearHover();
        // 切到非液态玻璃：清除所有 inline backdrop-filter，让 CSS 接管
        document.querySelectorAll(HOVER_SELECTOR).forEach((el) => {
          el.style.backdropFilter = "";
          el.style.webkitBackdropFilter = "";
        });
      } else {
        // 切回液态玻璃：重新给每个元素装上 inline filter
        document.querySelectorAll(HOVER_SELECTOR).forEach((el) => {
          const entry = elementMap.get(el);
          if (entry) {
            const chain = `url(#${entry.id}) blur(2px) saturate(150%) brightness(1.02)`;
            el.style.backdropFilter = chain;
            el.style.webkitBackdropFilter = chain;
          } else {
            // 还没分配过 filter（比如初始 hidden 的浮窗）就现场尝试
            setupElement(el);
          }
        });
      }
    }).observe(document.body, {
      attributes: true,
      attributeFilter: ["data-surface"]
    });

    document.addEventListener(
      "pointerover",
      (event) => {
        if (!active) return;
        const target = event.target.closest && event.target.closest(HOVER_SELECTOR);
        if (!target || target === currentHover) return;
        // 懒加载：默认 hidden 的元素（搜索引擎下拉、偏好面板）启动时尺寸为 0，
        // 第一次 hover 时再分配 filter
        if (!elementMap.has(target)) {
          setupElement(target);
          if (!elementMap.has(target)) return; // 真还没尺寸就放弃
        }
        if (currentHover) setHovered(currentHover, false);
        currentHover = target;
        setHovered(target, true);
      },
      { passive: true }
    );

    document.addEventListener(
      "pointerout",
      (event) => {
        if (!active || !currentHover) return;
        if (event.relatedTarget && currentHover.contains(event.relatedTarget)) return;
        clearHover();
      },
      { passive: true }
    );

    window.addEventListener("blur", clearHover, { passive: true });
    document.addEventListener(
      "visibilitychange",
      () => {
        if (document.hidden) clearHover();
      },
      { passive: true }
    );
  };

  if (document.body) {
    init();
  } else {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  }
})();
