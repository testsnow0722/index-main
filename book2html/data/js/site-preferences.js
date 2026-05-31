(() => {
  const storageKey = "sitePreferences";
  const defaults = {
    theme: "light",
    surface: "glass",
    density: "comfortable",
    themeBackgroundPriority: "off",
    backgroundBlur: 0,
    cardBrightness: 0,
    cardOpacity: 0,
    textContrast: "off",
    textContrastMethod: "sample",
    textColorMode: "default",
    textColor: "#2563eb",
    textBrightness: 0,
    textShadow: "off",
    textBold: "off"
  };

  const options = {
    theme: [
      { value: "light", label: "浅色" },
      { value: "dark", label: "深色" }
    ],
    surface: [
      { value: "glass", label: "毛玻璃" },
      { value: "liquid", label: "液态玻璃" },
      { value: "liquid-lite", label: "液态·兼容" },
      { value: "acrylic", label: "亚克力" },
      { value: "mica", label: "云母" },
      { value: "paper", label: "磨砂纸" },
      { value: "obsidian", label: "黑曜石" },
      { value: "neon", label: "赛博霓虹" },
      { value: "pixel", label: "8-bit 像素" },
      { value: "plain", label: "简洁" }
    ],
    density: [
      { value: "comfortable", label: "宽松" },
      { value: "compact", label: "紧凑" }
    ],
    themeBackgroundPriority: [
      { value: "off", label: "关闭" },
      { value: "on", label: "主题" },
      { value: "simple", label: "简洁" }
    ],
    textContrast: [
      { value: "off", label: "关" },
      { value: "primary", label: "标题" },
      { value: "full", label: "全部" }
    ],
    textContrastMethod: [
      { value: "sample", label: "标准" },
      { value: "enhance", label: "增强" }
    ]
  };
  const preferenceGroups = ["theme", "surface", "density", "themeBackgroundPriority", "backgroundBlur", "textColor"];
  const advancedPreferenceGroups = ["textBrightness", "cardBrightness", "cardOpacity", "textContrast", "textContrastMethod"];
  const nativeCardRendererSurfaces = new Set(["acrylic", "obsidian", "liquid", "liquid-lite", "pixel", "neon"]);
  const textColorPalette = [
    { value: "#111827", label: "墨黑" },
    { value: "#475569", label: "岩灰" },
    { value: "#dc2626", label: "绯红" },
    { value: "#ea580c", label: "橙色" },
    { value: "#d97706", label: "琥珀" },
    { value: "#16a34a", label: "翠绿" },
    { value: "#0891b2", label: "青蓝" },
    { value: "#2563eb", label: "蓝色" },
    { value: "#7c3aed", label: "紫色" },
    { value: "#c026d3", label: "洋红" },
    { value: "#db2777", label: "玫红" },
    { value: "#f8fafc", label: "雪白" }
  ];
  const backgroundBlurRange = { min: 0, max: 16, step: 0.1 };
  const brightnessRange = { min: -100, max: 100, step: 1 };
  const opacityRange = { min: -100, max: 100, step: 1 };
  const rangeConfigs = {
    backgroundBlur: {
      ...backgroundBlurRange,
      format: (value) => formatBackgroundBlur(value),
      output: (value) => `${formatBackgroundBlur(value)}px`,
      normalize: (value) => normalizeBackgroundBlur(value)
    },
    cardBrightness: {
      ...brightnessRange,
      format: (value) => `${normalizeCardBrightness(value)}`,
      output: (value) => formatSignedPercent(normalizeCardBrightness(value)),
      normalize: (value) => normalizeCardBrightness(value)
    },
    cardOpacity: {
      ...opacityRange,
      format: (value) => `${normalizeCardOpacity(value)}`,
      output: (value) => formatSignedPercent(normalizeCardOpacity(value)),
      normalize: (value) => normalizeCardOpacity(value)
    },
    textBrightness: {
      ...brightnessRange,
      format: (value) => `${normalizeTextBrightness(value)}`,
      output: (value) => formatSignedPercent(normalizeTextBrightness(value)),
      normalize: (value) => normalizeTextBrightness(value)
    }
  };

  const labels = {
    theme: "主题",
    surface: "质感",
    density: "密度",
    themeBackgroundPriority: "主题背景优先",
    backgroundBlur: "背景模糊",
    cardBrightness: "卡片明暗度",
    cardOpacity: "卡片透明度",
    textColor: "文字主题色",
    textBrightness: "文字明暗度",
    textContrast: "文字反色",
    textContrastMethod: "实现方式"
  };

  const normalizeBackgroundBlur = (value) => {
    if (value === "off") {
      return 0;
    }

    if (value === "light") {
      return 4;
    }

    if (value === "medium") {
      return 9;
    }

    const parsed = Number.parseFloat(value);

    if (!Number.isFinite(parsed)) {
      return defaults.backgroundBlur;
    }

    const stepped = Math.round(parsed / backgroundBlurRange.step) * backgroundBlurRange.step;
    return Math.min(backgroundBlurRange.max, Math.max(backgroundBlurRange.min, Number(stepped.toFixed(1))));
  };

  const formatBackgroundBlur = (value) => {
    const normalized = normalizeBackgroundBlur(value);
    return Number.isInteger(normalized) ? `${normalized}` : normalized.toFixed(1);
  };

  const normalizeBrightness = (value, fallback) => {
    const parsed = Number.parseFloat(value);

    if (!Number.isFinite(parsed)) {
      return fallback;
    }

    const stepped = Math.round(parsed / brightnessRange.step) * brightnessRange.step;
    return Math.min(brightnessRange.max, Math.max(brightnessRange.min, stepped));
  };

  const formatSignedPercent = (value) => `${value > 0 ? "+" : ""}${value}%`;

  const normalizeCardBrightness = (value) => normalizeBrightness(value, defaults.cardBrightness);

  const normalizeCardOpacity = (value) => {
    const parsed = Number.parseFloat(value);

    if (!Number.isFinite(parsed)) {
      return defaults.cardOpacity;
    }

    const stepped = Math.round(parsed / opacityRange.step) * opacityRange.step;
    return Math.min(opacityRange.max, Math.max(opacityRange.min, stepped));
  };

  const normalizeTextBrightness = (value) => {
    return normalizeBrightness(value, defaults.textBrightness);
  };

  const normalizeTextColor = (value, fallback = defaults.textColor) => {
    const color = String(value || "").trim();
    const match = color.match(/^#?([0-9a-f]{3}|[0-9a-f]{6})$/i);

    if (!match) {
      return fallback;
    }

    const raw = match[1].length === 3 ? match[1].replace(/(.)/g, "$1$1") : match[1];
    return `#${raw.toLowerCase()}`;
  };

  const getTextColorInputValue = (value) => {
    const color = String(value || "").trim();
    const match = color.match(/^#?([0-9a-f]{3}|[0-9a-f]{6})$/i);

    if (!match) {
      return null;
    }

    return normalizeTextColor(color);
  };

  const hexToRgb = (value) => {
    const color = normalizeTextColor(value);
    return {
      r: parseInt(color.slice(1, 3), 16),
      g: parseInt(color.slice(3, 5), 16),
      b: parseInt(color.slice(5, 7), 16),
      a: 1
    };
  };

  const rgbToHex = ({ r, g, b }) => {
    const toChannel = (value) => Math.round(Math.min(255, Math.max(0, value))).toString(16).padStart(2, "0");
    return `#${toChannel(r)}${toChannel(g)}${toChannel(b)}`;
  };

  const adjustTextColorBrightness = (color, brightness) => {
    const rgb = hexToRgb(color);
    const amount = normalizeTextBrightness(brightness);
    const target = amount >= 0 ? 255 : 0;
    const ratio = Math.abs(amount) / 100;

    return rgbToHex({
      r: rgb.r + (target - rgb.r) * ratio,
      g: rgb.g + (target - rgb.g) * ratio,
      b: rgb.b + (target - rgb.b) * ratio
    });
  };

  const getOptionValue = (group, value, fallback) => {
    if (group === "backgroundBlur") {
      return normalizeBackgroundBlur(value);
    }

    if (group === "cardBrightness") {
      return normalizeCardBrightness(value);
    }

    if (group === "cardOpacity") {
      return normalizeCardOpacity(value);
    }

    if (group === "textContrast" && value === "level1") {
      return "primary";
    }

    if (group === "textContrast" && value === "level2") {
      return "full";
    }

    return options[group].some((option) => option.value === value) ? value : fallback;
  };

  const readPreferences = () => {
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey) || "{}");

      return {
        theme: getOptionValue("theme", saved.theme, defaults.theme),
        surface: getOptionValue("surface", saved.surface, defaults.surface),
        density: getOptionValue("density", saved.density, defaults.density),
        themeBackgroundPriority: getOptionValue("themeBackgroundPriority", saved.themeBackgroundPriority, defaults.themeBackgroundPriority),
        backgroundBlur: getOptionValue("backgroundBlur", saved.backgroundBlur, defaults.backgroundBlur),
        cardBrightness: getOptionValue("cardBrightness", saved.cardBrightness, defaults.cardBrightness),
        cardOpacity: getOptionValue("cardOpacity", saved.cardOpacity, defaults.cardOpacity),
        textContrast: getOptionValue("textContrast", saved.textContrast, defaults.textContrast),
        textContrastMethod: getOptionValue("textContrastMethod", saved.textContrastMethod, defaults.textContrastMethod),
        textColorMode: saved.textColorMode === "custom" ? "custom" : defaults.textColorMode,
        textColor: normalizeTextColor(saved.textColor),
        textBrightness: normalizeTextBrightness(saved.textBrightness),
        textShadow: ["off", "on", "enhance"].includes(saved.textShadow) ? saved.textShadow : defaults.textShadow,
        textBold: saved.textBold === "on" ? "on" : defaults.textBold
      };
    } catch {
      return { ...defaults };
    }
  };

  const writePreferences = (preferences) => {
    try {
      localStorage.setItem(storageKey, JSON.stringify(preferences));
    } catch {
      // Preference persistence is optional for local-only usage.
    }
  };

  let preferences = readPreferences();
  let textContrastRequest = 0;
  let textContrastFrame = 0;
  let textContrastSamplerCache = { key: "", promise: null };
  let colorResolverElement = null;
  const localTextContrastSelector = [
    ".nav-item[data-text-tone]",
    ".nav-section-title[data-text-tone]",
    ".search-box[data-text-tone]",
    ".search-engine[data-text-tone]",
    ".header-menu a[data-text-tone]"
  ].join(", ");

  const getFallbackBackgroundColor = (styles) => {
    const surface = document.body.dataset.surface;

    if (surface === "obsidian" || surface === "neon" || surface === "pixel") {
      return { r: 24, g: 30, b: 40, a: 1 };
    }

    if (document.body.dataset.theme === "dark") {
      return { r: 15, g: 23, b: 42, a: 1 };
    }

    return parseColor(styles.getPropertyValue("--page-bg")) || { r: 246, g: 248, b: 249, a: 1 };
  };

  const parseColor = (value) => {
    const color = String(value || "").trim();

    if (color === "transparent") {
      return { r: 0, g: 0, b: 0, a: 0 };
    }

    const hex = color.match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);

    if (hex) {
      const raw = hex[1].length === 3 ? hex[1].replace(/(.)/g, "$1$1") : hex[1];

      return {
        r: parseInt(raw.slice(0, 2), 16),
        g: parseInt(raw.slice(2, 4), 16),
        b: parseInt(raw.slice(4, 6), 16),
        a: 1
      };
    }

    const rgb = color.match(/^rgba?\(([^)]+)\)$/i);

    if (rgb) {
      const content = rgb[1].trim();
      let parts;
      let alpha;
      const toRgbChannel = (part) => {
        const value = Number.parseFloat(part);
        return part.endsWith("%") ? value * 2.55 : value;
      };
      const toAlpha = (part) => {
        const value = Number.parseFloat(part);
        return part.endsWith("%") ? value / 100 : value;
      };

      if (content.includes(",")) {
        parts = content.split(",").map((part) => part.trim());
        alpha = parts[3];
      } else {
        const split = content.split("/");
        parts = split[0].trim().split(/\s+/);
        alpha = split[1];
      }

      return {
        r: toRgbChannel(parts[0]),
        g: toRgbChannel(parts[1]),
        b: toRgbChannel(parts[2]),
        a: alpha === undefined ? 1 : toAlpha(alpha.trim())
      };
    }

    const srgb = color.match(/^color\(\s*srgb\s+(.+)\)$/i);

    if (!srgb) {
      return null;
    }

    const split = srgb[1].split("/");
    const channels = split[0].trim().split(/\s+/);
    const toChannel = (part) => {
      const value = Number.parseFloat(part);
      return part.endsWith("%") ? value * 2.55 : value * 255;
    };
    const toAlpha = (part) => {
      const value = Number.parseFloat(part);
      return part.trim().endsWith("%") ? value / 100 : value;
    };

    return {
      r: toChannel(channels[0]),
      g: toChannel(channels[1]),
      b: toChannel(channels[2]),
      a: split[1] === undefined ? 1 : toAlpha(split[1])
    };
  };

  const getColorResolverElement = () => {
    if (colorResolverElement && colorResolverElement.isConnected) {
      return colorResolverElement;
    }

    colorResolverElement = document.createElement("span");
    colorResolverElement.setAttribute("aria-hidden", "true");
    colorResolverElement.style.position = "fixed";
    colorResolverElement.style.left = "-1px";
    colorResolverElement.style.top = "-1px";
    colorResolverElement.style.width = "0";
    colorResolverElement.style.height = "0";
    colorResolverElement.style.overflow = "hidden";
    colorResolverElement.style.pointerEvents = "none";
    document.body.append(colorResolverElement);
    return colorResolverElement;
  };

  const resolveColorValue = (value) => {
    const parsed = parseColor(value);

    if (parsed) {
      return parsed;
    }

    if (!document.body) {
      return null;
    }

    const resolver = getColorResolverElement();
    resolver.style.backgroundColor = "";
    resolver.style.backgroundColor = value;
    return parseColor(getComputedStyle(resolver).backgroundColor);
  };

  const resolveVariableColor = (name) => resolveColorValue(`var(${name})`);

  const withAlpha = (color, opacity) => {
    if (!color) {
      return null;
    }

    const alpha = Number.isFinite(opacity) ? opacity : 1;
    return { ...color, a: color.a * Math.min(1, Math.max(0, alpha)) };
  };

  const blendColor = (foreground, background) => {
    if (!foreground) {
      return background;
    }

    if (!background || foreground.a >= 1) {
      return { r: foreground.r, g: foreground.g, b: foreground.b, a: 1 };
    }

    return {
      r: foreground.r * foreground.a + background.r * (1 - foreground.a),
      g: foreground.g * foreground.a + background.g * (1 - foreground.a),
      b: foreground.b * foreground.a + background.b * (1 - foreground.a),
      a: 1
    };
  };

  const getLuminance = (color) => {
    const channel = (value) => {
      const normalized = value / 255;
      return normalized <= 0.03928 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
    };

    return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
  };

  const extractBackgroundImageUrl = (value) => {
    const match = String(value || "").match(/url\((?:"([^"]+)"|'([^']+)'|([^)]*))\)/);
    const url = match && (match[1] || match[2] || match[3]);

    if (!url || url === "none") {
      return "";
    }

    return new URL(url.trim(), window.location.href).href;
  };

  const sampleImageColor = (url) => new Promise((resolve, reject) => {
    const image = new Image();

    image.onload = () => {
      try {
        const canvas = document.createElement("canvas");
        const width = 24;
        const height = 14;
        const context = canvas.getContext("2d", { willReadFrequently: true });

        if (!context) {
          reject(new Error("Canvas is unavailable"));
          return;
        }

        canvas.width = width;
        canvas.height = height;
        context.drawImage(image, 0, 0, width, height);

        const pixels = context.getImageData(0, 0, width, height).data;
        let r = 0;
        let g = 0;
        let b = 0;
        let count = 0;

        for (let i = 0; i < pixels.length; i += 4) {
          const alpha = pixels[i + 3] / 255;

          if (alpha <= 0.02) {
            continue;
          }

          r += pixels[i] * alpha;
          g += pixels[i + 1] * alpha;
          b += pixels[i + 2] * alpha;
          count += alpha;
        }

        if (!count) {
          reject(new Error("No visible pixels"));
          return;
        }

        resolve({ r: r / count, g: g / count, b: b / count, a: 1 });
      } catch (error) {
        reject(error);
      }
    };

    image.onerror = reject;
    image.src = url;
  });

  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

  const clearLocalTextContrastTones = () => {
    document.querySelectorAll(localTextContrastSelector).forEach((element) => {
      delete element.dataset.textTone;
    });
  };

  const createImageSampler = (url, styles) => new Promise((resolve, reject) => {
    const image = new Image();

    image.onload = () => {
      try {
        const viewportWidth = Math.max(1, window.innerWidth || document.documentElement.clientWidth || 1);
        const viewportHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || 1);
        const viewportScale = Math.min(1, 520 / viewportWidth, 320 / viewportHeight);
        const canvas = document.createElement("canvas");
        const context = canvas.getContext("2d", { willReadFrequently: true });

        if (!context) {
          reject(new Error("Canvas is unavailable"));
          return;
        }

        canvas.width = Math.max(1, Math.round(viewportWidth * viewportScale));
        canvas.height = Math.max(1, Math.round(viewportHeight * viewportScale));

        const naturalWidth = image.naturalWidth || image.width;
        const naturalHeight = image.naturalHeight || image.height;
        const backgroundScale = Number.parseFloat(styles.getPropertyValue("--site-background-scale")) || 1;
        const coverScale = Math.max(canvas.width / naturalWidth, canvas.height / naturalHeight) * backgroundScale;
        const width = naturalWidth * coverScale;
        const height = naturalHeight * coverScale;
        const left = (canvas.width - width) / 2;
        const top = (canvas.height - height) / 2;

        context.drawImage(image, left, top, width, height);

        const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
        const sampleRect = (rect) => {
          const centerX = (rect.left + rect.width / 2) * viewportScale;
          const centerY = (rect.top + rect.height / 2) * viewportScale;
          const sampleWidth = clamp(rect.width * viewportScale, 8, Math.min(96, canvas.width));
          const sampleHeight = clamp(rect.height * viewportScale, 8, Math.min(72, canvas.height));
          const startX = Math.floor(clamp(centerX - sampleWidth / 2, 0, canvas.width - 1));
          const endX = Math.ceil(clamp(centerX + sampleWidth / 2, startX + 1, canvas.width));
          const startY = Math.floor(clamp(centerY - sampleHeight / 2, 0, canvas.height - 1));
          const endY = Math.ceil(clamp(centerY + sampleHeight / 2, startY + 1, canvas.height));
          let r = 0;
          let g = 0;
          let b = 0;
          let count = 0;

          for (let y = startY; y < endY; y += 1) {
            for (let x = startX; x < endX; x += 1) {
              const index = (y * canvas.width + x) * 4;
              const alpha = pixels[index + 3] / 255;

              if (alpha <= 0.02) {
                continue;
              }

              r += pixels[index] * alpha;
              g += pixels[index + 1] * alpha;
              b += pixels[index + 2] * alpha;
              count += alpha;
            }
          }

          return count ? { r: r / count, g: g / count, b: b / count, a: 1 } : null;
        };

        resolve({ sampleRect });
      } catch (error) {
        reject(error);
      }
    };

    image.onerror = reject;
    image.src = url;
  });

  const getImageSampler = (url, styles) => {
    const backgroundScale = styles.getPropertyValue("--site-background-scale").trim();
    const key = `${url}|${window.innerWidth}x${window.innerHeight}|${backgroundScale}`;

    if (textContrastSamplerCache.key === key && textContrastSamplerCache.promise) {
      return textContrastSamplerCache.promise;
    }

    textContrastSamplerCache = {
      key,
      promise: createImageSampler(url, styles)
    };

    return textContrastSamplerCache.promise;
  };

  const getVisibleRect = (element) => {
    if (!element) {
      return null;
    }

    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 ? rect : null;
  };

  const getSampleRect = (entry) => {
    const sampleRect = getVisibleRect(entry.sampleElement);
    const elementRect = getVisibleRect(entry.element);
    const rect = sampleRect || elementRect;

    if (!rect) {
      return null;
    }

    const width = clamp(rect.width * (entry.widthRatio || 0.86), 16, entry.maxWidth || 140);
    const height = clamp(rect.height * (entry.heightRatio || 1.2), 10, entry.maxHeight || 70);
    const centerX = rect.left + rect.width / 2;
    const centerY = sampleRect || !entry.fallbackY ? rect.top + rect.height / 2 : elementRect.top + elementRect.height * entry.fallbackY;

    return {
      left: centerX - width / 2,
      top: centerY - height / 2,
      width,
      height
    };
  };

  const getSurfaceFallbackColor = (kind) => {
    if (kind === "header") {
      return resolveVariableColor("--header-final-bg") || resolveVariableColor("--header-bg");
    }

    if (kind === "panel") {
      return resolveVariableColor("--panel-final-bg") || resolveVariableColor("--panel-bg");
    }

    return resolveVariableColor("--card-final-bg") || resolveVariableColor("--card-bg");
  };

  const getPseudoSurfaceColor = (element) => {
    try {
      const styles = getComputedStyle(element, "::before");
      const content = styles.content;

      if (!content || content === "none") {
        return null;
      }

      const color = parseColor(styles.backgroundColor);

      if (!color || color.a <= 0.02) {
        return null;
      }

      return withAlpha(color, Number.parseFloat(styles.opacity));
    } catch {
      return null;
    }
  };

  const getElementSurfaceColor = (element, kind = "card") => {
    const pseudoColor = element ? getPseudoSurfaceColor(element) : null;

    if (pseudoColor && pseudoColor.a > 0.02) {
      return pseudoColor;
    }

    const color = element ? parseColor(getComputedStyle(element).backgroundColor) : null;

    if (color && color.a > 0.02) {
      return color;
    }

    return getSurfaceFallbackColor(kind) || { r: 255, g: 255, b: 255, a: 0 };
  };

  const getLocalTextContrastEntries = () => {
    const entries = [];
    const add = (element, sampleElement, surfaceElement, options = {}) => {
      entries.push({
        element,
        sampleElement: sampleElement || element,
        surfaceElement: surfaceElement || element,
        surfaceKind: options.surfaceKind || "card",
        ...options
      });
    };

    document.querySelectorAll(".nav-item").forEach((element) => {
      add(element, element.querySelector(".nav-name"), element, {
        fallbackY: 0.38,
        heightRatio: 1.35,
        maxWidth: 120,
        maxHeight: 56
      });
    });

    document.querySelectorAll(".nav-section-title").forEach((element) => {
      add(element, element, element, {
        heightRatio: 1.1,
        maxHeight: 52
      });
    });

    document.querySelectorAll(".search-box").forEach((element) => {
      add(element, element.querySelector(".search-input"), element, {
        surfaceKind: "panel",
        widthRatio: 0.7,
        heightRatio: 0.8,
        maxWidth: 220,
        maxHeight: 52
      });
    });

    document.querySelectorAll(".search-engine:not([hidden])").forEach((element) => {
      add(element, element.querySelector(".search-engine-option") || element, element, {
        surfaceKind: "panel",
        widthRatio: 0.72,
        heightRatio: 1.2,
        maxWidth: 180,
        maxHeight: 58
      });
    });

    document.querySelectorAll(".header-menu a").forEach((element) => {
      add(element, element, element.closest(".header") || element, {
        surfaceKind: "header",
        heightRatio: 1.15,
        maxWidth: 100,
        maxHeight: 48
      });
    });

    return entries;
  };

  const setLocalTextContrastTones = (backgroundColor, styles, sampler) => {
    clearLocalTextContrastTones();

    getLocalTextContrastEntries().forEach((entry) => {
      const rect = getSampleRect(entry);

      if (!rect) {
        return;
      }

      const sampledColor = sampler ? sampler.sampleRect(rect) || backgroundColor : backgroundColor;
      const surfaceColor = getElementSurfaceColor(entry.surfaceElement, entry.surfaceKind);
      const finalColor = blendColor(surfaceColor, sampledColor);
      entry.element.dataset.textTone = getLuminance(finalColor) < 0.52 ? "dark" : "light";
    });
  };

  const setTextContrastTone = (backgroundColor) => {
    const cardColor = getElementSurfaceColor(document.querySelector(".nav-item") || document.querySelector(".nav-section-title"), "card");
    const finalColor = blendColor(cardColor, backgroundColor);
    document.body.dataset.textContrastTone = getLuminance(finalColor) < 0.52 ? "dark" : "light";
  };

  const updateTextContrastTone = () => {
    const request = ++textContrastRequest;
    const isSampleContrast = preferences.textContrast !== "off" && preferences.textContrastMethod === "sample";
    const isEnhancedContrast = preferences.textContrast !== "off" && preferences.textContrastMethod === "enhance";

    if (!isSampleContrast && !isEnhancedContrast) {
      delete document.body.dataset.textContrastTone;
      clearLocalTextContrastTones();
      return;
    }

    const styles = getComputedStyle(document.body);
    const backgroundUrl = extractBackgroundImageUrl(styles.getPropertyValue("--site-background-image"));
    const fallbackColor = getFallbackBackgroundColor(styles);
    const useColor = (color) => {
      if (request !== textContrastRequest) {
        return;
      }

      if (isEnhancedContrast) {
        delete document.body.dataset.textContrastTone;
        setLocalTextContrastTones(color, styles);
      } else {
        clearLocalTextContrastTones();
        setTextContrastTone(color);
      }
    };

    if (!backgroundUrl) {
      useColor(fallbackColor);
      return;
    }

    if (isEnhancedContrast) {
      getImageSampler(backgroundUrl, styles)
        .then((sampler) => {
          if (request !== textContrastRequest) {
            return;
          }

          delete document.body.dataset.textContrastTone;
          setLocalTextContrastTones(fallbackColor, styles, sampler);
        })
        .catch(() => useColor(fallbackColor));
      return;
    }

    sampleImageColor(backgroundUrl)
      .then(useColor)
      .catch(() => useColor(fallbackColor));
  };

  const scheduleTextContrastTone = () => {
    if (textContrastFrame) {
      window.cancelAnimationFrame(textContrastFrame);
    }

    textContrastFrame = window.requestAnimationFrame(() => {
      textContrastFrame = 0;
      updateTextContrastTone();
    });
  };

  const applyPreferences = () => {
    const useCustomTextColor = preferences.textColorMode === "custom" && preferences.textContrast === "off";
    const cardBrightness = normalizeCardBrightness(preferences.cardBrightness);
    const cardBrightnessAmount = Math.abs(cardBrightness);
    const cardOpacity = normalizeCardOpacity(preferences.cardOpacity);
    const cardOpacityFill = Math.max(0, cardOpacity);
    const cardLayerOpacity = cardOpacity < 0 ? Math.max(0, (100 + cardOpacity) / 100) : 1;
    const textBrightness = normalizeTextBrightness(preferences.textBrightness);
    const textBrightnessAmount = Math.abs(textBrightness);
    const useTextBrightness = preferences.textContrast === "off" && textBrightness !== 0;

    document.body.dataset.theme = preferences.theme;
    document.body.dataset.surface = preferences.surface;
    document.body.dataset.density = preferences.density;
    document.body.dataset.themeBackgroundPriority = preferences.themeBackgroundPriority;
    document.body.dataset.backgroundBlur = preferences.backgroundBlur > 0 ? "custom" : "off";
    document.body.dataset.cardBrightness = "custom";
    document.body.dataset.cardOpacity = "custom";
    document.body.dataset.cardRenderer = nativeCardRendererSurfaces.has(preferences.surface) ? "native" : "generic";
    document.body.dataset.cardOpacityDirection = cardOpacity > 0 ? "stacked" : cardOpacity < 0 ? "transparent" : "off";
    document.body.dataset.cardOpacityLevel = cardOpacity <= -100 ? "transparent" : cardOpacity === 0 ? "off" : "custom";
    document.body.dataset.textContrast = preferences.textContrast;
    document.body.dataset.textContrastMethod = preferences.textContrastMethod;
    document.body.dataset.textColorMode = preferences.textColorMode;
    document.body.dataset.textBrightness = useTextBrightness ? "custom" : "off";
    document.body.dataset.textShadow = preferences.textShadow;
    document.body.dataset.textBold = preferences.textBold;
    document.body.style.setProperty("--site-background-blur", `${formatBackgroundBlur(preferences.backgroundBlur)}px`);
    document.body.style.setProperty("--site-background-scale", String(1 + Math.min(preferences.backgroundBlur * 0.0045, 0.08)));

    document.body.style.setProperty("--card-brightness-base", `${100 - cardBrightnessAmount}%`);
    document.body.style.setProperty("--card-brightness-color", cardBrightness >= 0 ? "#fff" : "#000");
    document.body.style.setProperty("--card-opacity-base", `${100 - cardOpacityFill}%`);
    document.body.style.setProperty("--card-layer-base", `${cardLayerOpacity * 100}%`);
    document.body.style.setProperty("--card-layer-opacity", String(Number(cardLayerOpacity.toFixed(3))));

    if (useTextBrightness) {
      document.body.style.setProperty("--text-brightness-base", `${100 - textBrightnessAmount}%`);
      document.body.style.setProperty("--text-brightness-color", textBrightness > 0 ? "#fff" : "#000");
    } else {
      document.body.style.removeProperty("--text-brightness-base");
      document.body.style.removeProperty("--text-brightness-color");
    }

    if (useCustomTextColor) {
      document.body.style.setProperty("--custom-text-color", adjustTextColorBrightness(preferences.textColor, textBrightness));
    } else {
      document.body.style.removeProperty("--custom-text-color");
    }

    if (preferences.textContrast === "off") {
      delete document.body.dataset.textContrastTone;
      clearLocalTextContrastTones();
    } else if (preferences.textContrastMethod === "sample") {
      clearLocalTextContrastTones();
    } else if (preferences.textContrastMethod === "enhance") {
      delete document.body.dataset.textContrastTone;
    }

    scheduleTextContrastTone();
  };

  const updateControls = (root) => {
    root.querySelectorAll("[data-preference-option]").forEach((button) => {
      const group = button.dataset.preferenceGroup;
      const isActive = preferences[group] === button.dataset.preferenceOption;
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", String(isActive));
    });

    root.querySelectorAll("[data-preference-range]").forEach((input) => {
      const group = input.dataset.preferenceGroup;
      const config = rangeConfigs[group];
      const value = config ? config.format(preferences[group]) : preferences[group];
      const output = root.querySelector(`[data-preference-value="${group}"]`);
      const min = Number.parseFloat(input.min);
      const max = Number.parseFloat(input.max);
      const numericValue = Number.parseFloat(value);
      const progress = Number.isFinite(numericValue) && max > min ? ((numericValue - min) / (max - min)) * 100 : 0;

      input.value = value;
      input.style.setProperty("--range-progress", `${Math.min(100, Math.max(0, progress))}%`);

      if (output) {
        output.textContent = config ? config.output(preferences[group]) : value;
      }
    });

    root.querySelectorAll("[data-preference-reset]").forEach((button) => {
      const group = button.dataset.preferenceGroup;
      const isActive = preferences[group] === defaults[group];
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", String(isActive));
    });

    root.querySelectorAll("[data-text-color-default]").forEach((button) => {
      const isActive = preferences.textColorMode === "default";
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", String(isActive));
    });

    root.querySelectorAll("[data-text-shadow-toggle]").forEach((button) => {
      const isActive = preferences.textShadow !== "off";
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", String(isActive));
      button.textContent = `阴影:${preferences.textShadow === "enhance" ? "柔光" : preferences.textShadow === "on" ? "开" : "关"}`;
    });

    root.querySelectorAll("[data-text-bold-toggle]").forEach((button) => {
      const isActive = preferences.textBold === "on";
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", String(isActive));
    });

    root.querySelectorAll("[data-text-color-swatch]").forEach((button) => {
      const color = normalizeTextColor(button.dataset.textColorSwatch);
      const isActive = preferences.textColorMode === "custom" && color === preferences.textColor;

      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", String(isActive));
      button.disabled = preferences.textContrast !== "off";
    });

    root.querySelectorAll("[data-text-color-input]").forEach((input) => {
      input.value = preferences.textColor;
      input.classList.remove("is-invalid");
      input.disabled = preferences.textContrast !== "off";
    });

    root.querySelectorAll("[data-text-color-preview]").forEach((preview) => {
      preview.style.backgroundColor = adjustTextColorBrightness(preferences.textColor, preferences.textBrightness);
    });

    root.querySelectorAll("[data-text-color-dependent]").forEach((control) => {
      control.disabled = preferences.textContrast !== "off";
    });

    root.querySelectorAll('[data-preference-group="textColor"], [data-preference-group="textBrightness"]').forEach((group) => {
      group.classList.toggle("is-paused", preferences.textContrast !== "off");
      group.classList.toggle("is-default", preferences.textColorMode === "default");
    });
  };

  const setPreference = (group, value, root) => {
    const nextValue = rangeConfigs[group] ? rangeConfigs[group].normalize(value) : value;

    if (preferences[group] === nextValue) {
      return;
    }

    preferences = { ...preferences, [group]: nextValue };
    applyPreferences();
    writePreferences(preferences);
    updateControls(root);
  };

  const setDefaultTextColor = (root) => {
    if (preferences.textColorMode === "default") {
      return;
    }

    preferences = {
      ...preferences,
      textColorMode: "default"
    };
    applyPreferences();
    writePreferences(preferences);
    updateControls(root);
  };

  const setTextColor = (color, root) => {
    const nextColor = normalizeTextColor(color);

    if (preferences.textColorMode === "custom" && preferences.textColor === nextColor) {
      return;
    }

    preferences = {
      ...preferences,
      textColorMode: "custom",
      textColor: nextColor
    };
    applyPreferences();
    writePreferences(preferences);
    updateControls(root);
  };

  const toggleTextShadow = (root) => {
    const nextShadow = preferences.textShadow === "off" ? "on" : preferences.textShadow === "on" ? "enhance" : "off";

    preferences = {
      ...preferences,
      textShadow: nextShadow
    };
    applyPreferences();
    writePreferences(preferences);
    updateControls(root);
  };

  const toggleTextBold = (root) => {
    preferences = {
      ...preferences,
      textBold: preferences.textBold === "on" ? "off" : "on"
    };
    applyPreferences();
    writePreferences(preferences);
    updateControls(root);
  };

  const createTextColorPreferenceGroup = (root) => {
    const wrapper = document.createElement("div");
    const title = document.createElement("span");
    const actionRow = document.createElement("div");
    const defaultButton = document.createElement("button");
    const actionButtons = document.createElement("div");
    const shadowButton = document.createElement("button");
    const boldButton = document.createElement("button");
    const palette = document.createElement("div");
    const inputRow = document.createElement("div");
    const preview = document.createElement("span");
    const input = document.createElement("input");

    wrapper.className = "preference-group text-color-preference";
    wrapper.dataset.preferenceGroup = "textColor";
    title.className = "preference-label";
    title.textContent = labels.textColor;
    actionRow.className = "text-color-action-row";
    actionButtons.className = "text-color-actions";
    defaultButton.type = "button";
    defaultButton.className = "text-color-default";
    defaultButton.dataset.textColorDefault = "true";
    defaultButton.textContent = "跟随配色";
    defaultButton.setAttribute("aria-pressed", "false");
    defaultButton.addEventListener("click", () => setDefaultTextColor(root));
    shadowButton.type = "button";
    shadowButton.className = "text-shadow-toggle";
    shadowButton.dataset.textShadowToggle = "true";
    shadowButton.textContent = "阴影:关";
    shadowButton.setAttribute("aria-label", "字体阴影");
    shadowButton.setAttribute("aria-pressed", "false");
    shadowButton.addEventListener("click", () => toggleTextShadow(root));
    boldButton.type = "button";
    boldButton.className = "text-bold-toggle";
    boldButton.dataset.textBoldToggle = "true";
    boldButton.textContent = "加粗";
    boldButton.setAttribute("aria-label", "文字加粗");
    boldButton.setAttribute("aria-pressed", "false");
    boldButton.addEventListener("click", () => toggleTextBold(root));

    palette.className = "text-color-palette";
    palette.setAttribute("role", "group");
    palette.setAttribute("aria-label", labels.textColor);

    textColorPalette.forEach((option) => {
      const button = document.createElement("button");

      button.type = "button";
      button.className = "text-color-swatch";
      button.dataset.textColorSwatch = option.value;
      button.style.setProperty("--swatch-color", option.value);
      button.setAttribute("aria-label", option.label);
      button.setAttribute("title", option.label);
      button.addEventListener("click", () => setTextColor(option.value, root));
      palette.append(button);
    });

    inputRow.className = "text-color-input-row";
    preview.className = "text-color-preview";
    preview.dataset.textColorPreview = "true";
    preview.setAttribute("aria-hidden", "true");
    input.type = "text";
    input.className = "text-color-input";
    input.dataset.textColorInput = "true";
    input.inputMode = "text";
    input.maxLength = 7;
    input.spellcheck = false;
    input.placeholder = "#2563eb";
    input.setAttribute("aria-label", "文字色值");
    const commitInputColor = () => {
      const nextColor = getTextColorInputValue(input.value);

      if (nextColor) {
        setTextColor(nextColor, root);
      } else {
        updateControls(root);
      }
    };

    input.addEventListener("input", () => {
      const nextColor = getTextColorInputValue(input.value);
      input.classList.toggle("is-invalid", input.value.trim() !== "" && !nextColor);
    });
    input.addEventListener("change", commitInputColor);
    input.addEventListener("blur", commitInputColor);
    input.addEventListener("keydown", (event) => {
      if (event.key !== "Enter") {
        return;
      }

      commitInputColor();
    });

    actionButtons.append(shadowButton, boldButton);
    actionRow.append(defaultButton, actionButtons);
    inputRow.append(preview, input);
    wrapper.append(title, actionRow, palette, inputRow);
    return wrapper;
  };

  const createRangePreferenceGroup = (group, root) => {
    const wrapper = document.createElement("div");
    const titleRow = document.createElement("div");
    const title = document.createElement("span");
    const actions = document.createElement("div");
    const value = document.createElement("span");
    const input = document.createElement("input");
    const config = rangeConfigs[group];

    wrapper.className = "preference-group";
    wrapper.dataset.preferenceGroup = group;
    titleRow.className = "preference-label-row";
    title.className = "preference-label";
    title.textContent = labels[group];
    actions.className = "preference-label-actions";
    value.className = "preference-value";
    value.dataset.preferenceValue = group;
    actions.append(value);

    if (group === "textBrightness" || group === "cardBrightness" || group === "cardOpacity") {
      const reset = document.createElement("button");

      reset.type = "button";
      reset.className = "preference-reset";
      reset.dataset.preferenceGroup = group;
      reset.dataset.preferenceReset = group;
      reset.textContent = "默认";
      reset.setAttribute("aria-label", `${labels[group]}恢复默认`);
      reset.addEventListener("click", () => setPreference(group, defaults[group], root));

      if (group === "textBrightness") {
        reset.dataset.textColorDependent = "true";
      }

      actions.append(reset);
    }

    input.type = "range";
    input.className = "preference-range";
    input.min = String(config.min);
    input.max = String(config.max);
    input.step = String(config.step);
    input.dataset.preferenceGroup = group;
    input.dataset.preferenceRange = group;
    input.setAttribute("aria-label", labels[group]);
    if (group === "textBrightness") {
      input.dataset.textColorDependent = "true";
    }
    input.addEventListener("input", () => setPreference(group, input.value, root));

    titleRow.append(title, actions);
    wrapper.append(titleRow, input);
    return wrapper;
  };

  const createAdvancedPreferenceGroup = (root) => {
    const details = document.createElement("details");
    const summary = document.createElement("summary");
    const indicator = document.createElement("span");
    const content = document.createElement("div");

    details.className = "preference-advanced";
    summary.className = "preference-advanced-summary";
    summary.setAttribute("aria-label", "高级设置");
    summary.title = "高级设置";
    indicator.className = "preference-advanced-indicator";
    indicator.setAttribute("aria-hidden", "true");
    content.className = "preference-advanced-content";

    advancedPreferenceGroups.forEach((group) => {
      content.append(createPreferenceGroup(group, root));
    });

    summary.append(indicator);
    details.append(summary, content);
    return details;
  };

  const createPreferenceGroup = (group, root) => {
    if (group === "textColor") {
      return createTextColorPreferenceGroup(root);
    }

    if (rangeConfigs[group]) {
      return createRangePreferenceGroup(group, root);
    }

    const wrapper = document.createElement("div");
    const title = document.createElement("span");
    const control = document.createElement("div");

    wrapper.className = "preference-group";
    wrapper.dataset.preferenceGroup = group;
    title.className = "preference-label";
    title.textContent = labels[group];
    control.className = "segmented-control";
    control.setAttribute("role", "group");
    control.setAttribute("aria-label", labels[group]);

    options[group].forEach((option) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "segmented-option";
      button.dataset.preferenceGroup = group;
      button.dataset.preferenceOption = option.value;
      button.textContent = option.label;
      button.addEventListener("click", () => setPreference(group, option.value, root));
      control.append(button);
    });

    wrapper.append(title, control);
    return wrapper;
  };

  const createSettingsIcon = () => {
    const svgNamespace = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(svgNamespace, "svg");
    const circle = document.createElementNS(svgNamespace, "circle");
    const path = document.createElementNS(svgNamespace, "path");
    const label = document.createElement("span");

    svg.classList.add("preference-toggle-icon");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");

    circle.setAttribute("cx", "12");
    circle.setAttribute("cy", "12");
    circle.setAttribute("r", "3");

    path.setAttribute("d", "M19.4 15a1.7 1.7 0 0 0 .34 1.88l.04.04a2 2 0 1 1-2.83 2.83l-.04-.04a1.7 1.7 0 0 0-1.88-.34 1.7 1.7 0 0 0-1.03 1.56V21a2 2 0 1 1-4 0v-.07a1.7 1.7 0 0 0-1.03-1.56 1.7 1.7 0 0 0-1.88.34l-.04.04a2 2 0 1 1-2.83-2.83l.04-.04A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.56-1.03H3a2 2 0 1 1 0-4h.07A1.7 1.7 0 0 0 4.6 8.94a1.7 1.7 0 0 0-.34-1.88l-.04-.04a2 2 0 1 1 2.83-2.83l.04.04a1.7 1.7 0 0 0 1.88.34H9a1.7 1.7 0 0 0 1-1.56V3a2 2 0 1 1 4 0v.07a1.7 1.7 0 0 0 1.03 1.56 1.7 1.7 0 0 0 1.88-.34l.04-.04a2 2 0 1 1 2.83 2.83l-.04.04a1.7 1.7 0 0 0-.34 1.88v.03A1.7 1.7 0 0 0 20.93 10H21a2 2 0 1 1 0 4h-.07A1.7 1.7 0 0 0 19.4 15Z");

    label.className = "sr-only";
    label.textContent = "外观偏好";

    svg.append(circle, path);
    return [svg, label];
  };

  const renderPreferencePanel = () => {
    const headerContainer = document.querySelector("[data-site-header] .container");

    if (!headerContainer) {
      return;
    }

    const root = document.createElement("div");
    const toggle = document.createElement("button");
    const backdrop = document.createElement("div");
    const panel = document.createElement("div");
    const panelId = "site-preference-panel";

    const syncPanelPosition = () => {
      if (panel.hidden) {
        panel.style.removeProperty("left");
        panel.style.removeProperty("top");
        backdrop.style.removeProperty("left");
        backdrop.style.removeProperty("top");
        backdrop.style.removeProperty("width");
        backdrop.style.removeProperty("height");
        return;
      }

      const toggleRect = toggle.getBoundingClientRect();
      const panelRect = panel.getBoundingClientRect();
      const margin = 12;
      const left = Math.max(margin, Math.min(window.innerWidth - panelRect.width - margin, toggleRect.right - panelRect.width));
      const top = Math.max(margin, Math.min(window.innerHeight - panelRect.height - margin, toggleRect.bottom + 5));

      panel.style.left = `${left}px`;
      panel.style.top = `${top}px`;

      const rect = panel.getBoundingClientRect();
      backdrop.style.left = `${rect.left}px`;
      backdrop.style.top = `${rect.top}px`;
      backdrop.style.width = `${rect.width}px`;
      backdrop.style.height = `${rect.height}px`;
    };

    const setPanelOpen = (isOpen) => {
      panel.hidden = !isOpen;
      backdrop.hidden = !isOpen;
      root.classList.toggle("is-open", isOpen);
      document.body.classList.toggle("is-preference-panel-open", isOpen);
      toggle.setAttribute("aria-expanded", String(isOpen));

      if (isOpen) {
        syncPanelPosition();
        window.requestAnimationFrame(syncPanelPosition);
      } else {
        syncPanelPosition();
      }
    };

    root.className = "site-preferences";
    toggle.type = "button";
    toggle.className = "preference-toggle";
    toggle.setAttribute("aria-label", "外观偏好");
    toggle.setAttribute("aria-expanded", "false");
    toggle.setAttribute("aria-controls", panelId);
    toggle.append(...createSettingsIcon());

    backdrop.className = "preference-backdrop";
    backdrop.hidden = true;

    panel.className = "preference-panel";
    panel.id = panelId;
    panel.hidden = true;

    preferenceGroups.forEach((group) => {
      panel.append(createPreferenceGroup(group, panel));
    });

    const advanced = createAdvancedPreferenceGroup(panel);
    panel.append(advanced);
    advanced.addEventListener("toggle", () => {
      window.requestAnimationFrame(syncPanelPosition);
    });

    toggle.addEventListener("click", () => {
      setPanelOpen(panel.hidden);
    });

    document.addEventListener("click", (event) => {
      if (root.contains(event.target) || panel.contains(event.target)) {
        return;
      }

      setPanelOpen(false);
    });

    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") {
        return;
      }

      setPanelOpen(false);
      toggle.focus();
    });

    window.addEventListener("resize", () => {
      if (!panel.hidden) {
        syncPanelPosition();
      }
    });

    backdrop.addEventListener("click", () => {
      setPanelOpen(false);
    });

    root.append(toggle);
    headerContainer.append(root);
    document.body.append(backdrop, panel);
    updateControls(panel);
  };

  new MutationObserver(scheduleTextContrastTone).observe(document.body, {
    attributes: true,
    attributeFilter: ["style"]
  });
  new MutationObserver(scheduleTextContrastTone).observe(document.body, {
    attributes: true,
    subtree: true,
    attributeFilter: ["hidden"]
  });
  window.addEventListener("resize", scheduleTextContrastTone);
  window.addEventListener("scroll", scheduleTextContrastTone, { passive: true });

  applyPreferences();
  renderPreferencePanel();
})();
